package obi

import "core:strings"
import http "vendor/odin-http"

// Router is a struct that represents a router that maps HTTP methods and paths to their corresponding handlers.
Route :: struct {
	// method is the HTTP method (e.g., GET, POST) for the route.
	method:     http.Method,

	// segments is a list of segments that make up the route path.
	// eg: for the path "/users/:id", the segments would be ["users", ":id"]
	segments:   [dynamic]Segment,

	// path is the URL path for the route. eg: "/users", "/posts/:id"
	path:       string,

	// handler is the function that will be called when a request matches the method and path.
	handler:    Route_Handler,
	middleware: []Handler,
}

Router :: struct {
	routes: [dynamic]Route,
}

Group :: struct {
	router:     ^Router,
	prefix:     string,
	middleware: [dynamic]Handler,
}

Handler :: struct {
	callback: Handler_Proc,
	data:     rawptr,
}

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
	kind:  Segment_Kind,

	// value is the string value of the segment (e.g., "users" or ":id").
	value: string,
}

// Handler is a type that represents a function that handles an HTTP request and generates an HTTP response.
Handler_Proc :: #type proc(ctx: ^Context, data: rawptr = nil)

Route_Handler :: #type proc(ctx: ^Context)

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

@(private)
router_find :: proc(
	router: ^Router,
	method: http.Method,
	path: string,
) -> (
	^Route,
	[dynamic]Param,
	bool,
	bool,
) {
	// returns: route, params, matched, method_allowed
	path_segments := split_path(path)
	defer delete(path_segments)

	path_exists := false

	for &route in router.routes {
		if len(route.segments) != len(path_segments) do continue

		params := make([dynamic]Param)
		matched := true
		for i in 0 ..< len(route.segments) {
			seg := route.segments[i]
			switch seg.kind {
			case .Static:
				if seg.value != path_segments[i] {matched = false}
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
			return &route, params, true, true
		}
		delete(params)
	}

	return nil, nil, false, path_exists
}

split_path :: proc(path: string) -> [dynamic]string {
	segments := make([dynamic]string)
	parts := strings.split(path, "/")
	defer delete(parts)

	for segment in parts {
		if len(segment) == 0 do continue
		append(&segments, segment)
	}
	return segments
}

// router_get is a function that registers a handler for the specified path using the GET method.
@(private)
router_get :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .Get, path, handler, nil)
}

// router_post is a function that registers a handler for the specified path using the POST method.
@(private)
router_post :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .Post, path, handler, nil)
}

// router_put is a function that registers a handler for the specified path using the PUT method.
@(private)
router_put :: proc(router: ^Router, path: string, handler: Route_Handler) {
	router_add(router, .Put, path, handler, nil)
}


@(private)
router_add :: proc(
	router: ^Router,
	method: http.Method,
	path: string,
	handler: Route_Handler,
	middleware: []Handler,
) {
	append(
		&router.routes,
		Route {
			method = method,
			path = path,
			segments = parse_route(path),
			handler = handler,
			middleware = middleware,
		},
	)
}

@(private)
parse_route :: proc(path: string) -> [dynamic]Segment {
	parts := split_path(path)

	segments := make([dynamic]Segment)

	for part in parts {
		if len(part) > 0 && part[0] == ':' {
			append(
				&segments,
				Segment {
					kind  = .Parameter,
					value = part[1:], // store "id", not ":id"
				},
			)
		} else {
			append(&segments, Segment{kind = .Static, value = part})
		}
	}

	delete(parts)

	return segments
}

group_from_server :: proc(server: ^Server, prefix: string) -> Group {
	return Group{router = &server.router, prefix = prefix, middleware = make([dynamic]Handler)}
}

/*
Nesting a group under a group just concatenates prefixes and copies forward the parent's
middleware before you add more — that's a deliberate choice worth being explicit about:
a nested group inherits everything its parent had, and can only add to it, not remove from it.
That matches how Gin's route groups behave, and it's the intuitive expectation
(/api/v1/admin should get everything /api/v1 has, plus whatever's specific to /admin).
*/
group_from_group :: proc(parent: ^Group, prefix: string) -> Group {
	g := Group {
		router     = parent.router,
		prefix     = join_path(parent.prefix, prefix),
		middleware = make([dynamic]Handler),
	}
	for m in parent.middleware do append(&g.middleware, m)
	return g
}

group :: proc {
	group_from_server,
	group_from_group,
}

get_server :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_add(&server.router, .Get, path, handler, nil)
}

get_group :: proc(group: ^Group, path: string, handler: Route_Handler) {
	full_path := join_path(group.prefix, path)
	router_add(group.router, .Get, full_path, handler, group.middleware[:])
}
get :: proc {
	get_server,
	get_group,
}

post_server :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_add(&server.router, .Post, path, handler, nil)
}
post_group :: proc(group: ^Group, path: string, handler: Route_Handler) {
	router_add(group.router, .Post, join_path(group.prefix, path), handler, group.middleware[:])
}
post :: proc {
	post_server,
	post_group,
}

put_server :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_add(&server.router, .Put, path, handler, nil)
}
put_group :: proc(group: ^Group, path: string, handler: Route_Handler) {
	router_add(group.router, .Put, join_path(group.prefix, path), handler, group.middleware[:])
}
put :: proc {
	put_server,
	put_group,
}

delete_server :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_add(&server.router, .Delete, path, handler, nil)
}
delete_group :: proc(group: ^Group, path: string, handler: Route_Handler) {
	router_add(group.router, .Delete, join_path(group.prefix, path), handler, group.middleware[:])
}
del :: proc {
	delete_server,
	delete_group,
}

patch_server :: proc(server: ^Server, path: string, handler: Route_Handler) {
	router_add(&server.router, .Patch, path, handler, nil)
}
patch_group :: proc(group: ^Group, path: string, handler: Route_Handler) {
	router_add(group.router, .Patch, join_path(group.prefix, path), handler, group.middleware[:])
}
patch :: proc {
	patch_server,
	patch_group,
}

join_path :: proc(a: string, b: string) -> string {
	a := a
	if len(a) > 0 && a[len(a) - 1] == '/' {
		a = a[:len(a) - 1]
	}
	return strings.concatenate({a, b})
}
