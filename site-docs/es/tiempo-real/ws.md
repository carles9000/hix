# 🔌 WebSocket

Una conexión **WebSocket** abre un canal bidireccional persistente entre
el navegador y el servidor sobre TCP, después de un handshake HTTP. A
diferencia de HTTP normal - request/response - un WS deja el socket
abierto y ambos extremos pueden enviar mensajes cuando quieran, sin
cabeceras por cada uno.

Ideal para:

- **Chat** / mensajería en tiempo real.
- **Notificaciones push** (estado de pedidos, alertas).
- **Dashboards** que se actualizan al instante (sin polling).
- **Colaboración en vivo** (cursores compartidos, edición simultánea).
- **Juegos** y simulaciones de baja latencia.

```
Browser                                       HIX
   │                                            │
   │── GET /ws + Upgrade: websocket  ──────────>│  handshake
   │                                            │
   │<── HTTP 101 Switching Protocols  ──────────┤
   │                                            │
   │── frame "hola"  ──────────────────────────>│  bOnWsMessage
   │                                            │
   │<── frame "hola tú también" ────────────────┤  oConn:Send(...)
   │                                            │
   │── ping ───────────────────────────────────>│
   │<── pong  ──────────────────────────────────┤
   │                                            │
   │── frame CLOSE ────────────────────────────>│  bOnWsClose
```

---

## Cuándo NO usarlo

| Caso | Mejor opción |
|---|---|
| Solo el servidor empuja datos (no hay respuesta del cliente) | [SSE](sse.md) - más simple |
| Eventos esporádicos (cada minuto/hora) | [Long polling](longpolling.md) o webhook |
| Comunicación request/response normal | HTTP estándar |
| Cliente sin soporte WebSocket (raro en 2026) | SSE como fallback |

> WS abre un socket **permanente** por cliente conectado. 10 000 clientes
> = 10 000 sockets abiertos. Dimensiona `pool_ws` para soportarlos.

---

## Setup

### Pool dedicado en `hix.json`

`workers`: conexiones WS simultáneas máximas.
`ping_interval_s`: segundos entre pings server → client.
`ping_timeout_s`: segundos para que el cliente responda al ping.

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

> Cada conexión WS activa **bloquea** un worker hasta cerrar. Si esperas
> 500 clientes concurrentes, sube `workers` a 500.

### Callbacks en el servidor

```clipper
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()

   oSrv:bOnWsConnect := {|oConn|
      l( "WS connect: " + oConn:cIP )
   }

   oSrv:bOnWsMessage := {|oConn, cMsg, nOpcode|
      // nOpcode: 1=texto, 2=binario, 8=close, 9=ping, 10=pong
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

> No hay URL específica para WS - el handshake `Upgrade: websocket` se
> detecta por cabeceras, no por path. Toda conexión WS que llegue al
> servidor pasa por estos tres callbacks.

---

## `THixWsConn` - la conexión activa

Cada callback recibe el objeto `oConn` con la conexión actual:

| Propiedad / método | Tipo | Significado |
|---|---|---|
| `oConn:cIP` | string | IP del cliente |
| `oConn:lClosed` | lógico | `.T.` si ya se cerró |
| `oConn:Send( cText )` | método | Envía frame texto (opcode 1) |
| `oConn:SendBinary( cData )` | método | Envía frame binario (opcode 2) |
| `oConn:Close()` | método | Cierra la conexión (opcode 8) |

### Patrón típico

```clipper
oSrv:bOnWsMessage := {|oConn, cMsg, nOpcode|
   LOCAL hData

   IF nOpcode == 8         // CLOSE - el cliente cierra
      oConn:Close()
      RETURN NIL
   ENDIF

   IF nOpcode == 9         // PING - HIX responde pong automático
      RETURN NIL
   ENDIF

   IF nOpcode == 1         // texto
      hData := hb_jsonDecode( cMsg )    // intenta parsear como JSON
      _ProcessClientMessage( oConn, hData )
   ENDIF
}
```

---

## Cliente JavaScript

```javascript
const ws = new WebSocket("wss://app.com/ws")

ws.onopen    = () => console.log("Conectado")
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data)
  console.log("Recibido:", msg)
}
ws.onerror   = (e) => console.error("Error WS", e)
ws.onclose   = () => console.log("Cerrado")

