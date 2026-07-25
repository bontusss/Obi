package obi

import http "vendor/odin-http"

Request :: struct {
	inner:  ^http.Request,
	method: http.Method,
	path:   string,
	query:  string,
	params: [dynamic]Param,
}

Param :: struct {
	key:   string,
	value: string,
}
