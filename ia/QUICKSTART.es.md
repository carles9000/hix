# HIX AI System — Quickstart

**5 minutos desde una carpeta vacía con `hix.exe` hasta una app HIX corriendo con tests verificados por Claude.**

## Prerrequisitos

- Windows 10/11. Modo Desarrollador recomendado (permite symlinks sin admin).
- CLI de [Claude Code](https://claude.com/claude-code) instalado y con sesión iniciada.
- Una distribución binaria de HIX (típicamente `C:\hix\` con `hix.exe`, `hix.json` y las DLLs necesarias).

**No** necesitas Harbour, `hbmk2` ni ningún compilador para el flujo por defecto. `hix.exe` recompila tus `.prg` en memoria en cada request.

## 1. Instalar el sistema IA (30 s)

```
cd C:\hix\ia
.\scripts\install.bat C:\hix
```

Esto:
- Enlaza (symlink) todos los `hix-*` skills, agentes y comandos dentro de `~\.claude\`.
- Renderiza `~\.claude\hix-claude-rendered.md` con tu ruta real de HIX sustituida.
- Crea `C:\hix\CLAUDE.md` con un `@import` a ese fichero renderizado.
- Escribe `C:\hix\.claude\settings.local.json` con los permisos que necesitan las skills (PowerShell / Bash / curl) para que Claude Code no pregunte en cada comando.

Vuelve a ejecutarlo cuando quieras — es seguro e idempotente.

## 2. Bootstrap de la app (30 s)

```
cd C:\hix
claude
> /hix-init MyFirstApp
```

Claude aplica la plantilla `project-www` dentro de `C:\hix\www\`, activa `hixstyle` en `hix.json`, arranca `hix.exe` en background y verifica que `GET http://127.0.0.1:<puerto>/health` devuelve 200. Si algún paso falla, el skill aborta con el error exacto.

## 3. Añadir un recurso CRUD (1 min)

```
> /hix-add-crud Note
```

Claude superpone la plantilla `module-crud` (7 rutas: list / show / create-form / create-post / edit-form / update / delete), renderiza los 7 `*.test.json` que trae bajo `tests/` sustituyendo el token por `Note`, elimina cualquier DBF anterior y ejecuta `tests/run-live.ps1`. Esperado: **7/7 pass, exit 0**. Si algún test falla, Claude se detiene y reporta el assertion fallido tal cual.

No hace falta reiniciar `hix.exe` — controllers/models/views recompilan en memoria por request.

## 4. Añadir un endpoint propio (1 min)

```
> /hix-add-route Ping /ping GET
```

Añade un controller bajo `www/controllers/` y una entrada bajo `www/routes/`, renderiza 2 tests (cuerpo JSON 200 + 405 en método incorrecto) y los ejecuta. Esperado: **2/2 pass**.

`www/routes/*.json` se carga una vez al arrancar — Claude pasa `--restart` al runner para que `hix.exe` recoja la nueva ruta.

## 5. Añadir un middleware (1 min)

```
> /hix-add-middleware RequireApiKey
```

Genera `HixMwRequireApiKey` (deniega salvo que exista la cabecera `X-Api-Key`), un loader stub bajo `www/loaders/` que lo publica, un controller + ruta de probe, y 2 tests (401 sin cabecera / 200 con cabecera). Esperado: **2/2 pass**.

El skeleton entregado es una plantilla — sustituye el cuerpo de `HixMwRequireApiKey()` con tu lógica real de autenticación. Registro y cableado ya están hechos.

## 6. Verificar todo (30 s)

```
> /hix-test
```

Re-ejecuta cada `*.test.json` bajo `tests/` contra el `hix.exe` vivo. Sin build. Deberían seguir todos verdes (**11/11**). Si tocaste `hix.json`, `www/routes/*.json` o `www/loaders/*.prg` desde la última ejecución, añade `--restart`.

## 7. Pedir una revisión de código (30 s)

```
> /hix-review
```

Invoca al agente `hix-reviewer` (solo lectura): audita todo lo que hay bajo `www/` contra las reglas públicas de HIX y Harbour (colocación de `LOCAL`, `!=` en strings, formato del action string, args posicionales en `USendView`, registro de middlewares, whitelist ACL, etc.). Findings por severidad con citas `file:línea`. Si el proyecto está limpio, veredicto de una línea.

---

## Qué tienes ahora

- Una app hixstyle bajo `C:\hix\www\` con:
  - 7 rutas CRUD para `Note` en `/notes/*`.
  - Un endpoint `GET /ping`.
  - Un skeleton de middleware listo para proteger cualquier ruta.
- 11 tests, todos pasando, verificados contra el `hix.exe` vivo.
- Un `CLAUDE.md` en la raíz del proyecto que cualquier futura sesión de Claude carga automáticamente — con las reglas del framework HIX incluidas.

## Siguientes pasos

- Profundizar en el framework: `knowledge/es/00_overview.md` (empezar), después `knowledge/es/*.md` (12 documentos temáticos) o `knowledge/en/*.md`.
- Capacidades de los agentes: `claude/agents/README.md` — cuándo tirar de `hix-architect`, `hix-router-expert`, `hix-view-builder`, `hix-reviewer` en lugar de los comandos.
- Extender plantillas: `templates/README.md` para el catálogo de tokens; añade tu propia overlay bajo `templates/module-<name>/`.
- Añadir tus propios skills / comandos / agentes: `CONTRIBUTING.md`.
- Desinstalar: `.\scripts\uninstall.bat C:\hix` — limpia symlinks y restaura el `CLAUDE.md` de tu proyecto.

## Ruta source-first (legacy)

Si compilas tu propio `.exe` enlazado contra `hix_server.lib` (requiere Harbour + hbmk2), salta el paso 2 y usa `/hix-scaffold-source MiApp` en su lugar. Desde el paso 3 el flujo es idéntico, salvo que tú ejecutas `go.bat build` a mano antes de `/hix-test` — el sistema IA no gestiona builds source-first.

## Resolución de problemas

- **`/hix-init` reporta `hix.exe did not open port`**: revisa `C:\hix\.logs\hix.log`. La causa más común es otro proceso en el puerto configurado (el 80 requiere admin en Windows) o `hix.json` con `hixstyle.enabled` en `false`. El skill hace toggle, pero un JSON corrupto puede impedirlo.
- **`/hix-add-crud` falla en el test 3 o 4**: normalmente un DBF antiguo de una ejecución anterior. El skill borra `data/<entity>*.dbf` antes de cada ejecución, pero si lo tienes bloqueado (abierto por otro proceso), no puede. `taskkill //F //IM hix.exe` y reintentar.
- **Los slash commands no autocompletan en Claude Code**: reejecuta `.\scripts\install.bat <ruta-proyecto>` — los symlinks bajo `~\.claude\commands\` no se crearon (por ejemplo, el primer install falló silenciosamente).
- **`/hix-review` reporta "unknown agent"**: el symlink de agentes no cuajó. Mismo remedio — reinstalar.
- **PowerShell sigue preguntando en cada comando**: `install.bat` no escribió `.claude/settings.local.json` (¿error de permisos?). Reinstala; el fichero debe listar `Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)` en `permissions.allow`.
