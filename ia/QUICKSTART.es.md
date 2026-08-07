# HIX AI System — Quickstart

**5 minutos desde cero hasta una app HIX corriendo con tests verificados por Claude.**

## Prerrequisitos

- Windows 10/11. Modo Desarrollador recomendado (permite symlinks sin admin).
- CLI de [Claude Code](https://claude.com/claude-code) instalado y con sesión iniciada.
- Harbour + HIX instalados en `C:\HIX.PROJECT\hix\` (el padre de este repo).

## 1. Instalar (30 s)

```
cd C:\HIX.PROJECT\hix\ia
.\scripts\install.bat C:\tmp\MyFirstApp
```

Esto:
- Crea `C:\tmp\MyFirstApp\` y su `CLAUDE.md` (con un `@import` al CLAUDE.md del sistema IA).
- Enlaza (symlink) todos los `hix-*` skills, agentes y comandos dentro de `~\.claude\`.

Vuelve a ejecutarlo cuando quieras recoger nuevos elementos — es seguro e idempotente.

## 2. Generar un proyecto (30 s)

```
cd C:\tmp\MyFirstApp
claude
> /hix-scaffold MyFirstApp
```

Claude aplica la plantilla `project-web-crud`, verifica que `go.bat build` termine con exit 0 y reporta la estructura de ficheros. Si el build falla, el skill aborta — no se queda un proyecto a medio generar.

## 3. Añadir un recurso CRUD (1 min)

```
> /hix-add-crud Note
```

Claude superpone la plantilla `module-crud` (7 rutas: list / show / create-form / create-post / edit-form / update / delete), renderiza los 7 `*.test.json` que trae bajo `tests/` sustituyendo el token por `Note`, elimina cualquier DBF anterior, y ejecuta `tests/run.ps1`. Esperado: **7/7 pass, exit 0**. Si algún test falla, Claude se detiene y reporta el assertion fallido tal cual.

## 4. Añadir un endpoint propio (1 min)

```
> /hix-add-route Ping /ping GET
```

Añade un controller + entrada en el routes JSON, renderiza 2 tests (cuerpo JSON 200 + 405 en método incorrecto) y los ejecuta. Esperado: **2/2 pass**.

## 5. Añadir un middleware (1 min)

```
> /hix-add-middleware RequireApiKey
```

Genera `HixMwRequireApiKey` (deniega salvo que exista la cabecera `X-Api-Key`), un loader stub que lo publica, un controller + ruta de probe, y 2 tests (401 sin cabecera / 200 con cabecera). Esperado: **2/2 pass**.

El skeleton entregado es una plantilla — sustituye el cuerpo de `HixMwRequireApiKey()` con tu lógica real de autenticación. Registro y cableado ya están hechos.

## 6. Verificar todo (30 s)

```
> /hix-test
```

Rebuild completo + reejecución de cada `*.test.json` bajo `tests/`. Deberían seguir todos verdes.

## 7. Pedir una revisión de código (30 s)

```
> /hix-review
```

Invoca al agente `hix-reviewer` (solo lectura): audita el proyecto contra las reglas públicas de HIX y Harbour (colocación de `LOCAL`, `!=` en strings, formato del action string, `Start()`+join, args posicionales en `USendView`, registro de middlewares, whitelist ACL, etc.). Findings por severidad con citas `file:línea`. Si el proyecto está limpio, veredicto de una línea.

---

## Qué tienes ahora

- Un proyecto hixstyle bajo `C:\tmp\MyFirstApp\` con:
  - 7 rutas CRUD para `Note` en `/notes/*`.
  - Un endpoint `GET /ping`.
  - Un skeleton de middleware listo para proteger cualquier ruta.
- 11 tests, todos pasando, verificados por el runner.
- Un `CLAUDE.md` enlazado al del sistema IA de HIX para que cualquier futura sesión de Claude entienda el framework.

## Siguientes pasos

- Profundizar en el framework: `knowledge/es/00_overview.md` (empezar), después `knowledge/es/*.md` (12 documentos temáticos) o `knowledge/en/*.md`.
- Capacidades de los agentes: `claude/agents/README.md` — cuándo tirar de `hix-architect`, `hix-router-expert`, `hix-view-builder`, `hix-reviewer` en lugar de los comandos.
- Extender plantillas: `templates/README.md` para el catálogo de tokens; añade tu propia overlay bajo `templates/module-<name>/`.
- Añadir tus propios skills / comandos / agentes: `CONTRIBUTING.md`.
- Desinstalar: `.\scripts\uninstall.bat C:\tmp\MyFirstApp` — limpia symlinks y restaura el `CLAUDE.md` de tu proyecto.

## Resolución de problemas

- **`/hix-scaffold` reporta fallo de build**: comprueba primero manualmente que `go.bat` retorne exit 0 (`.\go.bat build`). La causa más común es que `PATH` no incluya `%hix%\dll\msvc` — la plantilla ya lo gestiona, pero una instalación corrupta puede no hacerlo.
- **`/hix-add-crud` falla en el test 3 o 4**: normalmente un DBF antiguo de una ejecución anterior. El skill borra `data/<entity>*.dbf` antes de cada ejecución, pero si lo tienes bloqueado (abierto por otro proceso), no puede. `taskkill //F //IM app.exe` y reintentar.
- **Los slash commands no autocompletan en Claude Code**: reejecuta `.\scripts\install.bat <ruta-proyecto>` — los symlinks bajo `~\.claude\commands\` no se crearon (por ejemplo, el primer install falló silenciosamente).
- **`/hix-review` reporta "unknown agent"**: el symlink de agentes no cuajó. Mismo remedio — reinstalar.
