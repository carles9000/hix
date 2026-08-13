# 🔌 WebSocket

Una connessione **WebSocket** apre un canale bidirezionale persistente tra
il browser e il server su TCP, dopo un handshake HTTP. A differenza del normale HTTP -
request/response - WS lascia il socket aperto ed entrambi i lati possono inviare messaggi
quando vogliono, senza header per ciascuno.

Ideale per:
- **Chat** / messaggistica in tempo reale.
- **Notifiche push** (stato ordini, alert).
- **Dashboard** che si aggiornano istantaneamente (senza polling).
- **Collaborazione live** (cursori condivisi, editing simultaneo).
- **Giochi** e simulazioni a bassa latenza.

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

## Quando NON usarlo

| Caso | Opzione migliore |
|---|---|
| Solo il server invia dati (nessuna risposta del client) | [SSE](sse.md) - più semplice |
| Eventi sporadici (ogni minuto/ora) | [Long polling](longpolling.md) o webhook |
| Comunicazione request/response normale | HTTP standard |
| Client senza supporto WebSocket (raro nel 2026) | SSE come fallback |

> WS apre un socket **permanente** per ogni client connesso. 10.000 client
> = 10.000 socket aperti. Dimensiona `pool_ws` per supportarli.

---

## Setup

### Pool dedicato in `hix.json`

`workers`: massimo numero di connessioni WS concorrenti.
`ping_interval_s`: secondi tra i ping server → client.
`ping_timeout_s`: secondi per la risposta del client al ping.

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

> Ogni connessione WS attiva **blocca** un worker finché non si chiude. Se ti aspetti
> 500 client concorrenti, alza `workers` a 500.

### Callback sul server

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

> Non c'è un URL specifico per WS - l'handshake è rilevato dagli header `Upgrade: websocket`,
> non dal path. Ogni connessione WS che raggiunge il server passa attraverso
> queste tre callback.

---

## `THixWsConn` — la connessione attiva

Ogni callback riceve l'oggetto `oConn` con la connessione corrente:

| Proprietà / metodo | Tipo | Significato |
|---|---|---|
| `oConn:cIP` | stringa | IP del client |
| `oConn:lClosed` | logico | `.T.` se già chiuso |
| `oConn:Send( cText )` | metodo | Invia frame di testo (opcode 1) |
| `oConn:SendBinary( cData )` | metodo | Invia frame binario (opcode 2) |
| `oConn:Close()` | metodo | Chiude la connessione (opcode 8) |

### Pattern tipico

```clipper
oSrv:bOnWsMessage := {|oConn, cMsg, nOpcode|
   LOCAL hData

   IF nOpcode == 8         // CLOSE - il client chiude
      oConn:Close()
      RETURN NIL
   ENDIF

   IF nOpcode == 9         // PING - HIX risponde pong automaticamente
      RETURN NIL
   ENDIF

   IF nOpcode == 1         // testo
      hData := hb_jsonDecode( cMsg )    // prova a parsare come JSON
      _ProcessClientMessage( oConn, hData )
   ENDIF
}
```

---

## Client JavaScript

```javascript
const ws = new WebSocket("wss://app.com/ws")

ws.onopen    = () => console.log("Connesso")
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data)
  console.log("Ricevuto:", msg)
}
ws.onerror   = (e) => console.error("Errore WS", e)
ws.onclose   = () => console.log("Chiuso")

// Invia messaggio
ws.send( JSON.stringify({ action: "subscribe", channel: "orders" }) )
```

> **Usa sempre `wss://` quando servi HTTPS.** Mischiare `ws://` con
> `https://` causa mixed-content e il browser lo blocca.

---

## Broadcast a più client

HIX non include un broadcaster nativo - mantienilo manualmente in un array condiviso
(con mutex):

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

E nelle callback:

