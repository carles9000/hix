# ⏳ Long polling


**Long polling** is the oldest "real-time" technique over HTTP: the
client makes a normal GET, and the server **keeps the response
open** until it has something to send (or a timeout occurs). On receipt, the client makes another GET — and so on indefinitely.

```
Browser  ── GET /poll ───────────────▶ HIX
   │                                     │
   │                                     │  wait for event (up to 30s)
   │                                     │   .
   │                                     │   .  Any news?  → no
   │                                     │   .  Any news?  → yes
   │<── 200 + JSON with event  ──────────┤
   │                                     │
   ├── GET /poll ───────────────────────>│  immediately another request
   │                                     │
   │                                     │   .
   │                                     │   . (30s timeout without event)
   │<── 200 + empty JSON ────────────────┤
   │                                     │
   ├── GET /poll ───────────────────────>│  client retries
```

Unlike SSE / WS:

- **One request per event** — each notification closes the GET.
- **No upgrade, no chunked** — works through any proxy / CDN / network.
- **Higher latency** than SSE/WS due to constant reset.

---

## When to use it

| Case | Long polling |
|---|---|
| Client doesn't support SSE / WS | ✅ Universal fallback |
| Passes through "weird" proxies (corporate firewall) | ✅ It's normal HTTP |
| Few sporadic events | ✅ Works |
| Dashboard with changes every second | ⚠️ Better SSE |
| Chat with many messages/s | ❌ Better WS |
| Binary data | ❌ Better WS |

> In 2026, **SSE** is almost always the better choice over long polling: same
> simplicity, fewer requests, ~0 latency. Use long polling only if SSE doesn't fit
> due to client or network constraints.

---

## Setup

### Pool in `hix.json`

`workers_longpoll`: maximum concurrent long polls.
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

> Just like SSE, each long poll **occupies one worker** from the
> `pool_rest` pool while waiting. Size according to concurrency.

### Long poll route

```clipper
oSrv:AddRouteGet( "poll", "/poll", {|| _LongPoll() } )

FUNCTION _LongPoll()
   LOCAL nStart   := Seconds()
   LOCAL nTimeout := 30                ; seconds
   LOCAL hEvent

   DO WHILE Seconds() - nStart < nTimeout
      IF _HayNuevoEvento( @hEvent )
         RETURN USendJson( { "ok" => .T., "event" => hEvent } )
      ENDIF
      hb_idleSleep( 0.5 )
   ENDDO

   // Timeout without news — "empty" response
   USendJson( { "ok" => .T., "event" => NIL } )
RETURN NIL
```

> If there's news → respond **immediately**. If timeout passes without
> news → respond "empty". The client retries in either case.

---

## JavaScript client

```javascript
async function poll() {
  try {
    const resp = await fetch("/poll")
    const data = await resp.json()

    if (data.event) {
      _ProcesarEvento(data.event)
    }
  } catch (e) {
    console.error("Poll error", e)
    await sleep(1000)    // backoff before retrying
  }

  // Immediately another poll
  poll()
}

poll()
```

> Don't mix `setInterval`/`setTimeout` with polling frequency — the
> server already waits for you. Retry **when you receive the response** is the
> correct pattern.

---

## Pattern with cursor / `last_id`

To avoid re-receiving events you've already seen on reconnect:

```clipper
FUNCTION _LongPoll()
   LOCAL nLastId  := Val( UGet( "since", "0" ) )
   LOCAL nStart   := Seconds()
   LOCAL nTimeout := 30
   LOCAL aEvents

   DO WHILE Seconds() - nStart < nTimeout
      aEvents := _GetEventsSince( nLastId )
      IF Len( aEvents ) > 0
         RETURN USendJson( { ;
            "events"  => aEvents,                        ;
            "last_id" => ATail( aEvents )[ "id" ]        ;
         } )
      ENDIF
      hb_idleSleep( 0.5 )
   ENDDO

   USendJson( { "events" => {}, "last_id" => nLastId } )
RETURN NIL
```

```javascript
let lastId = 0

async function poll() {
  try {
    const resp = await fetch(`/poll?since=${lastId}`)
    const data = await resp.json()

    for (const ev of data.events) {
      _ProcesarEvento(ev)
    }
    lastId = data.last_id
  } catch (e) {
    await sleep(1000)
  }
  poll()
}
poll()
```

