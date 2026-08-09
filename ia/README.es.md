# Sistema IA de HIX

**Estado**: 🟢 v0.2.0 — Binary-first

Herramientas de IA para ayudarte a construir aplicaciones HIX con Claude Code.

**Empieza en 5 minutos → [QUICKSTART.es.md](QUICKSTART.es.md)** · [EN](QUICKSTART.md)

**¿Actualizando desde v0.1? → [MIGRATE-v0.2.es.md](MIGRATE-v0.2.es.md)** · [EN](MIGRATE-v0.2.md)

## ¿Qué es esto?

Un conjunto de assets para Claude Code (skills, agents, slash commands, base de conocimiento) que permiten a Claude generar código HIX correcto e idiomático para tu proyecto.

HIX v0.2 es **binary-first**: recibes `hix.exe` + DLLs + una carpeta vacía, y el sistema IA scaffoldea la app `www/` encima. **Sin compilación** en el flujo por defecto — `hix.exe` recompila tus `.prg` en memoria en cada request.

Una vez instalado, puedes pedirle a Claude cosas como:

- *"Inicializa una app HIX llamada MyNotes"*
- *"Añade un módulo CRUD para `Note`"*
- *"Añade una ruta `GET /ping` y un middleware que requiera API key"*
- *"Revisa este proyecto contra las buenas prácticas de HIX"*

Claude genera los archivos, los cablea al `hix.exe` en marcha y ejecuta tests HTTP declarativos contra el servidor vivo — reportando OK solo cuando todos los tests pasan.

## Qué hay en v0.2.0

- **6 skills** — `hix-init` (por defecto), `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-run-tests`, `hix-scaffold-source` (legacy)
- **7 slash commands** — `/hix-init`, `/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`, `/hix-review`, `/hix-scaffold-source`
- **4 agentes** — `hix-architect` (diseño), `hix-router-expert` (rutas), `hix-view-builder` (vistas), `hix-reviewer` (auditoría)
- **4 plantillas** — `project-www` (binary-first), `project-web-crud` (source-first), `module-crud`, `module-route`, `module-middleware`
- **Runner de tests declarativo** — ficheros `*.test.json` verificados por `tests/run-live.ps1` contra un `hix.exe` vivo
- **Base de conocimiento** — 12 EN + 12 ES documentos sobre routing, middleware, controllers, views, models, validación, sessions/auth, hixstyle, helpers `U*`, reglas de Harbour

## Requisitos

- CLI de [Claude Code](https://claude.com/claude-code) instalado
- Windows 10/11 con:
  - **Modo Desarrollador activado** (recomendado, permite symlinks sin permisos de admin), o
  - Posibilidad de ejecutar PowerShell como Administrador (solo durante la instalación)
- Una distribución binaria de HIX (típicamente `C:\hix\` con `hix.exe`, `hix.json` y las DLLs necesarias)

Source-first (legacy) además necesita Harbour + hbmk2 para compilar tu propio `.exe`. No es necesario para el flujo por defecto.

## Instalación

    cd C:\hix\ia          # o donde extrajiste el bundle del sistema IA
    .\scripts\install.bat C:\MiProyecto

(Para detalles y ejecución directa en PowerShell consulta [INSTALL.es.md](INSTALL.es.md).)

Esto hace:

1. Crea symlinks `~\.claude\{skills,agents,commands}\hix-*` → el repo del sistema IA (los `git pull` propagan al instante).
2. Renderiza `~\.claude\hix-claude-rendered.md` con `{{HIX_ROOT}}` sustituido por tu ruta real de instalación.
3. Crea o actualiza `C:\MiProyecto\CLAUDE.md` añadiendo un `@import` al fichero renderizado.
4. Escribe `C:\MiProyecto\.claude\settings.local.json` con los permisos que necesitan las skills (PowerShell / Bash / curl), para que Claude Code no pregunte en cada comando.

Después, desde la carpeta que contiene `hix.exe`:

    cd C:\hix
    claude
    > /hix-init MiApp
    > /hix-add-crud Note
    > /hix-test

Para el paseo completo de 5 minutos consulta [QUICKSTART.es.md](QUICKSTART.es.md).

## Source-first (legacy)

Si compilas tu propio `.exe` enlazado contra `hix_server.lib` (requiere Harbour + hbmk2), usa:

    > /hix-scaffold-source MiApp

Esto genera el esqueleto `app.hbp` + `src/app.prg` + `go.bat`. A partir de ahí, todo lo demás (`/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`) funciona igual — pero el sistema IA no gestionará tu build. Tú ejecutas `go.bat build` antes de `/hix-test`.

## Arquitectura (referencia, no copia)

Los assets viven en este repo (`hix/ia/claude/`) y se **referencian** desde tu directorio de usuario de Claude Code (`~/.claude/`) mediante symlinks. Cuando haces `git pull` en este repo, tu Claude recibe la actualización al instante — sin reinstalar nada (excepto cuando cambia el propio CLAUDE.md renderizado; re-ejecuta `install.bat`).

## Desinstalar

    cd C:\hix\ia
    .\scripts\uninstall.bat C:\MiProyecto

Consulta [UNINSTALL.es.md](UNINSTALL.es.md) para más detalles.

## Documentación

- [QUICKSTART.es.md](QUICKSTART.es.md) — onboarding de 5 minutos (ES) · [EN](QUICKSTART.md)
- [INSTALL.es.md](INSTALL.es.md) — guía detallada de instalación (ES) · [EN](INSTALL.md)
- [UNINSTALL.es.md](UNINSTALL.es.md) — guía de desinstalación (ES) · [EN](UNINSTALL.md)
- [CONTRIBUTING.es.md](CONTRIBUTING.es.md) — cómo añadir skills / agents / commands (ES) · [EN](CONTRIBUTING.md)
- `knowledge/` — base de conocimiento que lee Claude (12 EN + 12 ES documentos temáticos)
- `templates/` — esqueletos de proyecto + módulo que aplica Claude
- `tests/` — runner de tests declarativo + self-tests
- [claude/agents/README.md](claude/agents/README.md) — índice de agentes y principios de diseño
- [claude/commands/README.md](claude/commands/README.md) — índice de slash commands
- [claude/skills/README.md](claude/skills/README.md) — índice de skills
- [CHANGELOG.md](CHANGELOG.md) — historial de versiones
- English · [README.md](README.md)

## Verificado end-to-end (v0.2.0)

Instalación limpia en `C:\hix` con solo `hix.exe` + DLLs:

- `/hix-init MiApp` → `/health` devuelve 200, sin prompts
- `/hix-add-crud Note` → **7/7 tests pass**
- `/hix-add-route Ping /ping GET` → **2/2 tests pass**
- `/hix-add-middleware RequireApiKey` → **2/2 tests pass**
- `/hix-test` suite completa → **11/11 tests pass**

## Licencia

Misma licencia que HIX — consulta `../license.md`
