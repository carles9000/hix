# 🔗 API - Endpoint `/hix-*`

Riferimento completo degli endpoint del pannello admin di HIX. Per i dettagli concettuali
(sessione, cookie firmato, configurazione iniziale) vedi
[sistema/hix-admin](../sistema/hix-admin.md).

---

## Riepilogo

| Endpoint                | Metodo      | Auth   | Funzione                              |
|-------------------------|-------------|:------:|---------------------------------------|
| `/hix-ping`             | `GET`       |   -    | Health check pubblico                 |
| `/hix-slow`             | `GET`       |   -    | Endpoint lento (3s) - debug latenza   |
| `/hix-status`           | `GET`       |   ✅   | Metriche in JSON                      |
| `/hix-monitor`          | `GET`       |   ✅   | Dashboard HTML live                  |
| `/hix-index`            | `GET`       |   ✅   | Lista HTML delle route registrate     |
| `/hix-trace`            | `GET POST`  |   ✅   | Stato trace/toggle per modulo         |
| `/hix-cache-clear`      | `GET`       |   ✅   | Pulisce la cache delle view compilate|
| `/hix-stop`             | `GET`       |   ✅   | Shutdown graceful di HIX              |
| `/hix-bench-start`      | `GET`       |   ✅   | Reset metriche (bench)                |
| `/hix-bench-stop`       | `GET`       |   ✅   | Dump JSON del bench                   |
| `/hix-routes/add`       | `POST`      |   ✅   | Aggiunge una route dinamica           |
| `/hix-routes/delete`    | `POST`      |   ✅   | Elimina una route per nome            |
| `/hix-routes/reload`    | `GET`       |   ✅   | Ricarica `routes/*.json`              |
| `/hix-routes/list`      | `GET`       |   ✅   | Lista HTML - solo route app          |
| `/hix-routes/listall`   | `GET`       |   ✅   | Lista HTML - tutte le route          |
| `/hix-login`            | `GET POST`  |   -    | Login admin                           |
| `/hix-logout`           | `GET`       |   -    | Chiude la sessione admin              |
| `/hix-setup`            | `GET POST`  |   -    | Configurazione iniziale credenziali   |

> **Auth** = richiede `HIX_AdminCheck(oReq)` prima di eseguire l'handler.
> In `env=dev` l'auth è disabilitata automaticamente - tutti gli endpoint rispondono senza
> cookie. In `env=prod` è richiesto un cookie `hix_admin` valido.

---

## Endpoint pubblici

### `GET /hix-ping`

Health check leggero - progettato per load balancer e monitoraggio esterno.

**Risposta `200 OK`** (JSON):

```json
{ "status": "ok", "server": "HIX/2.1" }
```

### `GET /hix-slow`

Come `ping` ma con `hb_idleSleep(3)`. Utile per testare timeout del client,
load balancer, o proxy frontale.

**Risposta `200 OK`** dopo 3 secondi:

```json
{ "status": "ok", "time": "12:34:56" }
```

---

## Metriche e monitor

### `GET /hix-status`

Dump dello stato del server (connessioni attive, richieste totali, errori, utilizzo pool,
alert di saturazione, ecc.) come JSON. Generato da `HIX_MetricsJson()`.

**Risposta `200 OK`** (estratto):

```json
{
  "uptime_s": 12345,
  "requests": { "total": 9876, "errors": 12 },
  "pool_http": { "workers": 64, "queue": 5, "alert": false },
  "pool_ws":   { "workers": 100, "active": 42 },
  "pool_rest": { "sse": 3, "longpoll": 1 }
}
```

Vedi [sistema/metriche](../sistema/metricas.md) per i dettagli completi dello schema.

### `GET /hix-monitor`

Serve `html/monitor.html` - dashboard HTML che consuma `/hix-status` ogni
`[monitor] interval_s` secondi e renderizza grafici. Utile per l'ispezione visuale.

### `GET /hix-index`

Pagina HTML self-contained con la **lista di tutte le route registrate** (nome,
metodi, pattern, pulsante "Apri"). Utile per scoprire cosa ha il server
senza accedere al codice.

