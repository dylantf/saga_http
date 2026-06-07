---
title: SagaHttp.Http
---

Low-level HTTP/1.1 server: request parsing, response encoding, connection lifecycle, supervised listener with graceful shutdown.

Consumers typically reach for `serve` plus a `Request -> Response`
handler; routers, effectful handlers, and anything more elaborate live
in libraries built on top. See `docs/guide/` for a how-to-use
overview and `docs/planning/http1.md` for the roadmap and explicit
scope decisions.

## Types

### HeaderResult

```saga
type HeaderResult =
  | Header String String BitString
  | Done BitString
```

Result of one `decode_header` call: either a parsed `(name, value)` pair
plus the unconsumed bytes, or `Done rest` indicating the headers section
has terminated and `rest` is the start of the body.

### HttpVersion

```saga
type HttpVersion =
  | Http1_0
  | Http1_1
```

HTTP versions this library accepts. Anything else (HTTP/0.9, HTTP/2.0,
malformed) is rejected at the parser with 505 — handlers never see it.

### RequestTarget

```saga
type RequestTarget =
  | Origin String (Maybe String)
  | Absolute String
  | Authority String
  | Asterisk
```

RFC 9112 §3.2 request-target forms. `path` on `Request` is still derived
from this (path portion for Origin/Absolute, the authority string for
Authority, "\*" for Asterisk) so existing handlers that only look at
`req.path` keep working; new code can match on `req.target` directly.

### Request

```saga
record Request {
  method: String,
  path: String,
  target: RequestTarget,
  version: HttpVersion,
  headers: List (String, String),
  body: Maybe BitString,
  peer: (String, Int)
}
```

Parsed HTTP request handed to user code. Header names are lowercased;
`body` is `Just` for requests with a Content-Length or chunked body and
`Nothing` otherwise; `peer` is resolved once per connection.

### ResponseBody

```saga
type ResponseBody =
  | Buffered String
  | BufferedBytes BitString
  | Streamed (Unit -> Unit needs {Chunked})
```

How a `Response` body is delivered. `Buffered`/`BufferedBytes` are sent as
a single Content-Length response; `Streamed` switches the response to
`Transfer-Encoding: chunked` and runs the producer to generate chunks.

### Response

```saga
record Response {
  status: Int,
  headers: List (String, String),
  body: ResponseBody
}
```

Outgoing response. Build directly or use the `text` / `bytes` / `stream`
constructors. `Date` and `Server` are injected at send time unless the
user has set them already (case-insensitive).

### ParseError

```saga
type ParseError =
  | BadRequest
  | PayloadTooLarge
  | ExpectationFailed
  | UnsupportedVersion
  | BodyReadTimeout
```

Reasons `parse_request` can fail. Each maps to a canned response in the
default connection loop: 400, 413, 417, 505, 408 respectively.

### SendSite

```saga
type SendSite =
  | SendResponse
  | SendChunk
  | SendChunkTerminator
  | SendContinue
```

Identifies which `Tcp.send` failed inside a `SendFailed` event so consumers
can distinguish, say, "lost the client mid-stream" from "couldn't even
send the response head."

### ServerEvent

```saga
type ServerEvent =
  | AcceptError String
  | ClientDisconnected
  | IdleTimeout
  | RequestParseError ParseError
  | HeadersTooLarge
  | BodyReadFailed String
  | BodyReadDeadlineExceeded
  | SendFailed SendSite String
  | OwnershipTransferFailed String
  | PipelinedRequestDropped
  | ConnectionLimitReached
  | ShutdownTimedOut Int
  | PeerAddressUnavailable String
```

Server-side observability events. Consumers attach a `Server` handler at
the `serve` boundary to log/metric/discard. Events cover the cases where
we previously dropped errors silently or `dbg`'d them inline.

### Config

```saga
record Config {
  port: Int,
  max_body_size: Int,
  max_header_size: Int,
  max_chunk_line_size: Int,
  max_trailer_size: Int,
  max_request_headers_size: Int,
  server_name: String,
  idle_timeout_ms: Int,
  read_timeout_ms: Int,
  total_body_timeout_ms: Int,
  max_connections: Int,
  max_header_count: Int
}
```

Tunables for a `serve` call. Most consumers start from `default_config`
and override fields with record-update syntax. See the per-field comments
below and `docs/guide/configuration.md` for grouped descriptions.

### ShutdownHandle

```saga
opaque type ShutdownHandle
```

### ShutdownResult

```saga
type ShutdownResult =
  | Drained
  | TimedOut
  | NoReply
```

Outcome of `shutdown_and_wait`. `Drained` is the happy path; `TimedOut`
means the deadline fired before all handlers exited (the count is on
the corresponding `ShutdownTimedOut` event); `NoReply` means the
supervisor died unexpectedly or never responded.

