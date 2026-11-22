# WDO SQLite3 — Configurazione

Ci sono tre modi per inizializzare il driver SQLite3 (singleton o pool). Il consigliato è il metodo dichiarativo tramite `hix.json` (o `www/config.json` con hixstyle).

## Metodo 1 — Dichiarativo (consigliato)

Aggiungi la sezione `databases` in `hix.json`:

```json
{
  "databases": {
    "APP": {
      "driver":                "sqlite3",
      "file":                  "www/data/app.db",
      "create":                true,
      "journal_mode":          "WAL",
      "synchronous":           "NORMAL",
      "foreign_keys":          true,
      "busy_timeout_ms":       5000,
      "key_ref":               "sqlite3"
    }
  }
}
```

In app con **hixstyle** non serve altro: `Start()` chiama automaticamente `HIX_InitPoolsFromConfig(.T.)` e `HIX_EndPoolsFromConfig()`.

In app senza hixstyle:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()
   HIX_ConfigAppLoad( "www/config.json" )
   HIX_InitPoolsFromConfig()   // interrompe se il singleton non si avvia (default)
   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
   HIX_EndPoolsFromConfig()
RETURN
```

### Campi disponibili

| Campo | Default | Descrizione |
|-------|---------|-------------|
| `driver` | _(obbligatorio)_ | `"sqlite3"` (case-insensitive) |
| `file` | `":memory:"` | Percorso al file `.db` (relativo alla directory di lavoro) |
| `create` | `true` | Crea il file se non esiste; `.F.` fallisce se non esiste |
| `journal_mode` | `"WAL"` | `WAL` / `DELETE` / `MEMORY` / `OFF`. WAL = migliore concorrenza |
| `synchronous` | `"NORMAL"` | `FULL` / `NORMAL` / `OFF`. NORMAL = buon equilibrio durabilità/velocità |
| `foreign_keys` | `true` | Attiva `PRAGMA foreign_keys=ON` |
| `busy_timeout_ms` | `5000` | Tempo massimo di attesa se un altro processo ha il file bloccato |
| <a name="pool_size"></a>`pool_size` | `1` | `1` = singleton (una connessione condivisa, mutex per operazione); `> 1` = pool reale di N connessioni con prenotazione per request. Vedi [Transazioni § Isolamento](transazioni.md#isolamento-delle-transazioni). Aggiunto in v2.5.3. |
| `timeout_ms` | `5000` | Timeout di prenotazione del pool (solo con `pool_size > 1`): se tutte le connessioni sono occupate, quanto aspetta `WDO_Get` prima di restituire `NIL` |
| `ping` | `false` | Ping on-acquire del pool (solo con `pool_size > 1`): verifica che la connessione sia ancora attiva prima di consegnarla all'handler |
| `debug` | `false` | Attiva `HIX_Dbg()` globalmente; scrive trace in `dbg.log` |
| `berror` | — | Nome della funzione Harbour per gestire gli errori del driver |
| `dll` | — | Percorso esplicito a `sqlcipher.dll` (override della risoluzione automatica) |

Campi SQLCipher (opzionali; ignorati se non c'è `key` né `key_ref`):

| Campo | Default | Descrizione |
|-------|---------|-------------|
| `key` | `""` | Passphrase in testo normale. Solo per test; usa `key_ref` in produzione |
| `key_ref` | `""` | Nome della chiave in `HIX_Keys` (consigliato) |
| `cipher_kdf_iter` | `0` | Iterazioni KDF PBKDF2 (0 = default SQLCipher ~256.000) |
| `cipher_page_size` | `0` | Dimensione pagina cifrata in byte (0 = default 4096) |
| `cipher_hmac_algorithm` | `""` | `HMAC_SHA512` / `HMAC_SHA1` (`""` = default SQLCipher 4.x) |
| `cipher_kdf_algorithm` | `""` | `PBKDF2_HMAC_SHA512` / `PBKDF2_HMAC_SHA1` (`""` = default) |

### key vs key_ref

!!! warning "Non mettere mai la passphrase in testo normale in produzione"
    Il campo `key` memorizza la passphrase direttamente nel JSON. Chiunque abbia accesso al file di configurazione conosce la chiave. Usa `key_ref` in produzione.

`key_ref` punta a una chiave memorizzata in `HIX_Keys`, che viene popolata dalla sezione `keys` di `www/config.json`:

```json
{
  "keys": {
    "sqlite3": "mia-passphrase-segreta-32char"
  },
  "databases": {
    "APP": {
      "driver":    "sqlite3",
      "file":      "www/data/app.db",
      "key_ref":   "sqlite3"
    }
  }
}
```

All'avvio, `HIX_InitPoolsFromConfig()` risolve `key_ref` → `HIX_KeyGet("sqlite3")` e passa la passphrase al driver. Il valore non rimane in memoria più del tempo necessario per aprire la connessione.

---

## Metodo 2 — Programmatico hash

```harbour
WDO_InitSqlite3Ex( "APP", { ;
   "file"            => hb_GetEnv( "DB_PATH" ),  ;
   "create"          => .T.,                      ;
   "journal_mode"    => "WAL",                    ;
   "synchronous"     => "NORMAL",                 ;
   "foreign_keys"    => .T.,                      ;
   "busy_timeout_ms" => 5000,                     ;
   "key"             => hb_GetEnv( "DB_KEY" ),    ;
   "cipher_kdf_iter" => 256000                    ;
} )
```

Utile quando il percorso o la passphrase vengono letti da variabili d'ambiente o da un vault esterno.

## Metodo 3 — Posizionale (legacy)

```harbour
//  WDO_InitSqlite3( cFile, lCreate, bError, cKey )
WDO_InitSqlite3( "data/app.db", .T., NIL, "" )   // senza cifratura