Ogni riga mostra:
- **Nome** - nome logico (`hix.status`, `users.list`, ...)
- **Metodi** - badge colorati per metodo (`GET`, `POST`, ...)
- **Pattern** - pattern URL (`/users/:id`)
- **Action** - pulsante "Apri" se la route accetta `GET`

---

## Trace

### `GET /hix-trace`

**Senza parametri:** ritorna lo stato corrente di tutti i trace per modulo in
JSON.

```json
{
  "app": true,
  "server": true,
  "worker_http": false,
  "worker_ws": false,
  ...
}
```

**Con `?mod=<module>&on=<0|1>`:** abilita o disabilita il trace per quel
modulo e ritorna lo stato aggiornato.

| Query                              | Effetto                                   |
|------------------------------------|-------------------------------------------|
| `?mod=worker_http&on=1`            | Abilita trace per il modulo `worker_http` |
| `?mod=worker_http&on=0`            | Disabilita trace per il modulo            |
| `?mod=all&on=1`                    | Abilita **tutti** i moduli                |
| `?mod=all&on=0`                    | Disabilita **tutti**                      |

Moduli disponibili: `app`, `server`, `worker_http`, `worker_ws`,
`worker_otros`, `pool`, `pool_detector`, `metrics`, `config`, `socket`,
`monitor`, `response`, `logger`, `error`.

> `WARN`/`ERROR`/`FATAL` sono sempre loggati, indipendentemente dal trace.

---

## Cache

### `GET /hix-cache-clear`

Elimina ricorsivamente la cache delle view compilate in `.cached/views/` (file `.hrb`
e `__*.prg`). Utile dopo un deploy in cui i file `.view.html` cambiano ma
`cache_disk = true` mantiene i vecchi HRB.

**Risposta `200 OK`:**

```json
{ "status": "ok", "deleted": 42, "path": "C:/hix.pro/.cached/views" }
```

> Non riguarda la cache RAM (`cache_ram`); quella si invalida da sola per `mtime`.

---

## Bench

### `GET /hix-bench-start`

Resetta **tutti i counter** del modulo metriche (`HIX_MetricsReset()`) e lascia
il server pronto per una nuova misurazione.

**Risposta `200 OK`:**

```json
{ "bench": "start" }
```

### `GET /hix-bench-stop`

Chiude il bench e ritorna un dump completo di `HIX_MetricsJson()`.

**Risposta `200 OK`:**

```json
{
  "bench": "stop",
  "metrics": { "uptime_s": 60, "requests": { "total": 50000, ... } }
}
```

---

## Shutdown graceful

### `GET /hix-stop`

Marca il server per fermarsi (`HIX_ServerRequestStop()`), chiude il keep-alive della
request corrente, e lascia che i worker finiscano i task in esecuzione prima di uscire.

**Risposta `200 OK`:**

```json
{ "status": "stopping" }
```

> Equivalente a un `Ctrl+C` controllato via HTTP. Il main loop esce quando ogni
> pool ha la coda vuota.

---

## API di gestione dinamica delle route

Permette di aggiungere, eliminare e ricaricare route **hot** senza riavviare HIX.
Le route create da questa API sono volatili (perse al riavvio) a meno che non le salvi
in `routes/*.json` prima.

> **Riservato:** i nomi con prefisso `hix.*` sono di proprietà del sistema e non possono
> essere registrati tramite questa API (risponde `400`).

### `POST /hix-routes/add`

Aggiunge una nuova route. Body **JSON**:

```json
{
  "name":       "users.list",
  "url":        "/users",
  "action":     "/controllers/users/list.prg",
  "method":     "GET",
  "middleware": "HIX_MwJwt",
  "scope":      ""
}
```

| Campo        | Tipo   | Obbligatorio | Note                                    |
|--------------|--------|:--------:|------------------------------------------|
| `name`       | string |    ✅    | Non può iniziare con `hix.`                 |
| `url`        | string |    ✅    | Pattern URL (supporta `:var`). Alias: `pattern` |
| `action`     | string |    ✅    | Path al PRG/HRB/HTML da eseguire          |
| `method`     | string |    ❌    | Default `*` (tutti). Separati da virgola: `GET,POST` |
| `middleware` | string |    ❌    | MW separati da virgola                   |
| `scope`      | string |    ❌    | Metadata liberi (es., `admin`)            |

