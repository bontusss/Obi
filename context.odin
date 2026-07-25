package obi

import "core:strings"
import http "vendor/odin-http"

Context :: struct {
	req:        ^Request,
	res:        ^Response,
	index:      int,
	middleware: []Handler,
	route:      Route_Handler,
	request_id: string,
	client_ip:  string,
}

param :: proc(ctx: ^Context, key: string) -> (string, bool) {
	for p in ctx.req.params {
		if p.key == key {
			return p.value, true
		}
	}
	return "", false
}

query :: proc(ctx: ^Context, key: string) -> (string, bool) {
	query := ctx.req.query
	key_bytes := transmute([]u8)key

	for len(query) > 0 {
		amp := strings.index_byte(query, '&')

		pair: string
		if amp == -1 {
			pair = query
			query = ""
		} else {
			pair = query[:amp]
			query = query[amp + 1:]
		}

		eq := strings.index_byte(pair, '=')

		name, value: string

		if eq == -1 {
			name = pair
			value = ""
		} else {
			name = pair[:eq]
			value = pair[eq + 1:]
		}

		if len(name) == len(key_bytes) && string(name) == string(key_bytes) {
			return string(value), true
		}
	}

	return "", false
}

next :: proc(ctx: ^Context) {
	ctx.index += 1

	if ctx.index < len(ctx.middleware) {
		m := ctx.middleware[ctx.index]
		m.callback(ctx, m.data)
		return
	}

	if ctx.route != nil {
		ctx.route(ctx)
	}
}

@(private)
index_byte :: proc(data: []u8, b: u8) -> int {
	for i := 0; i < len(data); i += 1 {
		if data[i] == b {
			return i
		}
	}

	return -1
}
