package main

import obi "../."
import "core:fmt"
import "core:time"


main :: proc() {
	size := []int{1, 10, 100, 1_000, 10_000}
	for n in size {
		r := obi.router_init()
		for i in 0 ..< n {
			obi.router_add(&r, .Get, fmt.tprintf("/resource%d/:id", i), dummy_handler, nil)
		}
		target := fmt.tprintf("/resource%d/42", n - 1)

		start := time.now()
		for i in 0 ..< 100_000 {
			_, params, _, _ := obi.router_find(&r, .Get, target)
			delete(params)
		}
		fmt.printf("N=%-6d %v\n", n, time.since(start))
	}
}

dummy_handler :: proc(c: ^obi.Context) {
	obi.status(c, .OK)
}
