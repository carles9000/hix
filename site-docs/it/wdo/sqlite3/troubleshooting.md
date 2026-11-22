# WDO SQLite3 — Troubleshooting

Guida alla diagnostica per gli errori più frequenti del driver SQLite3/SQLCipher.

## Mappa sintomo → soluzione

| Sintomo | Vai a |
|---------|-------|
| `sqlcipher.dll not found` / DLL non si carica | [§1](#1-dll-non-trovata) |
| `SQLITE_BUSY` / "database is locked" | [§2](#2-sqlite_busy-database-is-locked) |
| `SQLITE_NOTADB` / "SQLCipher key verification failed" | [§3](#3-chiave-errata-sqlite_notadb) |
| Sidecar `-wal` / `-shm` non si cancellano nei test | [§4](#4-sidecar-wal-shm-nei-test) |
| WARN `RELEASE_RECLAIM` nel log | [§5](#5-warn-release_reclaim) |
| `Count()` restituisce sempre -1 | [§6](#6-count-restituisce-1) |
| `Rekey("")` restituisce `.F.` | [§7](#7-rekey-restituisce-f-con-stringa-vuota) |

---

## 1. DLL non trovata

```
==> Error: Cannot load SQLite3 DLL: sqlcipher.dll
```

**Cause possibili:**

1. Le DLL non si trovano in nessuno dei percorsi cercati.
2. Il campo `"dll"` in `config.json` punta a un percorso errato.
3. Manca qualche DLL di dipendenza (`libcrypto-4-x64.dll`, `libssl-4-x64.dll`).
4. È stata copiata solo `sqlcipher.dll` ma non le sue dipendenze OpenSSL.

**Soluzioni:**

=== "Opzione A — sottodirectory dll/ accanto all'eseguibile"
    Copia le tre DLL nella sottodirectory `dll/` accanto all'eseguibile. Questo è il percorso che il driver cerca di default:

    ```
    miapp/
      miapp.exe
      dll/
        sqlcipher.dll
        libcrypto-4-x64.dll
        libssl-4-x64.dll
    ```

    Le DLL pronte da copiare si trovano in `resources/wdo/sqlite3/dll/`.

=== "Opzione B — variabile d'ambiente"
    ```
    set HIX_SQLITE3_DLL=C:\miapp\sqlite3\sqlcipher.dll
    ```
    Le DLL di dipendenza devono essere nella stessa directory o nel PATH.

=== "Opzione C — campo dll in config.json"
    ```json
    {
      "databases": {
        "APP": {
          "driver": "sqlite3",
          "dll":    "C:/miapp/sqlite3/sqlcipher.dll"
        }
      }
    }
    ```

Per verificare quale DLL sta usando il driver in runtime:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "nessun singleton" ) ; ENDIF
   USendJson( oConn:GetClientInfo() )
   oConn:Close()
} )
```

`GetClientInfo()` restituisce `dll_path` e `dll_source` tra gli altri campi.

---

## 2. SQLITE_BUSY — database is locked

```
Error WDO/SQLITE_BUSY  database is locked
```

**Cause possibili:**

1. Un altro processo (SQLite Browser, uno script di migrazione) ha il file aperto con un write lock.
2. Due thread stanno cercando di scrivere contemporaneamente e `busy_timeout_ms` è troppo basso.
3. Una transazione di scrittura è rimasta aperta senza `Commit()` né `Rollback()` (perdita di transazione).

**Soluzioni:**

**Aumentare `busy_timeout_ms`** se il problema è contesa di scrittura tra worker:

```json
{
  "databases": {
    "APP": {
      "busy_timeout_ms": 10000
    }
  }
}
```

**Verificare che nessun altro processo abbia il file aperto:**

```bash
# Windows — quale processo ha il file aperto
handle64.exe app.db
```

**Cercare perdite di transazione** — verificare che tutti gli handler che chiamano `BeginTrans()` chiamino anche `Commit()` o `Rollback()` su tutti i percorsi di uscita, inclusi quelli di errore. Usare sempre `TRY / FINALLY`.

!!! info "WAL riduce ma non elimina i SQLITE_BUSY"
    In modalità WAL, più lettori possono coesistere con un writer. Ma se ci sono due writer contemporanei, il secondo aspetta comunque. `busy_timeout_ms` definisce quanto aspetta prima di restituire errore.

---

## 3. Chiave errata — SQLITE_NOTADB

```
==> Error: SQLCipher key verification failed for file: www/data/app.db
```

**Causa:** La passphrase configurata in `key` o risolta da `key_ref` non corrisponde a quella che ha cifrato il file.

**Questo messaggio appare una sola volta per file** (deduplicazione per percorso). Se vedi il messaggio ripetuto per percorsi diversi, ci sono più file con chiave errata.

**Diagnostica:**

1. Verifica il valore di `key_ref` nella sezione `keys` di `www/config.json`.
2. Se usi `key` direttamente, verifica che non ci siano spazi o caratteri invisibili.
3. Se il file è stato creato con una versione precedente di SQLCipher (< 4.0), i default KDF sono diversi — specifica `cipher_kdf_iter`, `cipher_hmac_algorithm` e `cipher_kdf_algorithm` esplicitamente.

**Nei test — installare bError per evitare che l'errore si propaghi:**

```harbour
LOCAL oConn := WDO_Sqlite3():New()
oConn:bError := {| oErr | .T. }   // assorbire l'errore senza Break()
oConn:cFile  := "test.db"
oConn:cKey   := "chiave-errata"
oConn:Open()

IF ! oConn:lConnect
   ? "Open fallito (atteso): " + oConn:cError
ENDIF
```

!!! warning "CLASSDATA lShowError INIT .T."
    Se `bError` è NIL e `lShowError` è attivo (il default), un `Open()` con chiave errata chiama `Break()` e propaga l'errore al sistema degli errori di Harbour. Negli handler HIX il dispatcher lo cattura e restituisce 500. Nei test unitari fuori dalla pipeline, installa `bError` prima di `Open()`.

---

## 4. Sidecar WAL/SHM nei test

```
// FErase( cDb ) cancella app.db ma i sidecar rimangono su disco
```

**Causa:** La modalità WAL crea `app.db-wal` e `app.db-shm`. Se la connessione non viene chiusa in modo pulito (o se c'è una transazione senza commit), i sidecar contengono dati e non vengono eliminati.

**Soluzione — cancellare tutti e tre i file:**

```harbour
FErase( cDb )
FErase( cDb + "-wal" )
FErase( cDb + "-shm" )
```

**Soluzione migliore — chiudere il singleton prima di cancellare:**

```harbour
WDO_EndSqlite3( "APP" )   // chiude in modo pulito + checkpoint automatico
FErase( cDb )
FErase( cDb + "-wal" )    // normalmente già vuoti dopo il checkpoint
FErase( cDb + "-shm" )
```

!!! tip "DB in memoria per i test"
    I test unitari che non necessitano di persistenza possono usare `"file": ":memory:"`. Un DB in memoria non genera sidecar, è istantaneo da creare/distruggere ed è isolato tra le esecuzioni.

    ```json
    { "driver": "sqlite3", "file": ":memory:", "create": true }
    ```

---

## 5. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Causa:** Un handler ha acquisito un riferimento al singleton con `WDO_Get()` e ha eseguito codice con il mutex del driver acquisito (es. in mezzo a un `Fetch` non terminato) senza rilasciarlo. Il dispatcher HIX rileva lo stato alla fine della request e forza il rilascio.

**In SQLite3 questo è meno grave che in MySQL/PG** (non c'è uno slot di pool che rimane bloccato), ma indica che uno statement non è stato rilasciato con `Free()`.

**Soluzione:** Individua l'handler che non chiama `oStmt:Free()` e aggiungilo in un blocco `FINALLY`:

```harbour
TRY
   oStmt := oConn:Prepare( "SELECT ..." )
   // ... logica ...
FINALLY
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Close()
END
```

---

## 6. Count() restituisce -1

```harbour
oStmt := oConn:Query( "SELECT * FROM utenti" )
? oStmt:Count()   // -1   ← comportamento atteso, non un bug
```

**Causa:** SQLite non conosce il numero totale di righe di un SELECT prima di averle percorse tutte. `sqlite3_data_count()` e `sqlite3_column_count()` non restituiscono il row count — solo il numero di colonne.

**Questa è una differenza fondamentale da MySQL/PG** dove `Count()` restituisce il numero di righe nel resultset.

**Soluzione — ottenere il totale prima se necessario:**

```harbour
// Ottenere il totale
oStmt  := oConn:Query( "SELECT count(*) FROM utenti" )
aRow   := oStmt:Fetch()
nTotal := Val( aRow[ 1 ] )
oStmt:Free()

// Poi ottenere i dati
oStmt := oConn:Query( "SELECT * FROM utenti LIMIT 20" )
aRows := oStmt:FetchAll( .T. )
oStmt:Free()

USendJson( { "total" => nTotal, "data" => aRows } )
```

!!! info "FetchAll e Count()"
    Dopo `FetchAll()`, `oStmt:Count()` restituisce ancora -1. `FetchAll` non memorizza il row count — restituisce direttamente l'array. Se hai bisogno del totale, usa `Len()` sull'array risultante:

    ```harbour
    aRows  := oStmt:FetchAll( .T. )
    nTotal := Len( aRows )
    ```

---

## 7. Rekey() restituisce .F. con stringa vuota

```harbour
IF ! oConn:Rekey( "" )
   le( "SQLCipher non può decifrare con rekey vuoto" )
ENDIF
```

**Causa:** SQLCipher non supporta `PRAGMA rekey = ''` per decifrare il file al suo posto. L'operazione è bloccata a livello del motore SQLCipher e restituisce un errore.

**Soluzione — processo ATTACH + sqlcipher_export:**

Vedi la sezione [Decifrare un DB cifrato](crittografia.md#decifrare-un-db-cifrato) nella documentazione sulla crittografia.

---

## Messaggi del logger — riferimento rapido

| Messaggio | Livello | Significato |
|-----------|---------|-------------|
| `==> Error: Cannot load SQLite3 DLL: ...` | ERROR | La DLL non esiste nel percorso o `hb_LibLoad` fallisce |
| `==> Error: SQLCipher key verification failed for file: ...` | ERROR | Passphrase errata o file non cifrato; `Open()` fallito |
| `WDO_LOG_SQLITE3_INIT_FAIL` | ERROR | Il singleton non è riuscito ad aprirsi all'avvio |
| `WDO_LOG_SQLITE3_BUSY` | WARN | `sqlite3_step` ha restituito `SQLITE_BUSY` dopo aver esaurito `busy_timeout` |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | La funzione del campo `berror` non è collegata all'eseguibile |
| `WDO_LOG_SQLITE3_INIT` | INFO | Singleton inizializzato correttamente |
| `WDO_LOG_SQLITE3_END` | INFO | Singleton chiuso correttamente allo spegnimento del server |
| `WDO_WARN_RELEASE_RECLAIM` | WARN | Statement non rilasciato rilevato e forzato dal dispatcher |
