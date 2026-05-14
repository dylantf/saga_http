# SagaHttp

A low-level HTTP library for the [Saga](https://saga-lang.org) language, built on top of Erlang's `gen_tcp`. Covers HTTP/1.0 and HTTP/1.1.

> **Status: Work in progress.** Not ready for production use. APIs and behavior may change without notice.

## About

SagaHttp handles request parsing, response encoding, connection lifecycle, and graceful shutdown — the wire-level concerns of an HTTP/1.1 server. Routing, query parsing, cookies, JSON helpers, and other framework concerns are deliberately left to libraries built on top.

Each connection runs in its own lightweight BEAM process via Saga's actor pattern and effect system. A supervisor owns the listener and tracks every live connection; an acceptor process hands new sockets to per-connection handler processes. Concurrency and multi-core scheduling come for free from the BEAM — there's no thread pool to size, no event loop to share, and a crash in one request can't take down others. Shutdown is bounded and cooperative: the listener stops accepting, in-flight sockets are closed, and handlers are awaited to a deadline.

## Requirements

- Erlang/OTP 27
- The [Saga compiler](https://saga-lang.org)

## Install

Add to your `project.toml`:

```toml
[deps]
saga_http = { git = "https://github.com/dylantf/saga_http" }
```

## Quick start

```saga
module Main

import Std.Actor (beam_actor)
import SagaHttp.Http (serve, await_shutdown, default_config, text,
                      Request, Response, print_events)

fun handle : Request -> Response
handle req = text 200 $"hello {req.path}"

main () = {
  case serve default_config handle {
    Err e -> dbg ("startup failed", e)
    Ok h -> await_shutdown h
  }
} with {beam_actor, print_events}
```

See the [library guide](./docs/library-guide.md) for more.

## Modules

- `SagaHttp.Tcp` — TCP server/socket primitives
- `SagaHttp.Http` — HTTP/1.0 and HTTP/1.1 request/response handling

## Documentation

- [Library guide](./docs/library-guide.md)
- [API reference](./docs/library/)
