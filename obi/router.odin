package obi

import "core:strings"

// Router is a struct that represents a router that maps HTTP methods and paths to their corresponding handlers.
Route :: struct {
	// method is the HTTP method (e.g., GET, POST) for the route.
	method:  Method,

	// segments is a list of segments that make up the route path.
	// eg: for the path "/users/:id", the segments would be ["users", ":id"]
	segments: [dynamic]Segment,

	// path is the URL path for the route. eg: "/users", "/posts/:id"
	path:    string,

	// handler is the function that will be called when a request matches the method and path.
	handler: Route_Handler,
}

Handler :: struct {
	callback: Handler_Proc,
	data: rawptr,
}

// Handler is a type that represents a function that handles an HTTP request and generates an HTTP response.
Handler_Proc :: #type proc(ctx: ^Context, data: rawptr = nil)

Route_Handler :: #type proc(ctx: ^Context)

// Middleware_Handler :: #type proc(ctx: ^Context, data: rawptr)

// Middleware :: struct {
//     procedure: Middleware_Handler,
//     data: rawptr,
// }


Method :: enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,
    HEAD,
}

method_to_string :: proc(method: Method) -> string {
	switch method {
	case .GET:
		return "GET"
	case .POST:
		return "POST"
	case .PUT:
		return "PUT"
	case .PATCH:
		return "PATCH"
	case .DELETE:
		return "DELETE"
	case .OPTIONS:
		return "OPTIONS"
	case .HEAD:
		return "HEAD"
	}
	return "Unknown"
}

// Segment_Kind is an enum that represents the type of a segment in a route path.
@(private)
Segment_Kind :: enum {
	// Static segments are fixed parts of the path (e.g., "users" in "/users/:id").
    Static,

	// Parameter segments are variable parts of the path (e.g., ":id" in "/users/:id").
    Parameter,
}

// Segment is a struct that represents a segment of a route path, which can be either static or a parameter.
@(private)
Segment :: struct {
	// kind is the type of the segment (Static or Parameter).
    kind: Segment_Kind,

	// value is the string value of the segment (e.g., "users" or ":id").
    value: string,
}

// Router is a struct that represents a router that maps HTTP methods and paths to their corresponding handlers.
Router :: struct {
	routes: [dynamic]Route,
}

// router_init is a function that initializes a new Router with an empty list of routes.
router_init :: proc() -> Router {
	return Router{routes = make([dynamic]Route)}
}

// router_destroy is a function that destroys the given Router by deleting its list of routes.
router_destroy :: proc(router: ^Router) {
	for r in router.routes {
		delete(r.segments)
	}
	delete(router.routes)
}

// router_get is a function that registers a handler for the specified path using the GET method.
@(private)
router_get :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .GET, path, handler)
}

// router_post is a function that registers a handler for the specified path using the POST method.
@(private)
router_post :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .POST, path, handler)
}

// router_put is a function that registers a handler for the specified path using the PUT method.
@(private)
router_put :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .PUT, path, handler)
}

// router_patch is a function that registers a handler for the specified path using the PATCH method.
@(private)
router_patch :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .PATCH, path, handler)
}

// router_delete is a function that registers a handler for the specified path using the DELETE method.
@(private)
router_delete :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .DELETE, path, handler)
}

// router_options is a function that registers a handler for the specified path using the OPTIONS method.
@(private)
router_options :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .OPTIONS, path, handler)
}

// router_head is a function that registers a handler for the specified path using the HEAD method.
@(private)
router_head :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .HEAD, path, handler)
}

@(private)
router_add :: proc(
	router: ^Router,
	method: Method,
	path: string,
	handler: Route_Handler,
) {
	append(&router.routes, Route{
		method   = method,
		path     = path,
		segments = parse_route(path),
		handler  = handler,
	})
}


@(private)
parse_route :: proc(path: string) -> [dynamic]Segment {
	parts := split_path(transmute([]u8)path)

	segments := make([dynamic]Segment)

	for part in parts {
		if len(part) > 0 && part[0] == ':' {
			append(&segments, Segment{
				kind  = .Parameter,
				value = part[1:], // store "id", not ":id"
			})
		} else {
			append(&segments, Segment{
				kind  = .Static,
				value = part,
			})
		}
	}

	delete(parts)

	return segments
}


split_path :: proc(path: []u8) -> [dynamic]string {
    segments := make([dynamic]string)
    parts := strings.split(string(path), "/")
    defer delete(parts)

    for segment in parts {
        if len(segment) == 0 do continue
        append(&segments, segment)
    }
    return segments
}

// router_find is a function that finds the handler for the specified method and path in the given Router.
// It returns the handler and a boolean indicating whether the handler was found.
@(private)
router_find :: proc(router: ^Router, method: Method, path: []u8) -> (^Route, []Param, bool, bool) {
    // returns: route, params, matched, method_allowed
    path_segments := split_path(path)
    defer delete(path_segments)

    path_exists := false

    for &route in router.routes {
        if len(route.segments) != len(path_segments) do continue

        params := make([dynamic]Param)
        matched := true
        for i in 0..<len(route.segments) {
            seg := route.segments[i]
            switch seg.kind {
            case .Static:
                if seg.value != path_segments[i] { matched = false }
            case .Parameter:
                append(&params, Param{key = seg.value, value = path_segments[i]})
            }
        }

        if !matched {
            delete(params)
            continue
        }

        path_exists = true

        if route.method == method {
            return &route, params[:], true, true
        }
        delete(params)
    }

    return nil, nil, false, path_exists
}

// get registers a handler for the specified path using the GET method.
//
// Example:
//
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// get(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
get :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_get(&server.router, path, handler)
}

// post registers a handler for the specified path using the POST method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return	
// }
//
// post(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
post :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_post(&server.router, path, handler)
}

// put registers a handler for the specified path using the PUT method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// put(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
put :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_put(&server.router, path, handler)
}

// del registers a handler for the specified path using the DELETE method.
// this proc cant be named delete because it collides with the built-in delete identifier.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }

// delete(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
del :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_delete(&server.router, path, handler)
}
// patch registers a handler for the specified path using the PATCH method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// patch(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
patch :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_patch(&server.router, path, handler)
}

// options registers a handler for the specified path using the OPTIONS method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// options(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
options :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_options(&server.router, path, handler)
}

// head registers a handler for the specified path using the HEAD method.
//
// Example:
// ```odin
// server, err := new_server("localhost", 8080)
// if err != net.Listen_Error.None {
//     fmt.eprintln("new_server: ", err)
//     return
// }
//
// head(&server, "/hello", proc(req: Request, res: Response) {
//     res.write_string("Hello, World!")
// })
// ```
head :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_head(&server.router, path, handler)
}
