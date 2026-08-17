# 🕒 Metriche

HIX mantiene in memoria un set di **counter atomici** che descrivono in tempo reale
la salute e il carico del server: richieste servite, errori, connessioni attive,
byte trasferiti, latenze, memoria, hit cache delle view, ecc.

Questi counter sono esposti come JSON all'endpoint `/hix-status` (pannello admin)
e possono essere consumati da qualsiasi codice tramite gli helper `HIX_Metric*`. Un **thread di monitoraggio**
li aggiorna periodicamente con dati di sistema (memoria, uptime, saturazione code).

---

## Quando ti servono?

- Per **monitorare** la salute del server senza parsare i log.
- Per integrare HIX in una **dashboard esterna** (Prometheus, Grafana, Zabbix,
  Datadog) consumando il JSON.
- Per **alert automatici** quando una coda satura o la latenza media
  aumenta.
- Per far pubblicare alla tua applicazione i **suoi counter di business** (login, vendite,
  errori di pagamento...) attraverso lo stesso canale.

---

## Setup in `hix.json`

### Sezione `monitor`

```json
{
  "monitor": {
    "enabled":    true,
    "interval_s": 5,
    "alert_pct":  75
  }
}
```

| Chiave       | Tipo | Descrizione                                      |
|--------------|------|--------------------------------------------------|
| `enabled`    | bool | Avvia il thread di monitoraggio in background    |
| `interval_s` | int  | Tick ogni N secondi                              |
| `alert_pct`  | int  | % di coda che fa scattare l'allarme `SATURATED`  |

Il monitor è un **thread separato** che ogni `interval_s` secondi:
1. Aggiorna `uptimesec`.
2. Legge `Memory(HB_MEM_USED)` e `Memory(HB_MEM_USEDMAX)` e pubblica
   `memused` / `mempeak`.
3. Controlla che `oServer:lRunning = .T.` (rileva i crash).
4. Se qualche coda supera `alert_pct`, incrementa `saturated`.

> 💡 Con `"enabled": false` i counter esistono ancora e vengono aggiornati dai
> worker, ma **non c'è tick periodico** né misurazioni di memoria.

---

## Counter disponibili

| Chiave (`HIXM_*`)       | Descrizione                                          |
|-------------------------|------------------------------------------------------|
| `requests`              | Richieste totali servite                             |
| `errors`                | Errori ritornati (4xx/5xx)                           |
| `activehttp`            | Worker HTTP occupati adesso                          |
| `activews`              | Worker WebSocket occupati                            |
| `activeotros`           | Worker SSE / LongPoll occupati                       |
| `bytesin`               | Byte ricevuti nei body                               |
| `bytesout`              | Byte inviati nelle response                           |
| `saturated`             | Volte che una coda ha superato la soglia `alert_pct` |
| `uptimesec`             | Secondi dall'avvio                                   |
| `memused`               | Memoria corrente (byte, via `Memory(HB_MEM_USED)`)   |
| `mempeak`               | Picco storico di memoria                             |
| `req_ms_max`            | Latenza massima registrata (ms)                      |
| `req_ms_avg`            | Media mobile della latenza (ms)                      |
| `req_ms_count`          | Numero di richieste cronometrate                     |
| `req_slowest_dyn`       | Top-N richieste più lente (route dinamiche)           |
| `req_slowest_stat`      | Top-N richieste più lente (asset statici)             |
| `vcache_entries`        | Entry nella cache RAM delle view                     |
| `vcache_bytes`          | Byte occupati dalla cache RAM delle view              |
| `vcache_hits`           | Hit della cache                                      |
| `vcache_misses`         | Miss della cache (compilato/letto da disco)          |

Tutti i counter sono **interi**, accessibili tramite `HIX_MetricGet(HIXM_REQUESTS)` o
dalla loro chiave stringa diretta.

---

## API dal codice

```clipper
// Incrementa (delta opzionale, default 1)
HIX_Metric( "myapp.logins" )
HIX_Metric( "myapp.bytes_uploaded", 4096 )

// Decrementa (Max(0, ...) - mai negativo)
HIX_MetricDec( "myapp.active_sessions" )

// Set assoluto
HIX_MetricSet( "myapp.users_online", 47 )

// Lettura
nLogins := HIX_MetricGet( "myapp.logins" )

// Tempi per richiesta (media mobile + top-N)
HIX_MetricTiming( 152, "/api/checkout" )       // generico
HIX_MetricTimingDyn( 152, "/api/checkout" )    // solo top dinamico
HIX_MetricTimingStat( 12, "/static/logo.png" ) // solo top statico

// JSON serializzato con tutti i counter
cJson := HIX_MetricsJson()

// Reset (mantiene la config, azzera i counter)
HIX_MetricsReset()
```

> 🔒 **Thread-safe**: tutti gli incrementi sono protetti da mutex interno. Puoi
> chiamare da qualsiasi worker senza sincronizzare.

---

## L'endpoint `/hix-status`

Ritorna un JSON con **tutti** i counter e le top-N latenze:

```json
{
  "requests": 18472,
  "errors": 12,
  "activehttp": 3,
  "activews": 15,
  "activeotros": 1,
  "bytesin": 4823910,
  "bytesout": 92834729,
  "saturated": 0,
  "uptimesec": 78423,
  "memused": 41943040,
  "mempeak": 52428800,
  "req_ms_max": 412,
  "req_ms_avg": 18.43,
  "req_ms_count": 18472,
  "req_slowest_dyn": [
    { "ms": 412, "at": "2026-06-27 09:14:32", "path": "/api/reports/big" },
    { "ms": 308, "at": "2026-06-27 08:51:11", "path": "/api/export/csv" }
  ],
  "req_slowest_stat": [
    { "ms": 88, "at": "2026-06-27 09:02:14", "path": "/static/video.mp4" }
  ],
  "vcache_entries": 27,
  "vcache_hits": 18221,
  "vcache_misses": 245
}
```

È protetto dal [pannello admin](hix-admin.md): in `env = prod` richiede
il login tramite il cookie firmato `hix_admin`.

---

## Esempio: counter di business

Un controller che registra ogni login riuscito/fallito:

```clipper
// app/controllers/auth.prg
#include "hix_logger.ch"

FUNCTION login_post()
   LOCAL oVal := UValidateOrFail( { ;
      "email"    => "required|email",  ;
      "password" => "required|string"  ;
   } )

   IF oVal == NIL ; RETURN NIL ; ENDIF

   IF _CheckCredentials( oVal:Get("email"), oVal:Get("password") )
      HIX_Metric( "myapp.login.ok" )
      USession():Set( "user", oVal:Get("email") )
      USession():Save()
      RETURN URedirect( "/dashboard" )
   ENDIF

   HIX_Metric( "myapp.login.fail" )
   lw( "Login fallito: " + oVal:Get("email") )
RETURN USendView( "login.view.html", { "cError" => _( "ERR_AUTH" ) } )
```

E un endpoint pubblico che espone quei counter filtrati:

```clipper
oSrv:AddRouteGet( "ventas.kpis", "/api/kpis", {|| USendJson( { ;
   "logins_ok"   => HIX_MetricGet( "myapp.login.ok"   ), ;
   "logins_fail" => HIX_MetricGet( "myapp.login.fail" ), ;
   "uptime_s"    => HIX_MetricGet( "uptimesec"        )  ;
} ) } )
```

---

## Dump su console

```clipper
HIX_MetricsDump()
```

Stampa un riepilogo tabulato nel logger (utile quando si spegne il server):

```
=== Metrics ===============================
  uptime=78423s  requests=18472  errors=12
  active_http=3  active_ws=15  active_otros=1
  bytes_in=4823910  bytes_out=92834729  saturations=0
  req_ms_max=412ms  req_ms_avg=18.43ms  req_count=18472
  top slowest dyn (prg/hrb):
    412ms  2026-06-27 09:14:32  /api/reports/big
    308ms  2026-06-27 08:51:11  /api/export/csv
  top slowest stat (html/js/img/...):
     88ms  2026-06-27 09:02:14  /static/video.mp4
===========================================
```

`HIX_MetricsClose()` esegue automaticamente `Dump()` allo shutdown.

---

## Errori comuni

| Sintomo                                | Causa                                             | Fix                                         |
|----------------------------------------|---------------------------------------------------|---------------------------------------------|
| `/hix-status` ritorna `{}`             | Metriche non inizializzate                        | Controlla che `THixServer:New()` sia stato eseguito |
| `memused` sempre 0                     | Monitor disabilitato (`monitor.enabled = false`)  | Attivalo o chiama `HIX_MetricSet` manualmente |
| `saturated` aumenta senza traffico anomalo | `alert_pct` troppo basso                     | Alza a 80-90 o espandi i worker del pool    |
| `req_ms_avg` molto alto                | Pool saturo o view lenta                          | Controlla `req_slowest_dyn`, scala il pool  |
| `vcache_hits = 0`                      | Cache disabilitata o view sempre diverse          | Controlla la config `hixstyle.cache`        |

---

## Best practice

- **Prefissa i tuoi counter** con un namespace (`myapp.*`, `sales.*`...) per
  evitare collisioni con i counter del framework.
- Riserva `req_slowest_*` per diagnosticare regressioni dopo le modifiche - se appare una nuova
  route in cima, fai attenzione.
- Nei microservizi, **scrappa il JSON ogni 10-30 secondi** da Prometheus.
  Non serve una risoluzione maggiore di `interval_s`.
- Per azzerare tra test di carico: `HIX_MetricsReset()` prima di iniziare e
  `HIX_MetricsJson()` alla fine.
- Le metriche **non sono log**: non usarle per registrare eventi unici, solo per
  aggregati numerici.

---

## Metriche vs Boot Log

Vengono spesso confusi - non sono la stessa cosa:

| Aspetto       | Metriche                              | [Boot Log](bootlog.md)                       |
|---------------|---------------------------------------|----------------------------------------------|
| Finestra      | **Runtime** (mentre il server gira)  | **Avvio** (una sola volta, all'inizializzazione) |
| Contenuto     | Counter numerici (aggregati)          | Eventi discreti con stato e payload         |
| Aggiornamento | Continuo (worker, thread monitor)    | Solo durante l'inizializzazione dei sottosistemi |
| Uso tipico    | Dashboard, alert, SLO                 | Diagnosi dell'avvio, pannello admin          |
| Reset         | `HIX_MetricsReset()` (manuale)        | Automatico al riavvio `_Init()`              |

Usali insieme: il **boot log** ti dice se l'avvio è andato bene, le
**metriche** mostrano come si comporta il server una volta in esecuzione.
