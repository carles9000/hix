# 🛠️ Configurazione di `hix.json`

Tutta la configurazione di HIX risiede in un unico file `hix.json` situato accanto
all'eseguibile del server. Funziona allo stesso modo sia quando usi HIX in **modalità base**
(route programmatiche, template manuali) sia in **modalità HixStyle**
(motore MVC, loaders, view, controller).

---



## Convenzione delle colonne

Nella tabella principale ogni parametro ha due colonne che ne indicano l'ambiente:

| Colonna        | Significato                                                                |
|----------------|----------------------------------------------------------------------------|
| **Basic**      | Riguarda il server in modalità HIX base (route Harbour programmatiche + file statici) |
| **HixStyle**   | Riguarda il server in modalità HixStyle (`enabled = true`)                     |

✅ = il parametro è rilevante in quell'ambiente.
❌ = il parametro **non ha effetto** o non viene usato in quell'ambiente.

Le chiavi marcate solo sotto **HixStyle** sono:

- L'intera sezione `hixstyle`

Il resto riguarda entrambi gli ambienti allo stesso modo.

---

## Tabella principale dei parametri

| Sezione        | Chiave            | Default        | Basic | HixStyle | Descrizione                                                                          |
|----------------|-------------------|----------------|:-----:|:--------:|--------------------------------------------------------------------------------------|
| `server`       | `host`            | `localhost`    |   ✅   |    ✅    | Interfaccia di ascolto. `0.0.0.0` = tutte. `localhost` = solo locale.                |
| `server`       | `port`            | `80`           |   ✅   |    ✅    | Porta TCP. Le porte < 1024 richiedono admin/root.                                    |
| `server`       | `maxconn`         | `1024`         |   ✅   |    ✅    | Connessioni simultanee massime.                                                      |
| `server`       | `timeout`         | `30`           |   ✅   |    ✅    | Timeout di connessione (secondi).                                                    |
| `server`       | `name`            | `HIX/2.1`      |   ✅   |    ✅    | Valore dell'header HTTP `Server:`.                                                   |
| `server`       | `mode`            | `standalone`   |   ✅   |    ✅    | `standalone` oppure `proxied` (dietro nginx/Apache).                                 |
| `server`       | `trusted_proxies` | `127.0.0.1 ::1`|   ✅   |    ✅    | IP/CIDR attendibili, separati da spazio (`mode=proxied`).                            |
| `server`       | `ssl`             | `false`        |   ✅   |    ✅    | Abilita TLS. Richiede `cert_private` + `cert_public`.                                |
| `server`       | `cert_private`    | `""`           |   ✅   |    ✅    | Nome del file della chiave privata `.key` (dentro `paths.certs`).                    |
| `server`       | `cert_public`     | `""`           |   ✅   |    ✅    | Nome del file del certificato `.crt` (dentro `paths.certs`).                         |
| `server`       | `gzip`            | `true`         |   ✅   |    ✅    | Comprime le risposte HTTP.                                                           |
| `server`       | `gzip_min_size`   | `2048`         |   ✅   |    ✅    | Dimensione minima del body da comprimere (byte).                                     |
| `server`       | `autostart`       | `true`         |   ✅   |    ✅    | Apre il browser all'URL del server all'avvio.                                        |
| `server`       | `exec_timeout_ms` | `30000`        |   ✅   |    ✅    | Tempo massimo di esecuzione per `.prg`/`.hrb` (ms). `0` = nessun limite.             |
| `paths`        | `root`            | `www`          |   ✅   |    ✅    | Document root.                                                                       |
| `paths`        | `log`             | `.logs`        |   ✅   |    ✅    | Directory dei log.                                                                   |
| `paths`        | `tmp`             | `tmp`          |   ✅   |    ✅    | File temporanei (upload, transpile).                                                 |
| `paths`        | `errors`          | `.logs`        |   ✅   |    ✅    | Pagine di errore HTTP personalizzate.                                                |
| `paths`        | `session`         | `.sessions`    |   ✅   |    ✅    | Storage delle sessioni (`storage=file`).                                             |
| `paths`        | `certs`           | `certs`        |   ✅   |    ✅    | Directory dei certificati SSL/TLS.                                                   |
| `app`          | `errorsys`        | `""`           |   ✅   |    ✅    | Template HTML per la schermata errorsys (relativo a `root/`). Vuoto = usa quello interno. |
| `app`          | `default_page`    | `index.html`   |   ✅   |    ✅    | Risorsa predefinita quando l'URL non ha un file.                                     |
| `app`          | `dispatch_mode`   | `full`         |   ✅   |    ✅    | `routes` (solo programmatiche) / `static` (+ file) / `full` (+ prg/hrb).             |
| `app`          | `auto_close_dbf`  | `true`         |   ✅   |    ✅    | Chiude i DBF aperti al termine della richiesta.                                      |
| `app`          | `auto_close_dbf_log` | `false`     |   ✅   |    ✅    | Logga ogni auto-close di DBF.                                                        |
| `app`          | `env`             | `dev`          |   ✅   |    ✅    | `dev` (errori dettagliati) / `prod` (errori generici).                               |
| `app`          | `debug`           | `false`        |   ✅   |    ✅    | `true` = livello DEBUG su console.                                                   |
| `admin`        | `enabled`         | `true`         |   ✅   |    ✅    | `false` = disabilita il pannello admin e tutte le route `/hix-*`.                    |
| `admin`        | `user`            | `""`           |   ✅   |    ✅    | Utente admin.                                                                        |
| `admin`        | `password`        | `""`           |   ✅   |    ✅    | Hash MD5 della password. Vuoto = mostra `/hix-setup`.                                |
| `admin`        | `secret`          | `""`           |   ✅   |    ✅    | Chiave di firma del cookie, auto-generata da `/hix-setup`.                           |
| `detector`     | `workers`         | `4`            |   ✅   |    ✅    | Worker che rilevano il protocollo su ogni nuova connessione.                         |
| `detector`     | `queue_size`      | `256`          |   ✅   |    ✅    | Coda interna.                                                                        |
| `detector`     | `peek_timeout_ms` | `100`          |   ✅   |    ✅    | Attesa massima per il primo byte. LAN=10, internet=50.                              |
| `detector`     | `peek_bytes`      | `512`          |   ✅   |    ✅    | Byte da leggere per identificare il protocollo.                                      |
| `pool_http`    | `workers`         | `64`           |   ✅   |    ✅    | Worker HTTP (~1MB di stack/thread su Windows).                                       |
| `pool_http`    | `queue_size`      | `256`          |   ✅   |    ✅    | Coda delle richieste in attesa.                                                      |
| `pool_http`    | `read_timeout_ms` | `2000`         |   ✅   |    ✅    | Timeout di lettura dell'header HTTP (ms).                                            |
| `pool_http`    | `keep_alive`      | `true`         |   ✅   |    ✅    | Abilita HTTP Keep-Alive.                                                             |
| `pool_http`    | `keep_alive_max`  | `100`          |   ✅   |    ✅    | Numero massimo di richieste per connessione keep-alive.                              |
| `pool_ws`      | `workers`         | `100`          |   ✅   |    ✅    | Worker WebSocket. Ogni WS attivo usa 1 worker fino alla chiusura.                    |
| `pool_ws`      | `queue_size`      | `256`          |   ✅   |    ✅    | Coda delle connessioni in attesa.                                                    |
| `pool_ws`      | `ping_interval_s` | `30`           |   ✅   |    ✅    | Intervallo di ping del client (secondi).                                             |
| `pool_ws`      | `ping_timeout_s`  | `10`           |   ✅   |    ✅    | Timeout di risposta al ping (secondi).                                               |
| `pool_rest`    | `workers_sse`     | `20`           |   ✅   |    ✅    | Worker per Server-Sent Events (ogni SSE ne occupa 1).                                |
| `pool_rest`    | `workers_longpoll`| `10`           |   ✅   |    ✅    | Worker per Long Polling.                                                             |
| `pool_rest`    | `queue_size`      | `128`          |   ✅   |    ✅    | Coda condivisa.                                                                      |
| `pool_rest`    | `stream_timeout_s`| `3600`         |   ✅   |    ✅    | Durata massima di uno stream aperto (secondi).                                       |
| `pool_hix`     | `workers`         | `4`            |   ✅   |    ✅    | Worker dedicati al canale interno HIX.                                               |
| `pool_hix`     | `queue_size`      | `64`           |   ✅   |    ✅    | Coda del pool HIX.                                                                   |
| `pool_hix`     | `read_timeout_ms` | `2000`         |   ✅   |    ✅    | Timeout di lettura (ms).                                                             |
| `session`      | `storage`         | `memory`       |   ✅   |    ✅    | `memory` (volatile, veloce) / `file` (persistente).                                  |
| `session`      | `prefix`          | `sess_`        |   ✅   |    ✅    | Prefisso del nome file di sessione.                                                  |
| `session`      | `crypt`           | `false`        |   ✅   |    ✅    | Cripta i dati di sessione su disco.                                                  |
| `session`      | `seed`            | `""`           |   ✅   |    ✅    | Chiave di crittografia (richiesta se `crypt=true`).                                  |
| `session`      | `lifetime`        | `60`           |   ✅   |    ✅    | Durata della sessione in minuti (si applica al cookie utente e admin). `0` = illimitata. |
| `session`      | `gc_days`         | `3`            |   ✅   |    ✅    | Giorni per la GC dei file di sessione orfani (solo `storage=file`).                  |
| `monitor`      | `enabled`         | `true`         |   ✅   |    ✅    | Abilita il thread del monitor di salute.                                             |
| `monitor`      | `interval_s`      | `5`            |   ✅   |    ✅    | Intervallo di controllo (secondi).                                                   |
| `monitor`      | `alert_pct`       | `75`           |   ✅   |    ✅    | % di utilizzo della coda che attiva l'allarme `SATURATED`.                          |
| `log`          | `file`            | `hix.log`      |   ✅   |    ✅    | Nome del file di log (percorso = `paths.log`).                                       |
| `log`          | `level`           | `info`         |   ✅   |    ✅    | `debug` / `info` / `warn` / `error` / `fatal`.                                       |
| `log`          | `console`         | `true`         |   ✅   |    ✅    | `true` = duplica l'output sulla console.                                             |
| `log`          | `max_size_mb`     | `10`           |   ✅   |    ✅    | Dimensione massima prima della rotazione (MB).                                       |
| `log`          | `max_files`       | `0`            |   ✅   |    ✅    | Numero massimo di backup conservati. `0` = illimitato.                               |
| `access_log`   | `enabled`         | `true`         |   ✅   |    ✅    | Abilita il log degli accessi HTTP (Common Log Format).                               |
| `access_log`   | `file`            | `access.log`   |   ✅   |    ✅    | Nome del file del log accessi (percorso = `paths.log`).                              |
| `firewall`     | `mode`            | `blacklist`    |   ✅   |    ✅    | `blacklist` (blocca i listati) / `whitelist` (solo i listati).                       |
| `firewall`     | `filter`          | `""`           |   ✅   |    ✅    | Lista di IP/CIDR separati da virgola. Es.: `192.168.1.0/24, 10.0.0.0/8`.             |
| `hixstyle`     | `enabled`         | `false`        |   ❌   |    ✅    | Abilita il motore MVC HixStyle.                                                      |
| `hixstyle`     | `cache_disk`      | `true`         |   ❌   |    ✅    | Memorizza nella cache le view compilate su disco (`.cached/views/`).                 |
| `hixstyle`     | `trace`           | `false`        |   ❌   |    ✅    | Abilita il trace di HixStyle nel log.                                                |
| `hixstyle`     | `cache_ram`       | `false`        |   ❌   |    ✅    | Cache globale delle view in RAM condivisa tra i worker. ~10× più veloce del disco.   |
| `trace`        | `app`             | `true`         |   ✅   |    ✅    | Trace del modulo `app`.                                                              |
| `trace`        | `server`          | `true`         |   ✅   |    ✅    | Trace del modulo `server`.                                                           |
| `trace`        | `worker_http`     | `false`        |   ✅   |    ✅    | Trace del worker HTTP.                                                               |
| `trace`        | `worker_ws`       | `false`        |   ✅   |    ✅    | Trace del worker WebSocket.                                                          |
| `trace`        | `worker_otros`    | `false`        |   ✅   |    ✅    | Trace del worker SSE/LongPoll.                                                       |
| `trace`        | `pool`            | `false`        |   ✅   |    ✅    | Trace dei pool.                                                                      |
| `trace`        | `pool_detector`   | `false`        |   ✅   |    ✅    | Trace del detector di protocollo.                                                    |
| `trace`        | `metrics`         | `false`        |   ✅   |    ✅    | Trace del modulo metrics.                                                            |
| `trace`        | `config`          | `false`        |   ✅   |    ✅    | Trace del caricamento della configurazione.                                          |
| `trace`        | `socket`          | `false`        |   ✅   |    ✅    | Trace delle operazioni socket.                                                       |
| `trace`        | `monitor`         | `false`        |   ✅   |    ✅    | Trace del monitor.                                                                   |
| `trace`        | `response`        | `false`        |   ✅   |    ✅    | Trace del modulo response.                                                           |
| `trace`        | `logger`          | `false`        |   ✅   |    ✅    | Trace del logger stesso.                                                             |
| `trace`        | `error`           | `false`        |   ✅   |    ✅    | Trace degli errori.                                                                  |

