package obi

import "core:crypto"
import "core:encoding/base64"
import "core:fmt"
import "core:strings"
import "core:time"

Cors_Config :: struct {
	allow_origins: string,
}

@(private)
cors_handler :: proc(ctx: ^Context, data: rawptr) {
	config := (^Cors_Config)(data)
	response_header(ctx.res, "Access-Control-Allow-Origin", config.allow_origins)
	response_header(
		ctx.res,
		"Access-Control-Allow-Methods",
		"GET, POST, PUT, PATCH, DELETE, OPTIONS",
	)
	response_header(ctx.res, "Access-Control-Allow-Headers", "Content-Type, Authorization")

	if ctx.req.method == .OPTIONS {
		status(ctx, .No_Content)
		return
	}

	next(ctx)
}

cors :: proc(allow_origins: string) -> Handler {
	config := new(Cors_Config)
	config.allow_origins = allow_origins
	return Handler{callback = cors_handler, data = config}
}

generate_request_id :: proc() -> string {
	bytes: [16]byte
	crypto.rand_bytes(bytes[:])

	// Optional: make it RFC 4122 UUID v4
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	return fmt.tprintf(
		"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
		bytes[0],
		bytes[1],
		bytes[2],
		bytes[3],
		bytes[4],
		bytes[5],
		bytes[6],
		bytes[7],
		bytes[8],
		bytes[9],
		bytes[10],
		bytes[11],
		bytes[12],
		bytes[13],
		bytes[14],
		bytes[15],
	)
}

request_id_handler :: proc(ctx: ^Context, data: rawptr) {
	id := generate_request_id()

	ctx.request_id = id
	response_header(ctx.res, "X-Request-ID", id)
	next(ctx)
}

request_id :: proc() -> Handler {
	return Handler{callback = request_id_handler, data = nil}
}

Basic_Auth_Config :: struct {
	username: string,
	password: string,
	realm:    string,
}

@(private)
basic_auth_handler :: proc(ctx: ^Context, data: rawptr) {
	config := (^Basic_Auth_Config)(data)
	auth_header, ok := header_value(ctx.req.headers[:], "authorization")
	if !ok {
		unauthorized(ctx, config)
		return
	}

	auth := string(auth_header)

	if !strings.has_prefix(auth, "Basic ") {
		unauthorized(ctx, config)
		return
	}

	encoded := auth[6:]

	decoded, err := base64.decode(encoded)
	if err != nil {
		unauthorized(ctx, config)
		return
	}
	defer delete(decoded)

	credentials := string(decoded)

	colon := strings.index(credentials, ":")
	if colon < 0 {
		unauthorized(ctx, config)
		return
	}

	user := credentials[:colon]
	pass := credentials[colon + 1:]


	user_ok :=
		crypto.compare_constant_time(transmute([]byte)config.username, transmute([]byte)user) == 1

	pass_ok :=
		crypto.compare_constant_time(transmute([]byte)config.password, transmute([]byte)pass) == 1

	if !user_ok || !pass_ok {
		unauthorized(ctx, &Basic_Auth_Config{realm = config.realm})
		return
	}
	next(ctx)
}


@(private)
unauthorized :: proc(ctx: ^Context, config: ^Basic_Auth_Config) {
	response_header(ctx.res, "WWW-Authenticate", fmt.tprintf("Basic realm=\"%s\"", config.realm))

	status(ctx, .Unauthorized)
	text(ctx, "401 Unauthorized")
}

basic_auth :: proc(username, password: string, realm: string = "Restricted") -> Handler {
	config := new(Basic_Auth_Config)
	config.username = username
	config.password = password
	config.realm = realm
	return Handler{callback = basic_auth_handler, data = config}
}

@(private)
real_ip_handler :: proc(ctx: ^Context, data: rawptr) {
	// Check X-Forwarded-For header (common in proxy setups)
	if forwarded, ok := header_value(ctx.req.headers[:], "x-forwarded-for"); ok {
		// X-Forwarded-For can contain multiple IPs, the first is the client
		forwarded_str := string(forwarded)
		if comma := strings.index(forwarded_str, ","); comma != -1 {
			ctx.client_ip = strings.trim_space(forwarded_str[:comma])
		} else {
			ctx.client_ip = strings.trim_space(forwarded_str)
		}
	} else if real_ip_header, ok := header_value(ctx.req.headers[:], "x-real-ip"); ok {
		ctx.client_ip = string(real_ip_header)
	} else {
		// Fallback to connection remote address
		// Note: This would require storing the client address in the connection
		// ctx.client_ip = ctx.conn.remote_addr
	}
	next(ctx)
}

real_ip :: proc() -> Handler {
	return Handler{callback = real_ip_handler, data = nil}
}

@(private)
secure_headers_handler :: proc(ctx: ^Context, data: rawptr) {
	response_header(ctx.res, "X-Frame-Options", "DENY")
	response_header(ctx.res, "X-XSS-Protection", "1; mode=block")
	response_header(ctx.res, "X-Content-Type-Options", "nosniff")
	response_header(ctx.res, "Referrer-Policy", "no-referrer")
	response_header(
		ctx.res,
		"Strict-Transport-Security",
		"max-age=31536000; includeSubDomains; preload",
	)
	next(ctx)
}

secure_headers :: proc() -> Handler {
	return Handler{callback = secure_headers_handler, data = nil}
}

logger :: proc() -> Handler {
	return Handler{callback = logger_handler, data = nil}
}

@(private)
logger_handler :: proc(ctx: ^Context, data: rawptr) {
	start := time.now()
	next(ctx)
	log_request(ctx.req, ctx.res, start)
}