//  Con cifratura
WDO_InitSqlite3( "data/secure.db", .T., NIL, "mia-passphrase" )
```

Registra il singleton sotto la chiave `"SQLITE3"` (maiuscolo). Compatibile con script di migrazione precedenti a v2.5.0.

!!! info "Chiusura del singleton"
    Per chiudere il singleton registrato sotto qualsiasi chiave: `WDO_EndSqlite3("APP")` o `WDO_EndSqlite3("SQLITE3")`.

---

## DLL — SQLCipher e OpenSSL

Il driver necessita di queste DLL su Windows:

| DLL | Funzione |
|-----|----------|
| `sqlcipher.dll` | SQLite3 + motore di cifratura SQLCipher |
| `libcrypto-4-x64.dll` | OpenSSL — algoritmi AES, HMAC, PBKDF2 |
| `libssl-4-x64.dll` | OpenSSL — TLS (richiesta da libcrypto) |

Le tre DLL precompilate per Windows x64 (MinGW64 / OpenSSL 4.x) si trovano in `resources/wdo/sqlite3/dll/`. Copiale accanto all'eseguibile o aggiungi la loro directory al `PATH`.

### Precedenza di risoluzione di sqlcipher.dll

Il driver cerca la libreria in quest'ordine (priorità più alta prima):

1. **Campo `"dll"` in `config.json`** — percorso assoluto esplicito.
2. **Variabile d'ambiente `HIX_SQLITE3_DLL`** — percorso assoluto al file.
3. **Variabile d'ambiente `WDO_SQLITE3_DLL`** — percorso assoluto al file.
4. **Directory dell'eseguibile** `hb_DirBase() + "dll\sqlcipher.dll"`.
5. **Directory dell'eseguibile** `hb_DirBase() + "sqlcipher.dll"`.
6. **PATH di sistema** — nome canonico `sqlcipher.dll`.

Il tag di risoluzione viene salvato in `oConn:cDllSource` (`"override"`, `"env"`, `"exedir"`, `"default"`) per la diagnostica.

### Se la DLL non viene trovata

```
==> Error: Cannot load SQLite3 DLL: sqlcipher.dll
```

=== "Opzione A — accanto all'eseguibile"
    Copia le tre DLL nella sottodirectory `dll/` accanto all'eseguibile del server. È l'opzione più semplice e usa `hb_DirBase() + "dll\sqlcipher.dll"`.

=== "Opzione B — variabile d'ambiente"
    ```
    set HIX_SQLITE3_DLL=C:\miapp\sqlite3\sqlcipher.dll
    ```

=== "Opzione C — campo dll in config.json"
    ```json
    {
      "databases": {
        "APP": {
          "driver": "sqlite3",
          "dll":    "C:/miapp/sqlite3/sqlcipher.dll",
          ...
        }
      }
    }
    ```

---

## Sidecar WAL — backup e test

!!! warning "Il WAL crea file aggiuntivi"
    Con `journal_mode=WAL`, SQLite genera due file accanto al `.db`:

    - `app.db-wal` — log di scrittura non confermato
    - `app.db-shm` — memoria condivisa (indice del WAL)

    **Backup:** copia tutti e tre i file atomicamente mentre l'app non scrive, oppure usa l'API di backup di SQLite (`sqlite3_backup_*`).

    **Test:** quando elimini il DB di test, elimina anche i sidecar:

    ```harbour
    FErase( cDb )
    FErase( cDb + "-wal" )
    FErase( cDb + "-shm" )
    ```

    Se la connessione viene chiusa in modo pulito (`WDO_EndSqlite3`), SQLite esegue un checkpoint automatico e i sidecar diventano vuoti o scompaiono.

---

## Handler di errore personalizzato

```harbour
FUNCTION MioSqliteErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[SQLite3] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

Referenziala nel JSON:

```json
"berror": "MioSqliteErrorHandler"
```

!!! warning "Requisiti della funzione"
    Deve essere una `FUNCTION` pubblica collegata staticamente all'eseguibile. Se non trovata, il driver scrive un WARN all'avvio e usa l'handler predefinito (che chiama `Break()` e delega al sistema degli errori di Harbour).