> Hot-toggle del trace: `GET /hix-trace?mod=<module>&on=1`.
> `WARN`/`ERROR`/`FATAL` sono sempre loggati, indipendentemente dal trace.

---

## Riepilogo delle sezioni

### `server` - rete e identità
Definisce come il server ascolta: interfaccia, porta, TLS e modalità (standalone o
dietro un proxy). Da impostare prima del primo avvio in produzione.

### `paths` - layout disco
Struttura delle directory del server. Da modificare se vuoi spostare `www/`, i log o
le sessioni su un'altra unità.

### `app` - applicazione
Template `errorsys` per la schermata di errore di sistema, `env` (dev/prod),
`debug`, dispatcher, timeout di esecuzione, pagina predefinita. Le pagine di errore personalizzate vivono nella cartella fissa
`<paths.root>/errors/`. Il file
`<paths.root>/config.json` (opzionale) e la cartella
`<paths.root>/loaders/` (opzionale) vengono caricati automaticamente se esistono.

### `admin` - pannello `/hix-*`
Credenziali del pannello admin. Se lasci `password` vuoto, il primo accesso a
`/hix-setup` lo configura. `enabled = false` disattiva tutte le route `/hix-*`.

### `detector`, `pool_http`, `pool_ws`, `pool_rest`, `pool_hix` - concorrenza
Dimensioni di pool e code. I default gestiscono traffico medio; regola se il
monitor riporta saturazione (`SATURATED` quando la coda supera `alert_pct`).

### `session` - sessioni HTTP
`memory` è la più veloce ma si perde al riavvio. `file` persiste ma
aggiunge I/O. Per multi-processo usa sempre `file` con `seed`.

### `monitor`, `log`, `access_log` - osservabilità
Logger principale con rotazione, log accessi CLF e health monitor che espone
`/hix-status`. Vedi anche: [sistema/logger](../../sistema/logger.md),
[sistema/metriche](../../sistema/metricas.md).

### `firewall` - filtraggio IP
Whitelist o blacklist di IP/CIDR. Vedi
[hixstyle/seguridad/firewall](../../hixstyle/seguridad/firewall.md).

### `hixstyle` - motore MVC
Abilita e configura HixStyle. Si applica solo se `enabled = true`.

### `trace` - verbosità per modulo
Flag binari per abilitare i trace di ciascun modulo core. Utili per
diagnosticare problemi specifici senza inondare il log.


Anche se molti parametri sono visibili, questa è solo la definizione dei parametri di un
web server. Non dovresti modificare questi parametri a meno che tu non sappia esattamente cosa fanno.
Non preoccuparti all'inizio: tutto è già configurato.
