# 📝 Boot Log

**HIX** cattura in un **hash statico thread-safe** tutto ciò che accade durante
l'avvio del server: file di configurazione caricati, sottosistemi inizializzati, loader compilati,
middleware applicati, e route registrate. Questo record rimane accessibile a runtime
per l'ispezione, la diagnostica, o per mostrarlo in una UI admin.

Ogni evento viene salvato come array di **4 elementi**:

```harbour
{ cAction, lStatus, cValue, xCargo }
```

| Campo     | Tipo | Significato                                                           |
|-----------|------|-----------------------------------------------------------------------|
| `cAction` | `C`  | Tipo di azione: `"file"`, `"config"`, `"init"`, `"route"`, ...      |
| `lStatus` | `L`  | `.T.` se l'operazione è riuscita, `.F.` se è fallita                |
| `cValue`  | `C`  | Identificativo leggibile della risorsa (`myapp.prg`, `users.list`, ...) |
| `xCargo`  | `X`  | Payload libero (descrizione errore, metadata, `NIL` di default)     |

---

## Quando ti serve?

- Per **diagnosticare** perché un modulo, middleware o route non si è caricato.
- Per esporre lo **stato di avvio** al team come JSON o view.
- Per verificare a colpo d'occhio che **tutti i sottosistemi** (logger, proxy,
  firewall, access log, metriche, socket) siano partiti senza errori.

---

## Sezioni

L'hash è organizzato per **processi di caricamento**. Le sezioni standard sono:

| Sezione       | Contenuto                                                           |
|---------------|---------------------------------------------------------------------|
| `config`      | File di configurazione caricati (`hix.json`, `www/config.json`, …) |
| `server`      | Sottosistemi inizializzati: logger, proxy, firewall, access log, metriche… |
| `loaders`     | File `.prg` compilati e caricati da `www/loaders/`                 |
| `middlewares` | Middleware caricati da `www/middlewares/config.json`                |
| `routes`      | Route registrate (JSON o programmatiche; esclude le `hix.*` interne) |

Puoi aggiungere le tue sezioni da codice chiamando `HIX_BootLogAdd`.

---

## API pubblica

```harbour
HIX_BootLog()                                          // hash completo (clonato)
HIX_BootLogSection( cKey )                             // array di una sezione
HIX_BootLogAdd( cKey, cAction, lStatus, cValue, xCargo ) // aggiunge evento
HIX_BootLogReset()                                     // svuota l'hash
HIX_BootLogShow()                                      // dump su console formattato
HIX_BootLogAction( bAction )                           // callback su ogni Add
HIX_BootLogVerbose( lOn )                              // abilita/disabilita verbose
HIX_BootLogIsVerbose()                                 // interroga il flag verbose
```

### `HIX_BootLog()`

Ritorna una **copia clonata** dell'hash completo, thread-safe. Ideale per
inviarla come JSON:

```harbour
oSrv:AddRouteGet( "hix.boot", "/hix-boot", {|| USendJson( HIX_BootLog() ) } )
```

### `HIX_BootLogSection( cKey )`

Ritorna l'array di una specifica sezione (o `{}` se non esiste):

```harbour
aRoutes := HIX_BootLogSection( "routes" )
FOR EACH aItem IN aRoutes
   ? aItem[3], aItem[4]     // cValue, xCargo
NEXT
```

### `HIX_BootLogAdd( cKey, cAction, lStatus, cValue, xCargo )`

Aggiunge un'entry. `lStatus` di default è `.T.`; `xCargo` di default è `NIL`.
Se `lStatus == .F.` e `xCargo == NIL`, viene sostituito con un placeholder
localizzato (`BOOT_ERR_NO_DESC`) così la UI non vede `NIL` negli errori.

```harbour
HIX_BootLogAdd( "loaders", "file", .T., "myapp.prg" )
HIX_BootLogAdd( "loaders", "file", .F., "bad.prg", oErr:description )
```

### `HIX_BootLogReset()`

Svuota l'hash. Viene chiamato automaticamente all'inizio di `_Init()` se il processo
possiede i globali.

### `HIX_BootLogShow()`

Stampa il contenuto su console con formato leggibile, in ordine logico
(`config → server → loaders → middlewares → routes`):

```
=== HIX Boot Log ===
[config]
  OK  file     hix.json
  OK  file     www/config.json
[server]
  OK  init     logger level=info console=T
  OK  init     access_log enabled=T file=access.log
  OK  init     metrics
  OK  init     socket ssl=F
[loaders]
  OK  file     myapp.prg
  ERR file     bad.prg  -> Unterminated string 'x, HB_COMPILEFROMBUF
[middlewares]
  OK  file     cors.prg
  OK  config   session: cookie=hix_sess ttl=3600 storage=memory
[routes]
  OK  init     users.list  -> type:compiled, route=[/users], method[GET,OPTIONS], context:[]
  OK  init     admin.edit  -> type:file[api.json], route=[/admin/:id], method[GET,POST,OPTIONS], context:[admin]
========================
```

