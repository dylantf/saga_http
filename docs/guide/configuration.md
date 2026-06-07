# Configuration

```saga
pub record Config { ... }
pub fun default_config : Config
```

Use record update to customise:

```saga
serve { default_config | port: 4000, max_body_size: 4 * 1024 * 1024 } handle
```

Fields, grouped by purpose:

## Identity

| Field         | Default       | Notes                                   |
| ------------- | ------------- | --------------------------------------- |
| `port`        | `8080`        | TCP port to listen on                   |
| `server_name` | `"saga_http"` | Sent as `Server:` header; `""` opts out |

## Framing limits

| Field                      | Default   | Notes                                                        |
| -------------------------- | --------- | ------------------------------------------------------------ |
| `max_body_size`            | `1048576` | Cap on request body bytes (CL or chunked total)              |
| `max_header_size`          | `8192`    | Per-line cap (request line or any single header line)        |
| `max_chunk_line_size`      | `1024`    | Cap on a chunk-size line (hex + optional `;ext`)             |
| `max_trailer_size`         | `8192`    | Cap on the trailer section after the final 0-chunk           |
| `max_request_headers_size` | `65536`   | Cap on cumulative request line + headers (slowloris defense) |
| `max_header_count`         | `100`     | Cap on number of headers in a request                        |

## Timeouts

| Field                   | Default | Notes                                                          |
| ----------------------- | ------- | -------------------------------------------------------------- |
| `idle_timeout_ms`       | `30000` | Wait for _next_ request on a keep-alive socket                 |
| `read_timeout_ms`       | `30000` | Wait for individual reads mid-request (body, chunks, trailers) |
| `total_body_timeout_ms` | `60000` | Cumulative wall-clock deadline for reading one body            |

## Capacity

| Field             | Default | Notes                                                            |
| ----------------- | ------- | ---------------------------------------------------------------- |
| `max_connections` | `10000` | Simultaneously-tracked connections; over-cap sockets are dropped |
