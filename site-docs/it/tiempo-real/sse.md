# 📡 SSE - Server-Sent Events

**Server-Sent Events** è push **unidirezionale** dal server al client
su HTTP normale. Il client apre la connessione con un GET e la tiene
aperta; il server invia "eventi" in formato `text/event-stream`
senza mai chiudere la response (o fino a un timeout).

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
   │                                    │  ...per minuti/ore
```

Vs WebSocket:

- **Più semplice**: HTTP normale, niente upgrade, passa attraverso proxy e
  firewall senza alcuna configurazione.
- **Solo server → client**: il client non può inviare nulla sullo
  stesso canale (usa un POST separato se necessario).
- **Riconnessione automatica**: il browser si riconnette automaticamente se il
  canale cade - WS non lo fa.

---

## Quando usarlo

| Caso | SSE |
|---|---|
| Dashboard con aggiornamenti live | ✅ Ideale |
| Stream di log di una web console | ✅ Ideale |
| Notifiche push (unidirezionali) | ✅ Ideale |
| Chat bidirezionale | ❌ Meglio [WebSocket](ws.md) |
| Dati binari (immagini, audio) | ❌ SSE è solo testo - usa WS |
| Client con internet instabile | ✅ Si riconnette automaticamente |
| Comportamento request/response standard | ❌ HTTP normale |

---

## Formato `text/event-stream`

Ogni evento è **uno o più campi `key: value`** seguiti da **una riga vuota**:

```
data: hello

data: {"n":1}

event: notice
data: {"msg":"update"}

id: 42
data: {"order":42,"status":"shipped"}

retry: 5000
data: configura solo il retry, nessun payload utile
```

| Campo | Significato |
|---|---|
| `data:` | Payload - la riga vuota alla fine chiude l'evento |
| `event:` | Nome evento - il client può filtrare per nome |
| `id:` | Identificativo - il browser lo invia come `Last-Event-ID` alla riconnessione |
| `retry:` | Millisecondi da aspettare per la riconnessione |
| `: comment` | Commento / keep-alive - il browser lo ignora |

Ogni chunk che invii **deve finire con `\n\n`** (riga vuota) perché il
browser elabori l'evento.

---

## Setup

### Pool dedicato in `hix.json`

`workers_sse`: massimo numero di connessioni SSE concorrenti.
`stream_timeout_s`: secondi massimi per connessione (`0` = nessun limite).

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

> Ogni connessione SSE **occupa un worker dal pool `pool_rest`** finché
> non si chiude. 20 connessioni simultanee = `workers_sse = 20`. Se ti aspetti 200
> utenti che visualizzano il dashboard live, alza `workers_sse` a 200.

### Route SSE

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

> `X-Accel-Buffering: no` disabilita il buffering di Nginx - senza di esso,
> Nginx può tenere i tuoi chunk in memoria fino all'arrivo della response "completa"
> e il client non vedrà nulla in tempo reale.

---

## API Stream

| Funzione | Cosa fa |
|---|---|
| `USendStreamStart( cMime, nStatus, hExtra )` | Invia gli header + apre lo stream |
| `USendChunk( cData )` | Invia un chunk (un evento SSE completo, con `\n\n` finale) |
| `USendStreamEnd()` | Chiude lo stream in modo pulito |

Internamente HIX usa **transfer-encoding chunked** e tiene il socket
aperto tra le chiamate.

---

## Client JavaScript

```javascript
const evt = new EventSource("/events")

evt.onmessage = (e) => {
  // evento senza "event:" -> onmessage
  const data = JSON.parse(e.data)
  console.log("Tick:", data.n)
}

evt.addEventListener("notice", (e) => {
  console.log("Notice:", e.data)
})

evt.onerror = (e) => {
  // Il browser riproverà automaticamente
  console.log("Errore / disconnessione", e)
}

