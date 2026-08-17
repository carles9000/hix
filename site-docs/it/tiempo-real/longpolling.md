# ⏳ Long polling

Il **long polling** è la più antica tecnica "real-time" su HTTP: il
client fa un GET normale, e il server **tiene la response aperta**
finché non ha qualcosa da inviare (o scade un timeout). Alla ricezione, il client fa un altro GET - e così via all'infinito.

```
Browser  ── GET /poll ───────────────▶ HIX
   │                                     │
   │                                     │  aspetta evento (fino a 30s)
   │                                     │   .
   │                                     │   .  Novità?  -> no
   │                                     │   .  Novità?  -> sì
   │<── 200 + JSON con evento  ──────────┤
   │                                     │
   ├── GET /poll ───────────────────────>│  immediatamente un'altra request
   │                                     │
   │                                     │   .
   │                                     │   . (timeout 30s senza evento)
   │<── 200 + JSON vuoto ────────────────┤
   │                                     │
   ├── GET /poll ───────────────────────>│  il client riprova
```

A differenza di SSE / WS:
- **Una request per evento** - ogni notifica chiude il GET.
- **Niente upgrade, niente chunked** - funziona attraverso qualsiasi proxy / CDN / rete.
- **Latenza più alta** di SSE/WS a causa del reset costante.

---

## Quando usarlo

| Caso | Long polling |
|---|---|
| Il client non supporta SSE / WS | ✅ Fallback universale |
| Passa attraverso proxy "strani" (firewall aziendale) | ✅ È HTTP normale |
| Pochi eventi sporadici | ✅ Funziona |
| Dashboard con cambiamenti ogni secondo | ⚠️ Meglio SSE |
| Chat con molti messaggi/s | ❌ Meglio WS |
| Dati binari | ❌ Meglio WS |

> Nel 2026, **SSE** è quasi sempre la scelta migliore rispetto al long polling: stessa
> semplicità, meno request, latenza ~0. Usa il long polling solo se SSE non è adatto
> per vincoli del client o della rete.

---

## Setup

### Pool in `hix.json`

`workers_longpoll`: massimo numero di long poll concorrenti.
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

> Proprio come SSE, ogni long poll **occupa un worker** dal pool
> `pool_rest` durante l'attesa. Dimensiona in base alla concorrenza.

### Route long poll

```clipper
oSrv:AddRouteGet( "poll", "/poll", {|| _LongPoll() } )

FUNCTION _LongPoll()
   LOCAL nStart   := Seconds()
   LOCAL nTimeout := 30                ; secondi
   LOCAL hEvent

   DO WHILE Seconds() - nStart < nTimeout
      IF _HayNuevoEvento( @hEvent )
         RETURN USendJson( { "ok" => .T., "event" => hEvent } )
      ENDIF
      hb_idleSleep( 0.5 )
   ENDDO

   // Timeout senza novità - risposta "vuota"
   USendJson( { "ok" => .T., "event" => NIL } )
RETURN NIL
```

> Se ci sono novità → rispondi **immediatamente**. Se scade il timeout senza
> novità → rispondi "vuoto". Il client riprova in entrambi i casi.

---

## Client JavaScript

```javascript
async function poll() {
  try {
    const resp = await fetch("/poll")
    const data = await resp.json()

    if (data.event) {
      _ProcesarEvento(data.event)
    }
  } catch (e) {
    console.error("Errore poll", e)
    await sleep(1000)    // backoff prima di riprovare
  }

  // Immediatamente un altro poll
  poll()
}

poll()
```

> Non mischiare `setInterval`/`setTimeout` con la frequenza di polling - il
> server ti sta già aspettando. Riprova **quando ricevi la risposta** è il
> pattern corretto.

---

## Pattern con cursore / `last_id`

Per evitare di ricevere di nuovo eventi già visti alla riconnessione:

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

## Confronto rapido

| | Long poll | SSE | WebSocket |
|---|---|---|---|
| Direzione | ←→ (un evento per request) | ← (server → client) | ↔ (bidirezionale) |
| Transport | HTTP normale | HTTP normale | TCP upgrade |
| Passa attraverso proxy | ✅ Sì | ✅ Sì (con buffering off) | ⚠️ Richiede config |
| Riconnessione automatica | Manuale (client) | ✅ Browser nativo | Manuale (client) |
| Latenza | Alta (una request per evento) | Bassa | Minima |
| Carico server | Alto (molte request) | Medio | Basso |
| Client JS | `fetch` + loop | `EventSource` | `WebSocket` |
| Complessità | 🟢 Minima | 🟢 Bassa | 🟡 Media |
| Worker occupati | 1 per client in attesa | 1 per client connesso | 1 per client connesso |

---

## Pattern utili

### Timeout breve + retry veloce

Se la tua rete taglia a 60s, meglio un timeout breve:

```clipper
LOCAL nTimeout := 25    ; 25s - sotto il taglio tipico
```

### Notifica fine attesa con tipo

```clipper
USendJson( { "type" => "event", "data" => hEvent } )    // c'è un evento
USendJson( { "type" => "idle" } )                       // timeout senza evento
```

Il client differenzia e processa solo i tipi `event`.

### Combina con la coda eventi

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

E da qualsiasi action HTTP:

```clipper
PushEvent( { "type" => "order_created", "id" => nId } )
```

> **Attenzione** - questa è una FIFO globale, non per client. Per la consegna "uno a uno",
> il client ha bisogno della propria coda identificata da session /
> token. Long poll multi-client con consegna garantita diventa rapidamente
> più complesso di un broker dedicato.

---

## Errori comuni

| Sintomo | Causa |
|---|---|
| Il client riceve la risposta e la processa di nuovo | Il client riprova senza aspettare la risposta - aggiungi `await` |
| Pool `pool_rest` pieno con traffico basso | Timeout troppo lungo o client che non chiudono alla ricezione |
| Il client sembra "bloccato" senza ricevere | Il server è bloccato in attesa - usa `hb_idleSleep` brevi nel loop |
| Eventi duplicati alla riconnessione | Nessun cursore - aggiungi `last_id` o `since` |
| Latenza alta tra evento e consegna | `hb_idleSleep` troppo lungo nel loop (>1s) |
| `502 Bad Gateway` casuali | Proxy che taglia a 60s - abbassa `nTimeout` a 25-30s |

---

## Best practice

1. **Timeout `<` timeout del proxy.** Se il tuo Apache/Nginx taglia a 60s,
   il timeout del long poll a 25-30s. Il server dovrebbe chiudere in modo pulito,
   non il proxy.
2. **Riprova alla ricezione, non tramite timer.** Il prossimo poll parte
   quando arriva la risposta - niente sovrapposizioni.
3. **Backoff su errore.** Se il GET fallisce, aspetta 1-2s prima di
   riprovare. Senza questo, un server giù riceve 100 req/s dal client.
4. **Cursore (`since`/`last_id`).** Per non perdere o duplicare eventi.
5. **Limita con `stream_timeout_s`.** Anche se hai un timeout interno, il
   limite del pool è l'ultima difesa contro worker bloccati.
6. **Preferisci SSE se è un'opzione.** Il long polling ha senso come
   fallback o quando l'ambiente non permette SSE/WS.
