# WDO MySQL - Configurazione

Ci sono tre modi per avviare il pool MySQL. Quello consigliato è il dichiarativo da `config.json`.

## Metodo 1 - Dichiarativo (consigliato)

Aggiungi la sezione `databases` in `www/config.json`:

```json
{
  "databases": {
    "mysql": {
      "driver":     "mysql",
      "host":       "127.0.0.1",
      "user":       "harbour",
      "pwd":        "hb1234",
      "db":         "employees",
      "port":       3306,
      "pool_size":  5,
      "timeout_ms": 5000,
      "ping":       true,
      "berror":     "WDO_DefaultErrorHandler"
    }
  }
}
```

In `app.prg` con **hixstyle** non hai bisogno di altro: `Start()` chiama automaticamente `HIX_InitPoolsFromConfig()` e `HIX_EndPoolsFromConfig()`.

In app senza hixstyle:

```harbour
PROCEDURE Main()

   LOCAL oSrv := THixServer():New()
   
   HIX_ConfigAppLoad( "www/config.json" )
   
   HIX_InitPoolsFromConfig()   // interrompe se qualche pool fallisce (default)
   
   oSrv:Start()

   HIX_EndPoolsFromConfig()
RETURN
```


Negli handler: `WDO_Get("mysql")` e `WDO_Get("analytics")` coesistono nello stesso processo.

### Campi disponibili

| Campo | Default | Descrizione |
|-------|---------|-------------|
| `driver` | _(obbligatorio)_ | `"mysql"` o `"mariadb"` (case-insensitive) |
| `host` | `"localhost"` | IP o hostname del server |
| `user` | `""` | Utente di autenticazione |
| `pwd` | `""` | Password |
| `db` | `""` | Database di default |
| `port` | `3306` | Porta TCP |
| `pool_size` | `5` | Numero di connessioni all'avvio |
| `timeout_ms` | `5000` | Tempo massimo di attesa in `WDO_Get()` (0 = infinito) |
| `ping` | `true` | Ping prima di consegnare ogni slot; riconnette se è inattivo |
| `berror` | - | Nome della funzione Harbour per gestire gli errori del pool |
| `dll` | - | Percorso esplicito alla DLL (override della risoluzione automatica) |

!!! tip "berror di default"
    `"berror": "WDO_DefaultErrorHandler"` è già incluso nella lib: registra l'errore con `le()` e restituisce 500 se c'è una richiesta attiva. Sufficiente per la maggior parte dei progetti.

## Metodo 2 - Programmatico hash

```harbour
WDO_InitPoolMySqlEx( "mysql", { ;
   "host"       => hb_GetEnv( "DB_HOST" ), ;
   "user"       => hb_GetEnv( "DB_USER" ), ;
   "pwd"        => hb_GetEnv( "DB_PWD" ),  ;
   "db"         => "employees",            ;
   "pool_size"  => 10,                     ;
   "timeout_ms" => 5000,                   ;
   "ping"       => .T.,                    ;
   "berror"     => "WDO_DefaultErrorHandler" ;
} )
```

Utile quando le credenziali vengono lette da variabili d'ambiente o segreti.

## Metodo 3 - Posizionale (legacy)

```harbour
WDO_InitPoolMySql( "localhost", "harbour", "hb1234", "employees", 3306, ;
                    5,     /* pool_size   */ ;
                    5000,  /* timeout_ms  */ ;
                    .T.,   /* ping        */ ;
                    {|oErr, oConn| WdoErrorHandler( oErr, oConn ) } )
```

Registra il pool sotto la chiave fissa `"MYSQL"`. Compatibile con codice precedente alla v2.3.01.

---

## DLL - driver MySQL vs MariaDB

Il driver richiede la libreria client del protocollo MySQL:

| `"driver"` | DLL Windows | SO Linux |
|-----------|-------------|----------|
| `"mysql"` | `libmysql64.dll` | `libmysqlclient.so` |
| `"mariadb"` | `libmariadb64.dll` | `libmariadb.so` |

### Precedenza di risoluzione della DLL

Il driver cerca la libreria in questo ordine (priorità maggiore prima):

1. **Campo `"dll"` in `config.json`** - percorso assoluto esplicito per pool.
2. **Variabile d'ambiente `WDO_LIB_MYSQL`** - percorso assoluto al file.
3. **Variabile d'ambiente `WDO_PATH_MYSQL`** - directory; il driver aggiunge il nome canonico.
4. **Directory dell'eseguibile** (`hb_DirBase()`).
5. **PATH di sistema** - nome canonico senza percorso.

### Diagnostica

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "pool unavailable" ) ; ENDIF
   USendJson( { ;
      "dll_source" => oConn:DllSource(), ;
      "dll_path"   => oConn:DllPath(),   ;
      "server"     => oConn:mysql_get_server_info() ;
   } )
   oConn:Close()
} )
```

`DllSource()` restituisce `"override"`, `"WDO_LIB_MYSQL"`, `"WDO_PATH_MYSQL"`, `"exedir"` o `"default"`.

### Se la DLL non viene trovata

Il pool fallisce all'avvio e scrive in console:

```
==> Error: Cannot load MySQL DLL
```

Con `HIX_InitPoolsFromConfig(.T.)` il server si interrompe. Con `.F.` continua, ma `WDO_Get("mysql")` restituirà NIL e gli handler risponderanno con 503.

---

## Gestore degli errori personalizzato

Se hai bisogno di logica custom (alert Slack, metriche, ecc.), definisci una funzione pubblica:

```harbour
FUNCTION WdoErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[WDO] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

E referenziala nel JSON:

```json
"berror": "WdoErrorHandler"
```
