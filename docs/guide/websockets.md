# WebSockets

`saga_http` includes low-level WebSocket support for HTTP/1.1 upgrade
requests. It owns the protocol mechanics: handshake validation, frame
encoding/decoding, ping/pong, close frames, fragmentation, and socket
lifecycle. Routers and frameworks should wrap this API with their own route
ergonomics.

## Upgrade From A Handler

Use `websocket` inside a normal HTTP handler. Invalid upgrade requests return
`400 Bad Request`; valid requests send `101 Switching Protocols` and then run
the callback with the `WebSocket` effect.

```saga
import SagaHttp.Http (Request, Response, text, websocket)
import SagaHttp.WebSocket (WebSocket)

fun handle : Request -> Response
handle req =
  if req.path == "/ws" then websocket req socket
  else text 200 "connect to /ws"

fun socket : Unit -> Unit needs {WebSocket}
socket () = case read_message! () {
  Ok (Just (WebSocket.TextMessage text)) -> {
    let _ = send_text! ("echo:" <> text)
    ()
  }
  Ok (Just (WebSocket.BinaryMessage bytes)) -> {
    let _ = send_binary! bytes
    ()
  }
  Ok Nothing -> ()
  Err _ -> ()
}
```

Use `websocket_with` when you need explicit runtime limits.

```saga
let options = WebSocket.Options {
  max_frame_size: 1048576,
  max_message_size: 1048576,
  read_timeout_ms: 30000,
}
```

`max_frame_size` caps a single frame. `max_message_size` caps the assembled
message after continuations.

## Runtime Contract

The `WebSocket` effect exposes:

```saga
read_message! ()      # Result (Maybe Message) Error
send_text! text       # Result Unit Error
send_binary! bytes    # Result Unit Error
close_websocket! code reason
```

`read_message!` returns `Ok Nothing` after a valid close or disconnected peer.
Incoming ping frames are answered automatically before the next application
message is returned.

Concurrency rules:

- One active reader per WebSocket connection.
- Multiple sender processes may call `send_text!` or `send_binary!`.
- Send ordering across multiple sender processes follows BEAM scheduling and
  should not be treated as deterministic application ordering.
- `close_websocket!` can race with read or send calls; callers should handle
  `Ok Nothing`, `SendError`, or read errors after close.

Internally, the runtime stores connection state in `ets_ref` so a handler may
spawn helper processes that use the same `WebSocket` effect. For stricter
single-owner architectures, keep raw WebSocket calls in one connection process
and let other processes send it typed actor messages.

## Protocol Support

The runtime supports:

- masked client frames and unmasked server frames
- text and binary messages
- fragmented text/binary messages
- ping/pong control frames
- close code and UTF-8 reason validation
- separate frame and assembled-message limits

Deferred features include proactive heartbeat policy, subprotocol negotiation
helpers, and per-message compression.
