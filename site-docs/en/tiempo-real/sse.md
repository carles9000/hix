# 📡 SSE - Server-Sent Events

**Server-Sent Events** is **unidirectional** push from server to client
over normal HTTP. The client opens the connection with a GET and keeps
it open; the server sends "events" in `text/event-stream` format
without ever closing the response (or until a timeout).

```
Browser  ── GET /events ──────────────>HIX
   │  Accept: text/event-stream         │
   │                                    │  USendStreamStart("text/event-stream", 200)
   │<── 200 OK + headers stream ────────┤
   │                                    │
   │<── data: {"n":1}\n\n ──────────────┤  USendChunk(...)
   │<── data: {"n":2}\n\n ──────────────┤  USendChunk(...)
   │<── data: {"n":3}\n\n ──────────────┤  USendChunk(...)
   │                                    │
   │                                    │  ...for minutes/hours
```

Vs WebSocket:

- **Simpler**: normal HTTP, no upgrade needed, passes through proxies and
  firewalls without any configuration.
- **Server → client only**: the client cannot send anything on the
  same channel (use a separate POST if needed).
- **Auto-reconnect**: the browser reconnects automatically if the
  channel drops — WS doesn't do that.

---

## When to use it

| Case | SSE |
|---|---|
| Live-updating dashboard | ✅ Ideal |
| Web console log stream | ✅ Ideal |
| Push notifications (one-way) | ✅ Ideal |
| Bidirectional chat | ❌ Better [WebSocket](ws.md) |
| Binary data (images, audio) | ❌ SSE is text-only — use WS |
| Client with unstable internet | ✅ Reconnects automatically |
| Standard request/response behavior | ❌ Normal HTTP |

---

## `text/event-stream` format

Each event is **one or more `key: value` fields** followed by **a
blank line**:

```
data: hello

data: {"n":1}

event: notice
data: {"msg":"update"}

id: 42
data: {"order":42,"status":"shipped"}

retry: 5000
data: configures retry only, no useful payload
```

| Field | Meaning |
|---|---|
| `data:` | Payload — the blank line at the end closes the event |
| `event:` | Event name — the client can filter by name |
| `id:` | Identifier — the browser sends it as `Last-Event-ID` on reconnect |
| `retry:` | Milliseconds to wait for reconnection |
| `: comment` | Comment / keep-alive — the browser ignores it |

Each chunk you send **must end in `\n\n`** (blank line) for the
browser to process the event.

---

## Setup

### Dedicated pool in `hix.json`

`workers_sse`: maximum concurrent SSE connections.
`stream_timeout_s`: maximum seconds per connection (`0` = no limit).

```json
{
  "pool_rest": {
    "workers_sse":      20,
    "workers_longpoll": 10,
    "queue_size":       128,
    "stream_timeout_s": 3600
  }
}
```

> Each SSE connection **occupies one worker from the `pool_rest` pool** until
> it closes. 20 simultaneous connections = `workers_sse = 20`. If you expect 200
> users viewing the live dashboard, bump `workers_sse` to 200.

### SSE route

```clipper
oSrv:AddRouteGet( "events", "/events", {||
   _StreamEvents()
} )

FUNCTION _StreamEvents()
   LOCAL i := 0

   USendStreamStart( "text/event-stream", 200, { ;
      "Cache-Control"     => "no-cache",   ;
      "X-Accel-Buffering" => "no"          ;
   } )

   DO WHILE i < 100
      i++
      USendChunk( "data: " + hb_jsonEncode( { "n" => i } ) + hb_eol() + hb_eol() )
      hb_idleSleep( 1 )
   ENDDO

   USendStreamEnd()
RETURN NIL
```

> `X-Accel-Buffering: no` disables Nginx buffering — without it,
> Nginx may hold your chunks in memory until the "complete" response arrives
> and the client won't see anything in real-time.

---

## Stream API

