# HTTP/2 plan

## Overview

HTTP/2 is a binary protocol that multiplexes multiple request/response streams
over a single TCP connection. The main differences from HTTP/1.1:

- Binary framing instead of text
- Multiple concurrent streams on one connection
- Header compression (HPACK)
- Flow control per stream and per connection
- Server push (optional, low priority)

## Components

### 1. Frame parser/encoder

HTTP/2 communication is through frames. Every frame has a 9-byte header:

```
[3 bytes length] [1 byte type] [1 byte flags] [4 bytes stream id]
```

Followed by a variable-length payload. Frame types:

- **Data (0)** - request/response body
- **Headers (1)** - compressed headers
- **Priority (2)** - stream priority
- **RST_STREAM (3)** - cancel a stream
- **Settings (4)** - connection configuration
- **Push Promise (5)** - server push
- **Ping (6)** - keep-alive / latency measurement
- **GoAway (7)** - graceful connection shutdown
- **Window Update (8)** - flow control
- **Continuation (9)** - large header continuation

Pure Saga. BitString parsing for decoding, BitString construction for encoding.

### 2. Connection upgrade

Two paths into HTTP/2:

- **Prior knowledge** - client sends the connection preface directly
  (`PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`). `erlang:decode_packet` already
  detects this as a special case.
- **Upgrade from HTTP/1.1** - client sends `Connection: Upgrade, HTTP2-Settings`
  headers. Less common, mostly for unencrypted HTTP/2.

After the preface, the server sends a Settings frame and the connection
switches to binary framing.

### 3. HPACK header compression

HTTP/2 compresses headers using HPACK (RFC 7541):

- A static table of 61 common headers (`:method: GET`, `:status: 200`, etc.)
- A dynamic table that grows per connection as new headers are seen
- Huffman coding for header values

Use the Erlang `hpack_erl` Hex package via FFI for a first pass. Pure Saga
implementation could come later.

### 4. Stream multiplexing

Each request/response is a "stream" with a 31-bit integer ID. Odd IDs are
client-initiated, even are server-initiated.

Stream state machine:

```
idle -> open -> half-closed (remote) -> closed
                half-closed (local)  -> closed
```

Each stream tracks: state, receive/send window sizes, accumulated data,
expected content length.

Natural fit for Saga's actor model: one process per stream within a
connection.

### 5. Flow control

Window-based. Prevents fast senders from overwhelming slow receivers.

- Connection-level window: shared across all streams
- Stream-level window: per stream
- Initial window: 65,535 bytes (configurable via Settings)
- Sender must not exceed the window
- Receiver sends Window Update frames to replenish

Pure Saga integer tracking.

### 6. Error handling

Two levels:

- **Stream error** - RST_STREAM frame, kills one stream
- **Connection error** - GoAway frame, kills the whole connection

Error codes: protocol error, flow control error, stream closed, frame size
error, compression error, etc.

## Dependencies

- `hpack_erl` Hex package for HPACK compression
- Everything else is pure Saga + our existing Tcp module

## Implementation order

1. Frame parser/encoder (BitString operations, no Erlang needed)
2. Connection preface detection and Settings exchange
3. HPACK integration (FFI to hpack_erl)
4. Single-stream request/response
5. Stream multiplexing
6. Flow control
7. Error handling (RST_STREAM, GoAway)
8. Server push (low priority)
