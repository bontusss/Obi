package obi

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:strings"
import http "vendor/odin-http"

Response :: struct {
	inner: ^http.Response,
}

status :: proc(ctx: ^Context, status: http.Status, loc := #caller_location) {
	http.response_status(ctx.res.inner, status)
}

text :: proc(ctx: ^Context, text: string, status: http.Status = .OK, loc := #caller_location) {
	http.respond_plain(ctx.res.inner, text, status, loc)
}

// json :: proc(ctx: ^Context, v: any, status: http.Status = .OK) {
// 	http.respond_json(ctx.res.inner, v, status)
// }

json :: proc(ctx: ^Context, v: V, status: http.Status = .OK) {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	strings.write_string(&b, "{")
	fmt.sbprintf(&b, `"success":%v,"message":`, v.success)

	// Marshal message separately so quotes/newlines are escaped
	msg_bytes, _ := json.marshal(v.message)
	strings.write_bytes(&b, msg_bytes)

	// Only append data if present
	if v.data != nil {
		data_bytes, err := json.marshal(v.data)
		if err == nil {
			strings.write_string(&b, `,"data":`)
			strings.write_bytes(&b, data_bytes)
		}
	}

	strings.write_string(&b, "}")
	body := strings.to_string(b)

	// Set up response exactly like respond_json does
	ctx.res.inner.status = status
	http.headers_set_content_type(&ctx.res.inner.headers, "application/json")

	// Write body using odin-http's response writer (same internals as respond_json)
	rw: http.Response_Writer
	buf: [128]byte
	http.response_writer_init(&rw, ctx.res.inner, buf[:])
	defer io.close(rw.w)

	io.write_string(rw.w, body)
}

respond :: proc(ctx: ^Context, status: http.Status = .OK, loc := #caller_location) {
	http.respond(ctx.res.inner, status, loc)
	return
}

V :: struct {
	success: bool,
	message: string,
	data:    any,
}

ok :: proc(message: string = "", data: any = nil) -> V {
	return V{success = true, message = message, data = data}
}

err :: proc(message: string, data: any = nil) -> V {
	return V{success = false, message = message, data = data}
}
