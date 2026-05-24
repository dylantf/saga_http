# Getting started

A how-to for building on top of `saga_http`. The intended consumer is a
router or framework author; this guide assumes you can read Saga already
and just need to know what this library exposes and how to wire it. For
language syntax see [`llms-full.txt`](../../../saga-website/public/llms-full.txt).

This library does HTTP/1.1 parsing, response encoding, connection
management, and graceful shutdown. Routing, query parsing, cookies,
and similar concerns are covered under [Scope](#scope).

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

`serve` returns immediately after the listener and supervisor are up;
`await_shutdown` blocks the main process so the executable doesn't
exit. A `Server` handler (here `print_events`) is required at the
`serve` boundary — use `discard_events` if you don't want logging.

## Scope

`saga_http` handles the wire: parsing requests, encoding responses,
and managing the connection lifecycle. For routing, middleware, and
the rest of the framework story, look at Edda.
