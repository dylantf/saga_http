# Architectural recipes

## Recipe A: build a router on top of `serve`

The handler shape `serve` takes is **pure**: `Request -> Response`,
no effects. This is the cheapest way to get going — the router does
its own matching, returns a `Response`, and `serve` handles the
socket lifecycle.

```saga
type Route = Route String String (Request -> Response)

fun route_table : List Route
route_table = [
  Route "GET" "/users"  list_users,
  Route "POST" "/users" create_user,
]

fun match_route : List Route -> Request -> Response
match_route routes req = case routes {
  [] -> text 404 "not found"
  (Route m p h) :: rest ->
    if req.method == m && req.path == p then h req
    else match_route rest req
}

fun app : Request -> Response
app = match_route route_table

main () = {
  case serve default_config app {
    Ok h -> await_shutdown h
    Err e -> dbg e
  }
} with {beam_actor, discard_events}
```

**Limitation:** because the handler signature is `Request -> Response`
with no `needs` clause, your route handlers can't perform effects.
No logging, no DB access, no IO from a route. If your router is just
proving out routing design with static responses, this is fine. As
soon as a handler needs effects, switch to Recipe B.

## Recipe B: build a custom connection loop

If your handlers need effects, run your own loop using the parsing
primitives directly. The relevant public surface:

```saga
pub fun parse_request : Config -> Tcp.Socket -> (String, Int) -> BitString
  -> Result (Request, BitString) ParseError
  needs {Server}

pub fun send_response : Config -> Tcp.Socket -> HttpVersion -> String -> Response
  -> Unit needs {Server}

pub fun should_keep_alive : Request -> Bool
```

The shape of one connection:

1. Resolve the peer once (`Tcp.peername`).
2. Read from the socket until you've buffered the full header section
   (everything up to and including `\r\n\r\n`).
3. Call `parse_request` with that buffer. It will read the body from
   the socket itself (Content-Length or chunked) and return the
   parsed `Request` plus any leftover bytes.
4. Call your effectful handler. The handler can have any `needs`
   clause your application provides handlers for at the outer
   boundary.
5. `send_response config socket req.version req.method resp`.
6. If `leftover` is non-empty, the client pipelined a follow-up
   request. Close the connection (we don't support pipelining).
7. Otherwise consult `should_keep_alive req` to decide whether to
   loop or close.

Sketch:

```saga
fun my_loop : Config -> Tcp.Socket -> (String, Int) -> Unit
  needs {Server, MyEffect}
my_loop config sock peer = {
  case read_headers sock <<>> config.idle_timeout_ms {
    Err _ -> Tcp.close sock
    Ok buf -> case parse_request config sock peer buf {
      Err err -> {
        event! (RequestParseError err)
        send_response config sock Http1_1 "GET" bad_request   # pick by err
        Tcp.close sock
      }
      Ok (req, leftover) -> {
        let resp = my_effectful_handler req
        send_response config sock req.version req.method resp
        if BitString.size leftover > 0 then {
          event! PipelinedRequestDropped
          Tcp.close sock
        }
        else if should_keep_alive req then my_loop config sock peer
        else Tcp.close sock
      }
    }
  }
}
```

**Honest caveats about what's exported today:**

- `read_until_headers_complete` (the helper that reads the socket
  until `\r\n\r\n` is buffered, with the slowloris cap) is **not
  `pub`**. To use Recipe B you have to either reimplement it or
  request that it be exported. The same goes for `find_crlf`,
  `header_section_size`, `read_line`, `read_n`. TODO: these would
  benefit from a public helper — likely a single `read_request_head`
  that returns the buffer ready for `parse_request`.
- Mapping `ParseError` back to the right canned response
  (`bad_request`, `payload_too_large`, `expectation_failed`,
  `version_not_supported`, `request_timeout`) is currently done
  inline inside `handle_connection`; you'll need to duplicate that
  small case-of for now.
- `handle_connection` itself is `pub` and does steps 1–7 for you,
  but it takes the same pure `Request -> Response` shape as
  `serve` — so it doesn't help with the effects problem.

If you're running Recipe B inside the supervisor that `serve`
provides, you can't: `serve`'s entry point is hard-wired to
`handle_connection`. For now, a custom loop means spawning your own
listener with `Tcp.listen` / `Tcp.accept` and giving up the supervisor
and graceful-shutdown machinery this library ships. TODO: a future
`serve_with` that accepts an arbitrary connection handler would close
this gap.