**Risposta `200 OK`** se aggiunta:

```json
{ "ok": true, "name": "users.list" }
```

**Risposta `409 Conflict`** se la route esiste già (nessuna sovrascrittura):

```json
{ "ok": false, "error": "route duplicata o non valida", "name": "users.list" }
```

**Risposta `400 Bad Request`** se il JSON non è valido o il nome è riservato:

```json
{ "ok": false, "error": "JSON body non valido" }
```

### `POST /hix-routes/delete`

Elimina una route per nome. Body **JSON**:

```json
{ "name": "users.list" }
```

**Risposta `200 OK`:**

```json
{ "ok": true, "name": "users.list" }
```

**Risposta `400 Bad Request`** se manca `name`:

```json
{ "ok": false, "error": "name obbligatorio" }
```

### `GET /hix-routes/reload`

Elimina **tutte le route applicative** (quelle che non sono `hix.*`) e ricarica quelle
definite in `www/routes/*.json` con `HIX_LoadRoutes()`.

**Risposta `200 OK`:**

```json
{ "ok": true, "total_deleted": 12, "total_loaded": 14 }
```

Utile nei workflow di deploy: copi il nuovo `routes/users.json` sul server
e lanci `/hix-routes/reload` dalla tua pipeline.

### `GET /hix-routes/list`

Pagina HTML con le **route applicative** (esclude le route di sistema `hix.*`). Colonne:
nome, metodi, pattern, middleware, action.

### `GET /hix-routes/listall`

Come `/hix-routes/list` ma include **tutte** le route (sistema + applicative).

---

## Autenticazione

### `GET /hix-login`

Pagina HTML con il form di login (username + password). Self-contained - non usa
CDN o asset esterni.

Accetta `?next=<url>` per reindirizzare dopo un login riuscito (default:
`/hix-status`).

### `POST /hix-login`

Processa il login. Body **form-urlencoded**:

| Campo      | Tipo   | Note                                        |
|------------|--------|----------------------------------------------|
| `user`     | string | Username admin                               |
| `password` | string | Password in chiaro (hash MD5 sul server)    |
| `next`     | string | URL a cui reindirizzare dopo il login       |

Se le credenziali sono valide:
- Emette `hix_admin = <ts>:<sign>` cookie firmato con `oCfg:cAdminSecret`,
  valido per `session.lifetime` minuti.
- Reindirizza a `next` (o `/hix-status` se vuoto).

Se falliscono: risponde `401 Unauthorized` con il form e un messaggio di errore.

### `GET /hix-logout`

Cancella il cookie `hix_admin` (lo fa scadere immediatamente) e reindirizza a
`/hix-login`.

### `GET /hix-setup`

Pagina HTML con il form per la **creazione iniziale delle credenziali**. Mostrata solo se
`oCfg:cAdminUser` o `oCfg:cAdminPassword` sono vuoti.

Se le credenziali esistono già: reindirizza a `/hix-login`.

### `POST /hix-setup`

Crea le credenziali per la prima volta. Body **form-urlencoded**:

| Campo       | Tipo   | Validazione                               |
|-------------|--------|------------------------------------------|
| `user`      | string | Non vuoto                                |
| `password`  | string | Lunghezza minima 6                       |
| `password2` | string | Deve corrispondere a `password`          |

Se validano:
- Salva `oCfg:cAdminUser = user`
- Salva `oCfg:cAdminPassword = MD5(password)`
- Genera e salva `oCfg:cAdminSecret = MD5(timestamp + user + password)`
- Salva tutto in `hix.json` con `oCfg:Generate()`
- Reindirizza a `/hix-login`

Se ci sono errori: risponde `422 Unprocessable Entity` con il form e il
messaggio di errore corrispondente.

---

## Cookie di sessione admin `hix_admin`

Formato del valore del cookie:

```
<unix_timestamp>:<md5_sign>
```

Dove:
- `unix_timestamp` = momento in secondi in cui il cookie è stato emesso
- `md5_sign` = `MD5(secret + "|" + unix_timestamp)`

