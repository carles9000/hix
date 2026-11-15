# ⚙️ Sottosistema Compile — `HIX_Compile*`

HIX espone un sottosistema unificato per compilare ed eseguire codice Harbour
dinamico dall'interno della tua applicazione. È il percorso utilizzato
internamente dal dispatcher (file `.prg` caricati dinamicamente), dai loader,
dai middleware e dal motore di viste. È disponibile anche per i tuoi controller
quando hai bisogno di compilare o eseguire un `.prg` o un HRB pre-compilato
durante una risposta.

> 🧭 **Introdotto in v2.3.12**, consolidato in **v2.4.0** come unico percorso
> di compilazione nella lib. Il vecchio `HIX_CompileFile` è stato rimosso
> in v2.4.0.

---

## Perché un sottosistema

Prima di v2.3.12 esistevano due percorsi distinti: uno per il compile puro
(`HIX_CompileFile` + `hb_CompileFromBuf`) e uno per compile+run, con
contratti di errore diversi e stack walker specifici per ogni chiamante.
Il risultato: codice duplicato, errori difficili da propagare e boot log
asimmetrici tra loader e dispatcher.

v2.4.0 consolida tutti questi percorsi (dispatcher, loader, middleware
loader, motore di viste) su un **unico contratto hash**:

```
{ ok, phase, hrb, err, diagnostics, preambleLines, where }
```

- `ok` — booleano, `.T.` se la fase finale non ha prodotto errori.
- `phase` — in quale fase si è fermata l'esecuzione: `"compile"`, `"load"`, `"run"`.
- `hrb` — bytes dell'HRB risultante dal compile (se la fase compile è passata).
- `err` — hash di errore normalizzato (vedi sotto). `NIL` se `ok=.T.`.
- `diagnostics` — array di diagnostici secondari (warning, righe, ...).
- `preambleLines` — numero di righe di preamble iniettate (regola `line` in `err`).
- `where` — informazioni di localizzazione del compile (filename, ecc.).

---

## API pubblica

Tutte le funzioni **non propagano mai `Break`**: restituiscono l'hash con
`ok=.F.` e `err` popolato se qualcosa fallisce. Non è mai necessario
racchiuderle in `TRY/CATCH`.

### `HIX_CompileCode( cSource [, hOpts] [, cFilename] )`

Compila una sorgente `.prg` in memoria. Opzioni tipiche in `hOpts`:
`{ "virtualName" => "my_module", "runtime" => .F. }`. `cFilename`
etichetta l'errore quando il compile fallisce.

```clipper
LOCAL hRes := HIX_CompileCode( "FUNCTION Foo() ; RETURN 42" )
IF ! hRes["ok"]
   le( "Compile fallito: " + hRes["err"]["description"] )
   RETURN NIL
ENDIF
// hRes["hrb"] contiene l'HRB pronto per l'esecuzione
```

### `HIX_CompileCodeFromFile( cPath )`

Wrapper compile-only da disco. Restituisce lo stesso hash. È il percorso
usato dal dispatcher e dai loader per compilare file `.prg` su disco.

```clipper
LOCAL hRes := HIX_CompileCodeFromFile( "www/controllers/my_action.prg" )
IF ! hRes["ok"]
   USendError( 500, "Compile: " + hRes["err"]["description"] )
   RETURN NIL
ENDIF
```

### `HIX_CompileRunPrg( cPath [, ...args] )`

Compile + esegui in un solo passo. Cattura anche gli errori runtime, non
solo quelli di compile. Restituisce lo stesso contratto hash — `phase` sarà
`"compile"` se è caduto durante la compilazione e `"run"` se è caduto
durante l'esecuzione.

```clipper
LOCAL hRes := HIX_CompileRunPrg( "scripts/report.prg", nUserId, cPeriod )
IF ! hRes["ok"]
   // Stesso formato sia per errori di compile che runtime
   USendError( 500, hRes["err"]["description"] )
   RETURN NIL
ENDIF
```

### `HIX_CompileRunHrb( cHrbBytes [, cVirtualName [, ...args]] )`

Esegue un HRB già compilato (bytes). Utile quando hai il `.hrb` in cache
o lo hai generato con `HIX_CompileCode` e salvato su disco.
Internamente usa `HB_HRB_BIND_FORCELOCAL` per evitare collisioni con
altri HRB caricati.

```clipper
LOCAL cHrb := hb_MemoRead( "cache/report.hrb" )
LOCAL hRes := HIX_CompileRunHrb( cHrb, "report", nUserId )
```

### `HIX_CompileLastError()`

Restituisce uno snapshot dell'ultimo errore runtime catturato dal
sottosistema. **`THREAD STATIC`** — un thread vede solo i propri errori.
Utile quando hai chiamato `HIX_CompileRunPrg` e hai bisogno dello stack
completo oltre all'`err` già nell'hash.

