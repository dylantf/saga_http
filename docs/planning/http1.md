# saga_http roadmap

## Done

- [x] TCP primitives (listen, accept, recv, send, close)
- [x] HTTP request parsing (request line, headers, body via Content-Length)
- [x] HTTP response encoding (status line, headers, body)
- [x] Keep-alive (connection reuse)
- [x] One process per connection
- [x] Case-insensitive header storage
- [x] Chunked transfer encoding (request) - parse `Transfer-Encoding: chunked` bodies
- [x] Chunked transfer encoding (response) - stream response bodies via the `Chunked` effect (`Http.stream` constructor + `write_chunk!`)
- [x] Connection handling - HTTP/1.0 defaults to close, HTTP/1.1 defaults to keep-alive
- [x] Error responses - 400 Bad Request for malformed requests
- [x] HEAD requests - skip the response body
- [x] Body size limits - reject bodies exceeding configurable `max_body_size`
- [x] BitString-based wire data - `Tcp.recv`/`Tcp.send` and parsing operate on bytes, not codepoints
- [x] Header size limits - configurable `max_header_size`, `max_chunk_line_size`, `max_trailer_size` on `Config`
- [x] 100 Continue - interim `100 Continue` for HTTP/1.1 clients with `Expect: 100-continue`; ignored for HTTP/1.0; unsupported Expect values → 417
- [x] Multi-value headers - headers are now `List (String, String)` preserving order and duplicates; helpers `find_header` (first match, case-insensitive) and `find_all_headers` (all matches) for lookup; `replace_header` for server-controlled overrides
- [x] Date / Server response headers - injected by `send_response` via `set_default_header` (user-supplied values take precedence); `Server` is configurable via `Config.server_name` ("" to opt out)
- [x] Idle / keep-alive and per-read timeouts - separate `Config.idle_timeout_ms` (next-request wait on keep-alive) and `Config.read_timeout_ms` (mid-request body/chunk reads), both default 30000ms
- [x] Fragmented header reads - keep reading until the header terminator (`\r\n\r\n`) before parsing, instead of assuming one TCP read contains the whole header section
- [x] Cumulative request-header cap - configurable `max_request_headers_size` limits the full request line + headers section, not only individual lines
- [x] Response header sanitization - validate response header names as HTTP tokens and neutralize CR/LF in response header values
- [x] Request smuggling defenses - reject `Transfer-Encoding` + `Content-Length`, conflicting duplicate `Content-Length`, malformed/negative `Content-Length`, duplicate `Transfer-Encoding` header lines, and malformed chunk-size lines
- [x] Streamed response framing - strip user-provided `Content-Length` from streamed responses and emit `Transfer-Encoding: chunked`
- [x] Connection token parsing - parse comma-separated `Connection` values case-insensitively (`close`, `keep-alive`, etc.)
- [x] Pipelining policy enforcement - detect leftover bytes after a request and close the connection instead of dropping or accidentally processing pipelined requests
- [x] Server-side error observability - typed `Server` effect with `ServerEvent` variants (`AcceptError`, `ClientDisconnected`, `IdleTimeout`, `RequestParseError`, `HeadersTooLarge`, `BodyReadFailed`, `SendFailed`, `OwnershipTransferFailed`, `PipelinedRequestDropped`, `ShutdownTimedOut`); ships with `discard_events` and `print_events` default handlers
- [x] Graceful shutdown - `serve` returns a `ShutdownHandle` after spawning a supervisor + acceptor; `shutdown_and_wait handle deadline_ms` closes the listener, force-closes all tracked connection sockets so blocked recvs (idle keep-alive, mid-headers, mid-body) wake immediately, drains via `Monitor`, and returns `Drained` / `TimedOut` / `NoReply`. `await_shutdown handle` blocks until the supervisor exits. `Main.saga` wires this to `Std.Process.Signal`: first SIGTERM begins drain, second force-exits via `Process.exit 1`. Trade-off: requests that are mid-response when shutdown is triggered get a truncated response.

## Explicit HTTP/1.1 choices

- Request pipelining — do not support it. Clients deprecated it (Chrome years ago, Firefox by default). If a pipelined follow-up request is detected in the parser buffer, respond to the first request and close the connection.
- Chunked request trailers — currently consumed and ignored. Decide later whether to expose them, validate them more deeply, or keep ignoring them as documented behavior.
- Reverse-proxy edge hardening — not yet a goal. The parser is much less naive now, but this is not intended to compete with Cowboy/Hyper as a hardened public edge server yet.

