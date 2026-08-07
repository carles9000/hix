# HIX — Overview

**HIX** is a web server framework written in [Harbour](https://harbour.github.io/). Multi-threaded, pool-based, supports HTTP, WebSocket, SSE, LongPoll.

## Key ideas

- **Data-driven configuration** — routes, middleware, application config live in JSON files that HIX auto-loads at startup (`hixstyle` mode, see `09_hixstyle.md`).
- **Convention over code** — a project laid out per convention (`www/routes/`, `www/controllers/`, etc.) needs almost no Harbour glue.
- **Thread-safe workers** — a pool of HTTP workers handles concurrent requests. Each worker is a Harbour thread with its own state.
- **`U*` helpers** for everything a route action needs to do: read the request, respond with JSON/HTML/text, set cookies, redirect, validate input, render views.

## Minimal server (imperative style)

    #include "hix_const.ch"

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

## Minimal server (hixstyle mode)

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

With `hixstyle.enabled=true` in `hix.json`, `Start()` auto-loads routes from `www/routes/*.json`, middleware config from `www/middlewares/config.json`, app config from `www/config.json`.

## Response protocols

- HTTP request/response (JSON, HTML, plain text, files, streams)
- WebSocket (`bOnWsConnect`, `bOnWsMessage`, `bOnWsClose`)
- Server-Sent Events (`USendStreamStart` + `USendChunk` + `USendStreamEnd`)
- Long polling (via streaming chunked)

## Non-goals

- No template engine other than the built-in `.view.html` (`@args` + `{{ expr }}`).
- No ORM; models use raw DBF/CDX via Harbour's RDD layer.
- No dependency manager; you compile with `hbmk2` + a `.hbp` project file.

## Where things live

| Path | Purpose |
|------|---------|
| `src/` | HIX library source |
| `dll/` | Prebuilt DLLs the app links against |
| `examples/` | Reference projects (`api/`, `web/crud`, `server/`) |
| `site-docs/` | Human docs (mkdocs) |
| `ia/` | This system — LLM-oriented tooling |

## Next

- Project layout → `01_project_layout.md`
- Routes → `02_routing.md`
- `U*` reference → `10_u_helpers_ref.md`