| Function | What it does |
|---|---|
| `USendStreamStart( cMime, nStatus, hExtra )` | Sends headers + opens the stream |
| `USendChunk( cData )` | Sends a chunk (a complete SSE event, with final `\n\n`) |
| `USendStreamEnd()` | Closes the stream cleanly |

Internally HIX uses **transfer-encoding chunked** and keeps the socket
open between calls.

---

## JavaScript client

```javascript
const evt = new EventSource("/events")

evt.onmessage = (e) => {
  // event without "event:" → onmessage
  const data = JSON.parse(e.data)
  console.log("Tick:", data.n)
}

evt.addEventListener("notice", (e) => {
  console.log("Notice:", e.data)
})

evt.onerror = (e) => {
  // The browser will retry automatically
  console.log("Error / disconnection", e)
}

// Close manually
// evt.close()
```

> The browser reconnects automatically. If you need to avoid duplicates, send
> `id:` in each event and on reconnect the browser will attach the `Last-Event-ID` header
> automatically.

---

## Useful patterns

### Heartbeat to prevent proxy timeouts

Proxies close idle sockets (60–120s typically). Send a
comment `:` every X seconds:

```clipper
DO WHILE lRunning
   IF Seconds() - nLastBeat >= 20
      USendChunk( ": keep-alive" + hb_eol() + hb_eol() )
      nLastBeat := Seconds()
   ENDIF

   IF _HayNuevoEvento( @hEvent )
      USendChunk( "data: " + hb_jsonEncode( hEvent ) + hb_eol() + hb_eol() )
   ENDIF

   hb_idleSleep( 1 )
ENDDO
```

### Named events and client-side filtering

```clipper
USendChunk( "event: order_update" + hb_eol() + ;
            "data: " + hb_jsonEncode( hOrder ) + hb_eol() + hb_eol() )

USendChunk( "event: alert" + hb_eol() + ;
            "data: " + hb_jsonEncode( hAlert ) + hb_eol() + hb_eol() )
```

```javascript
evt.addEventListener("order_update", (e) => { ... })
evt.addEventListener("alert",        (e) => { ... })
```

### Recover after reconnection (`Last-Event-ID`)

```clipper
FUNCTION _StreamEvents()
   LOCAL nLastId := Val( UHeader( "last-event-id", "0" ) )

   USendStreamStart( "text/event-stream", 200, { "Cache-Control" => "no-cache" } )

   // Re-emit lost events since nLastId
   FOR EACH hEvent IN _GetEventsSince( nLastId )
      USendChunk( "id: "   + hb_NToS( hEvent["id"] ) + hb_eol() + ;
                  "data: " + hb_jsonEncode( hEvent ) + hb_eol() + hb_eol() )
   NEXT

   // Continue with new events
   DO WHILE _HayMas( nLastId, @hNext )
      USendChunk( "id: "   + hb_NToS( hNext["id"] ) + hb_eol() + ;
                  "data: " + hb_jsonEncode( hNext ) + hb_eol() + hb_eol() )
      nLastId := hNext["id"]
      hb_idleSleep( 1 )
   ENDDO

   USendStreamEnd()
RETURN NIL
```

### Client closes → exit the loop

Detecting client disconnection is tricky: in standard HTTP the server
doesn't get immediate notification. The usual approach is to check the error flag
when writing:

```clipper
DO WHILE lRunning
   USendChunk( "data: " + hb_jsonEncode( hEvent ) + hb_eol() + hb_eol() )
   IF UContext():oReq:lClosed
      lRunning := .F.
   ENDIF
   hb_idleSleep( 1 )
ENDDO
USendStreamEnd()
```

> **Always limit with `stream_timeout_s`** in the pool. Even if you don't detect
> the disconnection, the worker is freed when the timeout expires.

---

## SSE Broadcast

Chunks are sent **per connection**. If you want to send the same event
to N clients, maintain a list:

