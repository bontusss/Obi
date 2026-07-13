package obi

import "core:strings"
import "core:fmt"

@(private)
join_path :: proc(a: string, b: string) -> string {
	a := a
	if len(a) > 0 && a[len(a) - 1] == '/' {
		a = a[:len(a) - 1]
	}
	return strings.concatenate({a, b})
}

// dump_routes is a function that prints the registered routes of the given router to the console.
@(private)
print_routes :: proc(router: ^Router) {
	fmt.println("available routes:")
	for route in router.routes {
		fmt.printfln("%-6s %s", method_to_string(route.method), route.path)
	}
}
