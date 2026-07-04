package main

import "core:fmt"

import "obi"

main :: proc() {
	server := obi.new_server()
	server.log = true // enable logging for the server

	obi.del(&server, "/hello", proc(req: ^obi.Request, res: ^obi.Response) {
		res.status = .OK
		obi.send_text(res, "Hello, World!")
	})

	err := obi.listen_and_serve(&server, "127.0.0.1", 8080)
	if err != .None {
		fmt.eprintln("listen_and_serve: ", err)
		return
	}
}