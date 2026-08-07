# Guía de Instalación

> English · [INSTALL.md](INSTALL.md)

## Requisitos previos

| Requisito | Notas |
|-----------|-------|
| CLI de Claude Code | https://claude.com/claude-code — debe estar en el PATH |
| Repo HIX clonado | Este repo, en `C:\HIX.PROJECT\hix\` (ruta ahora mismo hard-coded — ver [issue en Backlog](.claude/plans/tasks_hix_ia_system.md)) |
| Windows 10/11 | Modo Desarrollador ACTIVADO muy recomendado |

### Activar Modo Desarrollador (una sola vez por máquina)

Configuración → *Para desarrolladores* → **Modo de desarrollador: activado**

O por PowerShell (admin):

    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 1 /f

Sin Modo Desarrollador el instalador hace fallback a copia — todo funciona igual, pero un `git pull` en el repo HIX **no** propagará los cambios a tu `~/.claude/`. Tendrías que volver a ejecutar la instalación.

## Instalar en un proyecto

Lo más sencillo (recomendado):

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\install.bat C:\Ruta\A\MiProyecto

Forzar copia de ficheros (sin symlinks):

    .\scripts\install.bat C:\Ruta\A\MiProyecto /copy

O invocar PowerShell directamente:

    powershell -NoProfile -ExecutionPolicy Bypass ^
        -File C:\HIX.PROJECT\hix\ia\scripts\install.ps1 ^
        -Target C:\Ruta\A\MiProyecto

## Qué hace el instalador

1. **Crea o actualiza** `C:\Ruta\A\MiProyecto\CLAUDE.md`
   - Si no existía: lo crea con un título + el bloque de import de HIX.
   - Si existía: añade un bloque de import al final. El contenido previo se preserva.
   - El import apunta a `C:\HIX.PROJECT\hix\ia\claude\CLAUDE.md` con la sintaxis `@`.
2. **Crea entradas `hix-*` en `~\.claude\{skills,agents,commands}\`**
   - Symlinks por defecto (fuente única, se actualiza con `git pull`).
   - Ficheros/directorios normales si se usa `-ForceCopy` o no hay capacidad de symlink.
   - Solo se tocan entradas que empiecen por `hix-` o `hix.`. Nunca se modifican tus propias skills/agents/commands.
3. **Muestra un resumen** de todas las acciones.

## Después de instalar

    cd C:\Ruta\A\MiProyecto
    claude

Dentro de Claude Code:

    > /hix-scaffold web-crud MiApp

Si el skill responde, el cableado es correcto.

## Verificar la instalación manualmente

    Get-ChildItem "$env:USERPROFILE\.claude\skills\" | Where-Object Name -like 'hix-*'
    Get-Content C:\Ruta\A\MiProyecto\CLAUDE.md

Esperado:
- Una entrada `hix-scaffold` en `skills\` (SymbolicLink o Directory)
- El `CLAUDE.md` del proyecto termina con:

      # HIX AI System -- auto-imported
      @C:\HIX.PROJECT\hix\ia\claude\CLAUDE.md

## Problemas frecuentes

### "la ejecución de scripts está deshabilitada en este sistema"

Has saltado el wrapper `.bat`. O usa `install.bat` (recomendado) o añade `-ExecutionPolicy Bypass` a la invocación de PowerShell.

### "No se puede crear el vínculo simbólico. El cliente no tiene los privilegios requeridos."

Modo Desarrollador desactivado y PowerShell no es admin. Dos opciones:

- **Preferida**: activa el Modo Desarrollador (ver Requisitos previos) y vuelve a ejecutar.
- **Fallback**: ejecuta con `/copy` — perderás la actualización automática con `git pull`.

### Claude Code no ve el comando `/hix-scaffold`

- Confirma que existe el symlink/copia en `~\.claude\skills\hix-scaffold\SKILL.md`.
- Reinicia Claude Code — algunos hosts cachean el índice de skills al arrancar.

### No se aplica el import del CLAUDE.md

Claude Code lee `CLAUDE.md` solo desde la raíz del proyecto. Confirma que has lanzado `claude` desde el mismo directorio que contiene `CLAUDE.md` (no desde un subdirectorio).

## Actualizar

Si has instalado con symlinks (por defecto), basta con:

    cd C:\HIX.PROJECT\hix
    git pull

Skills, agents, commands, knowledge — todo se actualiza al instante en cada proyecto instalado.

Si has instalado con `/copy`, vuelve a ejecutar `install.bat` tras el `git pull`.

## Desinstalar

Ver [UNINSTALL.es.md](UNINSTALL.es.md).
