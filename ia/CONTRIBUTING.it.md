# Contribuire all'HIX AI System

> Spagnolo · [CONTRIBUTING.es.md](CONTRIBUTING.es.md)

Grazie per voler migliorare HIX per tutti. Questa guida spiega come aggiungere o modificare ogni tipo di asset.

## Regole d'oro

1. **Tutti gli asset destinati a Claude Code devono avere il prefisso `hix-`** (skill, agent, command). L'installer tocca solo le entry con quel prefisso.
2. **Ogni skill o command che genera codice deve includere un `*.test.json`** sotto la sua cartella `tests/` (vedi [framework dei test — Sessione 4](.)). Niente test → niente merge.
3. **Gli script PowerShell restano solo ASCII.** Windows PowerShell 5.1 legge i `.ps1` come Windows-1252 di default e corrompe i caratteri UTF-8, causando errori di parser. Usa `--` invece di `—`.
4. **L'inglese è la lingua predefinita per nomi file e identificatori di codice.** I doc leggibili vanno in EN + ES (file side-by-side con suffisso `.es.md`).

## Aggiungere una nuova skill

Directory: `claude/skills/hix-<nome>/`

Minimo:

    hix-<name>/
        SKILL.md
        tests/
            <case>.test.json

Template di `SKILL.md`:

    ---
    name: hix-<name>
    description: >
        Una frase che descrive cosa fa la skill + quando usarla.
        Includi frasi trigger che l'utente potrebbe dire.
    ---

    # hix-<name> -- Titolo breve

    ## Quando usarla
    - "frase 1"
    - "frase 2"

    ## Istruzioni per Claude
    Step numerati. Referenzia i template per path assoluto
    (C:\HIX.PROJECT\hix\ia\templates\<template>\).

    ## Test
    Vedi tests/<case>.test.json

## Aggiungere un nuovo slash command

Directory: `claude/commands/hix-<nome>.md` (singolo file, senza sottocartella).

Template:

    ---
    description: Sommario di una riga. Mostrato nel / picker.
    argument-hint: <arg1> <arg2>
    ---

    Frase di scopo.

    Argomenti: $ARGUMENTS

    Step: (numerati - Claude li eseguirà)
    1. ...
    2. ...

Se il command orchestra una skill, mantieni il file command sottile - metti la logica nella skill e fai invocare quella dal command.

## Aggiungere un nuovo agent

Directory: `claude/agents/hix-<nome>.md`

Template:

    ---
    name: hix-<name>
    description: Quando Claude Code deve delegare a questo agent (sii specifico).
    tools: Read, Grep, Glob    # strumenti permessi; tienili al minimo
    ---

    Sei uno specialista in <dominio>. Dato <input>, produci <output>.
    Referenza: `hix/ia/knowledge/<doc_rilevante>.md`

NON spedire agent con strumenti `Edit` o `Write` a meno che non siano strettamente richiesti - la maggior parte degli agent fa solo ricerca e produce un report.

## Aggiungere knowledge (`knowledge/`)

- Un argomento per file, <2000 token.
- Pattern di filename: `<NN>_<argomento>.md` (es. `03_middleware.md`) per un ordine stabile.
- EN sotto `knowledge/en/`, ES sotto `knowledge/es/` - stessi filename.
- Aggiorna `knowledge/INDEX.md` quando aggiungi un file.

I doc di knowledge sono ciò che Claude legge come riferimento. Mantienili densi, fattuali e ricchi di esempi di codice.

## Aggiungere un template (`templates/`)

- Nomi directory: `project-<kind>/` per progetti completi, `module-<kind>/` per moduli riutilizzabili.
- Token supportati: `{{PROJECT_NAME}}`, `{{PROJECT_NAME_LOWER}}`, `{{DATE}}`, `{{YEAR}}`, `{{AUTHOR}}`, `{{ENTITY}}`, `{{ENTITY_LOWER}}`.
- Niente dati demo nei DBF - solo header.
- Includi un `README.md` nel template che spieghi quali token si aspetta.

## Aggiornare il CHANGELOG

Ogni modifica merged aggiunge un'entry sotto `[Unreleased]` in cima a `CHANGELOG.md`. Al rilascio, quel blocco viene rinominato alla nuova versione + data.

## Testare il tuo contributo localmente

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\install.bat C:\tmp\hix_contrib_test

Apri Claude Code in `C:\tmp\hix_contrib_test`, invoca la tua skill/command/agent, verifica il comportamento. Poi esegui i test automatici (Sessione 4 - in arrivo).

Disinstalla quando hai finito:

    .\scripts\uninstall.bat C:\tmp\hix_contrib_test

## Sottomettere una PR

- Nome del branch: `ia/<kind>/<name>` - es. `ia/skill/hix-add-crud`, `ia/knowledge/routing`.
- Titolo della PR: `[ia] <kind>: <cosa>` - es. `[ia] skill: add hix-add-crud`.
- Corpo della PR: link all'issue correlata, lista di cosa hai aggiunto, menzione dei test inclusi.
