# Guía de Instalación

> English · [INSTALL.md](INSTALL.md)

## Requisitos previos

| Requisito | Notas |
|-----------|-------|
| CLI de Claude Code | https://claude.com/claude-code — debe estar en el PATH |
| Distribución HIX | Una carpeta con `hix.exe`, `hix.json` y las DLLs de runtime. Ubicación típica: `C:\hix\`. El bundle del sistema IA vive al lado en `<hix>\ia\`. |
| Windows 10/11 | Modo Desarrollador ACTIVADO muy recomendado |

Harbour + `hbmk2` **no** son necesarios para el flujo binary-first por defecto. Solo hacen falta si usas `/hix-scaffold-source` (legacy) para compilar tu propio `.exe`.

### Activar Modo Desarrollador (una sola vez por máquina)

Configuración → *Para desarrolladores* → **Modo de desarrollador: activado**

O por PowerShell (admin):

    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 1 /f

Sin Modo Desarrollador el instalador hace fallback a copia — todo funciona igual, pero un `git pull` en el repo HIX **no** propagará los cambios a tu `~/.claude/`. Tendrías que volver a ejecutar la instalación.

## Instalar en un proyecto

Lo más sencillo (recomendado):

    cd C:\hix\ia
    .\scripts\install.bat C:\Ruta\A\MiProyecto

Caso más común — instalar el sistema IA en la misma carpeta que contiene `hix.exe`, para poder lanzar `/hix-init` desde allí:

    cd C:\hix\ia
    .\scripts\install.bat C:\hix

Forzar copia de ficheros (sin symlinks):

    .\scripts\install.bat C:\Ruta\A\MiProyecto /copy

O invocar PowerShell directamente:

    powershell -NoProfile -ExecutionPolicy Bypass ^
        -File C:\hix\ia\scripts\install.ps1 ^
        -Target C:\Ruta\A\MiProyecto

## Qué hace el instalador

1. **Crea entradas `hix-*` en `~\.claude\{skills,agents,commands}\`**
   - Symlinks por defecto (fuente única, se actualiza con `git pull`).
   - Ficheros/directorios normales si se usa `-ForceCopy` o no hay capacidad de symlink.
   - Solo se tocan entradas que empiecen por `hix-` o `hix.`. Nunca se modifican tus propias skills/agents/commands.
2. **Renderiza `~\.claude\hix-claude-rendered.md`**
   - Lee `<hix>\ia\claude\CLAUDE.md` (que usa el placeholder `{{HIX_ROOT}}`).
   - Sustituye `{{HIX_ROOT}}` por el padre real de `<hix>\ia\` (típicamente `C:\hix`).
   - Escribe el fichero renderizado para que Claude Code lo pueda importar literalmente.
3. **Crea o actualiza** `C:\Ruta\A\MiProyecto\CLAUDE.md`
   - Si no existía: lo crea con un título + el bloque de import de HIX.
   - Si existía: añade un bloque de import al final. El contenido previo se preserva.
   - El import apunta a `~\.claude\hix-claude-rendered.md` con la sintaxis `@`.
4. **Escribe `C:\Ruta\A\MiProyecto\.claude\settings.local.json`**
   - Añade permisos (`Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)`, etc.) para que las skills HIX puedan ejecutar sus scripts PowerShell sin preguntar en cada comando.
   - Idempotente: las entradas existentes se preservan, solo se añaden las que faltan.
5. **Muestra un resumen** de todas las acciones.

## Después de instalar

    cd C:\hix          # o tu carpeta destino
    claude

Dentro de Claude Code:

    > /hix-init MiApp

Si el skill responde, el cableado es correcto.

## Verificar la instalación manualmente

    Get-ChildItem "$env:USERPROFILE\.claude\skills\" | Where-Object Name -like 'hix-*'
    Get-Content "$env:USERPROFILE\.claude\hix-claude-rendered.md" -TotalCount 5
    Get-Content C:\Ruta\A\MiProyecto\CLAUDE.md
    Get-Content C:\Ruta\A\MiProyecto\.claude\settings.local.json

Esperado:
- Entradas bajo `skills\`, `agents\`, `commands\` que empiezan por `hix-*` (SymbolicLink o Directory).
- El fichero renderizado `hix-claude-rendered.md` tiene tu ruta real de HIX expandida (ningún `{{HIX_ROOT}}` residual).
- El `CLAUDE.md` del proyecto termina con:

      # HIX AI System -- auto-imported
      @C:\Users\<tú>\.claude\hix-claude-rendered.md

- `settings.local.json` lista al menos `Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)` en `permissions.allow`.

## Problemas frecuentes

### "la ejecución de scripts está deshabilitada en este sistema"

Has saltado el wrapper `.bat`. O usa `install.bat` (recomendado) o añade `-ExecutionPolicy Bypass` a la invocación de PowerShell.

### "No se puede crear el vínculo simbólico. El cliente no tiene los privilegios requeridos."

Modo Desarrollador desactivado y PowerShell no es admin. Dos opciones:

- **Preferida**: activa el Modo Desarrollador (ver Requisitos previos) y vuelve a ejecutar.
- **Fallback**: ejecuta con `/copy` — perderás la actualización automática con `git pull`.

### Claude Code no ve el comando `/hix-init`

- Confirma que existen `~\.claude\commands\hix-init.md` y `~\.claude\skills\hix-init\SKILL.md`.
- Reinicia Claude Code — algunos hosts cachean el índice de skills al arrancar.

### No se aplica el import del CLAUDE.md

Claude Code lee `CLAUDE.md` solo desde la raíz del proyecto. Confirma que has lanzado `claude` desde el mismo directorio que contiene `CLAUDE.md` (no desde un subdirectorio).

### PowerShell sigue preguntando en cada comando

`install.bat` no escribió `.claude/settings.local.json` (¿error de permisos, o la ruta Target se resolvió mal?). Vuelve a ejecutar la instalación; verifica que el fichero existe y contiene la lista `permissions.allow` esperada.

### `{{HIX_ROOT}}` visible en el contexto de Claude

El fichero renderizado no se creó, o el `CLAUDE.md` del proyecto sigue importando el `<hix>\ia\claude\CLAUDE.md` maestro de una instalación pre-v0.2. Vuelve a ejecutar `install.bat` — regenera el fichero renderizado y actualiza la línea de import.

## Actualizar

Si has instalado con symlinks (por defecto):

    cd C:\hix          # o la carpeta que contiene ia\ como subdirectorio
    git pull

Skills, agents, commands, knowledge — todo se actualiza al instante en cada proyecto instalado.

El fichero renderizado `hix-claude-rendered.md` es una snapshot del momento de instalación. Vuelve a ejecutar `install.bat` tras `git pull` **solo si** el `CLAUDE.md` maestro cambió (por ejemplo, secciones nuevas). Para actualizaciones puras de skills/agentes, no hace falta reinstalar.

Si has instalado con `/copy`, vuelve a ejecutar `install.bat` tras cada `git pull`.

## Desinstalar

Ver [UNINSTALL.es.md](UNINSTALL.es.md).