// Enviar mensaje
ws.send( JSON.stringify({ action: "subscribe", channel: "orders" }) )
```

> **Usa `wss://` siempre que sirvas HTTPS.** Mezclar `ws://` con
> `https://` da mixed-content y el navegador bloquea.

---

## Broadcast a varios clientes

HIX no incluye un broadcaster nativo - manténlo a mano en un array
compartido (con mutex):

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

Y en los callbacks:

```clipper
oSrv:bOnWsConnect := {|oConn| WsRegister( oConn ) }
oSrv:bOnWsClose   := {|oConn| WsUnregister( oConn ) }

// Desde cualquier acción HTTP:
WsBroadcast( hb_jsonEncode( { "type" => "new_order", "id" => nId } ) )
```

---

## Ping / pong

HIX envía un **ping automático** cada `ping_interval_s` segundos. Si el
cliente no responde con pong en `ping_timeout_s` segundos, HIX cierra la
conexión.

Sirve para:

- Detectar clientes desconectados (router cayó, móvil en suspensión).
- Mantener la conexión viva contra proxies que cortan sockets idle.

```json
{
  "pool_ws": {
    "ping_interval_s": 30,
    "ping_timeout_s":  10
  }
}
```

> 30s/10s son valores sanos. Si pasas por Cloudflare u otros proxies que
> cortan a los 100s idle, `ping_interval_s` menor (15-20).

---

## Autenticación

El handshake WS lleva las cabeceras HTTP normales (cookies incluidas) -
puedes leer la cookie de sesión en `bOnWsConnect`:

```clipper
oSrv:bOnWsConnect := {|oConn|
   // En este momento HIX_GetRequest() no está disponible -
   // captúrate los datos durante el handshake si los necesitas.
   l( "WS connect from " + oConn:cIP )
}
```

Para auth, lo habitual es **pasar un token** como query string:

```javascript
const ws = new WebSocket("wss://app.com/ws?token=" + jwt)
```

Y validarlo en `bOnWsConnect` (lectura del request original): si no es
válido, `oConn:Close()` antes de registrar.

---

## Patrones útiles

### Subscriptions por canal

```clipper
// Estado por conexión - usar el hash de la conexión como llave
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

// Publicar a un canal concreto
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

### Mensajes binarios - enviar bytes

```clipper
LOCAL cImage := hb_MemoRead( "thumbnail.png" )
oConn:SendBinary( cImage )
```

El cliente recibe un `Blob` (browser) o `Buffer` (Node):

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

## Detrás de proxy

Para que un reverse proxy (Apache/Nginx) deje pasar el upgrade WS:

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

> **`proxy_read_timeout` largo** (24h aquí) - sin esto el proxy cierra
> el WS al primer minuto idle, aunque tengas ping/pong.

---

## Errores típicos

| Síntoma | Causa |
|---|---|
| Conexión rechazada `WebSocket handshake failed` | Pool WS sin workers libres - sube `pool_ws.workers` |
| Cliente desconecta a los 60s | Proxy con `proxy_read_timeout` bajo (Nginx default 60s) |
| `Mixed Content` en navegador | Página HTTPS abriendo `ws://` - usa `wss://` |
| `bOnWsMessage` nunca dispara | Opcode incorrecto en cliente, o frame mayor que buffer (>1MB) |
| WS abre y cierra inmediatamente | Cliente no responde al ping en `ping_timeout_s` |
| Memoria sube sin parar | No estás des-registrando conexiones en `bOnWsClose` |

---

## Buenas prácticas

1. **Limpieza en `bOnWsClose`.** Si llevas un registro de conexiones,
   borra la entrada - sin esto, mantienes referencias a sockets muertos.
2. **JSON para mensajes.** Texto plano es ambiguo; JSON deja claro el
   tipo (`{ "type": "ping", "data": ... }`).
3. **No bloquees el callback.** `bOnWsMessage` se ejecuta en el worker -
   si haces I/O lento ahí, otros clientes esperan. Para tareas pesadas,
   despacha a otro hilo.
4. **WSS en producción.** Igual que HTTPS: nada de WS plano por internet.
5. **Heartbeat opcional desde el cliente.** Además del ping/pong de HIX,
   un mensaje aplicativo cada N segundos te confirma que la lógica del
   cliente sigue viva.
6. **Acuerdo de protocolo.** Define una versión en el handshake o en el
   primer mensaje (`{ "v": 1, ... }`) - cuando evoluciones, el cliente
   sabe si entiende el servidor.

