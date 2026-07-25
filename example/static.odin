package main

import obi "../."
import "core:fmt"
import "core:strconv"
import "core:time"

main :: proc() {
	// Read env once, explicitly
	opts := obi.load_log_opts_from_env()

	// Or construct manually:
	// opts := obi.Log_Opts{
	//     enabled    = true,
	//     output     = .File,
	//     file_path  = "access.log",
	//     skip_paths = []string{"/health", "/favicon.ico"},
	// }

	s := obi.new_server(opts)
	// No need to manually add logger() — dev mode auto-injects it

	User :: struct {
		name: string `json:"user_name"`,
		age:  int,
		role: Role,
	}

	Role :: enum {
		user,
		admin,
	}

	obi.get(
		s,
		"/ping",
		proc(ctx: ^obi.Context) {
			user: User
			user.name = "bontus"
			user.age = 89
			user.role = Role.admin

			if user.role == Role.user {
				obi.json(ctx, obi.err("you are not authorized"), .Forbidden)
				return
			}
			// obi.text(ctx, "pong")
			obi.json(ctx, obi.ok("user created", user), .Created)
		},
	)

	obi.get(s, "/users/:id", proc(ctx: ^obi.Context) {
		id, ok := obi.param(ctx, "id")
		int_id, _ := strconv.parse_int(id)
		if int_id > 1 {
			obi.json(ctx, obi.err("pass a higher number"), .Bad_Request)
			return
		}
		obi.json(ctx, obi.ok(data = int_id))
	})

	slow_handler :: proc(ctx: ^obi.Context) {
		time.sleep(1 * time.Second)
		obi.text(ctx, "done")
	}
	obi.get(s, "/slow", slow_handler)
	obi.run(s, 8080)
}
