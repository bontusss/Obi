package main

import obi "../."
import "core:fmt"
import "core:strconv"
import "core:time"

main :: proc() {
	// Read env once, explicitly
	opts := obi.Log_Opts {
		enabled     = true,
		output      = .File,
		file_path   = "./example/obi.log",
		show_routes = true,
	}

	s := obi.new_server(opts)

	api := obi.group(s, "/test")
	obi.use(&api, obi.basic_auth("user", "pass"))
	obi.get(&api, "/auth", proc(c: ^obi.Context) {obi.text(c, "auth tested")})
	obi.run(s, 8080)
}
