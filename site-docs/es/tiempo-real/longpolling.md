# ⏳ Long polling


**Long polling** es la técnica más vieja de "tiempo real" sobre HTTP: el
cliente hace un GET normal, y el servidor **mantiene la respuesta
abierta** hasta que tiene algo que enviar (o se cumple un timeout). Al
recibir, el cliente vuelve a hacer otro GET — y así indefinidamente.

```
Browser  ── GET /poll ───────────────▶ HIX
   │                                     │
   │                                     │  espera evento (hasta 30s)
   │                                     │   .
   │                                     │   .  ¿hay novedad?  → no
   │                                     │   .  ¿hay novedad?  → sí
   │<── 200 + JSON con evento  ──────────┤
   │                                     │
   ├── GET /poll ───────────────────────>│  inmediatamente otro request
   │                                     │
   │                                     │   .
   │                                     │   . (timeout 30s sin evento)
   │<── 200 + JSON vacío ────────────────┤
   │                                     │
   ├── GET /poll ───────────────────────>│  cliente reintenta
```

A diferencia de SSE / WS:

- **Un request por evento** — cada notificación cierra el GET.
- **Sin upgrade**, sin chunked — funciona en cualquier proxy / CDN / red.
- **Más latencia** que SSE/WS por el reset constante.

---

## Cuándo usarlo

| Caso | Long polling |
|---|---|
| Cliente no soporta SSE / WS | ✅ Fallback universal |
| Pasa por proxies "raros" (corporate firewall) | ✅ Es HTTP normal |
| Pocos eventos esporádicos | ✅ Funciona |
| Dashboard con cambios cada segundo | ⚠️ Mejor SSE |
| Chat con muchos mensajes/s | ❌ Mejor WS |
| Datos binarios | ❌ Mejor WS |

> En 2026, casi siempre **SSE** es mejor opción que long polling: misma
> simplicidad, menos requests, latencia ~0. Usa long polling solo si SSE
> no encaja por restricciones del cliente o de la red.

---

## Setup

### Pool en `hix.json`

`workers_longpoll`: long polls simultáneos máximos.
`stream_timeout_s`: segundos máximos por conexión (`0` = sin límite).

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

> Igual que con SSE, cada long poll **ocupa un worker** del pool
> `pool_rest` mientras espera. Dimensiona según concurrencia.

### Ruta long poll

```clipper
oSrv:AddRouteGet( "poll", "/poll", {|| _LongPoll() } )

FUNCTION _LongPoll()
   LOCAL nStart   := Seconds()
   LOCAL nTimeout := 30                ; segundos
   LOCAL hEvent

   DO WHILE Seconds() - nStart < nTimeout
      IF _HayNuevoEvento( @hEvent )
         RETURN USendJson( { "ok" => .T., "event" => hEvent } )
      ENDIF
      hb_idleSleep( 0.5 )
   ENDDO

   // Timeout sin novedades — respuesta "vacía"
   USendJson( { "ok" => .T., "event" => NIL } )
RETURN NIL
```

> Si hay novedad → responde **inmediatamente**. Si pasa el timeout sin
> novedad → responde "vacío". El cliente reintenta en cualquier caso.

---

## Cliente JavaScript

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
    await sleep(1000)    // backoff antes de reintentar
  }

  // Inmediatamente otro poll
  poll()
}

poll()
```

> No metas `setInterval`/`setTimeout` con la frecuencia del polling — el
> servidor ya espera por ti. Reintentar **al recibir la respuesta** es el
> patrón correcto.

---

## Patrón con cursor / `last_id`

Para no re-recibir eventos ya vistos al reconectar:

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

## Comparativa rápida

| | Long poll | SSE | WebSocket |
|---|---|---|---|
| Dirección | ←→ (un evento por request) | ← (servidor → cliente) | ↔ (bidireccional) |
| Transporte | HTTP normal | HTTP normal | TCP upgrade |
| Atraviesa proxies | ✅ Sí | ✅ Sí (con buffering off) | ⚠️ Necesita config |
| Auto-reconexión | Manual (cliente) | ✅ Browser nativo | Manual (cliente) |
| Latencia | Alta (un request por evento) | Baja | Mínima |
| Carga servidor | Alta (muchos requests) | Media | Baja |
| Cliente JS | `fetch` + loop | `EventSource` | `WebSocket` |
| Complejidad | 🟢 Mínima | 🟢 Baja | 🟡 Media |
| Workers ocupados | 1 por cliente esperando | 1 por cliente conectado | 1 por cliente conectado |

---

## Patrones útiles

### Timeout corto + reintento rápido

Si tu red corta a los 60s, mejor un timeout corto:

```clipper
LOCAL nTimeout := 25    ; 25s — por debajo del corte típico

DO WHILE Seconds() - nStart < nTimeout
   ...
ENDDO
```

### Notificar fin de espera con tipo

```clipper
USendJson( { "type" => "event", "data" => hEvent } )    // hay evento
USendJson( { "type" => "idle" } )                       // timeout sin evento
```

El cliente diferencia y solo procesa los `event`.

### Combinar con cola de eventos

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

Y desde cualquier acción HTTP:

```clipper
PushEvent( { "type" => "order_created", "id" => nId } )
```

> **Caveat** — esto es FIFO global, no por cliente. Para entrega "uno a
> uno", el cliente necesita una cola propia identificada por sesión /
> token. Long poll multi-cliente con entrega garantizada se vuelve
> rápidamente más complejo que un broker dedicado.

---

## Errores típicos

| Síntoma | Causa |
|---|---|
| El cliente recibe respuesta y la vuelve a procesar | El cliente reintenta sin esperar la respuesta — pon `await` |
| Pool `pool_rest` lleno con poco tráfico | Timeout demasiado largo o clientes que no cierran al recibir |
| Cliente parece "atascado" sin recibir | El servidor está bloqueado esperando — usa `hb_idleSleep` corto en el loop |
| Eventos duplicados al reconectar | Sin cursor — añade `last_id` o `since` |
| Latencia alta entre evento y entrega | `hb_idleSleep` demasiado largo en el loop (>1s) |
| `502 Bad Gateway` aleatorio | Proxy cortando a los 60s — baja el `nTimeout` a 25-30s |

---

## Buenas prácticas

1. **Timeout `< timeout del proxy`.** Si tu Apache/Nginx cierra a los 60s,
   timeout del long poll a 25-30s. Quien debe cerrar limpio es el
   servidor, no el proxy.
2. **Reintenta al recibir, no por timer.** El siguiente poll arranca
   cuando la respuesta llega — sin solapamiento.
3. **Backoff ante errores.** Si el GET falla, espera 1-2s antes de
   reintentar. Sin esto, un servidor caído recibe 100 req/s del cliente.
4. **Cursor (`since`/`last_id`).** Para no perder ni duplicar eventos.
5. **Limita con `stream_timeout_s`.** Aunque ya tienes timeout interno, el
   límite del pool es la última defensa contra workers atascados.
6. **Prefiere SSE si es opción.** Long polling tiene sentido como
   fallback o cuando el entorno no permite SSE/WS.

