# WDO PostgreSQL — Concetto e Pool

Il driver `WDO_PG` avvolge la libreria client ufficiale di PostgreSQL (`libpq`) tramite `hb_DynCall`. Su di esso, `WDO_Pool` implementa il pool di connessioni thread-safe usato dagli handler HTTP.

## Il problema che il pool risolve

Immagina 100 richieste concorrenti, ciascuna che apre e chiude la propria connessione PostgreSQL:

```
Request 1  →  New() → TCP connect + auth (~1.2 ms) → Query → End() → socket in TIME_WAIT
Request 2  →  New() → TCP connect + auth (~1.2 ms) → Query → End() → socket in TIME_WAIT
...×100
```

Dopo qualche migliaio di richieste rapide su Windows, il sistema esaurisce le porte effimere e compare l'errore **10048** (`WSAEADDRINUSE`). Una seconda esecuzione del bench senza pool collassa esattamente con questo errore.

Con il pool, i socket vengono aperti **una sola volta** all'avvio e riusati indefinitamente:

```
Avvio:  WDO_Init → apre 5 connessioni TCP (una volta, costo ammortizzato)

Request 1  →  WDO_Get("PG") → slot #1 prestato (~0.005 ms) → Query → Close() → slot #1 restituito
Request 2  →  WDO_Get("PG") → slot #2 prestato (~0.005 ms) → Query → Close() → slot #2 restituito
...×100  →  si alternano sui 5 slot, senza aprire/chiudere socket
```

## Confronto di prestazioni

| Pattern | Costo per richiesta | Scala sotto carico |
|---------|--------------------|--------------------|
| `WDO_PG():New()` per richiesta | ~1.2 ms (90% è setup) | Collassa con 10048 |
| `WDO_Get("PG")` / `Close()` (pool) | ~0.06 ms (84% è la query) | Stabile indefinitamente |

**Il pool è ~20× più veloce** nell'overhead ed è l'unico approccio che scala in produzione.

## Come funziona il pool

### All'avvio dell'app

`WDO_InitPoolPg` (o l'avvio dichiarativo da `config.json`) crea `N` istanze di `WDO_PG`, le connette e le salva nell'array interno del pool marcate come libere.

### Per ogni richiesta

1. `WDO_Get("PG")` — acquisisce il mutex del pool, cerca il primo slot libero, lo marca come occupato e lo consegna al thread. Se tutti gli slot sono occupati, si blocca fino a che uno non viene liberato (o scade `timeout_ms`).
2. L'handler usa la connessione (Query, Prepare, Exec…).
3. `oConn:Close()` — restituisce lo slot al pool (senza chiudere il socket TCP). Se la connessione aveva una transazione aperta, esegue un Rollback automatico.

### Rete di sicurezza

Se un handler ha un bug e dimentica di chiamare `Close()`, il dispatcher di HIX chiama `WDO_ReleaseAllThread()` alla fine della richiesta. Questo restituisce qualsiasi slot che il thread ha in prestito. **Non ci sono leak possibili**, anche se il codice è trascurato.

### TCP preflight probe

Prima di chiamare `libpq`, il driver esegue un probe TCP di basso livello per verificare che il server risponda. Questo evita che `PQconnectdb` si blocchi fino a 2 minuti se l'host è spento o il firewall non restituisce RST. Se il probe fallisce, l'avvio del pool fallisce in millisecondi con un messaggio chiaro nel log.

## Chiave di pool predefinita

!!! info "Chiave predefinita: «PG» maiuscolo"
    `WDO_InitPoolPg` (posizionale) registra il pool sotto la chiave fissa `"PG"` (maiuscolo). Con `WDO_InitPoolPgEx` puoi scegliere un'altra chiave, ma `"PG"` è la convenzione del framework.

    Negli handler usa sempre `WDO_Get("PG")`, non `WDO_Get("pg")` (la chiave è case-sensitive).

## Regola base

!!! warning "All'interno di un handler HTTP"
    Usa sempre `WDO_Get("PG")` + `oConn:Close()`. **Mai** `WDO_PG():New()` dentro un controller.

`WDO_PG():New()` è legittimo solo in script CLI, test unitari o un sanity-ping di avvio. Il driver stesso avvisa nel log se rileva un `New()` dentro una richiesta HTTP.

## Quando usare `New()` direttamente

- Script da riga di comando (migrazioni, backup, report).
- Test unitari del driver.
- Connessioni con credenziali diverse da quelle del pool (altro DB, altro server).

## Ciclo di vita completo

```
Avvio
  └─ HIX_InitPoolsFromConfig()  (o WDO_InitPoolPg)
       └─ apre N connessioni TCP + auth PostgreSQL

  Per ogni richiesta:
  └─ WDO_Get("PG")    →  slot prestato
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  slot restituito al pool

Shutdown
  └─ HIX_EndPoolsFromConfig()  (o WDO_EndPoolPg)
       └─ chiude N socket (una volta)
```

!!! info "Passo successivo"
    Ora che hai capito il modello, [configura il pool in `config.json`](config.md).
