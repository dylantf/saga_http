# saga_http library guide

A how-to for building on top of `saga_http`. The intended consumer is a
router or framework author; this guide assumes you can read Saga already
and just need to know what this library exposes and how to wire it. For
language syntax see [`llms-full.txt`](../../saga-website/public/llms-full.txt).

This library does HTTP/1.1 parsing, response encoding, connection
management, and graceful shutdown. It does not do routing, query
parsing, cookies, or anything else listed under
[Out of scope](#what-this-library-does-not-do).

---

## 1. Quick start

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

---

## 2. The request model

```saga
pub record Request {
  method: String,
  path: String,
  target: RequestTarget,
  version: HttpVersion,
  headers: List (String, String),
  body: Maybe BitString,
  peer: (String, Int),
}
```

**`method`** — the raw method token off the wire, uppercase by
convention but not normalized. The library does not restrict the
method set; `BREW` will reach your handler.

**`path`** — a convenience derived from `target`. For `Origin` it's
the path without the query string; for `Absolute` it's the full URI;
for `Authority` it's the host:port string; for `Asterisk` it's `"*"`.

**`target`** — the parsed RFC 9112 §3.2 request-target:

```saga
pub type RequestTarget =
  | Origin String (Maybe String)   # path, optional query
  | Absolute String                # full URI; only valid for proxy-style
  | Authority String               # host:port; CONNECT only
  | Asterisk                       # "*"; OPTIONS only
```

Origin-form covers nearly all direct requests. Absolute-form appears
when the client is talking to a forward proxy. Authority-form is
restricted to `CONNECT`. Asterisk-form is restricted to `OPTIONS`.
Mismatched method/form combinations are rejected with 400 before your
handler runs.

If you need the query string, get it from `target`:

```saga
case req.target {
  Origin p (Just qs) -> ...
  Origin p Nothing   -> ...
  _ -> ...
}
```

Query *parsing* is not provided. See [out of scope](#what-this-library-does-not-do).

**`version`** — `Http1_0 | Http1_1`. Any other version (HTTP/0.9,
HTTP/2.0, garbage) is rejected at the parser with 505 *HTTP Version
Not Supported*; you won't see those requests.

**`headers`** — list of `(name, value)` in wire order. Header names
arrive **lowercased** (case-insensitive matching per RFC 9110).
Duplicates are preserved. For lookup use:

```saga
pub fun find_header : String -> List (String, String) -> Maybe String
pub fun find_all_headers : String -> List (String, String) -> List String
```

`find_header` is case-insensitive on the lookup key. Use
`find_all_headers` for headers that legitimately repeat (`Set-Cookie`,
`Cache-Control`, `Vary`).

**`body`** — `Just bytes` when the request had a body
(`Content-Length > 0` or `Transfer-Encoding: chunked`), `Nothing`
otherwise. Chunked bodies are fully buffered before your handler is
called; the library does not currently support streaming request
bodies into a handler. The buffered body is capped by
`Config.max_body_size`.

**`peer`** — `(ip, port)` of the connecting client, resolved once per
connection via `Tcp.peername`. Falls back to `("", 0)` if peername
failed at connection setup (a `PeerAddressUnavailable` event fires in
that case).

---

## 3. The response model

```saga
pub record Response {
  status: Int,
  headers: List (String, String),
  body: ResponseBody,
}

pub type ResponseBody =
  | Buffered String
  | BufferedBytes BitString
  | Streamed (Unit -> Unit needs {Chunked})
```

You can build a `Response` directly, but the constructors cover the
common cases:

```saga
pub fun text   : Int -> String -> Response                                          # Content-Type: text/plain
pub fun bytes  : Int -> List (String, String) -> BitString -> Response              # no default Content-Type
pub fun stream : Int -> List (String, String) -> (Unit -> Unit needs {Chunked}) -> Response
```

`text` defaults `Content-Type: text/plain`; `bytes` does not, because
binary payloads vary (`image/png`, `application/octet-stream`, …)
and guessing would be worse than forcing the caller to be explicit.

### Streaming

`stream` takes a producer function that runs under the `Chunked`
effect. Each `write_chunk!` is sent as a single Transfer-Encoding
chunk; the terminating zero-chunk is emitted when the producer
returns.

```saga
fun handle : Request -> Response
handle _ = stream 200 [("Content-Type", "text/plain")] (fun () -> {
  write_chunk! (BitString.from_string "alpha")
  write_chunk! (BitString.from_string "beta")
})
```

The library strips any user-supplied `Content-Length` and sets
`Transfer-Encoding: chunked` automatically on streamed responses
(mixing the two is a smuggling vector). Zero-length writes are
elided. If a write fails mid-stream a `SendFailed SendChunk` event
fires and the producer's continuation is dropped — your handler is
not resumed, the connection is closed.

`Chunked` is only in scope inside the `stream` producer. You cannot
call `write_chunk!` from your top-level handler; the body has to be
`Streamed` for it to be available.

### Header sanitization

When a response is sent:

- Header names that contain non-`tchar` bytes (CTLs, whitespace, `:`,
  high-bit bytes, …) are **dropped silently** to defend against
  user-controlled name smuggling.
- CR and LF bytes in header values are **replaced with space** to
  prevent response splitting. The header still goes out, just
  neutralised.

`Date` and `Server` are injected automatically unless you've set them
yourself (case-insensitively). Set `Config.server_name = ""` to omit
`Server` entirely.

### Pre-built error responses

For when you need to short-circuit:

```saga
pub val bad_request           # 400, Connection: close
pub val request_timeout       # 408, Connection: close
pub val payload_too_large     # 413, Connection: close
pub val expectation_failed    # 417, Connection: close
pub val version_not_supported # 505, Connection: close
```

These are values, not functions. The parser uses the same set when it
rejects a request; you'd typically reach for them only if you're
running a custom connection loop (see Recipe B below).

`status_text : Int -> String` covers the common reason phrases and
returns `"Unknown"` for anything not in the table. TODO: the table is
small; if you need full coverage you'll want to wrap this.

---

## 4. Server lifecycle

```saga
pub fun serve : Config -> (Request -> Response) -> Result ShutdownHandle String
  needs {Process, Actor SupMsg, Monitor, Timer, Server}
```

`serve` is **non-blocking**. It listens, spawns a supervisor that
owns the listener, spawns an acceptor that does the blocking
`Tcp.accept`, and returns. The supervisor tracks every live
connection process.

Two ways to wait on it:

```saga
pub fun await_shutdown    : ShutdownHandle -> Unit
pub fun shutdown_and_wait : ShutdownHandle -> Int -> ShutdownResult
```

- `await_shutdown` monitors the supervisor and returns when it dies,
  for any reason. Useful in `main` to keep the executable alive.
- `shutdown_and_wait h deadline_ms` initiates a graceful drain: closes
  the listener (stops accepting), closes every tracked connection
  socket (wakes any blocked `Tcp.recv` so the handler exits), then
  waits for handlers to finish via `Monitor`. Returns:

```saga
pub type ShutdownResult =
  | Drained        # all handlers exited within the deadline
  | TimedOut       # deadline expired; count is in ShutdownTimedOut event
  | NoReply        # supervisor died for an unexpected reason
```

Handlers mid-response when shutdown begins will see a truncated send
on a dead socket — that's the cost of bounded shutdown.

See [`src/Main.saga`](../src/Main.saga) for a SIGTERM-driven wiring
example.

### The `Server` effect

```saga
pub effect Server { fun event : ServerEvent -> Unit }
```

Every `serve` invocation needs a `Server` handler in scope. The
events cover places the library previously dropped errors silently:

| Variant | Meaning |
| --- | --- |
| `AcceptError String` | `accept()` returned an error; acceptor exits |
| `ClientDisconnected` | peer closed during the initial header read |
| `IdleTimeout` | idle/read timeout during the header read |
| `RequestParseError ParseError` | parse failed; error response already sent |
| `HeadersTooLarge` | cumulative header cap exceeded; 400 sent |
| `BodyReadFailed String` | `recv` failed mid-body; arg is the gen_tcp atom |
| `BodyReadDeadlineExceeded` | cumulative body-read deadline expired; 408 sent |
| `SendFailed SendSite String` | `Tcp.send` failed at the named site |
| `OwnershipTransferFailed String` | `gen_tcp:controlling_process` failed |
| `PipelinedRequestDropped` | leftover bytes after a request; connection closed |
| `ConnectionLimitReached` | `max_connections` cap hit; new socket dropped |
| `ShutdownTimedOut Int` | drain deadline expired; arg is connections still alive |
| `PeerAddressUnavailable String` | `Tcp.peername` failed; `req.peer = ("", 0)` |

`SendSite` distinguishes which send failed: `SendResponse`,
`SendChunk`, `SendChunkTerminator`, `SendContinue`.

Two ready-made handlers ship with the library:

```saga
pub handler discard_events for Server { event _ = resume () }
pub handler print_events   for Server { event e = { dbg e; resume () } }
```

`discard_events` for tests and benchmarks; `print_events` for
development. For production you'll want your own handler that
forwards to structured logging or metrics.

---

## 5. Configuration

```saga
pub record Config { ... }
pub val default_config : Config
```

Use record update to customise:

```saga
serve { default_config | port: 4000, max_body_size: 4 * 1024 * 1024 } handle
```

Fields, grouped by purpose:

### Identity

| Field | Default | Notes |
| --- | --- | --- |
| `port` | `8080` | TCP port to listen on |
| `server_name` | `"saga_http"` | Sent as `Server:` header; `""` opts out |

### Framing limits

| Field | Default | Notes |
| --- | --- | --- |
| `max_body_size` | `1048576` | Cap on request body bytes (CL or chunked total) |
| `max_header_size` | `8192` | Per-line cap (request line or any single header line) |
| `max_chunk_line_size` | `1024` | Cap on a chunk-size line (hex + optional `;ext`) |
| `max_trailer_size` | `8192` | Cap on the trailer section after the final 0-chunk |
| `max_request_headers_size` | `65536` | Cap on cumulative request line + headers (slowloris defense) |
| `max_header_count` | `100` | Cap on number of headers in a request |

### Timeouts

| Field | Default | Notes |
| --- | --- | --- |
| `idle_timeout_ms` | `30000` | Wait for *next* request on a keep-alive socket |
| `read_timeout_ms` | `30000` | Wait for individual reads mid-request (body, chunks, trailers) |
| `total_body_timeout_ms` | `60000` | Cumulative wall-clock deadline for reading one body |

### Capacity

| Field | Default | Notes |
| --- | --- | --- |
| `max_connections` | `10000` | Simultaneously-tracked connections; over-cap sockets are dropped |

---

## 6. Architectural recipes

### Recipe A: build a router on top of `serve`

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

### Recipe B: build a custom connection loop

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

---

## 7. What this library does NOT do

This is a low-level HTTP library: parse a request off a socket, build
a response, write it back. The following belong in a router or
framework built on top, not here. See
[Out of scope](planning/http1.md#out-of-scope-framework--router-concerns)
in the roadmap for the authoritative list.

- **Routing** — method/path matching, path parameters, route trees
- **Query string parsing** — `?foo=bar` is left as a raw string on
  `RequestTarget.Origin`; parsing it into a `Dict` is your router's
  job
- **Cookie parsing** and `Set-Cookie` builders
- **Typed header builder helpers** — Content-Type sugar, redirect
  helpers, cache-control DSLs
- **JSON request/response helpers**
- **Static file serving** — content-type detection, range requests,
  cache headers
- **Sessions, CSRF tokens, signed cookies, auth middleware**

If you find yourself wanting one of those, you're writing the
framework that sits on top of this library, not patching this one.
