# Guida all'installazione

> Spagnolo · [INSTALL.es.md](INSTALL.es.md)

## Prerequisiti

| Requisito | Note |
|-------------|-------|
| Claude Code CLI | https://claude.com/claude-code - deve essere nel PATH |
| Distribuzione HIX | Una cartella contenente `hix.exe`, `hix.json` e le DLL runtime. Posizione tipica: `C:\hix\`. Il bundle AI System vive accanto ad essa in `<hix>\ia\`. |
| Windows 10/11 | Developer Mode ON è fortemente consigliato |

Harbour + `hbmk2` **non** sono richiesti per il flusso predefinito binary-first. Servono solo se usi `/hix-scaffold-source` (legacy) per compilare il tuo `.exe`.

### Abilita Developer Mode (una volta per macchina)

Impostazioni → *Per sviluppatori* → **Modalità sviluppatore: On**

O via PowerShell (admin):

    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 1 /f

Senza Developer Mode l'installer fa fallback sulla copia di file - tutto funziona ancora, ma un `git pull` nel repo HIX **non** si propagherà al tuo `~/.claude/`. Dovresti rieseguire l'install.

## Installa in un progetto

Il più semplice (consigliato):

    cd C:\hix\ia
    .\scripts\install.bat C:\Path\To\MyProject

Caso comune - installa l'AI System nella stessa cartella che contiene `hix.exe`, così puoi guidare `/hix-init` da lì:

    cd C:\hix\ia
    .\scripts\install.bat C:\hix

Forza la copia di file (salta i symlink):

    .\scripts\install.bat C:\Path\To\MyProject /copy

O invoca PowerShell direttamente:

    powershell -NoProfile -ExecutionPolicy Bypass ^
        -File C:\hix\ia\scripts\install.ps1 ^
        -Target C:\Path\To\MyProject

## Cosa fa l'installer

1. **Crea entry `hix-*` in `~\.claude\{skills,agents,commands}\`**
   - Symlink per default (singola fonte di verità, aggiornamenti via `git pull`).
   - File/directory regolari se `-ForceCopy` o se la capacità di symlink non è disponibile.
   - Vengono toccate solo le entry che iniziano con `hix-` o `hix.`. Le tue skill/agent/command non vengono mai modificati.
2. **Renderizza `~\.claude\hix-claude-rendered.md`**
   - Legge `<hix>\ia\claude\CLAUDE.md` (che usa il placeholder `{{HIX_ROOT}}`).
   - Sostituisce `{{HIX_ROOT}}` con il parent reale di `<hix>\ia\` (tipicamente `C:\hix`).
   - Scrive il file renderizzato così Claude Code può importarlo verbatim.
3. **Crea o aggiorna** `C:\Path\To\MyProject\CLAUDE.md`
   - Se il file non esisteva: lo crea con un titolo + il blocco di import HIX.
   - Se esisteva: appende un blocco di import alla fine. Il contenuto esistente viene preservato.
   - L'import punta a `~\.claude\hix-claude-rendered.md` via sintassi `@`.
4. **Scrive `C:\Path\To\MyProject\.claude\settings.local.json`**
   - Aggiunge permessi (`Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)`, ecc.) così le skill HIX possono eseguire i loro script PowerShell senza prompt per comando.
   - Idempotente: le entry esistenti sono preservate, vengono aggiunte solo quelle mancanti.
5. **Stampa un riepilogo** di ogni azione eseguita.

## Dopo l'install

    cd C:\hix          # o la tua cartella target
    claude

Dentro Claude Code:

    > /hix-init MyApp

Se la skill risponde, il wiring è corretto.

## Verifica l'install manualmente

    Get-ChildItem "$env:USERPROFILE\.claude\skills\" | Where-Object Name -like 'hix-*'
    Get-Content "$env:USERPROFILE\.claude\hix-claude-rendered.md" -TotalCount 5
    Get-Content C:\Path\To\MyProject\CLAUDE.md
    Get-Content C:\Path\To\MyProject\.claude\settings.local.json

Atteso:
- Entry sotto `skills\`, `agents\`, `commands\` che iniziano con `hix-*` (SymbolicLink o Directory).
- Il `hix-claude-rendered.md` renderizzato ha il tuo path HIX reale espanso (nessun `{{HIX_ROOT}}` residuo).
- Il `CLAUDE.md` del progetto termina con:

      # HIX AI System -- auto-imported
      @C:\Users\<tuo utente>\.claude\hix-claude-rendered.md

- `settings.local.json` elenca almeno `Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)` in `permissions.allow`.

## Troubleshooting

### "execution of scripts is disabled on this system"

Hai bypassato il wrapper `.bat`. Usa `install.bat` (consigliato) o aggiungi `-ExecutionPolicy Bypass` all'invocazione di PowerShell.

### "Cannot create symbolic link. A required privilege is not held by the client."

Developer Mode è disattivato e PowerShell non gira come admin. Due soluzioni:
- **Preferita**: attiva Developer Mode (vedi Prerequisiti) e reinstalla.
- **Fallback**: esegui con `/copy` - perdi l'auto-update via `git pull`.

### Claude Code non vede il command `/hix-init`

- Conferma che il symlink/copy esiste in `~\.claude\commands\hix-init.md` e `~\.claude\skills\hix-init\SKILL.md`.
- Riavvia Claude Code - alcuni host cachano l'indice delle skill all'avvio della sessione.

### L'import di CLAUDE.md non viene applicato

Claude Code carica `CLAUDE.md` solo dalla root del progetto. Conferma di aver lanciato `claude` dalla stessa directory che contiene `CLAUDE.md` (non da una sottodirectory).

### PowerShell chiede ancora i permessi a ogni comando

`install.bat` non ha scritto `.claude/settings.local.json` (errore di permesso, o Target path risolto incorrettamente). Reinstalla; verifica che il file esista e contenga la lista `permissions.allow` attesa.

### `{{HIX_ROOT}}` visibile nel contesto di Claude

Il file renderizzato non è stato creato, o il `CLAUDE.md` del progetto importa ancora il master `<hix>\ia\claude\CLAUDE.md` da un'install pre-v0.2. Reinstalla - rigenera il file renderizzato e aggiorna la riga di import.

## Aggiornamento

Se installato con symlink (predefinito):

    cd C:\hix          # o la cartella che contiene ia\ come sottodirectory
    git pull

Skill, agent, command, knowledge - tutto si aggiorna istantaneamente per ogni progetto installato.

Il `hix-claude-rendered.md` renderizzato è uno snapshot al momento dell'install. Reinstalla dopo `git pull` **solo se** il template master `CLAUDE.md` stesso è cambiato (es. nuove sezioni). Per aggiornamenti puri di skill/agent, non serve reinstallare.

Se installato con `/copy`, reinstalla sempre dopo `git pull`.

## Uninstall

Vedi [UNINSTALL.md](UNINSTALL.md).
