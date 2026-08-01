# 🔌 WebSocket

A **WebSocket** connection opens a bidirectional persistent channel between
the browser and server over TCP, after an HTTP handshake. Unlike normal HTTP —
request/response — WS leaves the socket open and both ends can send messages
whenever they want, without headers for each one.

Ideal for:

- **Chat** / real-time messaging.
- **Push notifications** (order status, alerts).
- **Dashboards** that update instantly (without polling).
- **Live collaboration** (shared cursors, simultaneous editing).
- **Games** and low-latency simulations.

```
Browser                                       HIX
   │                                            │
   │── GET /ws + Upgrade: websocket  ──────────>│  handshake
   │                                            │
   │<── HTTP 101 Switching Protocols  ──────────┤
   │                                            │
   │── frame "hello"  ──────────────────────────>│  bOnWsMessage
   │                                            │
   │<── frame "hello too" ──────────────────────┤  oConn:Send(...)
   │                                            │
   │── ping ───────────────────────────────────>│
   │<── pong  ──────────────────────────────────┤
   │                                            │
   │── frame CLOSE ────────────────────────────>│  bOnWsClose
```

---

## When NOT to use it

| Case | Better option |
|---|---|
| Only server pushes data (no client response) | [SSE](sse.md) — simpler |
| Sporadic events (every minute/hour) | [Long polling](longpolling.md) or webhook |
| Normal request/response communication | Standard HTTP |
| Client without WebSocket support (rare in 2026) | SSE as fallback |

> WS opens a **permanent** socket per connected client. 10,000 clients
> = 10,000 open sockets. Size `pool_ws` to support them.

---

## Setup

### Dedicated pool in `hix.json`

`workers`: maximum concurrent WS connections.
`ping_interval_s`: seconds between pings server → client.
`ping_timeout_s`: seconds for the client to respond to ping.

```json
{
  "pool_ws": {
    "workers":         100,
    "queue_size":      256,
    "ping_interval_s": 30,
    "ping_timeout_s":  10
  }
}
```

> Each active WS connection **blocks** a worker until it closes. If you expect
> 500 concurrent clients, bump `workers` to 500.

### Callbacks on the server

```clipper
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()

   oSrv:bOnWsConnect := {|oConn|
      l( "WS connect: " + oConn:cIP )
   }

   oSrv:bOnWsMessage := {|oConn, cMsg, nOpcode|
      // nOpcode: 1=text, 2=binary, 8=close, 9=ping, 10=pong
      oConn:Send( "Echo: " + cMsg )
   }

   oSrv:bOnWsClose := {|oConn|
      l( "WS close: " + oConn:cIP )
   }

   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
RETURN
```

> There's no specific URL for WS — the handshake is detected by `Upgrade: websocket`
> headers, not by path. Every WS connection that reaches the server goes through
> these three callbacks.

---

## `THixWsConn` — the active connection

Each callback receives the `oConn` object with the current connection:

| Property / method | Type | Meaning |
|---|---|---|
| `oConn:cIP` | string | Client IP |
| `oConn:lClosed` | logical | `.T.` if already closed |
| `oConn:Send( cText )` | method | Sends text frame (opcode 1) |
| `oConn:SendBinary( cData )` | method | Sends binary frame (opcode 2) |
| `oConn:Close()` | method | Closes the connection (opcode 8) |

### Typical pattern

```clipper
oSrv:bOnWsMessage := {|oConn, cMsg, nOpcode|
   LOCAL hData

   IF nOpcode == 8         // CLOSE — client closes
      oConn:Close()
      RETURN NIL
   ENDIF

   IF nOpcode == 9         // PING — HIX responds pong automatically
      RETURN NIL
   ENDIF

   IF nOpcode == 1         // text
      hData := hb_jsonDecode( cMsg )    // try to parse as JSON
      _ProcessClientMessage( oConn, hData )
   ENDIF
}
```

---

## JavaScript client

```javascript
const ws = new WebSocket("wss://app.com/ws")

ws.onopen    = () => console.log("Connected")
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data)
  console.log("Received:", msg)
}
ws.onerror   = (e) => console.error("WS error", e)
ws.onclose   = () => console.log("Closed")

// Send message
ws.send( JSON.stringify({ action: "subscribe", channel: "orders" }) )
```

> **Always use `wss://` when serving HTTPS.** Mixing `ws://` with
> `https://` causes mixed-content and the browser blocks it.

---

## Broadcast to multiple clients

HIX doesn't include a native broadcaster — keep it manually in a shared
array (with mutex):

```clipper
STATIC s_aConnections := {}
STATIC s_oMutex       := NIL

INIT PROCEDURE _InitWsRegistry()
   s_oMutex := hb_mutexCreate()
RETURN

PROCEDURE WsRegister( oConn )
   hb_mutexLock( s_oMutex )
   AAdd( s_aConnections, oConn )
   hb_mutexUnlock( s_oMutex )
RETURN

PROCEDURE WsUnregister( oConn )
   LOCAL n
   hb_mutexLock( s_oMutex )
   n := AScan( s_aConnections, {|o| o == oConn } )
   IF n > 0
      hb_ADel( s_aConnections, n, .T. )
   ENDIF
   hb_mutexUnlock( s_oMutex )
RETURN

PROCEDURE WsBroadcast( cMsg )
   LOCAL oConn
   hb_mutexLock( s_oMutex )
   FOR EACH oConn IN s_aConnections
      IF ! oConn:lClosed
         oConn:Send( cMsg )
      ENDIF
   NEXT
   hb_mutexUnlock( s_oMutex )
RETURN
```

