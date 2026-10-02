# WDO MySQL — Concetto e Pool

Il driver `WDO_MySql` avvolge la libreria client di MySQL/MariaDB (`libmysqlclient` / `libmariadb`) tramite `hb_DynCall`. Su di esso, `WDO_Pool` implementa il pool di connessioni thread-safe usato dagli handler HTTP.

## Il problema che il pool risolve

Immagina 100 richieste concorrenti, ciascuna che apre e chiude la propria connessione MySQL:

```
Request 1  →  New() → TCP connect + auth (~0.7 ms) → Query → End() → socket in TIME_WAIT
Request 2  →  New() → TCP connect + auth (~0.7 ms) → Query → End() → socket in TIME_WAIT
...×100
```

Dopo qualche migliaio di richieste rapide su Windows, il sistema esaurisce le porte efimere e appare l'errore **10048** (`WSAEADDRINUSE`). La seconda esecuzione del benchmark senza pool collassa esattamente con questo errore.

Con il pool, i socket vengono aperti **una sola volta** all'avvio e riutilizzati indefinitamente:

```
Avvio:     WDO_Init → apre 5 connessioni TCP (una volta, costo ammortizzato)

Request 1  →  WDO_Get() → slot #1 prestato (~0.005 ms) → Query → Close() → slot #1 restituito
Request 2  →  WDO_Get() → slot #2 prestato (~0.005 ms) → Query → Close() → slot #2 restituito
...×100  →  si alternano sui 5 slot, senza aprire/chiudere socket
```

## Prestazioni a confronto

| Pattern | Costo per request | Scalabilità sotto carico |
|---------|-------------------|--------------------------|
| `WDO_MySql():New()` per request | ~0.77 ms (87% è setup) | Collassa con 10048 |
| `WDO_Get()` / `Close()` (pool) | ~0.06 ms (83% è la query) | Stabile indefinitamente |

**Il pool è ~13× più veloce** nell'overhead, ed è l'unico che scala in produzione.

## Come funziona il pool

### All'avvio dell'app

`WDO_InitPoolMySql` (o l'avvio dichiarativo da `config.json`) crea `N` istanze di `WDO_MySql`, le connette e le salva nell'array interno del pool contrassegnate come libere.

### Per ogni request

1. `WDO_Get("mysql")` — acquisisce il mutex del pool, cerca il primo slot libero, lo contrassegna come occupato e lo consegna al thread. Se tutti i slot sono occupati, blocca finché uno non si libera (o scade il `timeout_ms`).
2. L'handler usa la connessione (Query, Prepare, Exec…).
3. `oConn:Close()` — restituisce lo slot al pool (senza chiudere il socket TCP). Se la connessione aveva una transazione aperta, esegue il Rollback automatico.

### Rete di sicurezza

Se un handler ha un bug e dimentica di chiamare `Close()`, il dispatcher di HIX chiama `WDO_ReleaseAllThread()` al termine della richiesta. Questo restituisce qualsiasi slot che il thread ha in prestito. **Non sono possibili leak**, anche se il codice è trascurato.

## Regola di base

!!! warning "All'interno di un handler HTTP"
    Usa sempre `WDO_Get("mysql")` + `oConn:Close()`. **Mai** `WDO_MySql():New()` all'interno di un controller.

`WDO_MySql():New()` è legittimo solo in script CLI, test unitari o un sanity-ping di avvio. Lo stesso driver avvisa nel log se rileva un `New()` all'interno di una richiesta HTTP.

## Quando usare `New()` direttamente

- Script da riga di comando (migrazioni, backup, report).
- Test unitari del driver.
- Connessioni con credenziali diverse da quelle del pool (altro database, altro server).

## Ciclo di vita completo

```
Avvio
  └─ HIX_InitPoolsFromConfig()  (o WDO_InitPoolMySql)
       └─ apre N connessioni TCP

  Per ogni request:
  └─ WDO_Get("mysql")   →  slot prestato
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()      →  slot restituito al pool

Shutdown
  └─ HIX_EndPoolsFromConfig()  (o WDO_EndPoolMySql)
       └─ chiude gli N socket (una volta)
```

!!! info "Passo successivo"
    Ora che comprendi il modello, [configura il pool in `config.json`](config.md).
