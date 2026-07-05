---
title: SagaHttp.WebSocket
---

WebSocket protocol helpers.

This module owns WebSocket-specific handshake validation and, eventually,
frame parsing/encoding. HTTP connection loops live in `SagaHttp.Http`.

## Types

### HandshakeError

```saga
type HandshakeError =
  | WrongMethod String
  | UnsupportedHttpVersion
  | MissingConnectionUpgrade
  | MissingUpgradeHeader
  | UnsupportedUpgradeHeader String
  | MissingWebSocketVersion
  | UnsupportedWebSocketVersion String
  | MissingWebSocketKey
  | InvalidWebSocketKey
  deriving (Debug, Eq)
```

Errors returned while validating an HTTP WebSocket upgrade request.

### Handshake

```saga
record Handshake {
  key: String,
  accept_key: String
}
  deriving (Debug, Eq)
```

Validated handshake metadata needed to send the 101 response.

### Opcode

```saga
type Opcode =
  | Continuation
  | Text
  | Binary
  | Close
  | Ping
  | Pong
  deriving (Debug, Eq)
```

WebSocket frame opcodes.

### Frame

```saga
record Frame {
  fin: Bool,
  opcode: Opcode,
  payload: BitString
}
  deriving (Debug, Eq)
```

A decoded WebSocket frame.

### FrameOptions

```saga
record FrameOptions {
  max_frame_size: Int,
  require_mask: Bool
}
```

Pure frame decoder options.

### FrameError

```saga
type FrameError =
  | IncompleteFrame
  | ReservedBitsSet
  | InvalidOpcode Int
  | ClientFrameNotMasked
  | FrameTooLarge Int Int
  | InvalidControlFrame
  deriving (Debug, Eq)
```

Errors returned while decoding a WebSocket frame.

### Message

```saga
type Message =
  | TextMessage String
  | BinaryMessage BitString
  deriving (Debug, Eq)
```

Messages exposed by the socket-backed WebSocket runtime.

### Options

```saga
record Options {
  max_frame_size: Int,
  max_message_size: Int,
  read_timeout_ms: Int
}
```

Runtime options for a WebSocket connection.

### Error

```saga
type Error =
  | FrameDecodeError FrameError
  | ReadError String
  | SendError String
  | TextNotUtf8
  | UnexpectedContinuation
  | NewDataFrameDuringFragmentedMessage
  | MessageTooLarge Int Int
  | InvalidCloseFrame
  | InvalidCloseCode Int
  | CloseReasonTooLarge Int Int
  deriving (Debug, Eq)
```

Errors returned by socket-backed WebSocket operations.

## Effects

### WebSocket

```saga
effect WebSocket {
  fun read_message : Unit -> Result (Maybe Message) Error
  fun send_text : String -> Result Unit Error
  fun send_binary : BitString -> Result Unit Error
  fun close_websocket : Int -> String -> Result Unit Error
}
```

Effect installed while running a WebSocket connection.

## Functions

### websocket_guid

```saga
fun websocket_guid : String
```

Fixed WebSocket GUID from RFC 6455.

### default_frame_options

```saga
fun default_frame_options : FrameOptions
```

Default server-side frame decoder options.

### default_options

```saga
fun default_options : Options
```

Default WebSocket runtime options.

### accept_key

```saga
fun accept_key : String -> Result String HandshakeError
```

Compute `Sec-WebSocket-Accept` for a client `Sec-WebSocket-Key`.

The input must be standard base64 that decodes to 16 bytes.

### validate_handshake

```saga
fun validate_handshake : String -> Bool -> List (String, String) -> Result Handshake HandshakeError
```

Validate WebSocket upgrade headers and compute the accept key.

### response_headers

```saga
fun response_headers : Handshake -> List (String, String)
```

Headers required for a successful `101 Switching Protocols` response.

### decode_client_frame

```saga
fun decode_client_frame : BitString -> Result (Frame, BitString) FrameError
```

Decode one client-to-server frame and return the leftover bytes.

### decode_frame_with

```saga
fun decode_frame_with : FrameOptions -> BitString -> Result (Frame, BitString) FrameError
```

Decode one frame with explicit options and return the leftover bytes.

### encode_frame

```saga
fun encode_frame : Opcode -> BitString -> BitString
```

Encode one server-to-client frame.

### encode_text_frame

```saga
fun encode_text_frame : String -> BitString
```

Encode an unfragmented server text frame.

### run_connection

```saga
fun run_connection : Options -> Tcp.Socket -> Unit -> Unit needs {WebSocket} -> Unit
```

Run a handler with a socket-backed WebSocket effect.

The socket is closed when the handler returns.

### run_connection_with

```saga
fun run_connection_with : Options -> Tcp.Socket -> BitString -> Unit -> Unit needs {WebSocket} -> Unit
```

Run a handler with already-read WebSocket frame bytes.

### valid_close_code

```saga
fun valid_close_code : Int -> Bool
```

Returns True when a WebSocket close status code is valid on the wire.

