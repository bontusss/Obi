# Obi

Obi is a lightweight HTTP server framework for the Odin programming language. It provides a small but practical foundation for building web services with routing, request parsing, structured responses, and basic logging.

The project is intentionally minimal at this stage, but the core pieces are already in place for building simple APIs and prototypes in Odin.

## What Obi does

Obi currently supports:

- Creating an HTTP server and listening on a local address/port
- Registering handlers for common methods like GET and POST
- Matching static and parameterized routes such as `/users/:id`
- Parsing request lines, headers, and simple request bodies
- Building responses with status codes, headers, and plain-text or binary payloads
- Returning standard errors such as 400, 404, and 405
- Logging basic request/response information for development

## Project status

This project is an early-stage framework with a simple architecture and a clear path for growth. It is a good fit for learning, experimenting, and building small web services in Odin.

The next planned features are:

- Keep-alive support
- Request context handling
- Middleware support

## Requirements

Before building the project, make sure you have the Odin compiler installed and available on your PATH.

You can install Odin by following the official instructions at the Odin website.

## Quick start

From the repository root, build the sample application:

```bash
odin build main.odin -file -out:odin-web
```

Run the server:

```bash
./odin-web
```

The sample server will listen on `127.0.0.1:8080`.

You can test it with:

```bash
curl http://127.0.0.1:8080/hello
```

Expected response:

```text
Hello, World!
```

## Using Obi in a new project

The simplest way to use it in a new Odin project is:

1. Copy the [obi](obi) directory from this repository into your new project root.
2. Create a new entrypoint such as [main.odin](main.odin).
3. Import the framework with:

```odin
import "obi"
```

4. Create a server, register routes, and start listening:

```odin
package main

import "core:fmt"
import "obi"

main :: proc() {
    server := obi.new_server()

    obi.get(&server, "/hello", proc(req: ^obi.Request, res: ^obi.Response) {
        obi.send_text(res, "Hello from Obi")
    })

    err := obi.listen_and_serve(&server, "127.0.0.1", 8080)
    if err != .None {
        fmt.eprintln("listen_and_serve: ", err)
    }
}
```

As long as the project root contains the [obi](obi) package directory, Odin will resolve the import automatically.

## Example usage

The sample app in [main.odin](main.odin) shows the basic pattern for creating a server and registering handlers:

```odin
package main

import "core:fmt"
import "obi"

main :: proc() {
    server := obi.new_server()
    server.log = true

    obi.get(&server, "/hello", proc(req: ^obi.Request, res: ^obi.Response) {
        res.status = .OK
        obi.send_text(res, "Hello, World!")
    })

    err := obi.listen_and_serve(&server, "127.0.0.1", 8080)
    if err != .None {
        fmt.eprintln("listen_and_serve: ", err)
        return
    }
}
```

### Defining routes

Routes are registered with helper functions such as `obi.get` and `obi.post`:

```odin
obi.get(&server, "/health", proc(req: ^obi.Request, res: ^obi.Response) {
    res.status = .OK
    obi.send_text(res, "ok")
})
```

### Parameterized routes

Routes can include dynamic segments:

```odin
obi.get(&server, "/users/:id", proc(req: ^obi.Request, res: ^obi.Response) {
    res.status = .OK
    obi.send_text(res, "User ID: " + req.params[0].value)
})
```

### Sending responses

Responses can be built with the helper functions in the framework:

```odin
obi.send_text(res, "Hello from Obi")
```

You can also set a custom status and add headers:

```odin
res.status = .Created
obi.response_header(res, "Content-Type", "application/json")
obi.response_write_string(res, "{\"ok\":true}")
```

## Structure of the repository

- [main.odin](main.odin) — example application entry point
- [obi/server.odin](obi/server.odin) — server lifecycle and route registration
- [obi/router.odin](obi/router.odin) — route matching and parameterized path handling
- [obi/request.odin](obi/request.odin) — request parsing and request model
- [obi/response.odin](obi/response.odin) — response building and sending
- [obi/connection.odin](obi/connection.odin) — connection handling and request dispatch

## Current behavior and limitations

Obi is already usable for basic HTTP server tasks, but it is still an early implementation. Some important limitations to keep in mind:

- The current server uses a simple HTTP/1.0-style model with one request per connection
- Keep-alive is not yet implemented
- Middleware and request context support are not yet available
- The framework is focused on core request/response flow rather than advanced web features

These limitations are intentional while the library is still evolving.

## Roadmap

Planned improvements include:

1. Keep-alive support for persistent connections
2. Context propagation for handlers and middleware
3. Middleware registration and execution flow
4. More robust request and response helpers
5. Better examples and documentation as the feature set grows

## Contributing

Contributions are welcome. If you want to improve the router, expand the response helpers, or add new features, feel free to open a pull request or start a discussion around the repository.
