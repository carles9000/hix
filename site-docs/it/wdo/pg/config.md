# WDO PostgreSQL — Configurazione

Ci sono tre modi per avviare il pool PostgreSQL. Il consigliato è il metodo dichiarativo tramite `config.json`.

## Metodo 1 — Dichiarativo (consigliato)

Aggiungi la sezione `databases` in `www/config.json`:

```json
{
  "databases": {
    "PG": {
      "driver":             "pg",
      "host":               "127.0.0.1",
      "port":               5432,
      "user":               "postgres",
      "pwd":                "secret",
      "db":                 "myapp",
      "pool_size":          5,
      "timeout_ms":         5000,
      "ping":               true,
      "read_timeout_s":     30,
      "connect_timeout_s":  10,
      "sslmode":            "disable",
      "application_name":   "hix-worker",
      "client_encoding":    "UTF8",
      "berror":             "WDO_DefaultErrorHandler"
    }
  }
}
```

In `app.prg` con **hixstyle** non serve altro: `Start()` chiama automaticamente `HIX_InitPoolsFromConfig(.T.)` e `HIX_EndPoolsFromConfig()`.

In app senza hixstyle:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()
   HIX_ConfigAppLoad( "www/config.json" )
   HIX_InitPoolsFromConfig()   // interrompe se qualche pool fallisce (default)
   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
   HIX_EndPoolsFromConfig()
RETURN
```

### Pool multipli

Puoi dichiarare più database con chiavi diverse:

```json
{
  "databases": {
    "PG":        { "driver": "pg", "host": "127.0.0.1", "db": "myapp", ... },
    "PG_REPORT": { "driver": "pg", "host": "10.0.0.42", "db": "reports", ... }
  }
}
```

Negli handler: `WDO_Get("PG")` e `WDO_Get("PG_REPORT")` coesistono nello stesso processo.

### Campi disponibili

| Campo | Default | Descrizione |
|-------|---------|-------------|
| `driver` | _(obbligatorio)_ | `"pg"` (case-insensitive) |
| `host` | `"localhost"` | IP o hostname del server PostgreSQL |
| `user` | `""` | Utente di autenticazione |
| `pwd` | `""` | Password |
| `db` | `""` | Database di default |
| `port` | `5432` | Porta TCP |
| `pool_size` | `5` | Numero di connessioni aperte all'avvio |
| `timeout_ms` | `5000` | Tempo massimo di attesa in `WDO_Get()` (0 = infinito) |
| `ping` | `true` | Ping prima di consegnare ogni slot; riconnette se morto |
| `read_timeout_s` | `30` | `statement_timeout` in secondi applicato per sessione (0 = nessun timeout). Limita query impazzite; senza questo uno slot può rimanere occupato indefinitamente |
| `connect_timeout_s` | `10` | Timeout della fase di connessione TCP + auth in secondi (0 = nessun timeout). Evita che l'avvio del pool rimanga bloccato se il server non risponde |
| `sslmode` | `"disable"` | `disable` / `allow` / `prefer` / `require` / `verify-ca` / `verify-full` |
| `application_name` | `"hix-worker"` | Visibile in `pg_stat_activity` per identificare le connessioni del pool |
| `client_encoding` | `"UTF8"` | Encoding della sessione; deve corrispondere o essere compatibile con il DB |
| `debug` | `false` | Se qualsiasi pool ha `"debug": true`, attiva `HIX_Dbg()` globalmente: `dbg.log` cattura le trace di Acquire/Release e tutte le chiamate `HIX_Dbg()` nei controller. Solo per sviluppo |
| `berror` | — | Nome della funzione Harbour per gestire gli errori del pool |
| `dll` | — | Percorso esplicito a `libpq.dll` (override della risoluzione automatica) |

!!! warning "Relazione con `exec_timeout_ms`"
    `read_timeout_s` deve essere **maggiore** della query legittima più lenta e coerente con `exec_timeout_ms` del dispatcher (in `hix.json`). `read_timeout_s` viene implementato come `SET statement_timeout = N * 1000` per sessione, quindi influisce su tutte le query su quella connessione.

!!! tip "berror predefinito"
    `"berror": "WDO_DefaultErrorHandler"` è già incluso nella lib: registra l'errore con `le()` e restituisce 500 se c'è una request attiva. Sufficiente per la maggior parte dei progetti.

---

## Metodo 2 — Programmatico hash

```harbour
WDO_InitPoolPgEx( "PG", { ;
   "host"             => hb_GetEnv( "DB_HOST" ),     ;
   "user"             => hb_GetEnv( "DB_USER" ),     ;
   "pwd"              => hb_GetEnv( "DB_PWD"  ),     ;
   "db"               => "myapp",                    ;
   "pool_size"        => 10,                         ;
   "timeout_ms"       => 5000,                       ;
   "ping"             => .T.,                        ;
   "sslmode"          => "require",                  ;
   "application_name" => "hix-worker",               ;
   "client_encoding"  => "UTF8",                     ;
   "berror"           => "WDO_DefaultErrorHandler"   ;
} )
```

Utile quando le credenziali vengono lette da variabili d'ambiente o secret.

## Metodo 3 — Posizionale (legacy)

```harbour
WDO_InitPoolPg( "127.0.0.1", "postgres", "secret", "myapp", 5432, ;
                 5,     /* pool_size   */ ;
                 5000,  /* timeout_ms  */ ;
                 .T.    /* ping        */ )
