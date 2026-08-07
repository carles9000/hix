# Guía de Desinstalación

> English · [UNINSTALL.md](UNINSTALL.md)

## Desinstalar de un proyecto

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\uninstall.bat C:\Ruta\A\MiProyecto

O bien:

    powershell -NoProfile -ExecutionPolicy Bypass ^
        -File C:\HIX.PROJECT\hix\ia\scripts\uninstall.ps1 ^
        -Target C:\Ruta\A\MiProyecto

## Qué hace el desinstalador

1. **Elimina las entradas `hix-*` de `~\.claude\{skills,agents,commands}\`**
   - Solo se eliminan entradas que empiecen por `hix-` o `hix.`.
   - Da igual si eran symlinks o copias.
   - Tus propias skills/agents/commands no se tocan nunca.
2. **Limpia el `CLAUDE.md` del proyecto**
   - Elimina el bloque `# HIX AI System -- auto-imported` y su línea `@import`.
   - Preserva todo lo demás que hayas añadido tú.
   - Si el fichero se queda vacío, se borra.

## Qué NO se elimina

- Ficheros dentro de `C:\HIX.PROJECT\hix\ia\` — el origen queda intacto.
- Ficheros de tu proyecto que no sean `CLAUDE.md`.
- Cualquier directorio `.claude\` local a tu proyecto (el instalador tampoco lo tocaba).

## Desinstalar de varios proyectos

Ejecuta el comando una vez por proyecto. `~\.claude\` se limpia en la primera pasada; las siguientes solo limpian el `CLAUDE.md` de cada proyecto.

## Desinstalar globalmente (quitar skills/agents/commands, conservar el repo)

Si quieres mantener el repo HIX clonado pero dejar de exponer skills a Claude Code:

    Get-ChildItem "$env:USERPROFILE\.claude\skills\"   -Filter 'hix-*' | Remove-Item -Recurse -Force
    Get-ChildItem "$env:USERPROFILE\.claude\agents\"   -Filter 'hix-*' | Remove-Item -Recurse -Force
    Get-ChildItem "$env:USERPROFILE\.claude\commands\" -Filter 'hix-*' | Remove-Item -Recurse -Force

Tendrás que limpiar manualmente el `CLAUDE.md` de cada proyecto instalado (o ejecutar `uninstall.bat` por cada uno).