---

## Quick comparison

| | Long poll | SSE | WebSocket |
|---|---|---|---|
| Direction | ←→ (one event per request) | ← (server → client) | ↔ (bidirectional) |
| Transport | Normal HTTP | Normal HTTP | TCP upgrade |
| Passes through proxies | ✅ Yes | ✅ Yes (with buffering off) | ⚠️ Needs config |
| Auto-reconnect | Manual (client) | ✅ Browser native | Manual (client) |
| Latency | High (one request per event) | Low | Minimal |
| Server load | High (many requests) | Medium | Low |
| Client JS | `fetch` + loop | `EventSource` | `WebSocket` |
| Complexity | 🟢 Minimal | 🟢 Low | 🟡 Medium |
| Workers occupied | 1 per waiting client | 1 per connected client | 1 per connected client |

---

## Useful patterns

### Short timeout + fast retry

If your network cuts at 60s, better a short timeout:

```clipper
LOCAL nTimeout := 25    ; 25s — below typical cutoff
```

DO WHILE Seconds() - nStart < nTimeout
   ...
ENDDO
```

### Notify end of wait with type

```clipper
USendJson( { "type" => "event", "data" => hEvent } )    // there is an event
USendJson( { "type" => "idle" } )                       // timeout without event
```

The client differentiates and only processes the `event` types.

### Combine with event queue

```clipper
STATIC s_aQueue := {}
STATIC s_oMutex := NIL

INIT PROCEDURE _InitQueue()
   s_oMutex := hb_mutexCreate()
RETURN

PROCEDURE PushEvent( hEvent )
   hb_mutexLock( s_oMutex )
   AAdd( s_aQueue, hEvent )
   hb_mutexUnlock( s_oMutex )
RETURN

FUNCTION _LongPoll()
   LOCAL nStart   := Seconds()
   LOCAL nTimeout := 30
   LOCAL hEvent

   DO WHILE Seconds() - nStart < nTimeout
      hb_mutexLock( s_oMutex )
      IF Len( s_aQueue ) > 0
         hEvent := s_aQueue[1]
         hb_ADel( s_aQueue, 1, .T. )
         hb_mutexUnlock( s_oMutex )
         RETURN USendJson( { "event" => hEvent } )
      ENDIF
      hb_mutexUnlock( s_oMutex )

      hb_idleSleep( 0.5 )
   ENDDO

   USendJson( { "event" => NIL } )
RETURN NIL
```

And from any HTTP action:

```clipper
PushEvent( { "type" => "order_created", "id" => nId } )
```

> **Caveat** — this is global FIFO, not per client. For "one-to-one" delivery,
> the client needs its own queue identified by session /
> token. Multi-client long poll with guaranteed delivery quickly becomes
> more complex than a dedicated broker.

---

## Common errors

| Symptom | Cause |
|---|---|
| Client receives response and processes it again | Client retries without waiting for the response — add `await` |
| Pool `pool_rest` full with low traffic | Timeout too long or clients not closing on receipt |
| Client seems "stuck" without receiving | Server is blocked waiting — use short `hb_idleSleep` in loop |
| Duplicate events on reconnect | No cursor — add `last_id` or `since` |
| High latency between event and delivery | `hb_idleSleep` too long in loop (>1s) |
| Random `502 Bad Gateway` | Proxy cutting at 60s — lower `nTimeout` to 25–30s |

---

## Best practices

1. **Timeout `<` proxy timeout.** If your Apache/Nginx cuts at 60s,
   long poll timeout to 25–30s. The server should close cleanly,
   not the proxy.
2. **Retry on receipt, not by timer.** The next poll starts
   when the response arrives — no overlap.
3. **Backoff on error.** If GET fails, wait 1–2s before
   retrying. Without this, a down server gets 100 req/s from the client.
4. **Cursor (`since`/`last_id`).** To not lose or duplicate events.
5. **Limit with `stream_timeout_s`.** Even though you have internal timeout, the
   pool limit is the last defense against stuck workers.
6. **Prefer SSE if it's an option.** Long polling makes sense as
   fallback or when the environment doesn't allow SSE/WS.