Verifica su ogni richiesta:
1. Tokenizza per `:`
2. Ricalcola `MD5(secret + "|" + ts)` e confronta con `sign`
3. Se `nMinutes > 0`: controlla che `now - ts <= session.lifetime * 60`

Se un passaggio fallisce → reindirizza a `/hix-login?next=<current_path>`.

> La firma usa `cAdminSecret` che **deve** essere conservato in `hix.json`. Se lo
> ruoti, tutte le sessioni admin attive diventano invalide.

---

## Codici HTTP

| Codice                | Quando                                            |
|----------------------|---------------------------------------------------|
| `200 OK`             | Richiesta riuscita                                 |
| `302 Found`          | Redirect a `/hix-login`, `/hix-setup`, o `next=`  |
| `400 Bad Request`    | JSON non valido o nome route riservato (`hix.*`)  |
| `401 Unauthorized`    | Login fallito                                      |
| `409 Conflict`       | `/hix-routes/add` con nome già esistente           |
| `422 Unprocessable`  | `/hix-setup` con validazione fallita (password corta, ecc.) |

---

## Ricette comuni

### Ricaricare le route dopo un deploy

```bash
# 1. Carica il nuovo JSON
scp www/routes/users.json prod:/srv/hix/www/routes/

# 2. Ricarica
curl --cookie-jar /tmp/c.txt --cookie /tmp/c.txt \
     -d 'user=admin&password=secret' \
     https://myapp.com/hix-login

curl --cookie /tmp/c.txt https://myapp.com/hix-routes/reload
```

### Abilitare il trace WebSocket al volo

```bash
curl --cookie /tmp/c.txt \
     "https://myapp.com/hix-trace?mod=worker_ws&on=1"
```

### Fermare HIX da uno script di deploy

```bash
curl --cookie /tmp/c.txt https://myapp.com/hix-stop
# Il server risponde {"status":"stopping"} ed esce dopo aver drenato le code.
```

### Health check pubblico (no auth)

```bash
curl https://myapp.com/hix-ping
# {"status":"ok","server":"HIX/2.1"}
```

---

## Errori comuni

- **`302` che reindirizza a `/hix-setup` e non arriva mai al pannello** - `hix.json`
  ha `admin.user` e/o `password` vuoti. Visita `/hix-setup` dal tuo
  browser per crearli.
- **`302` che reindirizza a `/hix-login` con cookie corretto** - il cookie
  è scaduto (`session.lifetime` trascorso) o `cAdminSecret` è cambiato.
- **`409 duplicate` in `/hix-routes/add`** - la route esiste già. Eliminala prima
  con `/hix-routes/delete` o cambia il nome.
- **`400 reserved name`** - stai provando a registrare `hix.qualcosa`. Rinomina.
- **`/hix-status` ritorna HTML invece di JSON** - `admin.enabled = false` o
  non sei autenticato in `env = "prod"` (ti reindirizza al login HTML).

---

## Best practice

- In produzione, proteggi `/hix-*` anche a livello di proxy (`apache`/`nginx`)
  con una allowlist di IP per minimizzare la superficie d'attacco.
- Non registrare le tue route con prefisso `hix.*` - è riservato e HIX le rifiuterà.
- Le route create da `/hix-routes/add` sono **volatili**: se vuoi che sopravvivano
  al riavvio, salvali in `www/routes/*.json`.
- `cAdminSecret` è un segreto: non committarlo in git. Per ruotarlo, rigeneralo
  con `/hix-setup` (dopo aver cancellato `user`/`password` da `hix.json`).
- Usa `/hix-cache-clear` dopo qualsiasi deploy che tocca `.view.html` se hai
  `cache_disk = true`.
- Abilita i trace (`/hix-trace?mod=X&on=1`) solo per il tempo necessario a diagnosticare
  - il costo di logging può essere alto nei moduli hot (`worker_http`, `socket`).

---

## Risorse correlate

- Configurazione `hix.json`
- [Pannello Admin (overview)](../sistema/hix-admin.md)
- [Metriche](../sistema/metricas.md)
- [Logger](../sistema/logger.md)
- Errori HTTP
- Trace
