package obi

Context :: struct {
	req:        ^Request,
	res:        ^Response,


	index:      int,


	middleware: []Handler,
	route:      Route_Handler,
	request_id: string,
	client_ip:  string,
}

status :: proc(ctx: ^Context, status: Status) {
	send_status(ctx.res, status)
}

text :: proc(ctx: ^Context, text: string) {
	send_text(ctx.res, text)
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
		amp := index_byte(query, '&')

		pair: []u8
		if amp == -1 {
			pair = query
			query = nil
		} else {
			pair = query[:amp]
			query = query[amp + 1:]
		}

		eq := index_byte(pair, '=')

		name, value: []u8

		if eq == -1 {
			name = pair
			value = nil
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
