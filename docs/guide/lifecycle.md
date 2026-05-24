# Server lifecycle

```saga
pub fun serve : Config -> (Request -> Response) -> Result ShutdownHandle String
  needs {Process, Actor SupMsg, Monitor, Timer, Server}
```

`serve` is **non-blocking**. It listens, spawns a supervisor that
owns the listener, spawns an acceptor that does the blocking
`Tcp.accept`, and returns. The supervisor tracks every live
connection process.

Two ways to wait on it:

```saga
pub fun await_shutdown    : ShutdownHandle -> Unit
pub fun shutdown_and_wait : ShutdownHandle -> Int -> ShutdownResult
```

- `await_shutdown` monitors the supervisor and returns when it dies,
  for any reason. Useful in `main` to keep the executable alive.
- `shutdown_and_wait h deadline_ms` initiates a graceful drain: closes
  the listener (stops accepting), closes every tracked connection
  socket (wakes any blocked `Tcp.recv` so the handler exits), then
  waits for handlers to finish via `Monitor`. Returns:

```saga
pub type ShutdownResult =
  | Drained        # all handlers exited within the deadline
  | TimedOut       # deadline expired; count is in ShutdownTimedOut event
  | NoReply        # supervisor died for an unexpected reason
```

Handlers mid-response when shutdown begins will see a truncated send
on a dead socket — that's the cost of bounded shutdown.

See [`src/Main.saga`](../../src/Main.saga) for a SIGTERM-driven wiring
example.

## The `Server` effect

```saga
pub effect Server { fun event : ServerEvent -> Unit }
```

Every `serve` invocation needs a `Server` handler in scope. The
events cover places the library previously dropped errors silently:

| Variant | Meaning |
| --- | --- |
| `AcceptError String` | `accept()` returned an error; acceptor exits |
| `ClientDisconnected` | peer closed during the initial header read |
| `IdleTimeout` | idle/read timeout during the header read |
| `RequestParseError ParseError` | parse failed; error response already sent |
| `HeadersTooLarge` | cumulative header cap exceeded; 400 sent |
| `BodyReadFailed String` | `recv` failed mid-body; arg is the gen_tcp atom |
| `BodyReadDeadlineExceeded` | cumulative body-read deadline expired; 408 sent |
| `SendFailed SendSite String` | `Tcp.send` failed at the named site |
| `OwnershipTransferFailed String` | `gen_tcp:controlling_process` failed |
| `PipelinedRequestDropped` | leftover bytes after a request; connection closed |
| `ConnectionLimitReached` | `max_connections` cap hit; new socket dropped |
| `ShutdownTimedOut Int` | drain deadline expired; arg is connections still alive |
| `PeerAddressUnavailable String` | `Tcp.peername` failed; `req.peer = ("", 0)` |

`SendSite` distinguishes which send failed: `SendResponse`,
`SendChunk`, `SendChunkTerminator`, `SendContinue`.

Two ready-made handlers ship with the library:

```saga
pub handler discard_events for Server { event _ = resume () }
pub handler print_events   for Server { event e = { dbg e; resume () } }
```

`discard_events` for tests and benchmarks; `print_events` for
development. For production you'll want your own handler that
forwards to structured logging or metrics.
