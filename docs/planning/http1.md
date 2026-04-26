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

## HTTP/1.1 protocol

- [ ] Multi-value headers - `Dict String String` overwrites repeated headers. Matters for `Set-Cookie`, `Cache-Control`, etc. Switch to `Dict String (List String)` or comma-join per RFC 7230 §3.2.2.
- [ ] Date / Server response headers - RFC SHOULD include both. Trivial to add in `encode_buffered_bytes` / `encode_streamed_head`.
- [ ] Request pipelining - after parsing, leftover bytes in `rest` are discarded, so pipelined clients lose requests. Spec requires support; real-world clients rarely pipeline, but the gap should be a known limitation or fixed by threading the leftover buffer through `handle_connection`'s loop.
- [ ] Idle / keep-alive timeouts - currently a 30s `Tcp.recv` timeout doubles as the keep-alive idle timeout. Make it a `Config` knob, separate from per-read timeouts.
- [ ] Server-side error observability - introduce a typed effect (e.g. `Server` with `ServerEvent` variants for `ClientDisconnected`, `ParseError`, `AcceptError`) that the consumer handles at `serve` to log/metric/discard. Currently chunked send failures are `dbg`'d inline and parse errors are silent.

## Future

- [ ] TLS (wrap ssl module alongside gen_tcp)
- [ ] WebSockets
