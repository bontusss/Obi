package obi

import "core:net"
import "core:fmt"
import "core:time"

BUFFER_SIZE :: 4096

// Connection is a struct that represents a connection to a client, with its router, socket, and buffer.
Connection :: struct {
	router: ^Router,
	socket: net.TCP_Socket,
	buffer: [dynamic]u8,
	log:    bool, // indicates if the connection should log requests and responses
}

connection_init :: proc(socket: net.TCP_Socket, log: bool) -> Connection {
	return Connection{socket = socket, buffer = make([dynamic]u8), log = log}
}

connection_destroy :: proc(conn: ^Connection) {
	delete(conn.buffer)
	net.close(conn.socket)
}

connection_clear_buffer :: proc(conn: ^Connection) {
	clear(&conn.buffer)
}

request_destroy :: proc(req: ^Request) {
	delete(req.headers)
	delete(req.params)
}

// handle_connection is a function that handles a connection to a client, reading requests and writing responses.
// It reads data from the client, parses the request, and invokes the appropriate handler based on the request method and path.
@(private)
handle_connection :: proc(conn: ^Connection) {
	defer connection_destroy(conn)
	start := time.now()
	recv_buffer: [BUFFER_SIZE]u8

	for {
		n, err := net.recv_tcp(conn.socket, recv_buffer[:])
		if err != .None || n == 0 {
			break
		}

		append(&conn.buffer, ..recv_buffer[:n])

		req, parse_err := parse_request(conn.buffer[:])
		defer request_destroy(&req) // fires on continue, return, everything

		switch parse_err {
		case .Incomplete:
			continue

		case .Bad_Request_Line, .Bad_Header, .Bad_Content_Length:
			res := response_init(conn.socket)
			defer response_destroy(&res)
			send_status(&res, .Bad_Request)
			send_text(&res, "400 Bad Request")

			_ = response_send(&res)

			free_all(context.temp_allocator)
			return

		case .None:
			res := response_init(conn.socket)
			defer response_destroy(&res)			

			if route, params, ok, path_exists := router_find(conn.router, req.method, req.path); ok {
				req.params = params
				route.handler(&req, &res)
			} else if path_exists {
				send_status(&res, .Method_Not_Allowed)
				send_text(&res, "405 Method Not Allowed")
			} else {
				send_status(&res, .Not_Found)
				send_text(&res, "404 Not Found")
			}

			_ = response_send(&res)

			if conn.log do log_request(&req, &res, start)

			free_all(context.temp_allocator)

			// HTTP/1.0 style for now: one request per connection.
			return
		}
	}
}

// log_request is a function that logs the details of an HTTP request and its corresponding response, 
// including the method, path, status code, response size, and duration.
// Sample log output: 
// ```bash
// [127, 0, 0, 1]:36960 GET /users/42 -> 200 (422.9µs)
// ```
// TODO: fix the endpoint to display correctly
log_request :: proc(req: ^Request, res: ^Response, start_time: time.Time) {
	duration := time.since(start_time)
	fmt.printfln(
		"%s %s %d %dB %s",
		method_to_string(req.method),
		string(req.path),
		res.status,
		len(res.body),
		duration,
	)
}