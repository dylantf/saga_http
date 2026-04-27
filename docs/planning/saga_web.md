# SagaWeb brainstorming

This is a planning note for a future web/framework library built on top of
`saga_http`. The HTTP library should stay focused on protocol mechanics:
parsing, connection handling, response encoding, streaming, and HTTP/1.x
correctness. SagaWeb can explore the higher-level application model.

## North star

SagaWeb should feel like Saga, not like a direct port of Express/Phoenix/Rails.
The interesting primitive is not only "middleware calls next"; it is:

- route/application code is ordinary Saga functions
- request-scoped values are effects installed at the request boundary
- cross-cutting behavior is implemented with handlers
- traits describe data-dependent behavior such as encoding
- handler placement, `resume`, `return`, and `finally` provide middleware-like
  control flow

In short: routing is data/functions, environment policy is effects/handlers,
and encoding/decoding is traits.

## Core idea

The HTTP server already accepts:

```saga
Http.Request -> Http.Response
```

SagaWeb can compile a richer app/router shape down to that. Route handlers can
be effectful:

```saga
fun show_user : Unit -> Http.Response needs {RequestContext, HttpFail, Database, Json}
```

The framework boundary matches the route, installs request-local handlers, and
converts SagaWeb failures into normal HTTP responses.

## Ambient request context

The ambient-reader examples suggest a good shape for request data that should
not be threaded through every function argument:

```saga
effect RequestContext {
  fun request : Unit -> Http.Request
  fun request_id : Unit -> String
  fun param : String -> Maybe String
  fun query : String -> Maybe String
  fun header : String -> Maybe String
}
```

The router installs this handler once per request, closing over the matched
route params, parsed query string, and raw `Http.Request`.

Deep functions can ask for only what they need:

```saga
fun require_param : String -> String needs {RequestContext, HttpFail}
require_param name = case param! name {
  Just value -> value
  Nothing -> bad_request! $"missing route parameter: {name}"
}
```

## HTTP failures as control flow

Application-level failures can be modeled as an effect:

```saga
effect HttpFail {
  fun bad_request : String -> a
  fun unauthorized : String -> a
  fun forbidden : String -> a
  fun not_found : String -> a
}
```

The default handler converts these into `Http.Response` values. Applications can
replace that handler to change error bodies, logging, JSON envelopes, etc.

This keeps route code direct:

```saga
fun show_user : Unit -> Http.Response needs {RequestContext, HttpFail, Database, Json}
show_user () = {
  let id = require_param "id"
  let user = case find_user id {
    Just u -> u
    Nothing -> not_found! $"user not found: {id}"
  }
  json 200 user
}
```

## Writer-style telemetry

The ambient-writer example maps naturally to audit logs, metrics, trace spans,
or framework events:

```saga
record WebEvent {
  name: String,
  detail: String,
}
```

Route code can emit events without changing its return type:

```saga
fun checkout : Unit -> Http.Response needs {Tell WebEvent}
checkout () = {
  tell! (WebEvent { name: "checkout.started", detail: "" })
  ...
}
```

Different handlers can collect events for tests, log them, export metrics, or
ignore them.

## Middleware as handler control flow

Saga middleware can be richer than `Request -> next -> Response` because a
handler controls the continuation.

Where `resume` is placed determines behavior:

- before/after behavior: do work, `resume`, then inspect the returned value
- early exit: return a response without calling `resume`
- retry/fanout: call `resume` more than once
- cleanup: use `finally` after the continuation completes or aborts
- response transforms: use stacked `return` clauses

Example categories:

```saga
# Provide a capability to downstream route code.
with_auth req route

# Convert domain failures to HTTP responses.
with_http_errors route

# Observe or collect events from route execution.
with_telemetry route

# Transform successful responses.
with_security_headers route
```

Stacked `return` blocks are especially interesting for response pipelines.
Given:

```saga
route () with { add_security_headers, compress, access_log }
```

the inner handler's `return` transforms the route result first, then outer
handlers see the transformed result. This can model "successful response"
middleware separately from operation-level interception.

Ordering must be made legible in the API/docs. Handler stacking is powerful, but
web users need a simple mental model for inside/outside order.

## Plugins

A SagaWeb plugin might be less like a middleware object and more like a bundle
of handlers and helpers that provides capabilities:

- auth plugin provides `CurrentUser`
- session plugin provides `Session`
- router provides `RequestContext`
- telemetry plugin handles `Tell WebEvent`
- database plugin provides `Database`
- error plugin handles `HttpFail`

This suggests two plugin styles:

1. capability providers that install handlers for downstream route code
2. response/request wrappers that observe, transform, or short-circuit

Avoid over-designing a plugin abstraction at first. Plain functions and handler
factories may be enough until real patterns emerge.

## Traits

Traits should handle behavior based on data type, especially encoding and
decoding:

```saga
trait EncodeJson a {
  fun encode_json : a -> Json
}

fun json : Int -> a -> Http.Response where {a: EncodeJson}
```

Effects should not replace traits here. Encoding depends on what the value is;
effects are better for where the code is running and what capabilities are
available.

## Possible MVP

- route matching by method and path
- path params via `RequestContext`
- query parser via `RequestContext`
- `HttpFail` with default text responses
- response helpers: `text`, `html`, redirect helpers, header helpers
- basic plugin/wrapper examples using ordinary functions
- tests that run route handlers without sockets

Possible end-user shape:

```saga
fun app : Http.Request -> Http.Response
app req =
  Web.handle req [
    Web.get "/" home,
    Web.get "/users/:id" show_user,
    Web.post "/users" create_user,
  ]

fun show_user : Unit -> Http.Response needs {RequestContext, HttpFail}
show_user () = {
  let id = require_param "id"
  Http.text 200 $"user {id}"
}
```

## Open questions

- What is the exact route handler type with current effect-row ergonomics?
- Should route handlers take `Unit`, or should they still receive
  `Http.Request` directly?
- Should `RequestContext` expose the full request, or keep route code mostly on
  smaller operations?
- How should route ordering and fallback behavior be represented?
- Do we need a formal plugin type, or are handler factories enough initially?
- How much response transformation should happen through `return` handlers
  versus plain wrapper functions?
- Can we make handler stacking order obvious enough for web users?
