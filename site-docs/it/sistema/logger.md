# Logger

**HIX** include un **logger centralizzato thread-safe** che registra gli eventi del server
in un file con rotazione automatica. Viene usato sia dal server stesso
(startup, route, errori, sessioni, ecc.) sia dalla tua applicazione
tramite le macro `l()`, `lw()`, `le()`, `lf()` e `ld()`.

Insieme al log generale (`hix.log`), HIX mantiene in parallelo un
**access log in stile Apache CLF** (`access.log`) con una riga per ogni richiesta HTTP servita.

---

## Quando ti serve?

- Per **diagnosticare** il comportamento del server in produzione senza
  fermarlo.
- Per mantenere un **registro auditabile** delle richieste HTTP ricevute
  (`access.log`).
- Per far sì che i tuoi controller e middleware lascino **trace strutturate**
  con livelli di severità.

---

## Setup in `hix.json`

### Sezione `paths`

Definisci la directory comune dove vengono scritti tutti i log:

```json
{
  "paths": {
    "log": ".logs"
  }
}
```

### Sezione `log` - log generale

`level`: `debug` | `info` | `warn` | `error` | `fatal`.
`console = true` stampa anche su console.
`max_size_mb`: MB per la rotazione quando questa dimensione viene superata.
`max_files = 0`: backup illimitati.

```json
{
  "log": {
    "file":        "hix.log",
    "level":       "info",
    "console":     true,
    "max_size_mb": 10,
    "max_files":   0
  }
}
```

### Sezione `access_log` - log delle richieste

```json
{
  "access_log": {
    "enabled": true,
    "file":    "access.log"
  }
}
```

L'access log viene generato **automaticamente** da
`THixRequest:Respond()` - non devi chiamarlo manualmente.

> 💡 `errors.log` è riservato per futuri record strutturati di errori HTTP;
> oggi tutti gli errori vanno nel log generale con livello
> `ERROR` o `FATAL`.

---

## Livelli

| Macro  | Costante          | Livello | Quando usarlo                                |
|--------|-------------------|---------|----------------------------------------------|
| `ld()` | `HIX_LOG_DEBUG`   | 1       | Dettagli interni, solo sviluppo              |
| `l()`  | `HIX_LOG_INFO`    | 2       | Informazione operativa normale               |
| `lw()` | `HIX_LOG_WARN`    | 3       | Qualcosa di recuperabile che merita attenzione|
| `le()` | `HIX_LOG_ERROR`   | 4       | Errore che interessa la request o il sottosistema |
| `lf()` | `HIX_LOG_FATAL`   | 5       | Errore grave che può far crashare il server  |

Solo i messaggi **uguali o superiori** al `level` configurato
vengono scritti. `level=info` filtra `ld()`; `level=warn` filtra `ld()` e
`l()`; ecc.

---

## Uso dal codice

Qualsiasi `.prg` che vuole loggare deve includere l'header delle macro:

```clipper
#include "hix_logger.ch"

FUNCTION MyController()
   l( "Accesso al pannello utente" )
   IF ! _CheckPermissions()
      lw( "Tentativo di accesso non autorizzato da " + UIP() )
      RETURN USendError( 403 )
   ENDIF
   le( "Qualcosa è andato storto con il database" )
RETURN NIL
```

### Formato dell'output

```
[2026-06-27 09:14:32.123] [INFO ] [router] Route /users/42 -> users.show
[2026-06-27 09:14:32.456] [WARN ] [auth  ] Login fallito: carles
[2026-06-27 09:14:32.789] [ERROR] [db    ] Impossibile aprire customers.dbf
```

Ogni riga contiene:
1. Timestamp con millisecondi.
2. Livello di severità.
3. Modulo mittente (definito da `#define HIX_LOG_MODULE` all'inizio del .prg).
4. Messaggio libero.

> 📚 Il modulo si dichiara così in ogni file `.prg` del framework
> (e puoi fare lo stesso nei tuoi):
>
> ```clipper
> #define HIX_LOG_MODULE "myapp.users"
> #include "hix_logger.ch"
> ```

---

## Rotazione automatica

Quando `hix.log` raggiunge `max_size_mb`:
1. Il file corrente viene rinominato in `hix_YYYYMMDDHHMMSS_NNNNNN.log`.
2. Viene creato un nuovo `hix.log` vuoto.
3. Se `max_files > 0`, i backup più vecchi vengono eliminati per mantenere
   solo `max_files` file storici.

La rotazione è **seamless**: nessun log perso, gli handler di scrittura
sono sincronizzati tramite mutex.

```text
.logs/
   ├── hix.log                              <- attivo
   ├── hix_20260620120134000000.log         <- ruotato
   ├── hix_20260622150812000000.log
   └── access.log                           <- attivo (nessuna rotazione automatica)
```

> ⚠️ `access.log` **non ruota automaticamente**. Se ti serve con
> traffico elevato, configura `logrotate` (Linux) o uno script schedulato (Windows).

---

## Access log: formato CLF

`access.log` segue lo standard [Common Log Format](https://en.wikipedia.org/wiki/Common_Log_Format)
di Apache:

```
192.168.1.100 - - [27/Jun/2026:09:14:32 +0000] "GET /users/42 HTTP/1.1" 200
192.168.1.100 - - [27/Jun/2026:09:14:35 +0000] "POST /login HTTP/1.1" 302
10.0.0.5      - - [27/Jun/2026:09:14:40 +0000] "GET /admin HTTP/1.1" 403
```

Compatibile con strumenti standard (`awstats`, `goaccess`, `lnav`...).

---

## Tracciamento per modulo

`ld()` e `l()` accettano un filtro aggiuntivo per **modulo mittente**. Questo permette di
attivare il dettaglio solo da un sottosistema senza inondare il log:

```clipper
HIX_TraceSet( "router",  .T. )   // attiva DEBUG/INFO dal router
HIX_TraceSet( "session", .F. )   // silenzia DEBUG/INFO dalla sessione
HIX_TraceAll( .T. )              // attiva tutto
```

I livelli `WARN`, `ERROR` e `FATAL` **passano sempre** indipendentemente dal
filtro trace. Questa è la differenza chiave rispetto al semplice `level`:

- `level` = soglia globale per severità.
- `HIX_TraceSet` = filtro granulare per modulo, solo per i livelli bassi.

> 🔧 Utile per diagnosticare un problema in produzione senza abbassare `level`
> a `debug` (che genererebbe log enormi).

---

## Inizializzazione manuale

Nelle applicazioni standalone che avviano `THixServer` senza passare per
`hix.json`, devi inizializzare tu stesso il logger:

```clipper
HIX_LoggerInit( "logs/app.log", HIX_LOG_DEBUG, .T., 10485760, 5 )
//              ^cFile           ^level         ^console ^maxsize  ^maxfiles
```

Nel flusso normale con `hix.json`, `THixServer:New()` se ne occupa.

---

## Errori comuni

| Sintomo                            | Causa                                              | Fix                              |
|------------------------------------|----------------------------------------------------|----------------------------------|
| Il log è vuoto                     | Livello sopra i messaggi emessi                   | Abbassa `level` a `debug` o `info` |
| Appare in console ma non nel file  | `paths.log` punta a una directory senza permesso di scrittura | Crea/consenti la directory       |
| `access.log` non viene scritto     | `access_log.enabled = false`                       | Imposta `enabled = true`         |
| I log vecchi non vengono eliminati | `max_files = 0`                                    | Definisci un limite (`max_files = 10`) |
| Manca `l()` in un .prg             | Hai dimenticato `#include "hix_logger.ch"`        | Aggiungilo in header             |
