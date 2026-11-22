# WDO PostgreSQL — Troubleshooting

Guida alla diagnostica per gli errori più frequenti del driver PostgreSQL.

## Mappa sintomo → soluzione

| Sintomo | Vai a |
|---------|-------|
| L'app si blocca all'avvio senza messaggi (TCP probe) | [§1](#1-lapp-si-blocca-allavvio) |
| DLL non trovata / "Cannot load PostgreSQL DLL" | [§2](#2-dll-non-trovata) |
| `WDO_Get()` restituisce NIL sotto carico | [§3](#3-wdoget-restituisce-nil-sotto-carico) |
| "FATAL: password authentication failed" | [§4](#4-errore-di-autenticazione) |
| "SSL connection required" / errore SSL | [§5](#5-errore-ssl) |
| Spam di NOTICE in console ("tabella non esiste, salto") | [§6](#6-spam-notice-ddl) |
| WARN `RELEASE_RECLAIM` nel log | [§7](#7-warn-release_reclaim) |
| `psql` si connette ma l'app no | [§8](#8-psql-si-connette-ma-lapp-no) |

---

## 1. L'app si blocca all'avvio

L'app parte, nessun messaggio di errore, ma non risponde. Il processo rimane con un consumo di CPU minimo per minuti.

**Causa più frequente:** `PQconnectdb` di libpq aspetta la risposta TCP del server. Senza timeout di rete, può bloccarsi fino a 2 minuti se l'host non risponde (firewall che scarta pacchetti senza RST, host errato, PostgreSQL spento).

**Meccanismo di protezione — TCP preflight probe:**

WDO_PG fa un probe TCP di basso livello prima di chiamare `PQconnectdb`. Se l'host non risponde al probe entro `connect_timeout_s` secondi, il pool fallisce in millisecondi:

```
==> Error: WDO_PG TCP probe failed — host=10.0.0.42 port=5432
```

Se vedi questo messaggio, il problema è di rete o di host/porta errati.

**Diagnostica:**

=== "Windows"
    ```cmd
    :: Testare la connettività TCP direttamente
    Test-NetConnection -ComputerName 127.0.0.1 -Port 5432

    :: O con psql
    psql -h 127.0.0.1 -U postgres -d myapp
    ```

=== "Linux / WSL"
    ```bash
    nc -zv 127.0.0.1 5432
    psql -h 127.0.0.1 -U postgres -d myapp
    ```

**Soluzioni in ordine:**

1. Verifica che PostgreSQL sia avviato: `pg_ctl status` o `systemctl status postgresql`.
2. Controlla che `postgresql.conf` abbia `listen_addresses = '*'` o almeno `'127.0.0.1'`.
3. Verifica la porta: di default 5432, ma le installazioni custom possono usarne un'altra.
4. Controlla il firewall: PostgreSQL deve accettare connessioni TCP sulla porta configurata.
5. Riduci `connect_timeout_s` a 3 durante la diagnostica per fallire velocemente.

!!! info "Costo del TCP probe"
    Il probe aggiunge ~1–2 ms per ogni avvio del pool. Trascurabile e compensa eliminando i blocchi da 2 minuti.

---

## 2. DLL non trovata

```
==> Error: Cannot load PostgreSQL DLL (libpq.dll)
```

**Cause possibili:**

1. `libpq.dll` non si trova in nessuno dei percorsi cercati.
2. Il campo `"dll"` in `config.json` punta a un percorso errato.
3. `libpq.dll` esiste ma mancano le sue dipendenze (`libcrypto-4-x64.dll`, `libssl-4-x64.dll`, `libcurl-x64.dll`) — Windows non riesce a caricare la DLL senza un messaggio chiaro.

**Soluzioni:**

=== "Opzione A — accanto all'eseguibile"
    Copia le quattro DLL da `resources/wdo/pg/dll/` alla directory del server (`hb_DirBase()`). L'opzione più semplice.

    ```
    resources/wdo/pg/dll/
      libpq.dll
      libcrypto-4-x64.dll
      libssl-4-x64.dll
      libcurl-x64.dll
    ```

=== "Opzione B — variabile d'ambiente"
    ```cmd
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

Per vedere quale DLL sta usando il driver in runtime:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "nessun pool" ) ; ENDIF
   USendJson( { ;
      "dll_path"   => oConn:DllPath(),   ;
      "dll_source" => oConn:DllSource()  ;
   } )
   oConn:Close()
} )
```

!!! warning "Dipendenze di libpq"
    `libpq.dll` carica dinamicamente le sue dipendenze. Se `libcrypto-4-x64.dll` non si trova accanto all'eseguibile né nel `PATH`, otterrai un errore criptico di Windows ("punto di ingresso della procedura non trovato"). Copia sempre le quattro DLL insieme.

---

## 3. WDO_Get restituisce NIL sotto carico

```
WARN  WDO_Pool[PG] Acquire timeout after 5000ms
```

**Causa:** Tutti gli slot del pool sono occupati. Gli handler impiegano più del previsto e gli slot non vengono rilasciati in tempo.

**Diagnostica:**

```harbour
// Aggiungi questo endpoint per vedere lo stato in tempo reale
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "PG" ) )
   // { "size" => 5, "busy" => 5, "free" => 0, "closed" => false }
} )
```

Puoi anche interrogare le connessioni attive da PostgreSQL:

```sql
SELECT pid, application_name, state, query_start, query
FROM   pg_stat_activity
WHERE  application_name = 'hix-worker'
ORDER  BY query_start;
```

**Soluzioni (in ordine):**

1. **Aumentare `pool_size`** in `config.json` (inizia raddoppiando).
2. **Verificare che tutti gli handler chiamino `oConn:Close()`** — un singolo handler che fa trapelare una connessione sotto carico riempie il pool.
3. **Rivedere la latenza delle query** — query lente (senza indice, full scan) occupano gli slot più a lungo del necessario. Usa `EXPLAIN ANALYZE`.
4. **Aumentare `timeout_ms`** se i picchi sono brevi e il pool si libera presto.

---

## 4. Errore di autenticazione

```
FATAL:  password authentication failed for user "postgres"
```

o

```
FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "postgres", database "myapp"
```

**Cause:**

- Password errata in `config.json`.
- Il metodo di autenticazione in `pg_hba.conf` non consente la connessione dall'IP del server HIX.
- L'utente non esiste o non ha permessi sul database.

**Diagnostica:**

```bash
# Verificare che l'utente esista e la password sia corretta
psql -h 127.0.0.1 -U postgres -d myapp -c "SELECT 1"

# Rivedere pg_hba.conf
psql -U postgres -c "SHOW hba_file"
```

**Configurazione minima di `pg_hba.conf`** per connessioni locali con password:

```
# TYPE  DATABASE  USER      ADDRESS         METHOD
host    all       all       127.0.0.1/32    scram-sha-256
host    all       all       ::1/128         scram-sha-256
```

Dopo aver modificato `pg_hba.conf`:

```bash
pg_ctl reload   # o: SELECT pg_reload_conf();
```

---

## 5. Errore SSL

**Sintomo A — sslmode require ma il server non ha SSL:**

```
FATAL:  SSL connection required but not supported by server
```

**Soluzione:** Cambia `sslmode` in `"disable"` in `config.json` se PostgreSQL non è configurato con SSL, o configura SSL sul server.

**Sintomo B — certificate verification failed:**

```
FATAL:  certificate verify failed
```

**Soluzione:** Usa `sslmode: "require"` (verifica la cifratura ma non il certificato) invece di `"verify-ca"` o `"verify-full"` se non hai i certificati del server installati.

**Tabella modalità SSL:**

| `sslmode` | Cifratura | Verifica cert CA | Verifica hostname | Uso consigliato |
|-----------|-----------|------------------|-------------------|-----------------|
| `disable` | No | No | No | Sviluppo locale |
| `allow` | Se il server lo offre | No | No | — |
| `prefer` | Preferita ma non forzata | No | No | — |
| `require` | Sempre | No | No | Produzione senza PKI propria |
| `verify-ca` | Sempre | Sì | No | Produzione con CA propria |
| `verify-full` | Sempre | Sì | Sì | Massima sicurezza |

!!! tip "Inizia sempre con disable"
    Durante la diagnostica iniziale, imposta `sslmode: "disable"` per eliminare SSL come variabile. Una volta che la connessione funziona, attiva il livello SSL necessario.

---

## 6. Spam NOTICE DDL

**Sintomo:**

```
NOTICE:  table "temp_work" does not exist, skipping
```

Questi messaggi appaiono nella console del server HIX quando esegui `DROP TABLE IF EXISTS` su tabelle inesistenti. Non sono errori ma sporcano il log.

**Causa:** PostgreSQL emette NOTICE di default per operazioni DDL che "non fanno nulla" (IF EXISTS su oggetti assenti).

**Soluzione — `SET client_min_messages` per sessione:**

```harbour
// Silenziare i NOTICE solo nella sessione corrente (non influisce sul server)
oConn:Exec( "SET client_min_messages TO WARNING" )
oConn:Exec( "DROP TABLE IF EXISTS temp_work" )
oConn:Exec( "CREATE TABLE temp_work (id SERIAL PRIMARY KEY, ...)" )
// Ripristinare se vuoi rivedere i NOTICE in questa sessione
oConn:Exec( "SET client_min_messages TO NOTICE" )
```

!!! warning "Scope: solo la sessione corrente"
    `SET client_min_messages` influisce solo sulla connessione dove viene eseguito. Le altre connessioni del pool non sono interessate. Non è necessario né consigliabile cambiarlo a livello di server (`postgresql.conf`) solo per silenziare i NOTICE DDL.

---

## 7. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Causa:** Un handler ha acquisito una connessione con `WDO_Get()` ma non ha chiamato `oConn:Close()` prima di terminare. Il dispatcher HIX rileva la perdita alla fine della request e rilascia lo slot automaticamente.

**Gravità:** Non è un errore critico — lo slot viene recuperato. Ma il thread ha tenuto la connessione più a lungo del necessario, riducendo la disponibilità del pool sotto carico. Se l'handler aveva una transazione aperta, il pool esegue un Rollback automatico prima di rilasciare.

**Soluzione:** Individua l'handler che non chiude la connessione e aggiungi `oConn:Close()`, preferibilmente in un blocco `FINALLY`:

```harbour
TRY
   // ... logica dell'handler ...
FINALLY
   IF oConn != NIL ; oConn:Close() ; ENDIF
END
```

---

## 8. psql si connette ma l'app no

L'applicazione HIX non riesce a connettersi anche se `psql` con gli stessi parametri funziona perfettamente.

**Cause frequenti e verifiche:**

**A) `sslmode` errato:**

`psql` usa di default `sslmode=prefer` (prova SSL, accetta senza SSL). Se in `config.json` hai `sslmode: "require"` e il server PostgreSQL non ha SSL, l'app fallisce ma `psql` senza parametri funziona.

```bash
# Testare con lo stesso sslmode usato dall'app
psql "host=127.0.0.1 dbname=myapp user=postgres sslmode=disable"
```

**B) `pg_hba.conf` distingue tra utenti:**

`psql` può connettersi come `postgres` (superutente) anche se l'utente dell'app non ha accesso.

```bash
# Testare esattamente con l'utente configurato in config.json
psql -h 127.0.0.1 -U hix_user -d myapp
```

**C) Variabili d'ambiente che `psql` eredita ma l'app no:**

`psql` usa `PGPASSWORD`, `PGHOST`, `PGPORT` dall'ambiente. L'app HIX legge solo i campi da `config.json`.

```bash
# Verificare senza variabili d'ambiente
env -i psql "host=127.0.0.1 port=5432 dbname=myapp user=hix_user password=secret"
```

**D) DLL diversa da libpq di `psql`:**

Se il `psql` nel PATH usa libpq di un'installazione diversa dalla DLL che usa HIX, possono esserci differenze di protocollo o supporto di autenticazione.

```bash
# Vedere quale libpq usa psql
psql --version
# Vedere quale DLL usa HIX
curl http://localhost:8080/dbinfo
```

---

## Messaggi del logger — riferimento rapido

| Messaggio | Livello | Significato |
|-----------|---------|-------------|
| `WDO_LOG_POOL_INIT_FAIL` | WARN | Uno slot del pool non è riuscito ad aprirsi all'avvio |
| `WDO_LOG_ACQUIRE_TIMEOUT` | WARN | `WDO_Get()` ha aspettato `timeout_ms` senza ottenere uno slot |
| `WDO_LOG_PG_POOL_INIT_FAIL` | WARN | Nessuno slot del pool si è aperto; pool non disponibile |
| `WDO_ERR_LIB_NOT_FOUND` | ERROR | `libpq.dll` non esiste nel percorso cercato |
| `WDO_ERR_LIB_LOAD_FAIL` | ERROR | `libpq.dll` esiste ma `hb_LibLoad` non è riuscito a caricarla (dipendenze mancanti) |
| `WDO_WARN_NEW_IN_REQUEST` | WARN | `New()` chiamato dentro un handler HTTP |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | La funzione del campo `berror` non è collegata |
| `WDO_LOG_POOLS_INIT` | INFO | `N/M pool` inizializzati correttamente |
| `WDO_LOG_POOLS_END` | INFO | Pool chiusi allo spegnimento del server |
| `WDO_PG TCP probe failed` | ERROR | L'host non risponde al probe TCP prima di `PQconnectdb` |
| `WDO_ReleaseAllThread: reclaiming` | WARN | Slot non restituito dall'handler; reclamato dal dispatcher |
