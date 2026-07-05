# WebSocket Implementation Plan

WebSocket support should keep protocol mechanics in `saga_http`. Frameworks
such as Edda should only route the initial HTTP upgrade request and provide
ergonomic handler composition.

## Current Server Shape

- `handle_connection_loop` and `handle_streaming_connection_loop` own accepted
  TCP sockets and close them when the HTTP request/response cycle ends.
- `parse_request_head` already reads the request line and headers before body
  consumption. This is the right point to detect an upgrade.
- `ResponseBody.Streamed` proves that `send_response` can run code while it
  owns the socket, but WebSocket is not a response body. It needs an explicit
  "connection upgraded" outcome so the normal keep-alive loop does not resume.
- `Std.Crypto` now exposes SHA-1 plus standard base64 encode/decode, which the
  WebSocket handshake uses for `base64(sha1(sec-websocket-key <> GUID))`.

## Proposed API Direction

Add a low-level WebSocket module and keep the first public surface small:

- `SagaHttp.WebSocket` owns handshake helpers, frame encode/decode, message
  types, errors, and the socket-backed connection effect.
- `SagaHttp.Http` imports that module and gains an upgrade-capable response or
  handler result.
- Edda later wraps this with route helpers, for example `websocket "/chat" fn`.

Preferred runtime shape:

- Add a `ResponseBody.WebSocketUpgrade` variant carrying validated handshake
  metadata and a handler that runs with a WebSocket effect.
- Change `send_response` to return a connection disposition, such as
  `ResponseSent` or `ConnectionClosed`.
- When a WebSocket upgrade response is sent, `send_response` emits `101
  Switching Protocols`, runs the WebSocket handler, performs close cleanup, and
  returns `ConnectionClosed`.
- Connection loops stop instead of attempting keep-alive after an upgraded
  response.

This preserves the existing "handler returns a response" model while making
the socket takeover explicit.

## Step 1: Handshake Helpers

Status: done.

Implement pure/protocol helpers first.

- Added `SagaHttp.WebSocket` with `HandshakeError`, `Handshake`, `accept_key`,
  `validate_handshake`, and `response_headers`.
- Validates:
  - method is `GET`
  - HTTP version is `HTTP/1.1`
  - `Connection` contains `upgrade`
  - `Upgrade` equals `websocket`
  - `Sec-WebSocket-Version` equals `13`
  - `Sec-WebSocket-Key` is valid base64 and decodes to 16 bytes
- Uses `Std.Crypto.base64_encode`, `Std.Crypto.base64_decode`, and
  `Std.Crypto.sha1_digest`.
- Covered by unit tests for the RFC accept-key vector plus valid and invalid
  handshake cases.

## Step 2: Frame Codec

Status: done.

Built frame parsing and encoding independent of the server loop.

- Defined opcodes: continuation, text, binary, close, ping, pong.
- Decodes FIN, RSV bits, opcode, mask bit, payload length, optional extended
  lengths, optional mask key, and payload.
- Rejects client frames that are not masked.
- Rejects server-bound frames with RSV bits set until extensions exist.
- Applies the mask by XORing payload bytes with the 4-byte key.
- Encodes server frames without masking.
- Enforces configurable `max_frame_size`.
- Unit tested small, 16-bit extended, 64-bit extended, masked, unmasked, invalid
  opcode, and oversized frames.

## Step 3: Minimal Runtime Loop

Status: done.

Added the socket-backed `WebSocket` effect and `run_connection`.

- Supports unfragmented text and binary messages.
- Exposes:
  - `read_message! () -> Result (Maybe Message) Error`
  - `send_text! String -> Result Unit Error`
  - `send_binary! BitString -> Result Unit Error`
  - `close_websocket! Int String -> Result Unit Error`
- Automatically replies to ping with pong before delivering the next message.
- Surfaces close frames as `Ok Nothing` after sending a close reply.
- Closes the TCP socket when the handler returns.
- Covered by raw TCP integration tests with hand-built masked client frames.

## Step 4: HTTP Integration

Status: done.

Wired the upgrade response into `SagaHttp.Http`.

- Added `ResponseBody.WebSocketUpgrade`.
- Added `ConnectionDisposition` so `send_response` can report when a response
  has taken over and closed the connection.
- Added `websocket` and `websocket_with` helpers that validate a request and
  return either a `101` upgrade response or `400 Bad Request`.
- Passes HTTP parser leftover bytes into `WebSocket.run_connection_with`, so a
  client may send its first WebSocket frame in the same TCP packet as the HTTP
  upgrade request.
- Connection loops stop instead of attempting keep-alive after an upgraded
  response.
- Covered by integration tests for successful upgrade and missing-key rejection.

## Step 5: Protocol Completeness

Status: done enough for the first public low-level protocol.

Filled in the remaining RFC 6455 basics around the runtime loop.

- Fragmented text and binary messages are assembled across continuation frames.
- Ping/pong frames may interleave while a fragmented message is in progress.
- Control frames are rejected when fragmented or larger than 125 bytes.
- Runtime options include `max_message_size`, separate from `max_frame_size`.
- Incoming close payloads validate status code and UTF-8 close reason bytes.
- `close_websocket!` validates outgoing close code and caps reason bytes at
  123 bytes.
- The runtime still uses the existing read timeout; proactive heartbeat policy
  is deferred until a framework or application needs it.

## Step 6: Edda Adapter

Once `saga_http` is stable, add a thin framework layer.

- Convert Edda `Request`/route matches into the validated upgrade helper.
- Add a route helper such as `websocket "/chat" handler`.
- Keep cookies, headers, params, and auth middleware available before upgrade.
- Add an Edda E2E echo route.

## Deferred

- Per-message compression.
- Subprotocol negotiation helpers beyond exposing
  `Sec-WebSocket-Protocol`.
- GraphQL subscription protocol; build that above this message API.
