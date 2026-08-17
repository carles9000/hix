# 🔑 Chiavi e segreti - Store condiviso

Ogni motore di sicurezza di HIX (JWT, sessioni, token firmati, CSRF, resource IDs...) ha bisogno di una **chiave segreta** per firmare i dati. Per evitare di ripetere setup per modulo, HIX fornisce un unico store di chiavi:

- `HIX_KeySet( cName, cVal )` - salva una chiave con un nome.
- `HIX_KeyGet( cName, cDefault )` - la legge (o ritorna il default).
- `HIX_KeyExists( cName )` - controlla se esiste.

I motori leggono sempre tramite `HIX_KeyGet()`. **Non gli importa da dove arriva** la chiave - solo che sia caricata prima di `oSrv:Start()`.

## Chiavi usate da HIX

| Nome       | Consumato da | Default di fallback |
|------------|----------------------------------|----------------------|
| `csrf`     | CSRF (`HIX_CsrfMakeToken/Valid`) | `"H!x@CSRF@2026"` |
| `resource` | Resource IDs (`HIX_ResourceHtml`) | `"H!x@RES@2026"` |
| `jwt`      | JWT (`HIX_JwtEncode/Validate`) | `"H!x@JWT@2026"` |
| `session`  | Sessioni (seed per cifratura SID) | `"H!x@SESSION@2026"` |
| `token`    | Token firmati generici | `"H!x@TOKEN@2026"` |

> I default esistono affinché la libreria si avvii; **cambiali sempre** in produzione.

---

## Profilo HixStyle - caricamento automatico da `config.json`

In modalità **hixstyle** (`config.json` presente alla root del progetto), il bootstrap del server legge la sezione `keys` subito dopo aver applicato la configurazione Harbour e pubblica ogni entry nello store.

```json
{
  "sets": { "language": "IT", "dateformat": "dd/mm/yyyy" },
  "dbf":  { "rddname": "DBFCDX" },
  "keys": {
    "csrf":     "T7$k9pM2!vX4qL8w",
    "resource": "res-2026-abc",
    "jwt":      "hix-jwt-prod-2026",
    "session":  "sess-seed-random",
    "token":    "tok-2026-xyz"
  }
}
```

Al primo avvio, HIX genera `config.json` con questa sezione già seminata (con i default di fallback). Devi solo sostituire i valori con i tuoi e riavviare - niente ricompilazione.

## Profilo standalone - senza `config.json`

Se preferisci avviare senza `config.json` (avvio completamente programmatico), pubblica le chiavi tu stesso prima di `oSrv:Start()`:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()

   // Carica le chiavi da dove preferisci: file .ini, variabili d'ambiente,
   // KMS, hardcoded per lo sviluppo…
   HIX_KeySet( "csrf",    GetEnv( "HIX_CSRF_KEY" ) )
   HIX_KeySet( "jwt",     GetEnv( "HIX_JWT_KEY"  ) )
   HIX_KeySet( "session", GetEnv( "HIX_SESS_KEY" ) )

   oSrv:Start()
   IF oSrv:hThread != NIL ; hb_threadJoin( oSrv:hThread ) ; ENDIF
RETURN
```

I motori vedono esattamente la stessa cosa - l'unica differenza è da dove arriva il valore.

## Profilo legacy - setup per modulo

I setup storici (`HIX_MwJwtSetup`, `HixMwSessionSetup`, `HIX_TokenSetSecret`, …) **funzionano ancora**. Internamente delegano a `HIX_KeySet` con il nome di chiave appropriato.

```harbour
HIX_MwJwtSetup( "my-jwt-secret", 3600 )    // equivalente a HIX_KeySet("jwt", ...)
HIX_TokenSetSecret( "tok-2026" )           // equivalente a HIX_KeySet("token", ...)
```

Coesistono con le altre due modalità. Se mescoli le sorgenti, vince l'ultima scrittura.

---

## Precedenza

1. **Bootstrap HixStyle** - viene eseguito per primo: `HIX_KeysLoadFromAppConfig()`
   copia la sezione `keys` nello store.
2. **Setup per modulo** - qualsiasi `HIX_*Setup()` chiami dopo.
3. **`HIX_KeySet()` manuale** - il modo più diretto; sovrascrive quanto sopra.

Regola pratica: se un valore è in `config.json` **e** chiami anche
`HIX_MwJwtSetup("another")` in `Main()`, vince l'esecuzione successiva.

## Ispezione sicura

Per fare debug o esporre lo stato dello store senza rivelare segreti:

```harbour
? HIX_KeysAsHash()
// { "csrf" => "T7***4w", "jwt" => "hi***26", ... }
```

Ogni valore è mascherato mostrando solo i primi 2 e gli ultimi 2 caratteri.
È lo stesso hash che puoi emettere da un endpoint di stato interno.
