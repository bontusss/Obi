package obi

import "core:fmt"
import "core:net"
import "core:sys/posix"
import "core:thread"
import "core:time"

// Obi is a simple HTTP server framework for the Odin programming language.
// It provides a router that maps HTTP methods and paths to their corresponding handlers,
// and a server that listens for incoming connections and handles them.

// Server is a struct that represents a server that listens for incoming connections and handles them.
Server :: struct {
	// socket is the TCP socket that listens for incoming connections.
	socket:       net.TCP_Socket,
	// router is the router that maps HTTP methods and paths to their corresponding handlers.
	router:       Router,
	running:      bool, // indicates if the server is running
	close:        bool, // guards close proc from running twice
	print_routes: bool, // indicates if the server should log requests and responses
	middleware:   [dynamic]Handler,
	idle_timeout: time.Duration,
	pool:         thread.Pool,
	worker_count: int,
}

Listen_Error :: union {
	Listen_Validation_Error,
	net.Network_Error,
}

Listen_Validation_Error :: enum {
	None,
	Invalid_Address,
	Invalid_Port,
}

Run_Error :: union {
	Listen_Error,
	net.Accept_Error,
}

// new_server is a function that creates a new server instance.
//
// Example:
// ```odin
// server := new_server()
// ```
new_server :: proc() -> Server {
	return Server {
		router = router_init(),
		print_routes = false,
		idle_timeout = 30 * time.Second,
		worker_count = 8,
	}
}

// listen is a function that listens for incoming connections on the specified address and port.
// It returns a net.Listen_Error indicating the result of the operation.
//1", 8000)
// Example:
// ```odin
// server, err := new_server()
// if err != Serve_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return .Accept_Failed
// }
// err = listen(&server, "localhost", 8080)
// if err != Serve_Error.None {
//     fmt.eprintln("listen: ", err)
listen :: proc(server: ^Server, address: string, port: int) -> Listen_Error {
	addr := net.parse_address(address)
	if addr == nil do return .Invalid_Address
	if port < 0 || port > 65535 do return .Invalid_Port

	endpoint := net.Endpoint {
		address = addr,
		port    = port,
	}

	socket, err := net.listen_tcp(endpoint)
	if err != net.Listen_Error.None {
		return err
	}
	server.socket = socket
	return .None
}

// serve is a function that serves incoming connections on the specified server.
// It blocks until the server is stopped or an error occurs.
//
// Example:
// ```odin
// server, err := new_server()
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
// err = serve(&server)
// if err != Serve_Error.None {
serve :: proc(server: ^Server) -> net.Accept_Error {
	if server.print_routes {
		print_routes(&server.router)
	}

	thread.pool_init(&server.pool, context.allocator, server.worker_count)
	thread.pool_start(&server.pool)

	server.running = true

	for server.running {
		socket, _, err := net.accept_tcp(server.socket)

		switch err {
		case .None:
			spawn_connection(server, socket)

		case .Interrupted, .Would_Block, .Timeout:
			continue

		case .Network_Unreachable,
		     .Insufficient_Resources,
		     .Invalid_Argument,
		     .Unsupported_Socket,
		     .Not_Listening,
		     .Aborted,
		     .Unknown:
			if !server.running do break

			fmt.eprintln("accept:", err)
			return err
		}
	}

	return .None
}

use :: proc {
	use_server,
	use_group,
}
use_server :: proc(server: ^Server, handler: Handler) {
	append(&server.middleware, handler)
}

use_group :: proc(group: ^Group, handler: Handler) {
	append(&group.middleware, handler)
}

// close is a function that closes the server and stops it from accepting new connections.
//
// Example:
// ```odin
// server, err := new_server()
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return .Listen_Failed
// }
// err = listen(&server, "localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("listen: ", err)
//     return .Listen_Failed
close :: proc(server: ^Server) {
	if server.close do return
	server.close = true
	server.running = false
	net.close(server.socket)
	thread.pool_finish(&server.pool)
	thread.pool_destroy(&server.pool)
	router_destroy(&server.router)
	for m in server.middleware {
		if m.data != nil do free(m.data)
	}
	delete(server.middleware)
}

/*
One honest tradeoff worth knowing, not fixing today
A connection sitting idle on a keep-alive, waiting inside recv_tcp for its next request 
(up to 30-second idle_timeout), is still "in-flight" from the pool's perspective — its worker 
thread hasn't returned from handle_connection yet. pool_finish will wait for it. In the worst case, 
if several clients are mid-keep-alive when signal shutdown happens, 
the process could take up to idle_timeout seconds to actually exit, not instantly. 
That's a real, honest limitation — a stricter version would force-close all client sockets 
on shutdown to cut this short, but that undermines genuinely in-flight requests getting to 
finish, which is the whole point. Most production servers handle this with a shutdown grace 
period cap (wait up to N seconds, then force-kill whatever's left, similar to Kubernetes' 
terminationGracePeriodSeconds) — worth keeping as a future refinement, not required for this 
to count as "graceful."
*/
run :: proc(server: ^Server, address := "127.0.0.1", port := 8000) -> Run_Error {
	fmt.printfln("Obi is listening on port %d", port)

	if err := listen(server, address, port); err != .None {
		return err
	}

	// periodic wake-up so the accept loop can notice a shutdown request
	net.set_option(server.socket, net.Socket_Option.Receive_Timeout, 1 * time.Second)

	g_server_for_shutdown = server
	posix.signal(.SIGINT, handle_shutdown_signal)
	posix.signal(.SIGTERM, handle_shutdown_signal)

	if err := serve(server); err != .None {
		return err
	}

	close(server)

	return nil
}
