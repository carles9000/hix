# Migración del Sistema IA de HIX v0.1 a v0.2

**Aplica a**: usuarios que instalaron `hix/ia` v0.1 (cualquier tag `ia-v0.1.x`) y quieren pasar a `ia-v0.2.0`.

**Tiempo de lectura**: 5 minutos.
**Tiempo de migración**: 2 minutos (Escenario A) o 10 minutos (Escenario B).

---

## TL;DR

| v0.1 | v0.2 | Acción |
|------|------|--------|
| `/hix-scaffold`         | `/hix-scaffold-source` | Renombrar en tus scripts propios y memoria muscular. |
| `/hix-compile-and-test` | `/hix-test`            | Renombrar **y** re-aprender semántica: sin build. |
| Source-first por defecto | Binary-first por defecto | `/hix-init` es el nuevo entry point. El flujo antiguo se preserva vía `/hix-scaffold-source`. |
| `CLAUDE.md` con ruta fija a `C:\HIX.PROJECT\hix\` | Token `{{HIX_ROOT}}`, expandido en tiempo de instalación | Re-ejecutar `install.bat` — ver verificación abajo. |
| Skill `hix-compile-and-test` | Skill `hix-run-tests` | La carpeta del skill se renombró. ¿Symlink obsoleto? Bórralo y re-instala. |

Todo lo anterior está detallado en `CHANGELOG.md` bajo `[0.2.0]`. Este documento te dice **qué hacer**, no qué cambió.

---

## Por qué existe v0.2

v0.1 asumía que eras desarrollador Harbour con `hbmk2` en el PATH — el sistema IA scaffoldeaba un proyecto source y compilaba un `.exe` por ti. Es un umbral alto para alguien que solo quiere una web app.

v0.2 invierte el default: HIX se distribuye como `hix.exe` prebuilt + DLLs. El sistema IA scaffoldea un directorio `www/` encima, y `hix.exe` recompila tus `.prg` en memoria en cada request. Sin build, sin instalación de Harbour, sin `hbmk2`.

El flujo source-first se mantiene para desarrolladores que lo necesiten (enlazar contra `hix_server.lib`, personalizar el binario del servidor) — ver Escenario A abajo.

---

## Elige tu ruta de migración

- **Escenario A** — Ya uso v0.1 source-first y quiero seguir así. Cambios mínimos.
- **Escenario B** — Quiero pasarme al nuevo flujo binary-first (recomendado para apps nuevas).

---

## Escenario A — Seguir en source-first (desarrolladores)

Sigues compilando tu propio `.exe` contra `hix_server.lib`. La actualización a v0.2 para ti es esencialmente cosmética.

### 1. Actualiza comandos y memoria muscular

- Donde tengas scripteado o documentado `/hix-scaffold`, renombra a `/hix-scaffold-source`.
- Donde tengas scripteado o documentado `/hix-compile-and-test`, renombra a `/hix-test`.

Los nombres viejos ya no resuelven — las carpetas de skills se renombraron en disco.

### 2. Re-ejecuta el instalador

    cd C:\ruta\a\hix\ia
    .\scripts\install.bat C:\MiProyecto

Esto regenera `~\.claude\hix-claude-rendered.md` con el token `{{HIX_ROOT}}` expandido, refresca los seis symlinks `~\.claude\skills\hix-*` y actualiza `.claude\settings.local.json` en tu proyecto con los nuevos permisos.

### 3. Verifica

    ls ~/.claude/skills/ | grep hix

Deberías ver:

    hix-add-crud
    hix-add-middleware
    hix-add-route
    hix-init
    hix-run-tests
    hix-scaffold-source

Si queda alguna entrada vieja (`hix-scaffold`, `hix-compile-and-test`, ...), bórrala a mano — `install.bat` no recolecta symlinks obsoletos:

    rm ~/.claude/skills/hix-scaffold
    rm ~/.claude/skills/hix-compile-and-test
    rm ~/.claude/commands/hix-scaffold.md
    rm ~/.claude/commands/hix-compile-and-test.md

### 4. Prueba de cordura en tu proyecto existente

Abre Claude en ese proyecto y ejecuta:

    > /hix-scaffold-source --help

Si Claude reconoce el comando e imprime la ayuda, has terminado.

---

## Escenario B — Pasar a binary-first (recomendado)

Quieres el nuevo flujo por defecto: sin instalar Harbour, sin `hbmk2`, sin build.

### 1. Consigue el bundle binario de HIX

Obtén `hix.exe` + DLLs de tu canal de distribución de HIX (ZIP de release, share interno, etc.). Necesitas:

    hix.exe
    libcrypto-3-x64.dll
    libssl-3-x64.dll
    libcurl.dll
    z.dll

Colócalos en un directorio vacío — la ubicación canónica es `C:\hix\`, pero funciona cualquier ruta absoluta.

Nota: `hix.json` **no es obligatorio de entrada**. Si falta, `/hix-init` arranca `hix.exe` una vez para que auto-genere el config por defecto, y luego para el proceso antes de continuar.

### 2. Coloca el sistema IA junto al binario

Copia el directorio `ia/` de este repo a `C:\hix\ia\` (o donde viva tu root de HIX):

    xcopy C:\ruta\a\hix\ia C:\hix\ia /E /I /Y

### 3. Ejecuta el instalador contra tu root de HIX

    cd C:\hix\ia
    .\scripts\install.bat C:\hix

Esto cablea los seis skills `hix-*`, cuatro agents y siete comandos en tu directorio de usuario de Claude Code. También crea `C:\hix\CLAUDE.md` y `C:\hix\.claude\settings.local.json`.

### 4. Bootstrap de tu primera app

Abre Claude desde tu root de HIX y ejecuta:

    cd C:\hix
    claude
    > /hix-init MiPrimeraApp

Esperado: `/health` responde 200, el navegador muestra la página de bienvenida, cero prompts durante el proceso.

### 5. Valida end-to-end

Ejecuta cada uno de los cinco comandos de seguimiento y confirma los recuentos de tests:

    > /hix-add-crud Note                        # 7/7 tests
    > /hix-add-route Ping /ping GET             # 2/2 tests
    > /hix-add-middleware RequireApiKey         # 2/2 tests
    > /hix-test                                 # 11/11 tests
    > /hix-review                               # limpio o findings citados con file:línea

Si alguno falla, captura la salida y abre un issue — esa combinación es el smoke test canónico para v0.2.

### 6. Retira tu proyecto source de v0.1 (opcional)

Si usabas v0.1 solo para construir apps de ejemplo, tu proyecto source de v0.1 queda superado — el flujo binary-first hace todo lo que hacías antes, menos el paso de compilar. Si tenías código Harbour no trivial en tu proyecto source, consérvalo; sigues pudiendo añadirle rutas binary-first si quieres.

---

## Checklist de verificación

Tras migrar, todo lo siguiente debe ser cierto:

- `~/.claude/hix-claude-rendered.md` existe y **no** contiene el literal `{{HIX_ROOT}}`. Verifícalo: `grep HIX_ROOT ~/.claude/hix-claude-rendered.md` no debe devolver nada.
- `~/.claude/skills/` contiene: `hix-init`, `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-run-tests`, `hix-scaffold-source`.
- `~/.claude/commands/` contiene: `hix-init.md`, `hix-add-crud.md`, `hix-add-route.md`, `hix-add-middleware.md`, `hix-test.md`, `hix-review.md`, `hix-scaffold-source.md`.
- `~/.claude/agents/` contiene: `hix-architect.md`, `hix-reviewer.md`, `hix-router-expert.md`, `hix-view-builder.md`.
- Desde un root de HIX, `/hix-init MyApp` termina con cero prompts y `/health` devuelve 200.

---

## Troubleshooting

**Aparece `{{HIX_ROOT}}` en la salida de Claude.**
El instalador no renderizó la plantilla, o la política de ejecución de PowerShell lo bloqueó. Re-ejecuta `scripts\install.bat` (el wrapper `.bat` bypasea la política). Si invocaste `install.ps1` directamente, usa `-ExecutionPolicy Bypass`.

**"Undefined function" o slash-command desconocido tras la migración.**
Symlinks obsoletos. Borra la entrada afectada en `~/.claude/skills/` o `~/.claude/commands/` y re-ejecuta `install.bat`.

**`/hix-init` aborta con "not a HIX binary distribution".**
No hay `hix.exe` en el root objetivo. Verifica que el directorio contenga `hix.exe` (las DLLs viven al lado).

**`/hix-init` reporta "did not create hix.json within 8 s".**
`hix.exe` falló al arrancar silenciosamente. Ejecútalo manualmente una vez desde el directorio objetivo (`.\hix.exe`) e inspecciona `.\.logs\hix.log`. Causas comunes: puerto 80 bloqueado (requiere admin) o una DLL ausente.

**Los viejos `hix-scaffold` / `hix-compile-and-test` siguen apareciendo en la lista de slash commands de Claude.**
Symlinks en `~/.claude/commands/` sin limpiar. Elimina `hix-scaffold.md` y `hix-compile-and-test.md` a mano y reabre Claude.

**`install.bat` se queja de que no puede crear symlinks.**
Activa el Modo Desarrollador de Windows (Configuración → Actualización y seguridad → Para desarrolladores) o pasa `/copy` para caer al modo copia:

    .\scripts\install.bat C:\hix /copy

El modo copia funciona pero rompe la propiedad de "`git pull` propaga al instante" — tendrás que re-ejecutar `install.bat` tras cada actualización del source.

---

## FAQ

**¿Tengo que migrar?**
No. v0.1 sigue funcionando si nunca re-instalas. Pero los fixes nuevos y skills solo aterrizan en v0.2+.

**¿Pueden coexistir v0.1 y v0.2 en la misma máquina?**
No limpiamente — ambos instalan en `~/.claude/skills/hix-*` y los nombres de carpeta colisionan. Elige uno.

**¿Pueden coexistir source-first y binary-first en la misma máquina?**
Sí. Ese es el objetivo de mantener `/hix-scaffold-source`. Proyectos distintos pueden usar flujos distintos.

**¿Dónde está el changelog?**
`CHANGELOG.md`, sección `[0.2.0]`.

**Moví mi carpeta `C:\hix\` tras instalar. Ahora nada funciona.**
El `CLAUDE.md` renderizado tiene la ruta vieja horneada dentro. Re-ejecuta `install.bat` desde la nueva ubicación.

---

## Documentos relacionados

- [CHANGELOG.md](CHANGELOG.md) — lista completa de cambios en v0.2.0.
- [INSTALL.es.md](INSTALL.es.md) — referencia de instalación.
- [QUICKSTART.es.md](QUICKSTART.es.md) — paseo de 5 minutos por el flujo binary-first.
- [README.es.md](README.es.md) — resumen del proyecto.