### `HIX_BootLogAction( bAction )`

Registra un **codeblock** che viene eseguito **ogni volta** che un'entry viene aggiunta
al boot log. Il codeblock riceve i cinque campi della entry appena inserita:

```harbour
{| cKey, cAction, lStatus, cValue, xCargo | ... }
```

È utile per:
- **Inoltrare** ogni evento al logger (`l()`/`lw()`/`le()`) in tempo reale.
- **Segnalare** errori a un sistema esterno (Sentry, webhook, e-mail).
- **Aggiornare una UI live** durante l'avvio (barra di avanzamento,
  pannello admin).

Passa `NIL` per disabilitarlo. Ritorna il codeblock precedente nel caso tu debba
ripristinarlo.

**Esempio - inoltro al logger con una funzione helper:**

```harbour
// All'avvio del server
HIX_BootLogAction( {|cKey, cAction, lStatus, cValue, xCargo| ;
   MyBootLog( cKey, cAction, lStatus, cValue, xCargo ) } )

// Funzione helper nella tua app
FUNCTION MyBootLog( cKey, cAction, lStatus, cValue, xCargo )
   _t( "[BOOT/" + cKey + "] " + cAction + " " + ;
      iif( lStatus, "OK", "ERR" ) + " " + cValue + ;
      iif( xCargo == NIL, "", " -> " + hb_CStr( xCargo ) ) )
RETURN NIL
```

Ogni entry aggiunta al boot log triggera `MyBootLog()` con i dati dell'evento;
la funzione li formatta e li invia a `_t()` (trace), che può
stamparli su console, file, o dove decidi tu.

> La callback viene invocata **fuori dal mutex interno** per non bloccare le altre
> scritture. Tuttavia, mantieni il codeblock **veloce** - viene eseguito sincronamente
> durante l'avvio.

### `HIX_BootLogVerbose( lOn )` / `HIX_BootLogIsVerbose()`

Abilita o interroga la modalità dettagliata (riservata a record estesi come
le singole entry di route). Ritorna il valore precedente.

---

## Formato di `xCargo` per sezione

### Loaders (errori)

Quando un `.prg`/`.hrb` fallisce, `xCargo` contiene:

```
<oError:description>, <oError:operation>
```

Esempio reale:

```
ERR file     no_symbol.hrb  -> Unknown or unregistered function symbol, ZDUMMY
```

Se l'errore non ha `operation`, appare solo la descrizione. Se non c'è
eccezione catturabile, viene usato il messaggio interno (`BOOT_LOADER_LOAD_FAIL_NX`).

### Middlewares

- `file` con successo → `xCargo` = `NIL`
- `file` con errore → `xCargo` = `"compile failed"`, `"handle NIL"` o
  `oErr:description`
- `config` (session/csrf setup) → `xCargo` = `NIL` e la descrizione va in
  `cValue`

### Routes

Ogni route registrata (tranne quelle interne `hix.*`) genera:

```
type:<type>, route=[<url>], method[<methods>], context:[<scope>]
```

Dove `type` è:
- `compiled` - la route è stata registrata da codice (per esempio con
  `AddRouteGet`).
- `file[<name.json>]` - la route è stata caricata da `www/routes/<name.json>`.

### Server

I sottosistemi sono registrati come `cAction = "init"` e `cValue` descrive la
risorsa con i suoi parametri chiave (`logger level=info console=T`,
`firewall mode=blacklist filter=…`, `socket ssl=T`, ecc.).

---

## Esporre il boot log all'utente

Siccome l'hash è serializzabile, il modo più diretto è una route HTTP:

```harbour
// Endpoint JSON grezzo
oSrv:AddRouteGet( "hix.boot", "/hix-boot", ;
   {|| USendJson( HIX_BootLog() ) } )

// Sezione specifica
oSrv:AddRouteGet( "hix.boot.routes", "/hix-boot/routes", ;
   {|| USendJson( HIX_BootLogSection( "routes" ) ) } )

// View HTML tabulata
oSrv:AddRouteGet( "hix.boot.html", "/hix-boot.html", ;
   {|| USendView( "hix/bootlog.html", { "hLog" => HIX_BootLog() } ) } )
```

Queste route dovrebbero essere protette con `HixMwAdmin` o il middleware di sessione
che usi nel tuo pannello admin.

---

## Esempio - sezione personalizzata

Puoi usare la tua sezione per registrare eventi durante l'avvio della tua applicazione:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()

   oSrv:bInit := {||
      HIX_BootLogAdd( "app", "init", .T., "warmup cache" )
      IF ! _LoadCatalog()
         HIX_BootLogAdd( "app", "init", .F., "catalog", "file corrotto" )
      ENDIF
   }

   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
RETURN
```

La tua sezione `app` apparirà alla fine del dump e anche nell'hash ritornato
da `HIX_BootLog()`.
