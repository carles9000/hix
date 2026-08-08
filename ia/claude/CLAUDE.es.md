# Proyecto HIX — Instrucciones para Claude

> Este archivo se autogenera durante la instalación con `{{HIX_ROOT}}` expandido a la ruta real de tu HIX, y luego lo importa el CLAUDE.md de la raíz de tu proyecto.

Estás ayudando al usuario a construir una aplicación web/API/servidor con **HIX**, un framework de servidor web basado en Harbour. HIX v0.2 es **binary-first**: el usuario recibe `hix.exe` + DLLs + una carpeta `www/` que scaffoldea con `/hix-init`. El flujo por defecto no requiere compilación.

## Ubicación del framework

- Código fuente de HIX (internals del framework, solo referencia): `{{HIX_ROOT}}\src\`
- Ejemplos HIX (patrones a seguir): `{{HIX_ROOT}}\examples\`
  - `examples/api/api.class/` — API basada en clases
  - `examples/api/api.function/` — API basada en funciones
  - `examples/web/crud/` — CRUD web (implementación de referencia para la plantilla `project-web-crud`)
  - `examples/server/` — servidor autónomo
- Documentación HIX (legible por humanos, solo referencia): `{{HIX_ROOT}}\site-docs\es\` (español) y `.../en/` (inglés)
- Base de conocimiento HIX (compacta, optimizada para LLM): `{{HIX_ROOT}}\ia\knowledge\` — 12 documentos EN + 12 ES que cubren routing, middleware, controllers, views, models, validación, sessions/auth, hixstyle, helpers `U*` y reglas de Harbour. Consulta aquí antes que `site-docs`.

## Reglas fundamentales

1. **Usa siempre los helpers `U*`** en codeblocks de rutas (`USendJson`, `USendHtml`, `USendError`, `UParam`, `UGet`, `UPost`, `UHeader`, `UCookie`, `USession`, `URedirect`, etc.). No llames nunca a `oReq:Respond()` directamente desde una acción de ruta — el closure del codeblock no captura `oReq` de forma fiable.
2. **Todas las declaraciones `LOCAL` deben ir al principio** de cada FUNCTION/PROCEDURE, antes del código ejecutable. Harbour no compilará en caso contrario.
3. **Cada `.prg` nuevo empieza con una cabecera** en inglés (campos: File, Author, Created, Modified, Version, Description, Usage, Notes).
4. **Prefiere la configuración JSON** (`www/routes/*.json`, `www/middlewares/config.json`, `www/config.json`) frente a Harbour a pelo — hixstyle es el modo por defecto.
5. **Comparación de strings**: usa `==`, nunca `!=`. Motivo: por defecto Harbour tiene `SET EXACT OFF`, así que `!=` no es fiable con prefijos (`"abc" != "ab"` devuelve `.F.`).
6. **Timestamps**: usa `Int( hb_TToSec( hb_DateTime() ) )` — `hb_UnixTime()` no existe en HIX y produce un error de linker.
7. **Las cadenas de acción de ruta** siguen siempre el formato `controllers/<method>@<CLASS>.prg` (con el sufijo `.prg`, método antes de la clase). El dispatcher busca el archivo en disco — cualquier otra forma falla silenciosamente al llegar la petición.
8. **Los middlewares del usuario se registran vía loaders**, no editando `www/middlewares/config.json`. Escribe `www/loaders/init_mw_<name>.prg` con `#include '/middlewares/<name>.prg'`; la sección `setup.*` del JSON es exclusivamente para los `HIX_Mw*` de fábrica (session, csrf, cors, ratelimit, methodfilter, jwt).

## Compilación

Binary-first (por defecto): **sin compilación**. `hix.exe` recompila `www/**/*.prg` en memoria por request (controllers, models, views) o por arranque (`www/loaders/*.prg`, `www/routes/*.json`, `hix.json`). Solo hace falta reiniciar `hix.exe` tras tocar esos ficheros de arranque.

Source-first (legacy, opt-in vía `/hix-scaffold-source`): el usuario mantiene un `app.hbp` + `src/app.prg` + `go.bat` y compila su propio `.exe` con `hbmk2`. El AI System no gestiona builds source-first — el usuario ejecuta `go.bat build` a mano.

## Testing (obligatorio)

Cada ruta o controlador que generes debe venir con un test declarativo **`*.test.json`**. Esquema y runner:

- Esquema: `{{HIX_ROOT}}\ia\tests\SCHEMA.md`
- Runner: `{{HIX_ROOT}}\ia\tests\run-live.ps1` — reutiliza o arranca `hix.exe`, invoca cada endpoint, verifica status + content-type + cuerpo, y hace teardown (solo si arrancó él el servidor). Códigos de salida: `0` todos verdes, `N` fallos, `2` inputs inválidos, `4` timeout de servidor.

Nunca marques una feature como hecha hasta que su test pase. Cuando un skill genera código, además renderiza y ejecuta los tests que trae — el skill solo reporta OK cuando el runner devuelve exit 0.

## Skills / comandos / agentes disponibles

Se cargan automáticamente desde `~/.claude/` tras ejecutar `scripts\install.bat` sobre tu proyecto.

**Skills** — `~/.claude/skills/hix-*/SKILL.md`

| Skill                    | Propósito                                              |
|--------------------------|--------------------------------------------------------|
| `hix-init`               | Scaffoldea `www/` sobre una distribución binaria de HIX (entrada por defecto). |
| `hix-add-crud`           | Añade un módulo CRUD completo (7 rutas + 7 tests).     |
| `hix-add-route`          | Añade una ruta HTTP + 2 tests.                          |
| `hix-add-middleware`     | Genera skeleton `HixMw<Name>` + ruta probe + 2 tests.  |
| `hix-run-tests`          | Ejecuta todos los `*.test.json` contra un `hix.exe` vivo. Sin build. |
| `hix-scaffold-source`    | Legacy: scaffold de proyecto source-first (`app.hbp` + `go.bat`). |

**Slash commands** — `~/.claude/commands/hix-*.md` (envoltorios finos sobre skills / agentes)

| Comando                    | Envuelve                          |
|----------------------------|-----------------------------------|
| `/hix-init`                | `hix-init`                        |
| `/hix-add-crud`            | `hix-add-crud`                    |
| `/hix-add-route`           | `hix-add-route`                   |
| `/hix-add-middleware`      | `hix-add-middleware`              |
| `/hix-test`                | `hix-run-tests`                   |
| `/hix-review`              | agente `hix-reviewer`             |
| `/hix-scaffold-source`     | `hix-scaffold-source` (legacy)    |

**Agentes** — `~/.claude/agents/hix-*.md` (invocados vía el `Task` tool con `subagent_type=<name>`)

| Agente               | Rol                                                        | ¿Escribe archivos? |
|----------------------|------------------------------------------------------------|--------------------|
| `hix-architect`      | Convierte una idea difusa en una lista ordenada de comandos | No                |
| `hix-router-expert`  | Grupos de rutas, `:var` con regex, cadenas de middleware   | Sí                |
| `hix-view-builder`   | Construye `.view.html` y cablea controllers                | Sí                |
| `hix-reviewer`       | Audita un proyecto contra las reglas públicas de HIX/Harbour | No              |

## Flujo típico

Para una app HIX web nueva (binary-first), esta es la secuencia canónica:

```
/hix-init MyApp                       # scaffoldea www/ sobre hix.exe, verifica /health
/hix-add-crud Note                    # primer recurso CRUD, 7/7 tests deben pasar
/hix-add-crud Tag                     # más recursos según haga falta
/hix-add-route Ping /ping GET         # cualquier endpoint no-CRUD
/hix-add-middleware RequireApiKey     # cualquier middleware propio del usuario
/hix-test                             # ejecuta todos los tests contra hix.exe vivo
/hix-review                           # auditoría final opcional contra las reglas
```

Para trabajos más elaborados (una app cuya forma aún no está clara, composición compleja de rutas, trabajo de vistas, code review), invoca el **agente** correspondiente vía el `Task` tool en lugar de disparar comandos a ciegas:

- `hix-architect` antes de `/hix-init` si el diseño está difuso.
- `hix-router-expert` cuando las rutas necesiten grupos, `:var` con regex o cirugía de middleware.
- `hix-view-builder` cuando haya que portar HTML o extraer partials compartidos.
- `hix-reviewer` (vía `/hix-review`) cuando el usuario pida una auditoría.

## Cuando dudes

- Lee primero un ejemplo parecido bajo `{{HIX_ROOT}}\examples\` — los patrones ahí son canónicos.
- Consulta `{{HIX_ROOT}}\ia\knowledge\es\*.md` para esquemas y convenciones antes de recurrir a `site-docs`.
- Si el usuario pregunta algo no cubierto por la base de conocimiento pública, pregunta antes de adivinar.
