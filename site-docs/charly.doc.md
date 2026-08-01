# charly.doc — Cómo funcionan las traducciones del manual HIX

Sempre que toqui algun fitxer del help en ES --> Ezecuta /translation-sync.

---

## Idiomas

- **ES = pivote** (el que tú editas).
- **EN = target** (Claude lo mantiene sincronizado).
- Añadir más idiomas es cambiar una lista en `sync.py` (campo `TARGETS`).

---

## Los 3 estados posibles

| Estado | Qué significa | Qué hace Claude |
|---|---|---|
| **DRIFT** | Tocaste el ES tras traducirlo | Re-traduce o parchea el EN |
| **PENDING** | Existe ES pero no EN | Traducción completa del EN |
| **ORPHAN** | Existe EN sin ES equivalente | Pregunta si borrar o restaurar |

---

## Flujo normal (cuando tú editas ES)

1. Editas cualquier `.md` bajo `site-docs/es/`.
2. Le dices a Claude: **`/translation-sync`**
3. Claude:
   - Detecta qué cambió.
   - Si el diff es pequeño (≤ 30 líneas): parchea el EN.
   - Si es grande: re-traduce entero.
   - Actualiza `mkdocs.yml` (nav EN).
   - Registra hash nuevo en el manifest.
   - Registra coste en `costs.log`.
   - Te enseña un resumen y pregunta si commit.

Tú solo dices `sí` al commit. Fin.

---

## Comandos manuales (si algún día quieres verlo tú)

Todos desde la raíz del repo:

```bash
# ¿Qué está desincronizado?
python .claude/translation/sync.py status

# Ver diff de un fichero ES desde el último sello
python .claude/translation/sync.py diff sistema/hix-admin.md --lang en

# Marcar como sincronizado (tras traducir a mano)
python .claude/translation/sync.py stamp sistema/hix-admin.md en --translator manual

# Regenerar todo el manifest desde cero
python .claude/translation/sync.py init
```

El script **nunca traduce**. Solo diagnostica y sella.

---

## Ficheros clave

| Fichero | Para qué |
|---|---|
| `site-docs/translation_manifest.json` | Fuente de verdad — hashes ES + EN |
| `.claude/translation/sync.py` | Script de diagnóstico |
| `.claude/commands/translation-sync.md` | Pipeline que sigue Claude |
| `.claude/translation/glossary.md` | Glosario ES→EN (Claude lo respeta) |
| `.claude/translation/instructions.md` | Reglas de traducción |
| `.claude/translation/costs.log` | Log de tokens + $ por capítulo |
| `.claude/translation/workflow.md` | Workflow manual (fallback legacy) |

---

## Renombrar un fichero ES

Si renombras `cabeceras.md` a `headers.md`, edita a mano la entrada en
`translation_manifest.json` para que el EN mantenga su nombre:

```json
"hixstyle/response/cabeceras.md": {
  "es_sha": "...",
  "translations": {
    "en": { "path": "hixstyle/response/headers.md", ... }
  }
}
```

La clave `"path"` es un override del mapeo 1:1 por defecto.

---

## Añadir un idioma nuevo (ej. catalán)

1. Abre `.claude/translation/sync.py`, línea `TARGETS = ["en"]`.
2. Cámbialo a `TARGETS = ["en", "ca"]`.
3. Crea la carpeta `site-docs/ca/`.
4. Ejecuta `python .claude/translation/sync.py init`.
5. Todo lo que falte en `ca/` saldrá como **PENDING** — Claude lo traduce con `/translation-sync`.

---

## Coste típico

- Haiku 4.5, ratio 60/40 in/out → **~$2.60 / M tokens**.
- Un capítulo medio: 20–40K tokens, ~$0.05–$0.10.
- Consulta el acumulado en `.claude/translation/costs.log`.

---

## Reglas de oro

- **Nunca** edites directamente `site-docs/en/` — se sobrescribe en el próximo sync.
- **Nunca** borres a mano un `.md` de EN si el ES sigue vivo — Claude lo detectaría como ORPHAN y preguntaría.
- **Sí** puedes editar EN si arreglas un typo ortográfico puntual: haz `sync.py stamp` después para no confundir al sistema.
- Los hashes se calculan con `git hash-object` → CRLF/LF no genera falsos drifts.
