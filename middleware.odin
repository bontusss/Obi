#+feature dynamic-literals
package obi

import "core:crypto"
import "core:encoding/base64"
import "core:fmt"
import "core:log"
import "core:net"
import "core:strings"
import "core:time"
import http "vendor/odin-http"

use :: proc {
	use_server,
	use_group,
}

use_server :: proc(server: ^Server, handler: Handler) {
	append(&server.middleware, handler)
}

use_group :: proc(group: ^Group, handler: Handler) {
	append(&group.middleware, handler)
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

	http.headers_set(&ctx.res.inner.headers, "X-Request-ID", id)
	ctx.request_id = id
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

	auth_header, ok := http.headers_get(ctx.req.inner.headers, "authorization")
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
	http.headers_set(
		&ctx.res.inner.headers,
		"WWW-Authenticate",
		fmt.tprintf("Basic realm=\"%s\"", config.realm),
	)

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
	if forwarded, ok := http.headers_get(ctx.req.inner.headers, "x-forwarded-for"); ok {
		// X-Forwarded-For can contain multiple IPs, the first is the client
		forwarded_str := string(forwarded)
		if comma := strings.index(forwarded_str, ","); comma != -1 {
			ctx.client_ip = strings.trim_space(forwarded_str[:comma])
		} else {
			ctx.client_ip = strings.trim_space(forwarded_str)
		}
	} else if real_ip_header, iok := http.headers_get(ctx.req.inner.headers, "x-real-ip"); iok {
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
	http.headers_set(&ctx.res.inner.headers, "X-Frame-Options", "DENY")
	http.headers_set(&ctx.res.inner.headers, "X-XSS-Protection", "1; mode=block")
	http.headers_set(&ctx.res.inner.headers, "X-Content-Type-Options", "nosniff")
	http.headers_set(&ctx.res.inner.headers, "Referrer-Policy", "no-referrer")
	http.headers_set(
		&ctx.res.inner.headers,
		"Strict-Transport-Security",
		"max-age=31536000; includeSubDomains; preload",
	)
	next(ctx)
}

secure_headers :: proc() -> Handler {
	return Handler{callback = secure_headers_handler, data = nil}
}

logger :: proc(s: ^Server) -> Handler {
	return Handler{callback = logger_handler, data = s}
}

@(private)
logger_handler :: proc(ctx: ^Context, data: rawptr) {
	s := (^Server)(data)
	if s == nil || !s.log_opts.enabled {
		next(ctx)
		return
	}

	// Skip noisy health checks
	for skip in s.log_opts.skip_paths {
		if ctx.req.path == skip {
			next(ctx)
			return
		}
	}

	start := time.now()
	next(ctx)
	duration := time.since(start)

	status := ctx.res.inner.status
	status_color, duration_color, reset, gray, method_color := "", "", "", "", ""

	ms := time.duration_milliseconds(duration)
	is_slow := ms > 500.0

	if s.log_opts.output == .Terminal {
		reset = "\x1b[0m"
		gray = "\x1b[90m"
		method_color = "\x1b[36m" // cyan

		// Duration: black on white, turns white on red if slow
		duration_color = "\x1b[30;47m"
		if is_slow {
			duration_color = "\x1b[37;41m"
		}

		code := int(status)
		switch {
		case code < 300:
			status_color = "\x1b[30;42m" // black on green
		case code < 400:
			status_color = "\x1b[30;43m" // black on yellow
		case code < 500:
			status_color = "\x1b[37;41m" // white on red
		case:
			status_color = "\x1b[37;45m" // white on magenta
		}
	}

	year, month, day := time.date(time.now())
	hour, minute, sec := time.clock(time.now())

	client_ip := ctx.client_ip
	if client_ip == "" {
		client_ip = fmt.tprintf("%v", ctx.req.inner.client)

		// Remove ":port" for IPv4 endpoints
		if idx := strings.last_index_byte(client_ip, ':'); idx >= 0 {
			client_ip = client_ip[:idx]
		}
	}

	slow_tag := ""
	if is_slow && s.log_opts.output == .Terminal {
		slow_tag = "\x1b[33m[SLOW]\x1b[0m "
	}

	msg := fmt.tprintf(
		"%s[obi]%s %04d/%02d/%02d %02d:%02d:%02d | %s%d%s | %s%8.3fms%s | %15s | %s%-7s%s %s%s",
		gray,
		reset,
		year,
		month,
		day,
		hour,
		minute,
		sec,
		status_color,
		status,
		reset,
		duration_color,
		ms,
		reset,
		client_ip,
		method_color,
		http_method_str(ctx.req.method),
		reset,
		slow_tag,
		ctx.req.path,
	)

	if is_slow {
		log.warnf("obi: slow request %s", msg)
	}

	obi_log(s, msg)
}

@(private)
obi_log :: proc(s: ^Server, msg: string) {
	if !s.log_opts.enabled do return
	if s.log_opts.output == .File && s.has_log_file {
		fmt.fprintln(s.log_file, msg)
	} else {
		fmt.println(msg)
	}
}
