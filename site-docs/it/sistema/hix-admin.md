# 👑 Pannello admin

HIX espone un set di **endpoint di amministrazione** sotto il prefisso `/hix-*`
che permettono di controllare lo stato del server, ricaricare le route, pulire le cache, abilitare/disabilitare
trace, e fermare il server in modo pulito. Tutti sono protetti da una **sessione admin
con cookie firmato** (`hix_admin`).

Il pannello si auto-configura al primo avvio: se non ci sono credenziali, reindirizza
a `/hix-setup` così puoi creare l'utente/password iniziale.

---

## Quando ti serve?

- Per **monitorare** il server in produzione (`/hix-status`).
- Per **ricaricare le route** da `routes/*.json` senza riavviare.
- Per **pulire la cache delle view** dopo un deploy.
- Per **fermare HIX** da uno script remoto senza accesso TTY.
- Per **abilitare trace** su moduli specifici e diagnosticare un problema.

---

## Setup in `hix.json`

### Sezione `admin`

`enabled = false` disabilita il pannello e le route `/hix-*`. `user` /
`password` vuoti abilitano `/hix-setup`. La durata della sessione admin è controllata da
`session.lifetime` (minuti).

```json
{
  "admin": {
    "enabled":  true,
    "user":     "",
    "password": "",
    "secret":   ""
  }
}
```

Con `user` e `password` vuoti, qualsiasi richiesta a un endpoint admin **reindirizza
a `/hix-setup`** per creare le credenziali. Una volta create, HIX le scrive in
`hix.json` con `oCfg:Generate()`.

### Comportamento per `env`

| `app.env` | Auth richiesta                  |
|-----------|---------------------------------|
| `dev`     | **No** - accesso aperto         |
| `prod`    | **Sì** - cookie `hix_admin`     |

In `dev` gli endpoint sono aperti per iterare velocemente. In `prod` richiedono il login.

---

## Endpoint disponibili

Tutti sono definiti in `src/hix_router.prg` e dipendono da `HIX_AdminCheck(oReq)`.

### Operativi

| Route                      | Metodo    | Descrizione                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-ping`                | GET       | Healthcheck pubblico (auth non richiesta)            |
| `/hix-status`              | GET       | JSON con tutte le [metriche](metricas.md)           |
| `/hix-monitor`             | GET       | Pagina HTML con dashboard interattiva                 |
| `/hix-index`               | GET       | Pagina HTML con la lista delle route registrate      |
| `/hix-stop`                | GET       | Ferma il server in modo pulito                       |
| `/hix-cache-clear`         | GET       | Pulisce la cache delle view (RAM + disco)            |
| `/hix-trace`               | GET/POST  | Elenca o regola i trace per modulo                    |

### Route dinamiche

| Route                      | Metodo    | Descrizione                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-routes/list`         | GET       | Elenca le route registrate (tranne le `hix.*` interne) |
| `/hix-routes/listall`      | GET       | Elenca TUTTE le route, incluse quelle di sistema     |
| `/hix-routes/add`          | POST      | Aggiunge una nuova route (body JSON)                  |
| `/hix-routes/delete`       | POST      | Elimina una route (body JSON `{name: "..."}`)         |
| `/hix-routes/reload`       | GET       | Ricarica le route da `routes/*.json`                  |

### Benchmark

| Route                      | Metodo    | Descrizione                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-bench-start`         | GET       | Resetta le metriche e avvia la finestra di misura    |
| `/hix-bench-stop`          | GET       | Ritorna JSON con le metriche accumulate nella finestra |

### Autenticazione

| Route                      | Metodo    | Descrizione                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-login`               | GET/POST  | Pagina e submit del login admin                       |
| `/hix-logout`              | GET       | Cancella il cookie `hix_admin`                       |
| `/hix-setup`               | GET/POST  | Pagina di creazione iniziale delle credenziali        |

> 🔒 Se `admin.enabled = false`, nessuna di queste route è registrata e qualsiasi
> richiesta a `/hix-*` ritorna 404.

---

## Sessione e cookie

Quando il login ha successo, HIX firma il cookie con HMAC simulato:

```
hix_admin = <timestamp>:<md5( cAdminSecret + "|" + timestamp )>
```

Su ogni richiesta admin, `HIX_AdminCheck(oReq)`:
1. Legge il cookie `hix_admin`.
2. Verifica la firma con `cAdminSecret`.
3. Controlla che `now - timestamp < session.lifetime * 60` (se `lifetime > 0`).
4. Se fallisce, reindirizza a `/hix-login?next=<current_route>`.