```clipper
oSrv:bOnWsConnect := {|oConn| WsRegister( oConn ) }
oSrv:bOnWsClose   := {|oConn| WsUnregister( oConn ) }

// Da qualsiasi action HTTP:
WsBroadcast( hb_jsonEncode( { "type" => "new_order", "id" => nId } ) )
```

---

## Ping / pong

HIX invia un **ping automatico** ogni `ping_interval_s` secondi. Se il
client non risponde con il pong entro `ping_timeout_s` secondi, HIX chiude la
connessione.

Usato per:
- Rilevare client disconnessi (router giù, mobile in sospensione).
- Mantenere la connessione viva contro proxy che tagliano i socket inattivi.

```json
{
  "pool_ws": {
    "ping_interval_s": 30,
    "ping_timeout_s":  10
  }
}
```

> 30s/10s sono valori ragionevoli. Se passi attraverso Cloudflare o altri proxy che
> tagliano a 100s di inattività, usa `ping_interval_s` più basso (15-20s).

---

## Autenticazione

L'handshake WS porta i normali header HTTP (cookie inclusi) -
puoi leggere il cookie di sessione in `bOnWsConnect`:

```clipper
oSrv:bOnWsConnect := {|oConn|
   // A questo punto HIX_GetRequest() non è disponibile -
   // cattura i dati durante l'handshake se ti servono.
   l( "WS connect da " + oConn:cIP )
}
```

Per l'auth, l'approccio usuale è **passare un token** come query string:

```javascript
const ws = new WebSocket("wss://app.com/ws?token=" + jwt)
```

E validalo in `bOnWsConnect` (leggi la request originale): se non è
valido, `oConn:Close()` prima di registrare.

---

## Pattern utili

### Sottoscrizioni per canale

```clipper
// Stato per connessione - usa l'hash della connessione come chiave
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

// Pubblica su un canale specifico
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

### Messaggi binari - invia bytes

```clipper
LOCAL cImage := hb_MemoRead( "thumbnail.png" )
oConn:SendBinary( cImage )
```

Il client riceve un `Blob` (browser) o `Buffer` (Node):

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

## Dietro un proxy

Affinché un reverse proxy (Apache/Nginx) faccia passare l'upgrade WS:

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

> **`proxy_read_timeout` lungo** (24h qui) - senza di esso il proxy chiude
> il WS al primo minuto di inattività, anche con ping/pong.

---

## Errori comuni

| Sintomo | Causa |
|---|---|
| Connessione rifiutata `WebSocket handshake failed` | Pool WS senza worker - alza `pool_ws.workers` |
| Il client si disconnette a 60s | Proxy con `proxy_read_timeout` basso (Nginx default 60s) |
| `Mixed Content` nel browser | Pagina HTTPS che apre `ws://` - usa `wss://` |
| `bOnWsMessage` non si attiva mai | Opcode sbagliato sul client, o frame più grande del buffer (>1MB) |
| WS si apre e si chiude immediatamente | Il client non risponde al ping entro `ping_timeout_s` |
| La memoria continua a crescere | Non stai deregistrando le connessioni in `bOnWsClose` |

---

## Best practice

1. **Cleanup in `bOnWsClose`.** Se mantieni un registro delle connessioni,
   cancella l'entry - senza di esso, tieni riferimenti a socket morti.
2. **JSON per i messaggi.** Il testo semplice è ambiguo; il JSON rende il
   tipo chiaro (`{ "type": "ping", "data": ... }`).
3. **Non bloccare la callback.** `bOnWsMessage` gira nel worker -
   se fai I/O lento lì, gli altri client aspettano. Per task pesanti,
   dispatcha su un altro thread.
4. **WSS in produzione.** Proprio come HTTPS: niente WS in chiaro su internet.
5. **Heartbeat opzionale dal client.** Oltre al ping/pong di HIX,
   un messaggio applicativo ogni N secondi conferma che la logica del client è viva.
6. **Accordo sul protocollo.** Definisci una versione nell'handshake o nel primo
   messaggio (`{ "v": 1, ... }`) - quando evolvi, il client
   sa se capisce il server.
