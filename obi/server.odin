package obi

import "core:fmt"
import "core:net"
import "core:thread"
import "core:time"

// Obi is a simple HTTP server framework for the Odin programming language.
// It provides a router that maps HTTP methods and paths to their corresponding handlers,
// and a server that listens for incoming connections and handles them.

// Server is a struct that represents a server that listens for incoming connections and handles them.
Server :: struct {
	// socket is the TCP socket that listens for incoming connections.
	socket:  net.TCP_Socket,
	// router is the router that maps HTTP methods and paths to their corresponding handlers.
	router:  Router,
	running: bool, // indicates if the server is running
	print_routes:     bool, // indicates if the server should log requests and responses
	middleware: [dynamic]Handler,
	idle_timeout: time.Duration
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
	return Server{router = router_init(), print_routes = false, idle_timeout = 30 * time.Second}
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
	if addr == nil  do return .Invalid_Address
	if port < 0 || port > 65535  do	return .Invalid_Port
	
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
			if !server.running {
				break
			}

			fmt.eprintln("accept:", err)
			return err
		}
	}

	return .None
}

// spawn_connection is a function that spawns a new connection to the server.
// It creates a new connection instance and handles the connection in a new thread.
//
// Example:
// ```odin
// spawn_connection(&server, socket)
// ```
@(private = "file")
spawn_connection :: proc(server: ^Server, socket: net.TCP_Socket) {
	net.set_option(socket, net.Socket_Option.Receive_Timeout, server.idle_timeout)
	client := new(Connection)
	client.socket = socket
	client.buffer = make([dynamic]u8)
	client.router = &server.router
	client.server = server

	// handle the connection in a new thread
	thread.run_with_poly_data(client, handle_connection)
}

// use :: proc(server: ^Server, handler: Handler) {
// 	append(&server.middleware, handler)
// }

use :: proc{use_server, use_group}
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
// }
//
// close(&server)
// ```
close :: proc(server: ^Server) {
	if !server.running do return
	server.running = false
	net.close(server.socket)
	router_destroy(&server.router)
	for m in server.middleware {
		if m.data == nil do free(m.data)
	}
	delete(server.middleware)
	
}


run :: proc(server: ^Server, address := "127.0.0.1", port := 8000) -> Run_Error {
	fmt.printfln("Obi is listening on port %d", port)

	if err := listen(server, address, port); err != .None {
		return err
	}

	if err := serve(server); err != .None {
		return err
	}
	return nil
}

