package obi

import "core:fmt"

// Header is a struct that represents an HTTP header with its name and value.
// an example of a header is "Content-Type: text/html"
@(private)
Header :: struct {
	name:  []u8,
	value: []u8,
}

// Request is a struct that represents an HTTP request with its method, path, query, version, headers, and body.
Request :: struct {
	// method is the HTTP method (e.g., GET, POST) of the request.
	method:  Method,
	// path is the URL path of the request (e.g., "/users", "/posts/1").
	path:    []u8,
	// query is the query string of the request (e.g., "id=1&name=John").
	query:   []u8,
	// version is the HTTP version of the request (e.g., "HTTP/1.1").
	version: []u8,
	// headers is a list of headers for the request.
	headers: [dynamic]Header,
	// body is the body of the request.
	body:    []u8,
	// params is a list of URL parameters for the request.
	params:  []Param,
}

Param :: struct {
    key: string,
    value: string,
}

// Parse_Error is an enum that represents the possible errors that can occur while parsing an HTTP request.
Parse_Error :: enum {
	None,
	Incomplete,
	Bad_Request_Line,
	Bad_Header,
	Bad_Content_Length,
}

// Parser is a struct that represents a parser for parsing HTTP requests.
@(private="file")
Parser :: struct {
	data: []u8,
	pos:  int,
}

// parse_request is a function that parses an HTTP request from the given raw data and returns a Request struct and a Parse_Error.
parse_request :: proc(raw: []u8) -> (Request, Parse_Error) {
	parser := Parser {
		data = raw,
	}

	req := Request {
		headers = make([dynamic]Header),
	}

	line, ok := read_line(&parser)
	// fmt.println("line:", string(line))
	if !ok {
		return req, .Incomplete
	}

	if err := parse_request_line(&req, line); err != .None {
		return req, err
	}

	if err := parse_headers(&parser, &req); err != .None {
		return req, err
	}

	if value, ok := header_value(req.headers[:], "content-length"); ok {
		n, ok := parse_uint(value)
		if !ok {
			return req, .Bad_Content_Length
		}

		if parser.pos + n > len(raw) {
			return req, .Incomplete
		}

		req.body = raw[parser.pos:parser.pos + n]
	}

	return req, .None
}

// parse_method is a function that parses the HTTP method from a string and returns the corresponding Method enum value and a boolean indicating success.
parse_method :: proc(method: string) -> (Method, bool) {
	if equal_fold_string(method, "GET")     do return .GET, true
	if equal_fold_string(method, "POST")    do return .POST, true
	if equal_fold_string(method, "PUT")     do return .PUT, true
	if equal_fold_string(method, "PATCH")   do return .PATCH, true
	if equal_fold_string(method, "DELETE")  do return .DELETE, true
	if equal_fold_string(method, "HEAD")    do return .HEAD, true
	if equal_fold_string(method, "OPTIONS") do return .OPTIONS, true

	return {}, false
}

// parse_request_line is a function that parses the request line of an HTTP request and populates the Request struct.
@(private="file")
parse_request_line :: proc(req: ^Request, line: []u8) -> Parse_Error {
	// fmt.println("request line:", string(line))

	s1 := index_byte(line, ' ')
	// fmt.println("s1 =", s1)

	if s1 == -1 {
		// fmt.println("rest =", string(line[s1+1:]))
		return .Bad_Request_Line
	}

	s2rel := index_byte(line[s1 + 1:], ' ')
	// fmt.println("s2rel =", s2rel)
	if s2rel == -1 {
		return .Bad_Request_Line
	}

	s2 := s1 + 1 + s2rel

	method, ok := parse_method(string(line[:s1]))
	if !ok {
		return .Bad_Request_Line // or .Bad_Request_Line
	}
	req.method = method

	target := line[s1 + 1:s2]

	if q := index_byte(target, '?'); q != -1 {
		req.path = target[:q]
		req.query = target[q + 1:]
	} else {
		req.path = target
	}

	req.version = line[s2 + 1:]

	return .None
}

// parse_headers is a function that parses the headers of an HTTP request and populates the Request struct.
@(private="file")
parse_headers :: proc(p: ^Parser, req: ^Request) -> Parse_Error {
	for {
		line, ok := read_line(p)
		if !ok {
			return .Incomplete
		}

		if len(line) == 0 {
			return .None
		}

		colon := index_byte(line, ':')
		if colon == -1 {
			return .Bad_Header
		}

		append(
			&req.headers,
			Header{name = trim_space(line[:colon]), value = trim_space(line[colon + 1:])},
		)
	}
}

// header_value is a function that retrieves the value of a header with the specified key.
@(private="file")
header_value :: proc(headers: []Header, key: string) -> ([]u8, bool) {
	for h in headers {
		if equal_fold_string(string(h.name), key) {
			return h.value, true
		}
	}

	return nil, false
}

// equal_fold_string is a function that compares two strings case-insensitively.
equal_fold_string :: proc(a, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}

	for i in 0..<len(a) {
		x := a[i]
		y := b[i]

		if 'A' <= x && x <= 'Z' {
			x += 'a' - 'A'
		}

		if 'A' <= y && y <= 'Z' {
			y += 'a' - 'A'
		}

		if x != y {
			return false
		}
	}

	return true
}

// index_byte is a function that finds the index of the first occurrence of a byte in a byte slice.
@(private="file")
index_byte :: proc(data: []u8, b: u8) -> int {
	for i := 0; i < len(data); i += 1 {
		if data[i] == b {
			return i
		}
	}

	return -1
}

// trim_space is a function that removes leading and trailing whitespace from a byte slice.
@(private="file")
trim_space :: proc(data: []u8) -> []u8 {
	start := 0
	end := len(data)

	for start < end && (data[start] == ' ' || data[start] == '\t') {
		start += 1
	}

	for end > start && (data[end - 1] == ' ' || data[end - 1] == '\t') {
		end -= 1
	}

	return data[start:end]
}

// parse_uint is a function that parses a byte slice as an unsigned integer and returns the integer value and a boolean indicating success.
@(private="file")
parse_uint :: proc(data: []u8) -> (int, bool) {
	n := 0

	for c in data {
		if c < '0' || c > '9' {
			return 0, false
		}

		n = n * 10 + int(c - '0')
	}

	return n, true
}

// read_line is a function that reads a line from the parser's data and returns the line and a boolean indicating success.
@(private="file")
read_line :: proc(p: ^Parser) -> ([]u8, bool) {
	start := p.pos

	for p.pos + 1 < len(p.data) {
		if p.data[p.pos] == '\r' && p.data[p.pos + 1] == '\n' {
			line := p.data[start:p.pos]
			p.pos += 2
			return line, true
		}

		p.pos += 1
	}

	return nil, false
}
