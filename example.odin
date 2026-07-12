#+feature dynamic-literals

package main

import "core:fmt"
import "core:net"

import "obi"

main :: proc() {
	server := obi.new_server()
	server.print_routes = true

	obi.use(&server, obi.logger())
	obi.use(&server, obi.real_ip())
	obi.use(&server, obi.secure_headers())
	obi.use(&server, obi.cors("*"))
	obi.use(&server, obi.request_id())

	User :: struct {
		name: string,
		age:  int,
	}

	hello :: proc(ctx: ^obi.Context) {
		obi.status(ctx, obi.Status.OK)
		obi.text(ctx, "Hello, World!")
	}

	// exercises: bind_json failure path, H for a hand-built error body,
	// and a plain struct passed straight to send_json on success
	create_user :: proc(ctx: ^obi.Context) {
		user: User

		if err := obi.bind_json(ctx, &user); err != .None {
			h := obi.new_h()
			defer obi.destroy_h(&h)
			obi.h_set(&h, "message", obi.json_error_text(err))
			obi.h_set(&h, "version", "1.0")

			obi.send_json(ctx, .Bad_Request, h)
			return
		}

		obi.send_json(ctx, .OK, user)
	}

	// exercises: H with a nested value, to confirm marshal recurses correctly
	info :: proc(ctx: ^obi.Context) {
		h := obi.new_h()
		// defer obi.destroy_h(&h)

		obi.h_set(&h, "service", "obi")
		obi.h_set(&h, "version", "1.0")
		obi.h_set(&h, "author", User{name = "bontus", age = 0})

		obi.send_json(ctx, .OK, h)
	}

	user_handler :: proc(ctx: ^obi.Context) {
		id, ok := obi.param(ctx, "id")
		if !ok {
			obi.status(ctx, obi.Status.Bad_Request)
			obi.text(ctx, "Missing user ID")
			return
		}
		obi.status(ctx, obi.Status.OK)
		obi.text(ctx, fmt.tprintf("User ID: %s", id))
	}

	search :: proc(ctx: ^obi.Context) {
		name, _ := obi.query(ctx, "name")
		active, _ := obi.query(ctx, "active")
		obi.text(ctx, fmt.tprintf("name=%s active=%s", name, active))
	}

	obi.get(&server, "/", hello)
	obi.get(&server, "/users/:id", user_handler)
	obi.get(&server, "/search", search)
	obi.get(&server, "/info", info)
	obi.post(&server, "/users", create_user)

	err := obi.run(&server, "127.0.0.1", 8000)

	switch err in err {
	case obi.Listen_Error:
		if err.(obi.Listen_Validation_Error) == .Invalid_Address {
			fmt.eprintln("Invalid address")
			return
		} else if err.(obi.Listen_Validation_Error) == .Invalid_Port {
			fmt.eprintln("Invalid port")
			return
		}
	case net.Accept_Error:
		if err != .None {
			fmt.eprintln("serve:", err)
			return
		}
	}
}
