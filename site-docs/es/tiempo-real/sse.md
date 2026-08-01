# 📡 SSE - Server-Sent Events

**Server-Sent Events** es push **unidireccional** del servidor al cliente
sobre HTTP normal. El cliente abre la conexión con un GET y la mantiene
abierta; el servidor va enviando "eventos" en formato `text/event-stream`
sin cerrar la respuesta nunca (o hasta un timeout).

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
   │                                    │  ...durante minutos/horas
```

Vs WebSocket:

- **Más simple**: HTTP normal, no necesita upgrade, atraviesa proxies y
  firewalls sin configurar nada.
- **Solo servidor → cliente**: el cliente no puede mandar nada por el
  mismo canal (usa un POST aparte si lo necesitas).
- **Auto-reconexión**: el navegador reconecta automáticamente al perder
  el canal - WS no hace eso.

---

## Cuándo usarlo

| Caso | SSE |
|---|---|
| Dashboard que se actualiza en vivo | ✅ Ideal |
| Stream de logs en consola web | ✅ Ideal |
| Notificaciones push (un solo sentido) | ✅ Ideal |
| Chat bidireccional | ❌ Mejor [WebSocket](ws.md) |
| Datos binarios (imágenes, audio) | ❌ SSE es solo texto - usa WS |
| Cliente sin internet estable | ✅ Reconecta solo |
| Comportamiento request/response | ❌ HTTP normal |

---

## Formato `text/event-stream`

Cada evento es **uno o varios campos `key: valor`** seguidos de **una
línea en blanco**:

```
data: hola

data: {"n":1}

event: notice
data: {"msg":"actualización"}

id: 42
data: {"order":42,"status":"shipped"}

retry: 5000
data: solo configura retry, sin payload útil
```

| Campo | Significado |
|---|---|
| `data:` | Payload - la línea en blanco al final cierra el evento |
| `event:` | Nombre de evento - el cliente puede filtrar por nombre |
| `id:` | Identificador - el navegador lo envía como `Last-Event-ID` al reconectar |
| `retry:` | Milisegundos de espera para reconexión |
| `: comentario` | Comentario / keep-alive - el navegador lo ignora |

Cada chunk tuyo **debe terminar en `\n\n`** (línea en blanco) para que el
navegador procese el evento.

---

## Setup

### Pool dedicado en `hix.json`

`workers_sse`: conexiones SSE simultáneas máximas.
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

> Cada conexión SSE **ocupa un worker del pool `pool_rest`** hasta que
> cierra. 20 conexiones simultáneas = `workers_sse = 20`. Si esperas 200
> usuarios viendo el dashboard en vivo, sube `workers_sse` a 200.

### Ruta SSE

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

> `X-Accel-Buffering: no` desactiva el buffering de Nginx - sin esto,
> Nginx puede guardar tus chunks en memoria hasta que llegue la respuesta
> "completa" y el cliente no vería nada en tiempo real.

---

## API de stream

| Función | Qué hace |
|---|---|
| `USendStreamStart( cMime, nStatus, hExtra )` | Manda cabeceras + abre el stream |
| `USendChunk( cData )` | Manda un chunk (un evento SSE entero, con `\n\n` final) |
| `USendStreamEnd()` | Cierra el stream limpiamente |

Internamente HIX usa **transfer-encoding chunked** y mantiene el socket
abierto entre llamadas.

---

## Cliente JavaScript

```javascript
const evt = new EventSource("/events")

evt.onmessage = (e) => {
  // evento sin "event:" → onmessage
  const data = JSON.parse(e.data)
  console.log("Tick:", data.n)
}

evt.addEventListener("notice", (e) => {
  console.log("Aviso:", e.data)
})

evt.onerror = (e) => {
  // El navegador reintentará automáticamente
  console.log("Error / desconexión", e)
}

