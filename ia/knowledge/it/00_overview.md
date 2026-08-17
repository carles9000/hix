# HIX — Panoramica

**HIX** è un framework per web server scritto in [Harbour](https://harbour.github.io/). Multi-thread, basato su pool, supporta HTTP, WebSocket, SSE, LongPoll.

## Idee chiave

- **Configurazione data-driven** — route, middleware, config applicativa vivono in file JSON che HIX auto-carica all'avvio (modalità `hixstyle`, vedi `09_hixstyle.md`).
- **Convention over code** — un progetto strutturato per convenzione (`www/routes/`, `www/controllers/`, ecc.) richiede pochissimo codice glue Harbour.
- **Worker thread-safe** — un pool di worker HTTP gestisce le richieste concorrenti. Ogni worker è un thread Harbour con il suo stato.
- **Helper `U*`** per tutto ciò che un'action di route deve fare: leggere la request, rispondere con JSON/HTML/testo, impostare cookie, redirect, validare input, renderizzare view.

## Server minimo (stile imperativo)

    #include "hix_const.ch"

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

## Server minimo (modalità hixstyle)

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

Con `hixstyle.enabled=true` in `hix.json`, `Start()` auto-carica le route da `www/routes/*.json`, la config middleware da `www/middlewares/config.json`, la config app da `www/config.json`.

## Protocolli di risposta

- HTTP request/response (JSON, HTML, plain text, file, stream)
- WebSocket (`bOnWsConnect`, `bOnWsMessage`, `bOnWsClose`)
- Server-Sent Events (`USendStreamStart` + `USendChunk` + `USendStreamEnd`)
- Long polling (via streaming chunked)

## Non-goals

- Nessun template engine oltre il `.view.html` integrato (`@args` + `{{ expr }}`).
- Nessun ORM; i model usano DBF/CDX grezzi tramite il layer RDD di Harbour.
- Nessun gestore di dipendenze; si compila con `hbmk2` + un file di progetto `.hbp`.

## Dove vivono le cose

| Path | Scopo |
|------|---------|
| `src/` | Sorgenti della libreria HIX |
| `dll/` | DLL precompilate a cui l'app si collega |
| `examples/` | Progetti di riferimento (`api/`, `web/crud`, `server/`) |
| `site-docs/` | Documentazione umana (mkdocs) |
| `ia/` | Questo sistema — strumenti LLM-oriented |

## Prossimo

- Layout del progetto → `01_project_layout.md`
- Route → `02_routing.md`
- Riferimento `U*` → `10_u_helpers_ref.md`
