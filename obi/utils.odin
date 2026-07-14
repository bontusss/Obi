package obi

import "core:fmt"
import "core:net"
import "core:strings"
import "core:sys/posix"
import "core:thread"

Signal :: posix.Signal // SIGINT = 2, SIGTERM = 15, etc.

@(private)
g_server_for_shutdown: ^Server

@(private)
handle_shutdown_signal :: proc "c" (sig: posix.Signal) {
	if g_server_for_shutdown != nil {
		g_server_for_shutdown.running = false
	}
}

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

// spawn_connection is a function that spawns a new connection to the server.
// It creates a new connection instance and handles the connection in a new thread.
//
// Example:
// ```odin
// spawn_connection(&server, socket)
// ```
@(private)
spawn_connection :: proc(server: ^Server, socket: net.TCP_Socket) {
	net.set_option(socket, net.Socket_Option.Receive_Timeout, server.idle_timeout)

	client := new(Connection)
	client.socket = socket
	client.buffer = make([dynamic]u8)
	client.router = &server.router
	client.server = server

	// handle the connection in a new thread
	thread.pool_add_task(&server.pool, context.allocator, connection_task, client)
}

connection_task :: proc(task: thread.Task) {
	conn := cast(^Connection)task.data
	handle_connection(conn)
}