## Effects

### Chunked

```saga
effect Chunked {
  fun write_chunk : BitString -> Unit
}
```

Effect available inside a `Streamed` response producer. Each `write_chunk!`
emits one Transfer-Encoding chunk; the zero-chunk terminator is sent
automatically when the producer returns.

### Server

```saga
effect Server {
  fun event : ServerEvent -> Unit
}
```

Observability effect. Every `serve` invocation needs a `Server` handler
in scope; the runtime emits a `ServerEvent` whenever something happens
outside the happy path (parse errors, send failures, timeouts, …).
`discard_events` and `print_events` are ready-made handlers.

## Handlers

### discard_events

```saga
handler discard_events for Server
```

Default no-op handler. Consumers in tests and benchmarks reach for this
when they don't care about events.

### print_events

```saga
handler print_events for Server
```

Debug handler that prints every event via `dbg`. Useful in `Main.saga`
during development; not appropriate for production where structured
logging or a metrics export is wanted instead.

## Values

### default_config

```saga
pub fun default_config : Config
```

Sensible defaults for local/internal deployments. Port 8080, 1MiB body
cap, 30s idle/read timeouts, 60s total body deadline, 10000 max
connections. Override with `{ default_config | field: ... }`.

### bad_request

```saga
pub fun bad_request : Int
```

Canned error responses used by the default connection loop when parsing
fails. All carry `Connection: close`. Reach for these when running your
own loop and you need to short-circuit before reaching a handler.

### request_timeout

```saga
pub fun request_timeout : Int
```

### payload_too_large

```saga
pub fun payload_too_large : Int
```

### expectation_failed

```saga
pub fun expectation_failed : Int
```

### version_not_supported

```saga
pub fun version_not_supported : Int
```

## Functions

### decode_request_line

```saga
fun decode_request_line : (data: BitString) -> (max_size: Int) -> Result (String, String, (Int, Int), BitString) String
```

Parse the request line off the front of `data`, returning
`(method, target, (major, minor), rest)`. `max_size` caps the request
line length; longer lines fail (→ 400 in the default loop).

### decode_header

```saga
fun decode_header : (data: BitString) -> (max_size: Int) -> Result HeaderResult String
```

Parse one header line off the front of `data`. See `HeaderResult`.
`max_size` caps the line length.

### current_http_date

```saga
fun current_http_date : Unit -> String
```

Returns the current UTC time as an IMF-fixdate string suitable for the
`Date` response header. NOT pure (it reads the system clock); typed as
pure for FFI ergonomics, matching the rest of our bridge surface.

### find_header

```saga
fun find_header : String -> List (String, String) -> Maybe String
```

First value matching `name`, case-insensitive. Returns Nothing if
the header isn't present. Use `find_all_headers` when a header may
legitimately appear more than once (e.g. `Set-Cookie`).

### find_all_headers

```saga
fun find_all_headers : String -> List (String, String) -> List String
```

All values matching `name`, in the order they appear. Useful for
headers that may legitimately repeat (`Set-Cookie`, `Cache-Control`,
`Vary`, etc.).

### replace_header

```saga
fun replace_header : String -> String -> List (String, String) -> List (String, String)
```

Replace any existing entries with this name (case-insensitively),
appending the new entry at the end. Used by encoders to set
server-controlled headers like Content-Length.

### set_default_header

```saga
fun set_default_header : String -> String -> List (String, String) -> List (String, String)
```

Append `(name, value)` only if no entry with this name (case-insensitively)
already exists. Used for headers we want to default but let the user override.

### text

```saga
fun text : Int -> String -> Response
```

Build a buffered text response with `Content-Type: text/plain`.

### bytes

```saga
fun bytes : Int -> List (String, String) -> BitString -> Response
```

Buffered binary response. Unlike `text`, no Content-Type is defaulted —
binary payloads vary (image/png, application/octet-stream, etc.), and
guessing here would be worse than forcing the caller to be explicit.

### stream

```saga
fun stream : Int -> List (String, String) -> Unit -> Unit needs {Chunked} -> Response
```

Build a chunked-streaming response. The producer runs after the response
head is sent; each `write_chunk!` flushes one chunk to the socket. Any
user-provided `Content-Length` is stripped (chunked framing replaces it).

### status_text

```saga
fun status_text : Int -> String
```

Standard reason phrase for an HTTP status code. Covers the codes this
library emits itself plus a handful of common ones; returns `"Unknown"`
for codes not in the table. Wrap if you need exhaustive coverage.

### encode_headers

```saga
fun encode_headers : List (String, String) -> String
```

Render a header list to its on-the-wire form (each line ending in CRLF,
no trailing blank line). Names that aren't valid HTTP tokens are dropped;
CR/LF in values is replaced with space. Mainly an implementation detail
of `send_response`, but exposed for callers building responses by hand.

