# saga_http roadmap

## Done

- [x] TCP primitives (listen, accept, recv, send, close)
- [x] HTTP request parsing (request line, headers, body via Content-Length)
- [x] HTTP response encoding (status line, headers, body)
- [x] Keep-alive (connection reuse)
- [x] One process per connection
- [x] Case-insensitive header storage

## HTTP/1.1 protocol

- [ ] Chunked transfer encoding (request) - parse `Transfer-Encoding: chunked` bodies
- [ ] Chunked transfer encoding (response) - stream response bodies in chunks
- [ ] Connection handling - HTTP/1.0 defaults to close, HTTP/1.1 defaults to keep-alive. Currently we always assume keep-alive.
- [ ] Error responses - return 400 Bad Request for malformed requests instead of silently closing
- [ ] Size limits - reject headers and bodies that exceed configurable max sizes
- [ ] 100 Continue - respond with `100 Continue` when client sends `Expect: 100-continue`
- [ ] HEAD requests - same as GET but skip the response body

## Future

- [ ] HTTP/2
- [ ] TLS (wrap ssl module alongside gen_tcp)
- [ ] WebSockets