Il cookie è **HttpOnly; SameSite=Lax; Path=/** e viene rinnovato a ogni login.

---

## Flusso del primo avvio

```
1. Avvii HIX per la prima volta (admin user/password vuoti)
            │
            ▼
2. Accedi a /hix-status
            │
            ▼
3. HIX reindirizza a /hix-setup
            │
            ▼
4. Compili user + password (minimo 6 caratteri)
            │
            ▼
5. HIX salva user/MD5(password)/secret in hix.json
            │
            ▼
6. Reindirizza a /hix-login
            │
            ▼
7. Fai il login → cookie hix_admin firmato → accesso completo
```

> 💡 Il `secret` viene generato con `MD5( timestamp + user + password )` al primo
> avvio. Se vuoi **invalidare tutte le sessioni admin**, basta svuotare `secret` in
> `hix.json` - HIX ne genererà uno nuovo al prossimo setup/login.

---

## Esempio: consumare `/hix-status` dal monitoraggio

```bash
# 1. Login e salva il cookie
curl -c hix.jar -X POST https://myserver.com/hix-login \
  -d 'user=admin&password=secret'

# 2. Consuma lo status
curl -b hix.jar https://myserver.com/hix-status
```

Output:

```json
{ "requests": 18472, "errors": 12, "uptimesec": 78423, ... }
```

Per l'integrazione con **Prometheus**, basta wrappare in un esportatore banale che
fa GET ogni 30 secondi.

---

## Trace dinamici con `/hix-trace`

`GET /hix-trace` ritorna l'hash dei trace attivi per modulo:

```json
{ "router": true, "session": false, "auth": true }
```

`POST /hix-trace` con body JSON regola un trace specifico:

```json
{ "module": "router", "enabled": true }
```

Utile per diagnosticare un problema in produzione senza toccare `hix.json`.
Quando hai finito, disabilita di nuovo il trace per mantenere il log pulito.

> 📚 Maggiori dettagli in [logger - trace per modulo](logger.md#trace-per-modulo).

---

## Disabilitare il pannello

In ambienti molto restrittivi puoi disattivare l'intero pannello:

```json
{
  "admin": {
    "enabled": false
  }
}
```

Questo **non registra gli endpoint admin** (`/hix-status`, `/hix-monitor`,
`/hix-stop`, `/hix-login`, `/hix-routes/*`, ecc.). Le richieste a quegli URL
ritornano 404.

> ℹ️ `/hix-ping` e `/hix-slow` sono **sempre** registrati (sono route di health-check pubbliche
> e non dipendono da `admin.enabled`).

> ⚠️ Se lo disabiliti, perdi `/hix-status` e gli altri endpoint. Per
> monitorare dovrai esporre un tuo endpoint che consumi `HIX_MetricsJson()`
> con la tua auth.

---

## Errori comuni

| Sintomo                                        | Causa                                              | Fix                                                |
|------------------------------------------------|----------------------------------------------------|----------------------------------------------------|
| `/hix-status` reindirizza a `/hix-setup`        | `admin.user` / `password` vuoti                    | Completa il setup da `/hix-setup`                   |
| Dopo il login, reindirizza di nuovo a `/hix-login` | `secret` diverso da quello che ha firmato il cookie | Cancella il cookie nel browser, rifai il login     |
| Il cookie scade troppo velocemente              | `session.lifetime` troppo basso                     | Alza il valore (minuti, `0` = indefinito)          |
| `/hix-routes/add` ritorna 401                  | Cookie admin mancante o scaduto                    | Fai prima il login a `/hix-login`                  |
| Non vuoi login in dev                          | Sei in `env = "prod"`                              | Cambia `app.env = "dev"`                           |

---

## Best practice

- **`app.env = "prod"` sempre su server esposti a internet.** Con `"dev"`
  chiunque può spegnere il server con `/hix-stop`.
- **Cambia `secret` periodicamente** svuotandolo in `hix.json` per forzare la rotazione
  del cookie.
- Se il tuo HIX è dietro [Apache/Nginx](apache-proxy.md), **limita l'accesso a
  `/hix-*` per IP** nel reverse proxy come ulteriore livello.
- **Non esporre `/hix-stop` o `/hix-cache-clear`** su internet aperto - proteggili
  con il firewall se possibile.
- Per CI/CD, **usa un account admin dedicato** diverso da quello dell'operatore umano;
  ruota la sua password quando ruoti il team.
