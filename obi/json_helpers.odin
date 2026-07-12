package obi

import "core:encoding/json"
import "core:fmt"

h :: struct {
	values: map[string]any,
}

new_h :: proc() -> h {
	return h{values = make(map[string]any, context.temp_allocator)}
}

newh_with_cap :: proc(capacity: int) -> h {
	return h{values = make(map[string]any, capacity)}
}

destroy_h :: proc(h: ^h) {
	if h == nil {
		return
	}
	delete(h.values)
}

h_set :: proc(h: ^h, key: string, value: any) {
	if h == nil {
		return
	}

	h.values[key] = value
}

delete_from_h :: proc(h: ^h, key: string) -> bool {
	if h == nil {
		return false
	}

	if key in h.values {
		delete_key(&h.values, key)
		return true
	}

	return false
}

has :: proc(h: ^h, key: string) -> bool {
	if h == nil {
		return false
	}

	_, ok := h.values[key]
	return ok
}

h_len :: proc(h: ^h) -> int {
	if h == nil {
		return 0
	}

	return len(h.values)
}

h_clear :: proc(h: ^h) {
	if h == nil {
		return
	}

	clear(&h.values)
}

h_get :: proc(h: ^h, key: string) -> (any, bool) {
	if h == nil {
		return nil, false
	}

	value, ok := h.values[key]
	return value, ok
}

JSON_Error :: enum {
	None,
	Empty_Body,
	Invalid_Content_Type,
	Invalid_JSON,
}

json_error_text :: proc(err: JSON_Error) -> string {
	switch err {
	case .Empty_Body:
		return "request body is empty"

	case .Invalid_Content_Type:
		return "Content-Type must be application/json"

	case .Invalid_JSON:
		return "invalid JSON"

	case .None:
		return "unknown JSON error"
	}

	return "unknown JSON error"
}


marshal_h :: proc(v: h) -> ([]u8, json.Marshal_Error) {
	buf: [dynamic]u8
	append(&buf, '{')

	first := true
	for key, val in v.values {
		if !first do append(&buf, ',')
		first = false

		key_bytes, err := json.marshal(key)
		if err != json.Marshal_Data_Error.None {
			fmt.eprintfln("marshal_h error_1", err)
			return nil, err
		}
		append(&buf, ..key_bytes)
		delete(key_bytes)

		append(&buf, ':')

		// val here is a fresh local `any`, copied out of the map by the range —
		// NOT the same as reflecting through the map's own Type_Info_Map value slot.
		// Passing it into marshal() as a genuine top-level call is what makes this work.
		val_bytes, v_err := json.marshal(val)
		if v_err != json.Marshal_Data_Error.None {
			fmt.eprintfln("marshal_h error_2", err)
			return nil, err
		}
		append(&buf, ..val_bytes)
		delete(val_bytes)
	}

	append(&buf, '}')
	return buf[:], nil
}