### encode_response

```saga
fun encode_response : (method: String) -> Response -> BitString
```

Pure: encodes a buffered response as a single BitString.
Panics if called with a Streamed response — use send_response instead.

### remove_header

```saga
fun remove_header : String -> List (String, String) -> List (String, String)
```

Drop every entry with this name, case-insensitively.

### send_response

```saga
fun send_response : Config -> Tcp.Socket -> HttpVersion -> String -> Response -> Unit needs {Server}
```

Send a response on `socket`, choosing buffered or chunked framing based
on `resp.body`. Injects `Date` and `Server` (unless already present),
computes Content-Length for buffered bodies, and runs the producer for
streamed bodies. For HEAD requests, only the head is sent. Errors are
reported via `SendFailed` events; this function does not return them.

### parse_version

```saga
fun parse_version : (Int, Int) -> Result HttpVersion ParseError
```

Validate the `(major, minor)` tuple from the request line. Only 1.0 and
1.1 are accepted; anything else returns `UnsupportedVersion` (→ 505).

### parse_target

```saga
fun parse_target : String -> String -> Result RequestTarget ParseError
```

Parse the raw request-target string per RFC 9112 §3.2. The bridge hands
us the target verbatim; the four forms are distinguished syntactically
and constrained by method (asterisk-form is OPTIONS-only, authority-form
is CONNECT-only).

### parse_request

```saga
fun parse_request : Config -> Tcp.Socket -> (String, Int) -> BitString -> Result (Request, BitString) ParseError needs {Server}
```

Returns the parsed Request along with any leftover bytes after the body
(a non-empty leftover indicates a pipelined follow-up request, which we
don't support — the caller should close the connection).

### decode_headers

```saga
fun decode_headers : Config -> List (String, String) -> BitString -> Result (List (String, String), BitString) ParseError
```

Builds the headers list in reverse to keep insertion O(1), then reverses
at the end so the wire-order is preserved for the user.

### read_body

```saga
fun read_body : Config -> Tcp.Socket -> List (String, String) -> BitString -> Result (Maybe BitString, BitString) ParseError needs {Server}
```

Returns the parsed body (if any) along with any bytes that remained
in the buffer after the body. Callers should treat non-empty leftover
as a pipelined-request signal and close the connection (we don't
support pipelining — see docs/planning/http1.md).

### parse_chunk_size

```saga
fun parse_chunk_size : BitString -> Maybe Int
```

Parse a chunk-size line: leading hex digits, optionally followed by
chunk extensions (";name=value"). Returns Nothing if no hex digits.

### should_keep_alive

```saga
fun should_keep_alive : Request -> Bool
```

Decide whether to reuse the connection after this request. Honours the
`Connection` header tokens (`close`, `keep-alive`); falls back to the
version default (HTTP/1.1: keep-alive, HTTP/1.0: close).

### handle_connection

```saga
fun handle_connection : Config -> Tcp.Socket -> Request -> Response -> Unit needs {Server}
```

Run the full request/response loop on an accepted socket: resolve the
peer once, then read → parse → invoke `on_request` → send → loop while
the connection is keep-alive. Handles every error path internally
(parse errors, timeouts, disconnects, pipelining) and closes the socket
before returning. Used by `serve`; usable directly if you're running
your own listener.

### serve

```saga
fun serve : Config -> Request -> Response -> Result ShutdownHandle String needs {Process, Actor SupMsg, Monitor, Timer, Server}
```

Start the server. Non-blocking: opens the listener, spawns supervisor +
acceptor, returns a `ShutdownHandle`. The caller is expected to keep its
process alive (typically via `await_shutdown`) so the supervisor isn't
orphaned. Returns `Err` with a gen_tcp reason if `listen` fails or the
initial controlling-process transfer fails.

### shutdown_and_wait

```saga
fun shutdown_and_wait : ShutdownHandle -> Int -> ShutdownResult needs {Process, Actor msg, Monitor}
```

Synchronous shutdown. Sends the shutdown signal, monitors the supervisor,
waits for it to die, decodes the result from its exit reason. The caller's
mailbox type is unconstrained — `Down` system messages match any `Actor msg`.

`deadline_ms` is the supervisor's drain deadline. `shutdown_and_wait` itself
adds a small grace period on top so a non-responsive supervisor still
returns `NoReply` instead of hanging.

### await_shutdown

```saga
fun await_shutdown : ShutdownHandle -> Unit needs {Actor msg, Monitor}
```

Blocks the caller until the server's supervisor exits. Useful in `main`
so the executable doesn't return immediately after `serve`. Returns
normally on any supervisor exit reason — callers that care about the
distinction should use `shutdown_and_wait` instead.