## HTTP/1.1 core backlog

- [ ] Transfer-Encoding list parsing - decide whether to support ordered values like `Transfer-Encoding: gzip, chunked`; otherwise reject anything except a single final `chunked` token with clear tests
- [ ] Request target forms - decide and test origin-form (`/path`), absolute-form (`http://host/path`), authority-form (`CONNECT host:port`), and asterisk-form (`OPTIONS *`)
- [ ] Method validation policy - decide whether to accept arbitrary token methods or restrict/normalize common methods
- [ ] HTTP version policy - decide whether unknown versions should be rejected instead of mapped to `Http1_0`
- [ ] Trailer policy - decide whether to expose trailers, validate them, or keep ignoring them as an explicit documented choice
- [ ] More status reason phrases - fill out common HTTP status text values, or consider standardizing/omitting reason phrases
- [ ] Binary buffered responses - add a `BufferedBytes BitString` response body variant so non-text responses do not require streaming
- [ ] Maximum request count per connection - configurable cap for long-lived keep-alive connections
- [ ] Maximum header count - complement byte-size limits and prevent many tiny headers from stressing parser/list work

## Security / robustness

- [ ] Backpressure / connection limits - cap concurrent accepted connections and define behavior when saturated
- [ ] Total body-read deadline - per-read timeouts exist; consider a total deadline for reading a request body
- [ ] Public-internet hardening pass - review request smuggling, malformed chunk extensions, odd whitespace, absolute-form targets, and proxy-facing behavior

## Performance / scalability

- [ ] Benchmark suite - add repeatable benchmarks for hello world, keep-alive, POST bodies, chunked request bodies, streamed responses, slow clients, and realistic handler work
- [ ] Compare against Cowboy and Express - use the same workload, concurrency, keep-alive settings, response body sizes, and machine
- [ ] Track latency percentiles - report p50/p95/p99, not only requests/sec
- [ ] Track BEAM/runtime stats - memory, process count, port count, reductions, scheduler utilization, run queue, and garbage collections
- [ ] Acceptor pool - evaluate multiple acceptor processes instead of one recursive accept loop
- [ ] Connection limits - cap max concurrent connections and define overload behavior
- [ ] Request limits - cap max requests per keep-alive connection
- [ ] Socket option tuning - evaluate `nodelay`, send/recv buffer sizes, send timeouts, backlog size, and OS file-descriptor limits
- [ ] Parser allocation profile - measure cost of `BitString` concatenation, header scanning, lowercasing, and list accumulation under load
- [ ] Header parsing stress tests - many small headers, large-but-valid headers, fragmented headers, and malicious slow header sends
- [ ] Body read stress tests - large bodies, fragmented bodies, slow bodies, and pipelined bytes after bodies
- [ ] Streaming response backpressure - measure slow-reader behavior and memory growth while producing chunks
- [ ] Idle connection scale test - measure memory and scheduler behavior with many idle keep-alive sockets
- [ ] Graceful overload story - decide whether to close, return 503, shed accepts, or apply per-IP/per-listener limits

## Protocol features

- [ ] TLS (wrap ssl module alongside gen_tcp)
- [ ] WebSockets
- [ ] Optional HTTP pipelining support - only if a real use case appears; current policy is close-on-detected-pipelining

## Framework ergonomics

- [ ] Router helper - route by method/path with path parameters
- [ ] Query string parser - expose parsed query params
- [ ] Request metadata - peer address, local address, scheme, and raw target where useful
- [ ] Header builder helpers - safer typed helpers for common response headers: content type, cache control, redirects, cookies
- [ ] Cookie helpers - parse request cookies and build `Set-Cookie`
- [ ] JSON helpers - optional request/response convenience once Saga has the right ecosystem pieces
- [ ] Static file response helper - content type detection, range policy decision, cache headers

## Documentation

- [ ] Supported HTTP/1.1 subset - document no pipelining, transfer-encoding scope, trailer behavior, request target forms, and parser limits
- [ ] Security limits and defaults - document body size, per-line header size, cumulative header size, trailer size, read timeout, and idle timeout
- [ ] Deployment stance - spell out that the current server is suitable for local/internal/behind-proxy use, not yet as a hardened public edge server