```clipper
STATIC s_aClients := {}
STATIC s_oMutex   := NIL

INIT PROCEDURE _InitSseRegistry()
   s_oMutex := hb_mutexCreate()
RETURN

FUNCTION _SseStream()
   LOCAL hClient := { "id" => hb_Random(), "queue" => {} }
   LOCAL cMsg

   hb_mutexLock( s_oMutex )
   AAdd( s_aClients, hClient )
   hb_mutexUnlock( s_oMutex )

   USendStreamStart( "text/event-stream", 200, { "Cache-Control" => "no-cache" } )

   DO WHILE ! UContext():oReq:lClosed
      hb_mutexLock( s_oMutex )
      DO WHILE Len( hClient["queue"] ) > 0
         cMsg := hClient["queue"][1]
         hb_ADel( hClient["queue"], 1, .T. )
         USendChunk( cMsg )
      ENDDO
      hb_mutexUnlock( s_oMutex )

      hb_idleSleep( 0.5 )
   ENDDO

   // Unregister
   hb_mutexLock( s_oMutex )
   AEval( s_aClients, {|h,n| iif( h["id"] == hClient["id"], hb_ADel(s_aClients,n,.T.), NIL ) } )
   hb_mutexUnlock( s_oMutex )

   USendStreamEnd()
RETURN NIL

PROCEDURE SseBroadcast( cData )
   LOCAL hClient
   LOCAL cChunk := "data: " + cData + hb_eol() + hb_eol()

   hb_mutexLock( s_oMutex )
   FOR EACH hClient IN s_aClients
      AAdd( hClient["queue"], cChunk )
   NEXT
   hb_mutexUnlock( s_oMutex )
RETURN
```

And from any HTTP action:

```clipper
SseBroadcast( hb_jsonEncode( { "type" => "order_created", "id" => nId } ) )
```

---

## Behind a proxy

| Proxy | Trick |
|---|---|
| **Nginx** | `proxy_buffering off;` + `proxy_read_timeout 24h;` |
| **Apache** | Normal `ProxyPass` — works |
| **Cloudflare** | Works, but with 100s timeout — send heartbeats every 30s |

### Nginx

```nginx
location /events {
   proxy_pass http://127.0.0.1:8080/events;
   proxy_http_version 1.1;
   proxy_set_header Connection "";
   proxy_buffering off;             # critical for SSE
   proxy_cache off;
   proxy_read_timeout 24h;
}
```

> The `X-Accel-Buffering: no` header in the response also disables it
> per request — useful if you don't control your Nginx config.

---

## Common errors

| Symptom | Cause |
|---|---|
| Client receives everything when stream closes, not in real-time | Proxy buffering — add `X-Accel-Buffering: no` |
| Client reconnects every 60s | Proxy with low `proxy_read_timeout` — raise to hours |
| Events arrive duplicated on reconnect | You don't use `id:` — the browser re-receives the last ones |
| Wrong `Content-Type` | Forgot `text/event-stream` in `USendStreamStart` |
| Only first event shows | Missing `\n\n` at the end of each chunk |
| SSE pool exhausted | `pool_rest.workers_sse` too low for expected concurrency |
| Memory leak with clients closing silently | Loop doesn't check `lClosed` or missing `stream_timeout_s` |

---

## Best practices

1. **Always `\n\n` at the end of the chunk.** Without the blank line, the
   browser accumulates without firing the event.
2. **`X-Accel-Buffering: no`** in headers — protects against Nginx by
   default.
3. **Heartbeats every 20–30s.** Comments `:` keep the socket
   alive and you detect disconnection sooner.
4. **Use `id:` if order matters.** With `Last-Event-ID` you can
   resume from where it broke.
5. **Limit with `stream_timeout_s`.** A hung SSE connection blocks a
   worker — the hard timeout frees it.
6. **Don't block with synchronous I/O.** Each SSE lives in its worker; if
   you wait for slow DB, the client waits too. Better an
   intermediate buffer + dedicated worker.