And in the callbacks:

```clipper
oSrv:bOnWsConnect := {|oConn| WsRegister( oConn ) }
oSrv:bOnWsClose   := {|oConn| WsUnregister( oConn ) }

// From any HTTP action:
WsBroadcast( hb_jsonEncode( { "type" => "new_order", "id" => nId } ) )
```

---

## Ping / pong

HIX sends an **automatic ping** every `ping_interval_s` seconds. If the
client doesn't respond with pong within `ping_timeout_s` seconds, HIX closes the
connection.

Used for:

- Detecting disconnected clients (router down, mobile in suspend).
- Keeping the connection alive against proxies that cut idle sockets.

```json
{
  "pool_ws": {
    "ping_interval_s": 30,
    "ping_timeout_s":  10
  }
}
```

> 30s/10s are sound values. If you go through Cloudflare or other proxies that
> cut at 100s idle, use lower `ping_interval_s` (15–20s).

---

## Authentication

The WS handshake carries normal HTTP headers (cookies included) —
you can read the session cookie in `bOnWsConnect`:

```clipper
oSrv:bOnWsConnect := {|oConn|
   // At this point HIX_GetRequest() is not available —
   // capture the data during handshake if you need it.
   l( "WS connect from " + oConn:cIP )
}
```

For auth, the usual approach is **pass a token** as query string:

```javascript
const ws = new WebSocket("wss://app.com/ws?token=" + jwt)
```

And validate it in `bOnWsConnect` (read the original request): if it's not
valid, `oConn:Close()` before registering.

---

## Useful patterns

### Subscriptions by channel

```clipper
// State per connection — use connection hash as key
STATIC s_hSubs := {=>}    // { connId => { "orders", "alerts" } }

oSrv:bOnWsMessage := {|oConn, cMsg, nOpcode|
   LOCAL hMsg, aChannels

   IF nOpcode != 1 ; RETURN NIL ; ENDIF

   hMsg := hb_jsonDecode( cMsg )
   IF hMsg["action"] == "subscribe"
      aChannels := iif( hb_HHasKey(s_hSubs, oConn), s_hSubs[oConn], {} )
      AAdd( aChannels, hMsg["channel"] )
      s_hSubs[oConn] := aChannels
      oConn:Send( hb_jsonEncode( { "ok" => .T., "channel" => hMsg["channel"] } ) )
   ENDIF
}

// Publish to a specific channel
PROCEDURE WsPublish( cChannel, cPayload )
   LOCAL oConn, aChans
   FOR EACH oConn IN hb_HKeys( s_hSubs )
      aChans := s_hSubs[ oConn ]
      IF AScan( aChans, cChannel ) > 0 .AND. ! oConn:lClosed
         oConn:Send( cPayload )
      ENDIF
   NEXT
RETURN
```

### Binary messages — send bytes

```clipper
LOCAL cImage := hb_MemoRead( "thumbnail.png" )
oConn:SendBinary( cImage )
```

The client receives a `Blob` (browser) or `Buffer` (Node):

```javascript
ws.binaryType = "arraybuffer"
ws.onmessage = (e) => {
  if (e.data instanceof ArrayBuffer) {
    const bytes = new Uint8Array(e.data)
    // ...
  }
}
```

---

## Behind a proxy

For a reverse proxy (Apache/Nginx) to let the WS upgrade through:

### Apache

```apache
<VirtualHost *:443>
   ServerName app.example.com
   SSLEngine on
   SSLCertificateFile ...

   ProxyPass        /ws  ws://127.0.0.1:8080/ws
   ProxyPassReverse /ws  ws://127.0.0.1:8080/ws

   ProxyPass        /  http://127.0.0.1:8080/
   ProxyPassReverse /  http://127.0.0.1:8080/
</VirtualHost>
```

### Nginx

```nginx
location /ws {
   proxy_pass http://127.0.0.1:8080/ws;
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   proxy_read_timeout 86400;
}
```

> **Long `proxy_read_timeout`** (24h here) — without it the proxy closes
> the WS at the first idle minute, even with ping/pong.

---

## Common errors

| Symptom | Cause |
|---|---|
| Connection refused `WebSocket handshake failed` | WS pool out of workers — bump `pool_ws.workers` |
| Client disconnects at 60s | Proxy with low `proxy_read_timeout` (Nginx default 60s) |
| `Mixed Content` in browser | HTTPS page opening `ws://` — use `wss://` |
| `bOnWsMessage` never fires | Wrong opcode on client, or frame larger than buffer (>1MB) |
| WS opens and closes immediately | Client doesn't respond to ping within `ping_timeout_s` |
| Memory keeps growing | You're not unregistering connections in `bOnWsClose` |

---

## Best practices

1. **Cleanup in `bOnWsClose`.** If you keep a registry of connections,
   delete the entry — without it, you hold references to dead sockets.
2. **JSON for messages.** Plain text is ambiguous; JSON makes the
   type clear (`{ "type": "ping", "data": ... }`).
3. **Don't block the callback.** `bOnWsMessage` runs in the worker —
   if you do slow I/O there, other clients wait. For heavy tasks,
   dispatch to another thread.
4. **WSS in production.** Just like HTTPS: no plain WS over the internet.
5. **Optional heartbeat from client.** Beyond HIX's ping/pong,
   an application message every N seconds confirms the client logic is alive.
6. **Protocol agreement.** Define a version in the handshake or in the
   first message (`{ "v": 1, ... }`) — when you evolve, the client
   knows if it understands the server.
