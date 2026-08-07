# HIX — Visión general

**HIX** es un framework de servidor web escrito en [Harbour](https://harbour.github.io/). Multi-thread, basado en pools, soporta HTTP, WebSocket, SSE y LongPoll.

## Ideas clave

- **Configuración data-driven** — rutas, middleware y config de aplicación viven en ficheros JSON que HIX auto-carga al arrancar (modo `hixstyle`, ver `09_hixstyle.md`).
- **Convención sobre código** — un proyecto que sigue la convención (`www/routes/`, `www/controllers/`, etc.) casi no necesita código Harbour de pegamento.
- **Workers thread-safe** — un pool de workers HTTP atiende peticiones concurrentes. Cada worker es un hilo Harbour con estado propio.
- **Helpers `U*`** para todo lo que una acción de ruta necesita: leer el request, responder JSON/HTML/texto, poner cookies, redirigir, validar entrada, renderizar vistas.

## Servidor mínimo (estilo imperativo)

    #include "hix_const.ch"

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

## Servidor mínimo (modo hixstyle)

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

Con `hixstyle.enabled=true` en `hix.json`, `Start()` auto-carga rutas desde `www/routes/*.json`, config de middleware desde `www/middlewares/config.json`, y config de app desde `www/config.json`.

## Protocolos de respuesta

- Petición/respuesta HTTP (JSON, HTML, texto plano, ficheros, streams)
- WebSocket (`bOnWsConnect`, `bOnWsMessage`, `bOnWsClose`)
- Server-Sent Events (`USendStreamStart` + `USendChunk` + `USendStreamEnd`)
- Long polling (via streaming chunked)

## Fuera de alcance

- No hay motor de plantillas más allá de `.view.html` (`@args` + `{{ expr }}`).
- No hay ORM; los modelos usan DBF/CDX puros vía la capa RDD de Harbour.
- No hay gestor de dependencias; se compila con `hbmk2` + un fichero `.hbp`.

## Dónde vive cada cosa

| Ruta | Propósito |
|------|-----------|
| `src/` | Código fuente de la librería HIX |
| `dll/` | DLLs precompiladas que enlaza la app |
| `examples/` | Proyectos de referencia (`api/`, `web/crud`, `server/`) |
| `site-docs/` | Docs para humanos (mkdocs) |
| `ia/` | Este sistema — tooling para LLM |

## Siguiente

- Estructura de proyecto → `01_project_layout.md`
- Rutas → `02_routing.md`
- Referencia `U*` → `10_u_helpers_ref.md`
