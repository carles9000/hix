# WDO MySQL - Troubleshooting

Guida alla diagnostica per gli errori più frequenti del driver MySQL.

## Mappa sintomo → soluzione

| Sintomo | Vai a |
|---------|-------|
| Errore 10048 / `WSAEADDRINUSE` all'avvio | [§1](#1-errore-10048-wsaeaddrinuse) |
| La DLL non si carica / "not found" in console | [§2](#2-dll-non-trovata) |
| `WDO_Get()` restituisce NIL sotto carico | [§3](#3-wdoget-restituisce-nil-sotto-carico) |
| "MySQL server has gone away" | [§4](#4-mysql-server-has-gone-away) |
| "Too many connections" in MySQL | [§5](#5-too-many-connections) |
| L'app si blocca all'avvio senza messaggi | [§6](#6-app-si-blocca-allavvio) |
| WARN `RELEASE_RECLAIM` nel log | [§7](#7-warn-release_reclaim) |

---

## 1. Errore 10048 WSAEADDRINUSE

```
Error WDO/500  Connection = (Failed connection)
Can't connect to MySQL server on 'localhost' (10048)
```

**Causa:** Stai usando `WDO_MySql():New()` all'interno di un handler HTTP (o fuori dal pool). Ogni richiesta apre un socket che rimane in `TIME_WAIT` ~60 s. Dopo ~10.000 richieste rapide, Windows esaurisce le porte efimere (intervallo 49152–65535).

**Soluzione:** Usa sempre `WDO_Get("mysql")` negli handler. Mai `New()` all'interno di un controller.

!!! warning "New() negli handler - avviso nel log"
    Il driver rileva questo pattern e scrive nel log:
    ```
    WARN  WDO_MySql:New called inside HTTP request handler.
          Use WDO_Get("mysql") + oConn:Close() instead.
    ```
    Se vedi questo avviso, individua l'handler che lo genera e modificalo per usare il pool.

---

## 2. DLL non trovata

```
==> Error: Cannot load MySQL DLL
```

**Cause possibili:**

1. La DLL non si trova in nessuno dei percorsi cercati.
2. Il campo `"dll"` in `config.json` punta a un percorso errato.
3. Stai usando `"driver": "mysql"` ma hai solo `libmariadb64.dll` (o viceversa).

**Soluzioni:**

=== "Opzione A - accanto all'eseguibile"
    Copia `libmysql64.dll` (o `libmariadb64.dll`) nella directory del server (`hb_DirBase()`). L'opzione più semplice.

=== "Opzione B - variabile d'ambiente"
    ```
    set WDO_LIB_MYSQL=C:\mysql\lib\libmysql64.dll
    ```

=== "Opzione C - campo dll in config.json"
    ```json
    {
      "databases": {
        "mysql": {
          "driver": "mysql",
          "dll": "C:/mysql/lib/libmysql64.dll",
          ...
        }
      }
    }
    ```

Per vedere quale DLL sta usando il driver in fase di esecuzione:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "no pool" ) ; ENDIF
   USendJson( { "dll_path" => oConn:DllPath(), "dll_source" => oConn:DllSource() } )
   oConn:Close()
} )
```

---

## 3. WDO_Get restituisce NIL sotto carico

```
WARN  WDO_Pool[MySQL] Acquire timeout after 5000ms
```

**Causa:** Tutti gli slot del pool sono occupati. Gli handler impiegano più del previsto e gli slot non vengono liberati in tempo.

**Diagnostica:**

```harbour
// Aggiungi questo endpoint per vedere lo stato in tempo reale
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "mysql" ) )
   // { "size" => 5, "busy" => 5, "free" => 0, "closed" => false }
} )
```

**Soluzioni (in ordine):**

1. **Aumentare `pool_size`** in `config.json` (inizia raddoppiando).
2. **Verificare che tutti gli handler chiamino `oConn:Close()`** - un solo handler che perde una connessione sotto carico riempie il pool.
3. **Rivedere la latenza delle query** - se le query lente occupano gli slot troppo a lungo, ottimizzare gli indici o aggiungere più slot.
4. **Aumentare `timeout_ms`** se i picchi sono brevi e il pool si libera presto.

---

## 4. MySQL server has gone away

```
Error WDO/500  Connection = (Failed connection)
MySQL server has gone away
```

**Causa:** La connessione TCP del pool era inattiva più a lungo del `wait_timeout` di MySQL (di default 8 ore, a volte 30 minuti in hosting condiviso). MySQL ha chiuso la connessione dal suo lato, ma lo slot del pool non lo sa.

**Soluzione:** Attiva `"ping": true` in `config.json`. Prima di consegnare ogni slot, il pool esegue un ping e riconnette se il socket è inattivo:

```json
{
  "databases": {
    "mysql": {
      "ping": true,
      ...
    }
  }
}
```

!!! info "Costo del ping"
    Il ping aggiunge ~0.5 ms per `WDO_Get()`. In pratica, irrilevante rispetto al costo di qualsiasi query reale. Consigliato sempre in produzione con MySQL remoto.

Se il problema persiste, aumenta `wait_timeout` in MySQL (`my.cnf`):
```ini
[mysqld]
wait_timeout = 28800
interactive_timeout = 28800
```

---

## 5. Too many connections

```
Can't connect to MySQL server (1040): Too many connections
```

**Causa:** Il numero di connessioni attive supera `max_connections` di MySQL (default 151).

**Diagnostica:**
```sql
SHOW STATUS LIKE 'Threads_connected';
SHOW VARIABLES LIKE 'max_connections';
```

**Soluzioni:**

1. **Ridurre `pool_size`** in `config.json` - non dovresti avere più connessioni WDO di quelle che MySQL può accettare.
2. **Aumentare `max_connections`** in `my.cnf` (con cautela: ogni connessione consuma ~1 MB di RAM):
   ```ini
   [mysqld]
   max_connections = 300
   ```
3. **Verificare che non ci siano pool duplicati** - se più istanze dell'app puntano allo stesso MySQL, il totale delle connessioni è la somma di tutti i pool.

Regola d'oro: `MySQL.max_connections > HIX_workers ≥ WDO_pool_size + 20 (margine admin)`.

---

## 6. App si blocca all'avvio

L'app si avvia, non ci sono messaggi di errore, ma non risponde.

**Causa più frequente:** La DLL si carica ma `mysql_real_connect` rimane in attesa - l'host non risponde (firewall, MySQL spento, hostname errato).

**Diagnostica:**

```bash
# Testare la connettività direttamente
mysql -h 127.0.0.1 -u harbour -p employees
```

!!! warning "localhost vs 127.0.0.1 su Linux"
    Su Linux, `mysql_real_connect("localhost")` usa il **socket Unix** (`/var/run/mysqld/mysqld.sock`) invece di TCP. Se il socket non esiste, la connessione si blocca. WDO rimappa automaticamente `"localhost"` in `"127.0.0.1"` per forzare TCP, ma se hai problemi su Linux verifica che mysqld sia in ascolto su TCP (`bind-address = 0.0.0.0`).

**Altre cause:**

- `lAbortOnFail = .T.` in `HIX_InitPoolsFromConfig` → il processo attende `Inkey(0)`. Se viene avviato come servizio senza console, si blocca in attesa di un tasto. Controlla il log di sistema (`journalctl -u hix` su Linux).
- Timeout di rete molto alto - prova a ridurre `timeout_ms` a 3000 per fallire rapidamente durante la diagnostica.

---

## 7. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Causa:** Un handler ha acquisito una connessione con `WDO_Get()` ma non ha chiamato `oConn:Close()` prima di terminare. Il dispatcher di HIX rileva il leak al termine della richiesta e libera lo slot automaticamente.

**Gravità:** Non è un errore critico - lo slot viene recuperato. Ma il thread ha tenuto la connessione più a lungo del necessario, il che riduce la disponibilità del pool sotto carico.

**Soluzione:** Individua l'handler che non chiude la connessione e aggiungi `oConn:Close()`, idealmente in un blocco `FINALLY`:

```harbour
TRY
   // ... logica dell'handler ...
