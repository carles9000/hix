# WDO SQLite3 — Crittografia con SQLCipher

SQLCipher è un'estensione di SQLite che cifra ogni pagina del file `.db` con **AES-256-CBC + HMAC-SHA512**. Il file cifrato è completamente opaco senza la passphrase — non può essere ispezionato né recuperato con gli strumenti SQLite standard.

La versione inclusa nella DLL di HIX è **SQLCipher 4.6.1 community**.

## Perché pagina per pagina

SQLCipher non cifra il file come un blocco monolitico. Ogni pagina SQLite (tipicamente 4096 byte) viene cifrata in modo indipendente con il proprio IV derivato dal numero di pagina. Questo consente:

- Accesso casuale efficiente — leggere la pagina 500 non richiede di decifrare le 499 precedenti.
- Integrità verificabile per pagina — un HMAC per pagina rileva modifiche parziali del file.
- Piena compatibilità con il motore SQLite — la cifratura è trasparente per i livelli superiori.

## Configurare la cifratura

=== "Dichiarativo (consigliato)"

    ```json
    {
      "keys": {
        "sqlite3": "la-mia-passphrase-segreta"
      },
      "databases": {
        "APP": {
          "driver":   "sqlite3",
          "file":     "www/data/app.db",
          "key_ref":  "sqlite3"
        }
      }
    }
    ```

    `key_ref` si risolve in `HIX_KeyGet("sqlite3")` all'avvio. La passphrase non appare mai nel codice sorgente né nei log.

=== "Programmatico"

    ```harbour
    WDO_InitSqlite3Ex( "APP", { ;
       "file"    => "www/data/secure.db",  ;
       "key_ref" => "sqlite3"              ;
    } )
    ```

=== "Solo per test"

    ```harbour
    WDO_InitSqlite3Ex( "APP", { ;
       "file" => "test.db",          ;
       "key"  => "chiave-di-test"    ;
    } )
    ```

    !!! danger "Non usare mai `key` in produzione"
        La passphrase rimane in chiaro nel codice sorgente o nel JSON di configurazione. Chiunque abbia accesso al repository o al server possiede la chiave.

## Verificare che il DB sia cifrato

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL
   RETURN USendError( 503, "DB non disponibile" )
ENDIF

IF oConn:IsEncrypted()
   l( "DB cifrato. SQLCipher " + oConn:GetCipherInfo()[ "cipher_version" ] )
ELSE
   lw( "ATTENZIONE: il DB non è cifrato" )
ENDIF

oConn:Close()
```

## GetCipherInfo() — parametri attivi

```harbour
hInfo := oConn:GetCipherInfo()
// {
//   "cipher_version" => "4.6.1 community",
//   "kdf_iter"       => 256000,
//   "page_size"      => 4096,
//   "hmac_algorithm" => "HMAC_SHA512",
//   "kdf_algorithm"  => "PBKDF2_HMAC_SHA512"
// }
```

Se la connessione non è cifrata, restituisce un hash vuoto `{=>}`.

## Rekey — cambiare la passphrase

`Rekey(cNewKey)` re-cifra l'intero file con la nuova passphrase:

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn:Rekey( "nuova-passphrase-sicura" )
   l( "Passphrase cambiata correttamente" )
   // oConn:cKey ora è "nuova-passphrase-sicura"
ELSE
   le( "Rekey fallito: " + oConn:cError )
ENDIF

oConn:Close()
```

!!! warning "Rekey con stringa vuota non decifra"
    ```harbour
    IF ! oConn:Rekey( "" )
       le( "SQLCipher rifiuta rekey con chiave vuota" )
    ENDIF
    ```
    SQLCipher non può decifrare il file al suo posto tramite `PRAGMA rekey`. Il driver restituisce `.F.` senza modificare il file. Per decifrare, usare il processo ATTACH + sqlcipher_export (vedi sotto).

## Decifrare un DB cifrato {#decifrare-un-db-cifrato}

Non è possibile con un semplice `Rekey("")`. Il processo corretto usa la CLI di SQLCipher (o una connessione programmatica con due ATTACH simultanei):

```sql
-- Dalla CLI di SQLCipher, con la chiave originale:
PRAGMA key = 'la-mia-passphrase';
ATTACH DATABASE 'plain.db' AS plaintext KEY '';
SELECT sqlcipher_export('plaintext');
DETACH DATABASE plaintext;
-- plain.db è ora un SQLite standard non cifrato
```

Da Harbour, lo stesso processo con due connessioni:

