---
title: SagaHttp.Tcp
---

Thin TCP wrappers around Erlang's `gen_tcp`, used by the HTTP server.

Sockets are opaque handles whose owning process is tracked by the
runtime — a socket closes automatically when its owner dies unless
ownership is transferred via `controlling_process`. `Socket` is an
accepted connection; `ListenSocket` is the listening endpoint that
produces them.

## Types

### Socket

```saga
opaque type Socket
```

### ListenSocket

```saga
opaque type ListenSocket
```

## Functions

### listen

```saga
fun listen : (port: Int) -> (backlog: Int) -> Result ListenSocket String
```

Open a listening socket on `port`. `backlog` is the OS-level pending-connection
queue size (passed through to `gen_tcp:listen`). Returns the listener or a
gen_tcp error reason atom (e.g. `"eaddrinuse"`).

### accept

```saga
fun accept : (socket: ListenSocket) -> Result Socket String
```

Block until a client connects, then return the accepted connection socket.
The caller becomes the socket's controlling process — transfer ownership
with `controlling_process` if a different process should outlive the caller.
Returns `Err "closed"` when the listener is closed underneath the call (this
is how graceful shutdown unblocks an accept loop).

### connect

```saga
fun connect : (host: String) -> (port: Int) -> (timeout: Int) -> Result Socket String
```

Open a client connection to `host:port`, giving up after `timeout` ms.
Useful for tests and any client work; the server side does not use it.

### local_port

```saga
fun local_port : (socket: ListenSocket) -> Result Int String
```

Returns the actual OS-assigned port for a listener. Useful when `listen`
was called with port `0` to let the kernel pick a free port (common in tests).

### recv

```saga
fun recv : (socket: Socket) -> (length: Int) -> (timeout: Int) -> Result BitString String
```

Read bytes from a connected socket. `length == 0` means "give me whatever
is available" (one TCP chunk); a positive `length` means "read exactly
this many bytes, blocking until they arrive or `timeout` ms elapses".
On timeout, returns `Err "timeout"`; on peer close, `Err "closed"`.

### send

```saga
fun send : (socket: Socket) -> (data: BitString) -> Result Unit String
```

Write `data` to the socket. `gen_tcp:send` is synchronous from the BEAM's
point of view — it returns after the data has been handed to the kernel
socket buffer, not after the peer has acked.

### close

```saga
fun close : (socket: Socket) -> Unit
```

Close an accepted connection socket. Idempotent and infallible from our
perspective; further sends/recvs on the socket will fail.

### close_listener

```saga
fun close_listener : (socket: ListenSocket) -> Unit
```

Same backend as `close`. Exposed separately so the type system distinguishes
closing an accepted connection from closing the listening socket itself
(the latter unblocks `accept` callers with an error, which is how graceful
shutdown stops accepting new connections).

### peername

```saga
fun peername : (socket: Socket) -> Result (String, Int) String
```

Returns `(ip, port)` of the connected peer. The IP is a dotted-quad / colon
notation string. Fails if the socket has already been closed or never
completed a connection.

### listener_controlling_process

```saga
fun listener_controlling_process : (socket: ListenSocket) -> (pid: Pid msg) -> Result Unit String
```

Transfer ownership of a listening socket to another process. Required
when the listener was created by a short-lived process and we want it
to keep accepting after that process exits — without transfer, the
listener is closed automatically when its creator dies.

### controlling_process

```saga
fun controlling_process : (socket: Socket) -> (pid: Pid msg) -> Result Unit String
```

Transfer ownership of an accepted connection socket. Same reason as the
listener variant: an accepted socket's controlling process is whoever
called `accept`, and the kernel closes the socket when that process dies.
To let connections outlive the acceptor (so a graceful shutdown can close
the listener without dropping in-flight requests), transfer to the
connection-handler process before the acceptor exits.

