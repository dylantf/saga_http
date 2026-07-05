# The response model

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
  | WebSocketUpgrade WebSocket.Options (Unit -> Unit needs {WebSocket.WebSocket})
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

## Streaming

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

## WebSocket upgrades

`WebSocketUpgrade` is constructed by `websocket` and `websocket_with`, not by
ordinary response helpers. The connection loop sends `101 Switching Protocols`,
runs the WebSocket callback, then closes the HTTP connection instead of
returning to keep-alive handling. See [WebSockets](websockets.md).

## Header sanitization

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

## Pre-built error responses

For when you need to short-circuit:

```saga
pub fun bad_request           # 400, Connection: close
pub fun request_timeout       # 408, Connection: close
pub fun payload_too_large     # 413, Connection: close
pub fun expectation_failed    # 417, Connection: close
pub fun version_not_supported # 505, Connection: close
```

These are values, not functions. The parser uses the same set when it
rejects a request; you'd typically reach for them only if you're
running a custom connection loop (see
[Recipe B](recipes.md#recipe-b-build-a-custom-connection-loop)).

`status_text : Int -> String` covers the common reason phrases and
returns `"Unknown"` for anything not in the table. TODO: the table is
small; if you need full coverage you'll want to wrap this.
