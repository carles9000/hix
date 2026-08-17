# Guida alla disinstallazione

> Spagnolo · [UNINSTALL.es.md](UNINSTALL.es.md)

## Disinstalla da un progetto

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\uninstall.bat C:\Path\To\MyProject

Oppure:

    powershell -NoProfile -ExecutionPolicy Bypass ^
        -File C:\HIX.PROJECT\hix\ia\scripts\uninstall.ps1 ^
        -Target C:\Path\To\MyProject

## Cosa fa l'uninstaller

1. **Rimuove le entry `hix-*` da `~\.claude\{skills,agents,commands}\`**
   - Vengono rimosse solo le entry che iniziano con `hix-` o `hix.`.
   - Siano symlink o copie, spariscono.
   - Le tue skill/agent/command non vengono mai toccati.
2. **Pulisce `CLAUDE.md` nel progetto**
   - Rimuove il blocco `# HIX AI System -- auto-imported` e la sua riga `@import`.
   - Preserva tutto il resto che hai aggiunto.
   - Se non c'era nient'altro nel file, il file viene eliminato.

## Cosa NON viene rimosso

- I file dentro `C:\HIX.PROJECT\hix\ia\` - i sorgenti restano intatti.
- I file dentro il tuo progetto diversi da `CLAUDE.md`.
- Qualsiasi directory `.claude\` locale del progetto (mai toccata nemmeno dall'installer).

## Disinstalla da più progetti

Esegui il comando una volta per progetto. `~\.claude\` viene pulito alla prima esecuzione; le successive puliscono solo il `CLAUDE.md` di ogni progetto.

## Disinstalla globalmente (rimuovi skill/agent/command, mantieni il repo)

Se vuoi mantenere il repo HIX clonato ma smettere di esporre skill a Claude Code:

    Get-ChildItem "$env:USERPROFILE\.claude\skills\"   -Filter 'hix-*' | Remove-Item -Recurse -Force
    Get-ChildItem "$env:USERPROFILE\.claude\agents\"   -Filter 'hix-*' | Remove-Item -Recurse -Force
    Get-ChildItem "$env:USERPROFILE\.claude\commands\" -Filter 'hix-*' | Remove-Item -Recurse -Force

Devi comunque pulire manualmente `CLAUDE.md` in ogni progetto installato (o eseguire `uninstall.bat` per progetto).
