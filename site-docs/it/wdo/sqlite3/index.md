# WDO SQLite3 — Concetto e Singleton

Il driver `WDO_Sqlite3` avvolge `sqlcipher.dll` tramite `hb_DynCall`. A differenza dei driver MySQL o PostgreSQL, **non c'è un pool** — il driver gestisce un'unica connessione condivisa tra tutti i worker del server HIX.

## Perché singleton e non pool

SQLite è una libreria incorporata nel processo, non un server TCP esterno. Non c'è handshake di rete, non ci sono socket effimeri che possono esaurirsi. Il file `.db` vive su disco e il driver lo apre **una sola volta** all'avvio.

Più connessioni simultanee allo stesso file SQLite sono possibili in modalità WAL, ma WDO usa una connessione condivisa con un mutex interno per serializzare le operazioni. Questo elimina la complessità del pool e rende il comportamento prevedibile:

```
Avvio:
  └─ HIX_InitPoolsFromConfig()
       └─ WDO_InitSqlite3Ex("APP", hParams)
            └─ sqlite3_open() — una sola volta

Per ogni richiesta:
  └─ WDO_Get("APP")   →  stessa istanza sempre (nessun checkout di slot)
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  no-op come singleton (ritorna allo stack di Harbour)

Shutdown:
  └─ HIX_EndPoolsFromConfig()
       └─ WDO_EndSqlite3("APP")
            └─ sqlite3_close() — una sola volta
```

!!! info "oConn:Close() è buona prassi anche se non fa nulla"
    Chiamare `Close()` mantiene la portabilità del codice tra driver. Se in futuro migri a MySQL o PG, lo stesso pattern `Get/Close` funziona senza modifiche. Il dispatcher HIX chiama anche `WDO_ReleaseAllThread()` alla fine di ogni richiesta; in SQLite3 non ha effetti dannosi.

## Modalità WAL — il default

Il driver attiva `PRAGMA journal_mode=WAL` all'avvio (configurabile). In modalità WAL:

- Più lettori possono leggere contemporaneamente mentre uno scrittore scrive.
- Le modifiche non confermate si accumulano nel sidecar `-wal` e vengono integrate nel `.db` al checkpoint.
- Le prestazioni di scrittura sono notevolmente migliori rispetto alla modalità DELETE (il default storico di SQLite).

!!! warning "Sidecar su disco"
    WAL crea due file aggiuntivi accanto al `.db`: `-wal` e `-shm`. Per il backup, copia tutti e tre. Per la cancellazione nei test, elimina anche i sidecar con `FErase(cDb + "-wal")` e `FErase(cDb + "-shm")`.

## Confronto di prestazioni

| Pattern | Costo per richiesta | Scala sotto carico |
|---------|--------------------|--------------------|
| `WDO_MySql():New()` per richiesta | ~0.77 ms (87% setup TCP) | Collassa con errore 10048 |
| `WDO_Get("mysql")` (pool 5 slot) | ~0.06 ms | Stabile indefinitamente |
| `WDO_Get("APP")` (SQLite3 singleton) | < 0.01 ms (senza TCP) | Serializza con mutex; scrittori in coda |

Il singleton SQLite3 è estremamente veloce per le letture concorrenti. Il collo di bottiglia è la serializzazione delle scritture: solo uno scrittore può eseguire alla volta.

## Quando usare SQLite3

- **App piccole e medie** con traffico moderato (< 50 req/s con scritture frequenti).
- **Sviluppo locale** senza server di database esterno.
- **Dati incorporati** — configurazione, sessioni, cache locale, code interne.
- **App portabili** — un solo file `.db` contiene tutto, anche cifrato con SQLCipher.
- **Test di integrazione** — database in memoria con `"file": ":memory:"`.

## Quando usare PostgreSQL o MySQL

- **Alta concorrenza di scrittura** — più di 100 richieste al secondo con scritture simultanee.
- **Dati condivisi** tra più istanze del server (SQLite3 non è un server di rete).
- **Replica o sharding** — SQLite non ha questi concetti.
- **Funzionalità avanzate** — JSONB con indici GIN (PG), procedure memorizzate complesse, GIS, ecc.
- **Dimensione dati > 1 GB** con scritture frequenti — il mutex di scrittura diventa un collo di bottiglia.

## Ciclo di vita completo

```
Avvio
  └─ HIX_InitPoolsFromConfig()
       └─ sqlite3_open() + PRAGMA di configurazione

  Per ogni richiesta:
  └─ WDO_Get("APP")   →  stessa istanza (il mutex interno gestisce la concorrenza)
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  no-op in singleton; il mutex è già rilasciato in Free()/Execute()

Shutdown
  └─ HIX_EndPoolsFromConfig()
       └─ WDO_EndSqlite3("APP")  →  sqlite3_close() + HB_LibFree()
```

!!! info "Passo successivo"
    Ora che hai capito il modello, [configura il singleton in `config.json`](config.md).
