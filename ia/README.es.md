# Sistema IA de HIX

**Estado**: 🟢 v0.1.0 — Primera release pública

Herramientas de IA para ayudarte a construir aplicaciones HIX con Claude Code.

**Empieza en 5 minutos → [QUICKSTART.es.md](QUICKSTART.es.md)** · [EN](QUICKSTART.md)

## ¿Qué es esto?

Un conjunto de assets para Claude Code (skills, agents, slash commands, base de conocimiento) que permiten a Claude generar código HIX correcto e idiomático para tu proyecto.

Una vez instalado, puedes pedirle a Claude cosas como:

- *"Crea un proyecto HIX nuevo llamado MyNotes"*
- *"Añade un módulo CRUD para `Note`"*
- *"Añade una ruta `GET /ping` y un middleware que requiera API key"*
- *"Revisa este proyecto contra las buenas prácticas de HIX"*

Claude genera los archivos, las rutas/middleware/controllers/views y ejecuta tests contra un servidor real para verificar que los endpoints funcionan — reportando OK solo cuando todos los tests pasan.

## Qué hay en v0.1.0

- **5 skills** — `hix-scaffold`, `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-compile-and-test`
- **6 slash commands** — `/hix-scaffold`, `/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`, `/hix-review`
- **4 agentes** — `hix-architect` (diseño), `hix-router-expert` (rutas), `hix-view-builder` (vistas), `hix-reviewer` (auditoría)
- **4 plantillas** — `project-web-crud`, `module-crud`, `module-route`, `module-middleware`
- **Runner de tests declarativo** — ficheros `*.test.json` verificados por `tests/run.ps1`
- **Base de conocimiento** — 12 EN + 12 ES documentos sobre routing, middleware, controllers, views, models, validación, sessions/auth, hixstyle, helpers `U*`, reglas de Harbour

## Requisitos

- CLI de [Claude Code](https://claude.com/claude-code) instalado
- Windows 10/11 con:
  - **Modo Desarrollador activado** (recomendado, permite symlinks sin permisos de admin), o
  - Posibilidad de ejecutar PowerShell como Administrador (solo durante la instalación)
- Harbour + HIX instalados en `C:\HIX.PROJECT\hix\` (este repo)

## Instalación

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\install.bat C:\MiProyecto

(Para detalles y ejecución directa en PowerShell consulta [INSTALL.es.md](INSTALL.es.md).)

Esto hace:

1. Crea o actualiza `C:\MiProyecto\CLAUDE.md` añadiendo un `@import` al CLAUDE.md del sistema IA de HIX.
2. Crea symlinks `~\.claude\skills\hix-*` → `C:\HIX.PROJECT\hix\ia\claude\skills\hix-*` (todas las skills de HIX quedan disponibles en cualquier proyecto).
3. Igual para `agents/` y `commands/`.

Luego:

    cd C:\MiProyecto
    claude
    > /hix-scaffold MiApp
    > /hix-add-crud Note
    > /hix-test

Para el paseo completo de 5 minutos consulta [QUICKSTART.es.md](QUICKSTART.es.md).

## Arquitectura (referencia, no copia)

Los assets viven en este repo (`hix/ia/claude/`) y se **referencian** desde tu directorio de usuario de Claude Code (`~/.claude/`) mediante symlinks. Cuando haces `git pull` en este repo, tu Claude recibe la actualización al instante — sin reinstalar nada.

## Desinstalar

    cd C:\HIX.PROJECT\hix\ia
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

## Verificado end-to-end (v0.1.0)

- `/hix-scaffold` + `/hix-add-crud` → **7/7 tests pass**
- `/hix-scaffold` + `/hix-add-route` → **2/2 tests pass**
- `/hix-scaffold` + `/hix-add-middleware` → **2/2 tests pass**

## Licencia

Misma licencia que HIX — consulta `../license.md`