```clipper
LOCAL hLast := HIX_CompileLastError()
IF hLast != NIL
   ld( "aStack: " + hb_ValToExp( hLast["aStack"] ) )
ENDIF
```

---

## Formato di `err` normalizzato

L'hash di errore dentro `hRes["err"]` ha sempre le stesse chiavi, sia da
compile che runtime. **Compile** produce il sottoinsieme:

| Chiave        | Significato                                      |
|---------------|--------------------------------------------------|
| `kind`        | `"compile"` o `"runtime"`                        |
| `severity`    | `"error"`, `"warning"`                           |
| `code`        | Codice numerico (preprocessore, parser)          |
| `description` | Messaggio principale — pronto da mostrare        |
| `file`        | File sorgente dove è stato rilevato l'errore     |
| `line`        | Riga (già corretta da `preambleLines`)           |
| `lineCode`    | Snippet esatto della riga che ha fallito         |

**Runtime** aggiunge il contesto completo Harbour:

| Chiave aggiuntiva | Significato                                     |
|-------------------|-------------------------------------------------|
| `operation`       | Funzione/operazione che ha fallito              |
| `args`            | Argomenti passati quando è andato in crash      |
| `subsystem`       | `oError:subSystem`                              |
| `genCode`         | `oError:genCode` (codice generico Harbour)      |
| `subCode`         | `oError:subCode`                                |
| `osCode`          | Codice OS se applicabile                        |
| `filename`        | File dell'errore runtime                        |
| `stack`           | Stack trace in formato testo                    |
| `aStack`          | Stack trace come array strutturato              |

---

## Esempio — controller che esegue uno script dinamico

```clipper
FUNCTION _RunUserScript()
   LOCAL cPath := "www/scripts/" + UParam( "name" ) + ".prg"
   LOCAL hRes

   IF ! hb_FileExists( cPath )
      RETURN USendError( 404, "Script non trovato" )
   ENDIF

   hRes := HIX_CompileRunPrg( cPath, USession( "user_id" ) )

   IF ! hRes["ok"]
      le( "Script fallito [" + hRes["phase"] + "]: " + hRes["err"]["description"] )
      RETURN USendJson( { ;
         "ok"    => .F.,                       ;
         "phase" => hRes["phase"],             ;
         "error" => hRes["err"]["description"],;
         "line"  => hRes["err"]["line"]        ;
      }, 500 )
   ENDIF

   USendJson( { "ok" => .T. } )
RETURN NIL
```

---

## Boot log arricchito

Da v2.4.0 in poi, quando un **loader** o un **middleware** fallisce durante
la compilazione all'avvio, il boot log mostra riga, codice e snippet invece
del solo messaggio. Non richiede configurazione — è automatico perché il
loader usa `HIX_CompileCodeFromFile` e traduce il suo hash direttamente
nel logger.

Formato tipico:

```
[loader] fail: www/loaders/stats.prg
   line: 42  (code: 2007)
   >>  LOCAL x = y + z        // = invece di :=
   description: Errore di sintassi
```

---

## Quando non usarlo

- **Non** chiamare `HIX_CompileRunPrg` nel hot path per script che non
  cambiano — compila ogni volta. Salva l'HRB con `HIX_CompileCode` + un
  `.md5` come cache e usa `HIX_CompileRunHrb` in seguito. È esattamente
  quello che fa il motore di viste internamente.
- **Non** usare questo sottosistema per valutare espressioni semplici.
  Per quello Harbour ha già `&(cExpr)` (macro-eval). Compile è pensato
  per blocchi `.prg` completi con `FUNCTION`/`PROCEDURE`.
- **Non** affidarsi a `err` che porta `aStack` quando `kind=="compile"`.
  Lo stack ha senso solo per errori runtime.

---

## Modifiche rispetto alle versioni precedenti

| Prima di v2.3.12                     | Da v2.4.0 in poi                                |
|--------------------------------------|-------------------------------------------------|
| `HIX_CompileFile( cPath )`           | **Rimossa.** Usare `HIX_CompileCodeFromFile( cPath )` per compile-only o `HIX_CompileRunPrg( cPath )` per compile+run. |
| `hb_CompileFromBuf` diretto          | Incapsulato in `HIX_CompileFromBuf` (low-level, uso interno di `HIX_CompileCode`) |
| `oError:operation == "line:N"`       | `oError:operation == "line N"`. Fonte ufficiale è `oErr:cargo["line"]` |
| `src/hix_prepro.prg`                 | Rimosso. Le direttive `TRY/CATCH/FINALLY` vivono ora in `src/include/hix_const.ch`. |

Vedi [changes/2.4.0.md](https://github.com/carles9000/hix.pro/blob/main/changes/2.4.0.md)
per la lista completa dei breaking change e l'audit trail della migrazione.
