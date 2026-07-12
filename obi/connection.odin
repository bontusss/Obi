package obi

import "core:fmt"
import "core:net"
import "core:time"

BUFFER_SIZE :: 4096

// Connection is a struct that represents a connection to a client, with its router, socket, and buffer.
Connection :: struct {
	// router is a pointer to the Router that will handle the requests for this connection.
	// It is used to find the appropriate handler for each request based on the request method and path.
	router: ^Router,

	// socket is the TCP socket that represents the connection to the client.
	// It is used to read data from and write data to the client.
	socket: net.TCP_Socket,

	// buffer is a dynamic array of bytes that holds the data read from the client.
	// It is used to accumulate data until a complete request can be parsed.
	buffer: [dynamic]u8,
	server: ^Server,
}

// connection_destroy is a function that cleans up the resources associated with a Connection struct.
@(private = "file")
connection_destroy :: proc(conn: ^Connection) {
	delete(conn.buffer)
	net.close(conn.socket)
}

// connection_clear_buffer is a function that clears the buffer of a Connection struct, removing all accumulated data.
@(private = "file")
connection_clear_buffer :: proc(conn: ^Connection) {
	clear(&conn.buffer)
}

// request_destroy is a function that cleans up the resources associated with a Request struct, including its headers and parameters.
@(private = "file")
request_destroy :: proc(req: ^Request) {
	delete(req.headers)
	delete(req.params)
}

// handle_connection is a function that handles a connection to a client, reading requests and writing responses.
// It reads data from the client, parses the request, and invokes the appropriate handler based on the request method and path.
@(private)
handle_connection :: proc(conn: ^Connection) {
	defer connection_destroy(conn)
	recv_buffer: [BUFFER_SIZE]u8

	for {
		req, consumed, parse_err := parse_request(conn.buffer[:])
		defer request_destroy(&req)

		switch parse_err {
		case .Incomplete:
			n, err := net.recv_tcp(conn.socket, recv_buffer[:])
			if err != .None || n == 0 {
				return
			}

			append(&conn.buffer, ..recv_buffer[:n])
			continue

		case .Bad_Request_Line, .Bad_Header, .Bad_Content_Length:
			res := response_init(conn.socket)
			send_status(&res, .Bad_Request)
			send_text(&res, "400 Bad Request")

			_ = response_send(&res)

			response_destroy(&res)
			free_all(context.temp_allocator)
			return

		case .None:
			res := response_init(conn.socket)
			defer response_destroy(&res)

			should_close := connection_should_close(&req)
			if should_close do response_header(&res, "Connection", "close")

			route, params, ok, path_exists := router_find(conn.router, req.method, req.path)

			handlers := make([dynamic]Handler, context.temp_allocator)
			append_elems(&handlers, ..conn.server.middleware[:])

			ctx := Context {
				req        = &req,
				res        = &res,
				index      = -1,
				middleware = handlers[:],
			}

			if ok {
				req.params = params
				ctx.route = route.handler
			} else if path_exists {
				ctx.route = method_not_allowed_handler
			} else {
				ctx.route = not_found_handler
			}

			next(&ctx)

			send_err := response_send(&res)

			connection_consume(conn, consumed)

			free_all(context.temp_allocator)

			if send_err != .None || should_close do return
			continue
		}
	}
}

@(private)
not_found_handler :: proc(ctx: ^Context) {
	status(ctx, .Not_Found)
	text(ctx, "404 Not Found")
}

@(private)
method_not_allowed_handler :: proc(ctx: ^Context) {
	status(ctx, .Method_Not_Allowed)
	text(ctx, "405 Method Not Allowed")
}

// connection_consume is a function that removes the consumed bytes from the buffer of a Connection struct.
// It is used to remove the bytes that have already been processed by the parser.
connection_consume :: proc(conn: ^Connection, n: int) {
	remainig := len(conn.buffer) - n

	if remainig > 0 {
		copy(conn.buffer[:remainig], conn.buffer[n:])
	}

	resize(&conn.buffer, remainig)
}

// connection_should_close is a function that determines whether the connection should be closed based on the "Connection" header of the request.
// If the "Connection" header is set to "close", the connection will be closed after the response is sent.
connection_should_close :: proc(req: ^Request) -> bool {
	if value, ok := header_value(req.headers[:], "connection"); ok {
		return equal_fold(value, transmute([]u8)string("close"))
	}

	return false
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
