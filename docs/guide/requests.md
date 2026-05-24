# The request model

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

Query *parsing* is not provided. See
[Scope](getting-started.md#scope).

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
