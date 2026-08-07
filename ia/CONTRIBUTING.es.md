# Contribuir al Sistema IA de HIX

> English · [CONTRIBUTING.md](CONTRIBUTING.md)

Gracias por querer mejorar HIX para todos. Esta guía explica cómo añadir o modificar cada tipo de asset.

## Reglas de oro

1. **Todos los assets dirigidos a Claude Code deben llevar el prefijo `hix-`** (skills, agents, commands). El instalador solo toca entradas con ese prefijo.
2. **Todo skill o command que genere código debe incluir un `*.test.json`** en su carpeta `tests/` (ver [framework de tests — Sesión 4](.)). Sin test → no se acepta.
3. **Los scripts PowerShell son solo ASCII.** Windows PowerShell 5.1 lee los `.ps1` como Windows-1252 por defecto y corrompe los caracteres UTF-8, causando errores de parser. Usa `--` en lugar de `—`.
4. **El inglés es el idioma por defecto para nombres de fichero e identificadores de código.** La documentación para humanos va en EN + ES (ficheros hermanos con sufijo `.es.md`).

## Añadir un skill nuevo

Directorio: `claude/skills/hix-<nombre>/`

Mínimo:

    hix-<nombre>/
        SKILL.md
        tests/
            <caso>.test.json

Plantilla de `SKILL.md`:

    ---
    name: hix-<nombre>
    description: >
        Una frase describiendo qué hace el skill + cuándo usarlo.
        Incluye frases-trigger que podría decir el usuario.
    ---

    # hix-<nombre> -- Título corto

    ## Cuándo usarlo
    - "frase 1"
    - "frase 2"

    ## Instrucciones para Claude
    Pasos numerados. Referencia plantillas por ruta absoluta
    (C:\HIX.PROJECT\hix\ia\templates\<plantilla>\).

    ## Test
    Ver tests/<caso>.test.json

## Añadir un slash command nuevo

Directorio: `claude/commands/hix-<nombre>.md` (un solo fichero, sin subcarpeta).

Plantilla:

    ---
    description: Resumen de una línea. Aparece en el selector /.
    argument-hint: <arg1> <arg2>
    ---

    Frase de propósito.

    Arguments: $ARGUMENTS

    Pasos: (numerados -- Claude los ejecutará)
    1. ...
    2. ...

Si el comando orquesta un skill, deja el fichero del comando fino -- pon la lógica en el skill y haz que el comando lo invoque.

## Añadir un agent nuevo

Directorio: `claude/agents/hix-<nombre>.md`

Plantilla:

    ---
    name: hix-<nombre>
    description: Cuándo Claude Code debe delegar en este agent (sé específico).
    tools: Read, Grep, Glob    # herramientas permitidas; al mínimo
    ---

    Eres un especialista en <dominio>. Dado <entrada>, produce <salida>.
    Referencia: `hix/ia/knowledge/<doc_relevante>.md`

NO añadas agents con `Edit` o `Write` a menos que sea estrictamente necesario -- la mayoría de agents solo investigan y producen un informe.

## Añadir knowledge (`knowledge/`)

- Un tema por fichero, <2000 tokens.
- Patrón de nombre: `<NN>_<tema>.md` (ej. `03_middleware.md`) para orden estable.
- EN en `knowledge/en/`, ES en `knowledge/es/` -- mismos nombres.
- Actualiza `knowledge/INDEX.md` al añadir un fichero.

Los docs de knowledge son lo que Claude lee como referencia. Que sean densos, factuales y con muchos ejemplos de código.

## Añadir una plantilla (`templates/`)

- Naming de directorio: `project-<tipo>/` para proyectos completos, `module-<tipo>/` para módulos reutilizables.
- Solo tokens soportados: `{{PROJECT_NAME}}`, `{{PROJECT_NAME_LOWER}}`, `{{DATE}}`, `{{YEAR}}`, `{{AUTHOR}}`, `{{ENTITY}}`, `{{ENTITY_LOWER}}`.
- Sin datos demo en los DBFs -- solo cabecera.
- Incluye un `README.md` en la plantilla explicando qué tokens espera.

## Actualiza el CHANGELOG

Cada cambio que se acepta añade una entrada bajo `[Unreleased]` al principio de `CHANGELOG.md`. Al hacer release, ese bloque se renombra a la nueva versión + fecha.

## Prueba tu contribución localmente

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\install.bat C:\tmp\hix_contrib_test

Abre Claude Code en `C:\tmp\hix_contrib_test`, invoca tu skill/command/agent, verifica el comportamiento. Luego ejecuta los tests automáticos (Sesión 4 -- próximamente).

Desinstala al acabar:

    .\scripts\uninstall.bat C:\tmp\hix_contrib_test

## Enviar un PR

- Nombre de rama: `ia/<tipo>/<nombre>` -- ej. `ia/skill/hix-add-crud`, `ia/knowledge/routing`.
- Título del PR: `[ia] <tipo>: <qué>` -- ej. `[ia] skill: add hix-add-crud`.
- Cuerpo del PR: enlace al issue relacionado, lista lo que has añadido, menciona los tests incluidos.
