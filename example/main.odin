package main

import "core:fmt"
import "core:net"
import "core:time"

import obi "../old-obi"

main :: proc() {
	server := obi.new_server()

	// obi.use(&server, obi.logger())
	// 	obi.use(&server, obi.real_ip())
	// 	obi.use(&server, obi.secure_headers())
	// 	obi.use(&server, obi.cors("*"))
	// 	obi.use(&server, obi.request_id())

	// 	// group prefix deliberately has a trailing slash, route path has a
	// 	// leading slash — tests whether double-slash concatenation still
	// 	// routes correctly (it should, since split_path filters empty segments)
	// 	api := obi.group(&server, "/api/v1/")
	// obi.use(&api, obi.basic_auth("user", "pass"))
	// 	obi.get(&api, "/users", user_handler)

	// 	// nested group: should inherit api's basic_auth AND require its own
	// 	// admin_guard, with a prefix of /api/v1/admin
	// 	admin := obi.group(&api, "/admin")

	// 	admin_guard :: proc(ctx: ^obi.Context, data: rawptr) {
	// 		fmt.println("admin_guard middleware ran")
	// 		obi.next(ctx)
	// 	}
	// 	obi.use(&admin, obi.Handler{callback = admin_guard, data = nil})
	// 	obi.get(&admin, "/settings", settings_handler)

	// 	User :: struct {
	// 		name: string,
	// 		age:  int,
	// 	}

	// 	user_handler :: proc(c: ^obi.Context) {
	// 		user: User
	// 		if err := obi.bind_json(c, &user); err != .None {
	// 			obi.send_json(c, .Bad_Request, obi.json_error_text(err))
	// 			return
	// 		}
	// 		obi.send_json(c, .OK, user)
	// 	}

	// 	settings_handler :: proc(c: ^obi.Context) {
	// 		obi.send_json(c, .OK, "admin settings")
	// 	}

	// 	hello :: proc(c: ^obi.Context) {
	// 		obi.send_json(c, .OK, "hello")
	// 	}

	// 	obi.get(&server, "/", hello) // still ungrouped, no auth required

	// 	post_handler :: proc(c: ^obi.Context) {
	// 		obi.send_json(c, .Created, User{name = "bontus", age = 67})
	// 	}
	// 	put_handler :: proc(c: ^obi.Context) {
	// 		obi.send_json(c, .OK, User{age = 67})
	// 	}
	// 	patch_handler :: proc(c: ^obi.Context) {
	// 		obi.send_json(c, .OK, User{name = "ukandu"})
	// 	}
	// 	delete_handler :: proc(c: ^obi.Context) {
	// 		obi.send_json(c, .No_Content, "deleted")
	// 	}
	// 	head_handler :: proc(c: ^obi.Context) {
	// 		obi.send_json(c, .OK, "head handler")
	// 	}
	// 	opions_handler :: proc(c: ^obi.Context) {
	// 		obi.send_json(c, .OK, "options handler")
	// 	}

	// 	slow :: proc(c: ^obi.Context) {
	// 		time.sleep(3 * time.Second)
	// 		obi.send_json(c, .OK, "finished slowly")
	// 	}

	// 	obi.static(&server, "/static", "./public")

	// 	obi.static(&server, "/assets", obi.Static_Config{root = "./assets", cache = true, etag = true})

	// 	obi.get(&server, "/slow", slow)
	// 	obi.post(&server, "/post", post_handler)
	// 	obi.put(&server, "/put", put_handler)
	// 	obi.patch(&server, "/patch", patch_handler)
	// 	obi.del(&server, "/delete", delete_handler)
	// 	obi.head(&server, "/head", head_handler)
	// 	obi.options(&server, "/options", opions_handler)

	obi.run(server, 8000)

}
