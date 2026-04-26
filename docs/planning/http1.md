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

## HTTP/1.1 protocol

- [ ] Header size limits - currently `max_chunk_line_size` and `max_trailer_size` are hardcoded; request header lines rely on `decode_packet` defaults. Make all of these configurable in `Config`.
- [ ] 100 Continue - respond with `100 Continue` when client sends `Expect: 100-continue`
- [ ] Server-side error observability - introduce a typed effect (e.g. `Server` with `ServerEvent` variants for `ClientDisconnected`, `ParseError`, `AcceptError`) that the consumer handles at `serve` to log/metric/discard. Currently chunked send failures are `dbg`'d inline and parse errors are silent.

## Future

- [ ] HTTP/2
- [ ] TLS (wrap ssl module alongside gen_tcp)
- [ ] WebSockets

## Future

- [ ] HTTP/2
- [ ] TLS (wrap ssl module alongside gen_tcp)
- [ ] WebSockets