```harbour
LOCAL oCipher := WDO_Sqlite3():New()
LOCAL oPlain  := WDO_Sqlite3():New()

oCipher:cFile := "secure.db"
oCipher:cKey  := "la-mia-passphrase"
oCipher:Open()

oPlain:cFile  := "plain.db"
oPlain:Open()

oCipher:Exec( "ATTACH DATABASE 'plain.db' AS plaintext KEY ''" )
oCipher:Exec( "SELECT sqlcipher_export('plaintext')" )
oCipher:Exec( "DETACH DATABASE plaintext" )

oCipher:Close()
oPlain:Close()
```

## Chiave errata — rilevamento e comportamento

Se la passphrase non corrisponde a quella che ha cifrato il file, SQLite restituisce `SQLITE_NOTADB` (26) all'esecuzione del primo PRAGMA di verifica. Il driver:

1. Rileva l'errore nella verifica interna (`SELECT count(*) FROM sqlite_master`).
2. Scrive **una sola riga** in console per file (deduplicata per path):
   ```
   ==> Error: SQLCipher key verification failed for file: www/data/app.db
   ```
3. Chiude la connessione con `sqlite3_close()` e libera la DLL.
4. Lascia `::lConnect = .F.` e `::lError = .T.`.

In un handler, questo si manifesta come `WDO_Get("APP")` che restituisce `NIL` (se la config usa `HIX_InitPoolsFromConfig`) o come un `bError` scattato se si usa `New()` direttamente:

```harbour
oConn := WDO_Get( "APP" )
IF oConn == NIL
   RETURN USendError( 503, "DB non disponibile" )   // passphrase errata o file corrotto
ENDIF
```

!!! tip "Il messaggio in console appare una sola volta"
    Il driver deduplica per path del file. Se 50 worker tentano di aprire lo stesso DB con chiave errata, nel log comparirà un solo messaggio. Facilita la diagnosi senza inondare il log di produzione.

## Parametri SQLCipher avanzati

La maggior parte delle app deve usare i default di SQLCipher 4.x. Modificare questi parametri solo se si hanno requisiti specifici di compatibilità o prestazioni:

| Parametro | Default SQLCipher 4.x | Quando cambiarlo |
|-----------|----------------------|------------------|
| `cipher_kdf_iter` | 256 000 | Abbassare a 1000–10 000 nei test per accelerare `Open()`. **Mai** in produzione. |
| `cipher_page_size` | 4096 | Solo se serve compatibilità con versioni precedenti di SQLCipher (< 4.0). |
| `cipher_hmac_algorithm` | `HMAC_SHA512` | Solo per interoperabilità con app che usano `HMAC_SHA1` (SQLCipher < 4.0). |
| `cipher_kdf_algorithm` | `PBKDF2_HMAC_SHA512` | Come il precedente. |

!!! warning "KDF iter e tempo di Open()"
    Con 256 000 iterazioni, `sqlite3_key()` impiega ~0,3 secondi su hardware moderno. Questo costo si paga **una sola volta** all'avvio del server, non per ogni request. È completamente accettabile in produzione.

    Nei test di integrazione dove `Open()` viene chiamato decine di volte, usare `"cipher_kdf_iter": 1000` per ridurre il tempo di setup da ~10s a ~40ms.

## Considerazioni sulle prestazioni

| Operazione | Overhead di cifratura |
|-----------|-----------------------|
| Lettura (SELECT) | ~5–10% rispetto a SQLite non cifrato |
| Scrittura (INSERT/UPDATE) | ~15% rispetto a SQLite non cifrato |
| Open() con `kdf_iter=256000` | ~0,3s (una sola volta all'avvio) |
| Rekey() — re-cifra tutto | Proporzionale alla dimensione del file (~2 MB/s) |

Benchmark su hardware di riferimento: Intel Core i7-10750H, SQLCipher 4.6.1, `PRAGMA synchronous=NORMAL`, modalità WAL.

## Riferimento API di cifratura

| Metodo / Proprietà | Descrizione |
|--------------------|-------------|
| `oConn:cKey := cPass` + `oConn:Open()` | Apre un file cifrato esistente |
| `oConn:IsEncrypted()` | `.T.` se la connessione è su un file cifrato |
| `oConn:lEncrypted` | DATA — riflette lo stato dopo `Open()` o `Rekey()` |
| `oConn:Rekey(cNewKey)` | Re-cifra il file con la nuova passphrase. `.T.` se OK |
| `oConn:GetCipherInfo()` | Hash con 5 campi: `cipher_version`, `kdf_iter`, `page_size`, `hmac_algorithm`, `kdf_algorithm` |