```

Registra il pool sotto la chiave fissa `"PG"`. Compatibile con codice precedente a v2.4.4.

Per chiudere:

```harbour
WDO_EndPoolPg()
```

---

## DLL — libpq e dipendenze

Il driver necessita di quattro DLL dalla distribuzione PostgreSQL per Windows:

| DLL | Funzione |
|-----|----------|
| `libpq.dll` | Libreria client PostgreSQL (protocollo wire) |
| `libcrypto-4-x64.dll` | Primitive crittografiche (SSL, SCRAM-SHA-256) |
| `libssl-4-x64.dll` | TLS per connessioni con `sslmode != disable` |
| `libcurl-x64.dll` | Usata da libpq per connessioni HTTP proxy |

Tutte e quattro le DLL pronte da copiare si trovano in `resources/wdo/pg/dll/` del progetto HIX.

### Precedenza di risoluzione di libpq.dll

Il driver cerca la libreria in quest'ordine (priorità più alta prima):

1. **Campo `"dll"` in `config.json`** — percorso assoluto esplicito per pool.
2. **Variabile d'ambiente `HIX_PG_DLL`** — percorso assoluto al file.
3. **Variabile d'ambiente `WDO_PG_DLL`** — percorso assoluto al file.
4. **Directory dell'eseguibile** (`hb_DirBase() + "dll\libpq.dll"`).
5. **PATH di sistema** — nome canonico `libpq.dll` senza percorso.

Il tag viene salvato in `oConn:DllSource()` per la diagnostica.

### Diagnostica

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "pool non disponibile" ) ; ENDIF
   USendJson( { ;
      "dll_source" => oConn:DllSource(), ;
      "dll_path"   => oConn:DllPath(),   ;
      "server"     => oConn:ServerInfo() ;
   } )
   oConn:Close()
} )
```

`DllSource()` restituisce `"override"`, `"env"`, `"exedir"` o `"default"`.

### Se la DLL non viene trovata

Il pool fallisce all'avvio e scrive sulla console:

```
==> Error: Cannot load PostgreSQL DLL (libpq.dll)
```

Con `HIX_InitPoolsFromConfig(.T.)` il server si interrompe. Con `.F.` continua, ma `WDO_Get("PG")` restituirà NIL e gli handler risponderanno con 503.

=== "Opzione A — accanto all'eseguibile"
    Copia le quattro DLL da `resources/wdo/pg/dll/` nella directory del server (`hb_DirBase()`). L'opzione più semplice, usa `cDllSource = "exedir"`.

=== "Opzione B — variabile d'ambiente"
    ```bash
    set HIX_PG_DLL=C:\postgresql\bin\libpq.dll
    ```

=== "Opzione C — campo dll in config.json"
    ```json
    {
      "databases": {
        "PG": {
          "driver": "pg",
          "dll": "C:/postgresql/bin/libpq.dll",
          "..."
        }
      }
    }
    ```

!!! warning "Le dipendenze di libpq devono essere accessibili"
    `libpq.dll` carica dinamicamente `libcrypto-4-x64.dll`, `libssl-4-x64.dll` e `libcurl-x64.dll`. Se queste DLL non si trovano accanto all'eseguibile né nel `PATH`, otterrai un errore di Windows facendo `hb_LibLoad("libpq.dll")` anche se il file esiste. Copia sempre le quattro DLL insieme.

---

## Handler di errore personalizzato

Se hai bisogno di logica custom (alert Slack, metriche, ecc.), definisci una funzione pubblica:

```harbour
FUNCTION WdoPgErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[WDO_PG] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

E referenziala nel JSON:

```json
"berror": "WdoPgErrorHandler"
```

!!! warning "Requisiti della funzione"
    Deve essere una `FUNCTION` pubblica (non `STATIC`, non `PROCEDURE`) e **collegata staticamente** all'eseguibile. Se si trova in un `.hrb` dinamico, `hb_isFunction` non la troverà all'avvio.