// Cerrar manualmente
// evt.close()
```

> El navegador reconecta solo. Si necesitas evitar duplicados, manda
> `id:` en cada evento y al reconectar usa el header `Last-Event-ID` que
> el navegador adjunta automáticamente.

---

## Patrones útiles

### Heartbeat para evitar timeouts de proxy

Los proxies cierran sockets idle (60-120s típicamente). Manda un
comentario `:` cada X segundos:

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

### Eventos con nombre y filtro en cliente

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

### Recuperar tras reconexión (`Last-Event-ID`)

```clipper
FUNCTION _StreamEvents()
   LOCAL nLastId := Val( UHeader( "last-event-id", "0" ) )

   USendStreamStart( "text/event-stream", 200, { "Cache-Control" => "no-cache" } )

   // Re-emite eventos perdidos desde nLastId
   FOR EACH hEvent IN _GetEventsSince( nLastId )
      USendChunk( "id: "   + hb_NToS( hEvent["id"] ) + hb_eol() + ;
                  "data: " + hb_jsonEncode( hEvent ) + hb_eol() + hb_eol() )
   NEXT

   // Continúa con eventos nuevos
   DO WHILE _HayMas( nLastId, @hNext )
      USendChunk( "id: "   + hb_NToS( hNext["id"] ) + hb_eol() + ;
                  "data: " + hb_jsonEncode( hNext ) + hb_eol() + hb_eol() )
      nLastId := hNext["id"]
      hb_idleSleep( 1 )
   ENDDO

   USendStreamEnd()
RETURN NIL
```

### Cliente cierra → terminar el loop

Detectar la desconexión es delicado: en HTTP estándar el servidor no
recibe notificación inmediata. Lo habitual es chequear el flag de error
al hacer el write:

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

> **Limita siempre con `stream_timeout_s`** en el pool. Aunque no detectes la
> desconexión, el worker se libera al expirar.

---

## Broadcast SSE

Los chunks se mandan **por conexión**. Si quieres mandar el mismo evento
a N clientes, mantén una lista:

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

   // Desregistrar
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

Y desde cualquier acción HTTP:

```clipper
SseBroadcast( hb_jsonEncode( { "type" => "order_created", "id" => nId } ) )
```

---

## Detrás de proxy

| Proxy | Truco |
|---|---|
| **Nginx** | `proxy_buffering off;` + `proxy_read_timeout 24h;` |
| **Apache** | `ProxyPass` normal - funciona |
| **Cloudflare** | Funciona, pero con timeout de 100s - manda heartbeats cada 30s |

### Nginx

```nginx
location /events {
   proxy_pass http://127.0.0.1:8080/events;
   proxy_http_version 1.1;
   proxy_set_header Connection "";
   proxy_buffering off;             # crítico para SSE
   proxy_cache off;
   proxy_read_timeout 24h;
}
```

> El header `X-Accel-Buffering: no` en el response también lo desactiva
> por request - útil si no controlas la config de Nginx.

---

## Errores típicos

| Síntoma | Causa |
|---|---|
| Cliente recibe todo al cerrarse el stream, no en vivo | Buffering de proxy - añade `X-Accel-Buffering: no` |
| Cliente reconecta cada 60s | Proxy con `proxy_read_timeout` bajo - sube a horas |
| Eventos llegan duplicados al reconectar | No usas `id:` - el navegador re-recibe los últimos |
| `Content-Type` mal | Olvido de `text/event-stream` en `USendStreamStart` |
| Solo se ve el primer evento | Falta el `\n\n` final en cada chunk |
| Pool SSE agotado | `pool_rest.workers_sse` demasiado bajo para concurrencia esperada |
| Memory leak con clientes que cierran sin avisar | El loop no detecta `lClosed` o falta `stream_timeout_s` |

---

## Buenas prácticas

1. **Siempre `\n\n` al final del chunk.** Sin la línea en blanco, el
   navegador acumula sin disparar evento.
2. **`X-Accel-Buffering: no`** en cabeceras - protege contra Nginx por
   defecto.
3. **Heartbeats cada 20-30s.** Los comentarios `:` mantienen el socket
   vivo y detectas antes la desconexión.
4. **Usa `id:` si el orden importa.** Con `Last-Event-ID` puedes
   reanudar desde donde se cortó.
5. **Limita con `stream_timeout_s`.** Una conexión SSE colgada bloquea un
   worker - el timeout duro lo libera.
6. **No bloquees con I/O síncrona.** Cada SSE vive en su worker; si
   esperas BD lenta, el cliente espera con él. Mejor un buffer
   intermedio + worker dedicado.

