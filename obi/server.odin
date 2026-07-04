package obi

import "core:fmt"
import "core:net"
import "core:thread"

// Obi is a simple HTTP server framework for the Odin programming language. 
// It provides a router that maps HTTP methods and paths to their corresponding handlers, 
// and a server that listens for incoming connections and handles them.

// Server is a struct that represents a server that listens for incoming connections and handles them.
Server :: struct {
	// socket is the TCP socket that listens for incoming connections.
	socket: net.TCP_Socket,
	// router is the router that maps HTTP methods and paths to their corresponding handlers.
	router:   Router,

	running:  bool, // indicates if the server is running

	log:      bool, // indicates if the server should log requests and responses
}


Serve_Error :: enum {
	// None indicates that the server is running successfully.
    None,
	// Accept_Failed indicates that the server failed to accept a new connection.
    Accept_Failed,
	// Network_Unreachable indicates that the server failed to listen on the specified address and port.
	Network_Unreachable,
}

Listen_And_ServeError :: enum {
	// None indicates that the server is running successfully.
	None,
	// Listen_Failed indicates that the server failed to listen on the specified address and port.
	Listen_Failed,
	// Accept_Failed indicates that the server failed to accept a new connection.
	Accept_Failed,
}


// new_server is a function that creates a new server instance.
//
// Example:
// ```odin
// server := new_server()
// ```
new_server :: proc() -> (Server) {
	return Server{
		router = router_init(),
		log = false,
	}
}

// listen is a function that listens for incoming connections on the specified address and port.
// It returns a net.Listen_Error indicating the result of the operation.
//
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
//     return .Listen_Failed
// }
// ```
listen :: proc(server: ^Server, address: string, port: int) -> net.Listen_Error {
	endpoint := net.Endpoint{address = net.parse_address(address), port = port}
	socket, err := net.listen_tcp(endpoint)
	if err != net.Listen_Error.None {
		return .Network_Unreachable
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
//     fmt.eprintln("serve: ", err)
//     return .Accept_Failed
// }
// ```
serve :: proc(server: ^Server) -> Serve_Error {
	if server.log {
		dump_routes(&server.router)
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
			return .Accept_Failed
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
@(private="file")
spawn_connection :: proc(server: ^Server, socket: net.TCP_Socket) {
	client := new(Connection)
	client.socket = socket
	client.buffer = make([dynamic]u8)
	client.router = &server.router
	client.log = server.log

	// handle the connection in a new thread
	thread.run_with_poly_data(client, handle_connection)
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
}

// listen_and_serve is a function that creates a new server instance and serves incoming connections on the specified address and port.
// 
// Example:
// ```odin
// err := listen_and_serve("localhost", 8080)
// if err != Serve_Error.None {
//     fmt.eprintln("listen_and_serve: ", err)
//     return
// }
// ```
listen_and_serve :: proc(server: ^Server, address: string, port: int) -> Listen_And_ServeError {	
	err := listen(server, address, port)
	if err != net.Listen_Error.None {
		return .Listen_Failed
	}

	serve_error := serve(server)
	if serve_error != Serve_Error.None {
		return .Accept_Failed
	}
	return .None
}

// get registers a handler for the specified path using the GET method.
//
// Example:
//
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// get(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
get :: proc(server: ^Server, path: string, handler: Handler) {
	router_get(&server.router, path, handler)
}

// post registers a handler for the specified path using the POST method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return	
// }
//
// post(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
post :: proc(server: ^Server, path: string, handler: Handler) {
	router_post(&server.router, path, handler)
}

// put registers a handler for the specified path using the PUT method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// put(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
put :: proc(server: ^Server, path: string, handler: Handler) {
	router_put(&server.router, path, handler)
}

// del registers a handler for the specified path using the DELETE method.
// this proc cant be named delete because it collides with the built-in delete identifier.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }

// delete(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
del :: proc(server: ^Server, path: string, handler: Handler) {
	router_delete(&server.router, path, handler)
}
// patch registers a handler for the specified path using the PATCH method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// patch(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
patch :: proc(server: ^Server, path: string, handler: Handler) {
	router_patch(&server.router, path, handler)
}

// options registers a handler for the specified path using the OPTIONS method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// options(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
options :: proc(server: ^Server, path: string, handler: Handler) {
	router_options(&server.router, path, handler)
}

// head registers a handler for the specified path using the HEAD method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// head(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
head :: proc(server: ^Server, path: string, handler: Handler) {
	router_head(&server.router, path, handler)
}

// delete registers a handler for the specified path using the DELETE method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// delete(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
// dump_routes is a function that prints the registered routes of the given router to the console.
@(private="file")
dump_routes :: proc(router: ^Router) {
	for route in router.routes {
		fmt.printfln(
			"%-6s %s",
			method_to_string(route.method),
			route.path,
		)
	}
}