FINALLY
   IF oConn != NIL ; oConn:Close() ; ENDIF
END
```

---

## Messaggi del logger (riferimento rapido)

| Messaggio | Livello | Significato |
|-----------|---------|-------------|
| `WDO_LOG_POOL_INIT_FAIL` | WARN | Uno slot del pool non è riuscito ad aprirsi all'avvio |
| `WDO_LOG_ACQUIRE_TIMEOUT` | WARN | `WDO_Get()` ha atteso `timeout_ms` senza ottenere uno slot |
| `WDO_LOG_MYSQL_POOL_INIT_FAIL` | WARN | Nessuno slot del pool si è aperto; pool non disponibile |
| `WDO_ERR_LIB_NOT_FOUND` | ERROR | La DLL non esiste nel percorso cercato |
| `WDO_ERR_LIB_LOAD_FAIL` | ERROR | La DLL esiste ma `hb_LibLoad` non è riuscito a caricarla |
| `WDO_WARN_NEW_IN_REQUEST` | WARN | `New()` chiamato all'interno di un handler HTTP |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | La funzione del campo `berror` non è collegata |
| `WDO_LOG_POOLS_INIT` | INFO | `N/M pools` inizializzati correttamente |
| `WDO_LOG_POOLS_END` | INFO | Pool chiusi allo spegnimento del server |
