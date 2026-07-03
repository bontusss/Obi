package obi

import "core:net"
import "core:fmt"

// Response is a struct that represents an HTTP response with its status, headers, and body.
Response :: struct {
	client:  net.TCP_Socket,
    status:  Status,
    headers: [dynamic]Header,   // reuse the Header struct from request.odin
    body:    [dynamic]u8,
	written: bool, // indicates if the response has been written to the client
}

// Status is an enum that represents the possible HTTP status codes for a response.
Status :: enum int {
	OK                  = 200,
	Created             = 201,
	No_Content          = 204,

	Bad_Request         = 400,
	Not_Found           = 404,
	Method_Not_Allowed  = 405,

	Internal_Server_Error = 500,
}

status_text :: proc(status: Status) -> string {
	switch status {
	case .OK:
		return "OK"
	case .Created:
		return "Created"
	case .No_Content:
		return "No Content"
	case .Bad_Request:
		return "Bad Request"
	case .Not_Found:
		return "Not Found"
	case .Method_Not_Allowed:
		return "Method Not Allowed"
	case .Internal_Server_Error:
		return "Internal Server Error"
	}

	return "Unknown"
}

response_init :: proc(client: net.TCP_Socket) -> Response {
	return Response {
		client = client,
		status = .OK,
		headers = make([dynamic]Header),
		body = make([dynamic]u8),
	}
}

response_destroy :: proc(res: ^Response) {
	delete(res.headers)
	delete(res.body)
}

send_status :: proc(res: ^Response, status: Status) {
	if res.written do return // prevent writing to the response after it has been sent
	res.status = status
}

response_header :: proc(res: ^Response, key, value: string) {
	if res.written do return

	for &header in res.headers {
		if equal_fold_string(string(header.name), key) {
			header.value = transmute([]u8)value
			return
		}
	}

	append(&res.headers, Header{
		name  = transmute([]u8)key,
		value = transmute([]u8)value,
	})
}

response_write :: proc(res: ^Response, data: []u8) {
	if res.written do return // prevent writing to the response after it has been sent
	append(&res.body, ..data)
}

response_write_string :: proc(res: ^Response, s: string) {
	if res.written do return // prevent writing to the response after it has been sent
	append(&res.body, ..transmute([]u8)s)
}

send_text :: proc(res: ^Response, text: string) {
	response_header(res, "Content-Type", "text/plain; charset=utf-8")
	response_write_string(res, text)
}

response_send :: proc(res: ^Response) -> net.TCP_Send_Error {
	if res.written {
		return .None
	}

	if !has_header(res.headers[:], "Content-Type") {
		response_header(res, "Content-Type", "text/plain; charset=utf-8")
	}

	err := write_response(res)
	if err == .None {
		res.written = true
	}

	return err
}

// write_response is a function that writes the given HTTP response to the specified TCP socket.
// It returns a net.TCP_Send_Error indicating the result of the operation.
write_response :: proc(res: ^Response) -> net.TCP_Send_Error {
	socket_write_string(
		res.client,
		fmt.tprintf(
			"HTTP/1.1 %d %s\r\n",
			int(res.status),
			status_text(res.status),
		),
	) or_return

	socket_write_string(
		res.client,
		fmt.tprintf("Content-Length: %d\r\n", len(res.body)),
	) or_return

	for header in res.headers {
		if equal_fold_string(string(header.name), "content-length") {
			continue
		}

		socket_write(res.client, header.name[:]) or_return
		socket_write_string(res.client, ": ") or_return
		socket_write(res.client, header.value[:]) or_return
		socket_write_string(res.client, "\r\n") or_return
	}

	socket_write_string(res.client, "\r\n") or_return

	if len(res.body) > 0 {
		socket_write(res.client, res.body[:]) or_return
	}

	return .None
}

@(private)
socket_write_string :: proc(client: net.TCP_Socket, s: string) -> net.TCP_Send_Error {
	return socket_write(client, transmute([]u8)s)
}

@(private)
socket_write :: proc(client: net.TCP_Socket, data: []u8) -> net.TCP_Send_Error {
	sent := 0

	for sent < len(data) {
		n, err := net.send_tcp(client, data[sent:])
		if err != .None {
			return err
		}

		sent += n
	}

	return .None
}

// has_header is a function that checks if the given headers contain a header with the specified key (case-insensitive).
// It returns true if the header is found, otherwise false.
// Example:
//```odin
// headers := []Header{
//     {name: transmute([]u8)string("Content-Type"), value: transmute([]u8)string("text/html")},
//     {name: transmute([]u8)string("Content-Length"), value: transmute([]u8)string("123")},
// }
// if has_header(headers[:], "content-type") {
//     fmt.println("Content-Type header is present")
// } else {
//     fmt.println("Content-Type header is not present")
// }
//```
@(private)
has_header :: proc(headers: []Header, key: string) -> bool {
	for h in headers {
		if equal_fold_string(string(h.name), key) {
			return true
		}
	}

	return false
}