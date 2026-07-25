package obi

import "core:fmt"
import "core:log"
import "core:net"
import "core:os"
import "core:strings"
import http "vendor/odin-http"


Server :: struct {
	inner:        http.Server,
	router:       Router,
	middleware:   [dynamic]Handler,
	log_opts:     Log_Opts,
	log_file:     ^os.File,
	has_log_file: bool,
}

// Global pointer so the bridge can reach obi router.
// Odin has no closures; this is the idiomatic workaround.
@(private)
g_server: ^Server

Log_Opts :: struct {
	enabled:     bool, // dev_mode itself
	show_routes: bool, // startup route table, default true
	output:      enum {
		Terminal,
		File,
	},
	file_path:   string, // used when output == .File
	skip_paths:  []string, // e.g. {"/health", "/ping"}
}

DEFAULT_LOG_OPTS :: Log_Opts {
	enabled     = true,
	show_routes = true,
	output      = .Terminal,
	file_path   = "",
	skip_paths  = nil,
}

// Explicit env loader. Call this once in main() and pass the result to new_server.
load_log_opts_from_env :: proc() -> Log_Opts {
	opts := DEFAULT_LOG_OPTS

	if strings.compare(os.get_env("OBI_MODE", context.allocator), "production") == 0 {
		opts.enabled = false
		opts.show_routes = false
	}

	if strings.compare(os.get_env("OBI_LOG_OUTPUT", context.allocator), "file") == 0 {
		opts.output = .File
		opts.file_path = os.get_env("OBI_LOG_FILE", context.allocator)
		if opts.file_path == "" do opts.file_path = "obi.log"
	}

	return opts
}

new_server :: proc(log_opts: Log_Opts = DEFAULT_LOG_OPTS) -> ^Server {
	s := new(Server)

	s.log_opts = log_opts
	s.has_log_file = false

	s.router = router_init()
	http.server_shutdown_on_interrupt(&s.inner)

	// Observability middleware — always on
	use(s, request_id())
	use(s, real_ip())

	if log_opts.enabled do use(s, logger(s))

	// open log file once if needed
	if log_opts.enabled && log_opts.output == .File && log_opts.file_path != "" {
		file, open_err := os.open(log_opts.file_path, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
		if open_err == os.ERROR_NONE {
			s.log_file = file
			s.has_log_file = true
		} else {
			log.errorf("obi: failed to open log file: %s", log_opts.file_path)
		}
	}
	return s
}

destroy_server :: proc(s: ^Server) {
	router_destroy(&s.router)
	if s.has_log_file {
		os.close(s.log_file)
		s.has_log_file = false
	}
	free(s)
}

@(private)
bridge :: proc(req: ^http.Request, res: ^http.Response) {
	s := g_server
	if s == nil {
		http.respond(res, http.Status.Internal_Server_Error)
		return
	}


	// split path from query string
	path := req.url.raw
	// path := full
	// query_bytes: []u8
	// if q := strings.index_byte(full, '?'); q != -1 {
	// 	path = full[:q]
	// 	query_bytes = transmute([]u8)full[q + 1:]
	// }

	rl, ok := req.line.(http.Requestline)
	if !ok {
		http.respond(res, http.Status.Internal_Server_Error)
		return
	}
	method := rl.method

	route, params, matched, path_exists := router_find(&s.router, method, req.url.path)
	if !matched {
		if path_exists {
			http.respond(res, http.Status.Method_Not_Allowed)
		} else {
			http.respond(res, http.Status.Not_Found)
		}
		return
	}

	handlers := make([dynamic]Handler, context.allocator)
	append(&handlers, ..s.middleware[:]) // server level middleware
	append(&handlers, ..route.middleware) // route level middleware

	// Wrap odin-http types in Obi's req and res
	obi_req := &Request {
		inner = req,
		method = method,
		path = req.url.path,
		query = req.url.query,
		params = params,
	}

	obi_res := &Response{inner = res}

	ctx := Context {
		req        = obi_req,
		res        = obi_res,
		index      = -1, // start before first middleware
		middleware = handlers[:],
		route      = route.handler,
	}

	next(&ctx)

	// router_find allocates params with make([dynamic]Param)
	delete(params)
}


run :: proc(s: ^Server, port: int) {
	g_server = s
	defer destroy_server(s)

	if s.log_opts.enabled && s.log_opts.show_routes do print_routes(s)

	fmt.printfln("obi is running on port %v", port)

	endpoint := net.Endpoint {
		address = net.IP4_Loopback,
		port    = port,
	}

	err := http.listen_and_serve(&s.inner, http.handler(bridge), endpoint)
	if err != nil {
		fmt.eprintln("server error:", err)
	}
}


print_routes :: proc(s: ^Server) {
	max_method := 6
	max_path := 20

	for route in s.router.routes {
		m_len := len(http_method_str(route.method))
		if m_len > max_method {max_method = m_len}
		if len(route.path) > max_path {max_path = len(route.path)}
	}

	fmt.printfln("")
	fmt.printf("[obi] Registered routes: \n")
	fmt.printfln(strings.repeat("-", max_method + max_path + 28))

	for route in s.router.routes {
		mw_count := len(route.middleware)
		m_str := http_method_str(route.method)

		mc := method_color(route.method)
		reset := "\x1b[0m"
		gray := "\x1b[90m"
		fmt.printf(
			"%s[obi]%s %s%-*s%s %-*s → %d middleware\n",
			gray,
			reset,
			mc,
			max_method,
			m_str,
			reset,
			max_path,
			route.path,
			mw_count,
		)
	}

	fmt.printfln("")
}

@(private)
log_line :: proc(s: ^Server, msg: string) {
	if !s.log_opts.enabled do return
	if s.log_opts.output == .File && s.has_log_file {
		fmt.fprintln(s.log_file, msg)
	} else {
		fmt.println(msg)
	}
}

@(private)
http_method_str :: proc(m: http.Method) -> string {
	switch m {
	case .Get:
		return "GET"
	case .Post:
		return "POST"
	case .Put:
		return "PUT"
	case .Patch:
		return "PATCH"
	case .Delete:
		return "DELETE"
	case .Options:
		return "OPTIONS"
	case .Head:
		return "HEAD"
	case .Connect:
		return "CONNECT"
	case .Trace:
		return "TRACE"
	case:
		return "UNKNOWN"
	}
}

@(private)
method_color :: proc(m: http.Method) -> string {
	#partial switch m {
	case .Get:
		return "\x1b[32m" // green
	case .Post:
		return "\x1b[34m" // blue
	case .Put:
		return "\x1b[33m" // yellow
	case .Patch:
		return "\x1b[36m" // cyan
	case .Delete:
		return "\x1b[31m" // red
	case:
		return "\x1b[0m"
	}
}