// Chiudi manualmente
// evt.close()
```

> Il browser si riconnette automaticamente. Se hai bisogno di evitare duplicati, invia
> `id:` in ogni evento e alla riconnessione il browser allegherà l'header `Last-Event-ID`
> automaticamente.

---

## Pattern utili

### Heartbeat per prevenire i timeout dei proxy

I proxy chiudono i socket inattivi (60-120s tipicamente). Invia un
commento `:` ogni X secondi:

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

### Eventi con nome e filtro lato client

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

### Recupero dopo riconnessione (`Last-Event-ID`)

```clipper
FUNCTION _StreamEvents()
   LOCAL nLastId := Val( UHeader( "last-event-id", "0" ) )

   USendStreamStart( "text/event-stream", 200, { "Cache-Control" => "no-cache" } )

   // Re-emetti gli eventi persi da nLastId
   FOR EACH hEvent IN _GetEventsSince( nLastId )
      USendChunk( "id: "   + hb_NToS( hEvent["id"] ) + hb_eol() + ;
                  "data: " + hb_jsonEncode( hEvent ) + hb_eol() + hb_eol() )
   NEXT

   // Continua con i nuovi eventi
   DO WHILE _HayMas( nLastId, @hNext )
      USendChunk( "id: "   + hb_NToS( hNext["id"] ) + hb_eol() + ;
                  "data: " + hb_jsonEncode( hNext ) + hb_eol() + hb_eol() )
      nLastId := hNext["id"]
      hb_idleSleep( 1 )
   ENDDO

   USendStreamEnd()
RETURN NIL
```

### Il client chiude → esci dal loop

Rilevare la disconnessione del client è complicato: in HTTP standard il server
non riceve notifica immediata. L'approccio usuale è controllare il flag di errore
durante la scrittura:

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

> **Limita sempre con `stream_timeout_s`** nel pool. Anche se non rilevi
> la disconnessione, il worker viene liberato allo scadere del timeout.

---

## SSE Broadcast

I chunk sono inviati **per connessione**. Se vuoi inviare lo stesso evento
a N client, mantieni una lista:

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

   // Deregistra
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

E da qualsiasi action HTTP:

```clipper
SseBroadcast( hb_jsonEncode( { "type" => "order_created", "id" => nId } ) )
```

---

## Dietro un proxy

| Proxy | Trucco |
|---|---|
| **Nginx** | `proxy_buffering off;` + `proxy_read_timeout 24h;` |
| **Apache** | Normale `ProxyPass` - funziona |
| **Cloudflare** | Funziona, ma con timeout di 100s - invia heartbeat ogni 30s |

### Nginx

```nginx
location /events {
   proxy_pass http://127.0.0.1:8080/events;
   proxy_http_version 1.1;
   proxy_set_header Connection "";
   proxy_buffering off;             # critico per SSE
   proxy_cache off;
   proxy_read_timeout 24h;
}
```

> L'header `X-Accel-Buffering: no` nella response lo disabilita
> per richiesta - utile se non controlli la tua config Nginx.

---

## Errori comuni

| Sintomo | Causa |
|---|---|
| Il client riceve tutto quando lo stream si chiude, non in tempo reale | Buffering del proxy - aggiungi `X-Accel-Buffering: no` |
| Il client si riconnette ogni 60s | Proxy con `proxy_read_timeout` basso - alza a ore |
| Eventi duplicati alla riconnessione | Non usi `id:` - il browser riceve di nuovo gli ultimi |
| `Content-Type` sbagliato | Dimenticato `text/event-stream` in `USendStreamStart` |
| Appare solo il primo evento | Manca `\n\n` alla fine di ogni chunk |
| Pool SSE esaurito | `pool_rest.workers_sse` troppo basso per la concorrenza attesa |
| Memory leak con client che chiudono silenziosamente | Il loop non controlla `lClosed` o manca `stream_timeout_s` |

---

## Best practice

1. **Sempre `\n\n` alla fine del chunk.** Senza la riga vuota, il
   browser accumula senza far partire l'evento.
2. **`X-Accel-Buffering: no`** negli header - protegge da Nginx di default.
3. **Heartbeat ogni 20-30s.** I commenti `:` tengono vivo il socket
   e rilevi la disconnessione prima.
4. **Usa `id:` se l'ordine conta.** Con `Last-Event-ID` puoi
   riprendere da dove si è interrotto.
5. **Limita con `stream_timeout_s`.** Una connessione SSE appesa blocca un
   worker - il timeout hard lo libera.
6. **Non bloccare con I/O sincrono.** Ogni SSE vive nel suo worker; se
   aspetti un DB lento, il client aspetta anche lui. Meglio un
   buffer intermedio + worker dedicato.
