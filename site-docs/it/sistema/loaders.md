# Loader e hook utente

**HIX** può caricare dinamicamente codice utente quando il server si avvia.
Qualsiasi file `.prg` situato in `www/loaders/` viene compilato in `.hrb`, caricato in memoria,
e le sue funzioni diventano **globalmente accessibili** da qualsiasi route,
middleware, controller o view.

In aggiunta al caricamento, HIX definisce due **hook del ciclo di vita**:

| Hook       | Quando viene eseguito                              | Usato per                          |
|------------|----------------------------------------------------|--------------------------------------|
| `USERINIT` | Dopo aver caricato i loader, prima di accettare traffico | Aprire connessioni, caching di dati, ecc. |
| `USEREXIT` | Quando si ferma il server, prima di chiudere i socket | Chiudere connessioni, flushare buffer  |

Entrambi sono opzionali: se non esistono, HIX non fa nulla. Se esistono, sono
invocati automaticamente.

---

## Quando ti serve?

- Per **caricare codice applicativo** senza ricompilare la libreria HIX.
- Per **inizializzare risorse** di cui la tua app ha bisogno di avere disponibili alla prima
  richiesta (pool DB, cache in memoria, warmup indici, ecc.).
- Per **rilasciare le risorse** in modo pulito quando il server si ferma
  (chiudere handle, flushare log custom, chiudere socket aperti).

---

## Directory `www/loaders/`

```
www/
└─ loaders/
   ├─ 00_bootstrap.prg     ← definizioni di USERINIT / USEREXIT
   ├─ helpers.prg          ← funzioni di utilità
   ├─ tcustomers.prg       ← model, classi, ecc.
   └─ …
```

Regole:
- Ogni `.prg` viene compilato **una sola volta** in `.hrb` (che viene salvato nella
  stessa directory accanto al `.prg`).
- Agli avvii successivi, HIX **ricompila solo** i file `.prg` il cui mtime è
  successivo al `.hrb` corrispondente. I file `.hrb` già aggiornati vengono caricati
  direttamente.
- L'ordine alfabetico del nome file definisce l'ordine di tentativo di caricamento. Se ci sono
  **dipendenze incrociate** tra moduli, HIX itera attraverso diversi passaggi
  finché non le risolve tutte.
- I simboli sono pubblicati con `hb_hrbLoad( 0x2, ... )` (BIND_LAZY), quindi
  diventano disponibili al resto del server.

Ogni tentativo (successo o fallimento) viene registrato nel **Boot Log** sotto la
sezione `"loaders"`:

```
[loaders]
  OK  file     00_bootstrap.prg
  OK  file     tcustomers.prg
  ERR file     bad.prg  -> Unterminated string 'x, HB_COMPILEFROMBUF
```

Vedi [Boot Log](bootlog.md) per ispezionare i risultati da codice o esporli come JSON.

---

## Ciclo di vita completo

Questo è l'ordine esatto degli eventi all'avvio e allo stop del server:

```
THixServer:Start()
   │
   ├─ HIX_Loaders()        ← compila e carica www/loaders/*.prg
   │
   ├─ Eval( ::bInit, SELF ) ← callback opzionale dal programmatore (bInit)
   │
   ├─ HIX_UserInit()        ← invoca USERINIT() se hb_IsFunction("USERINIT")
   │
   └─ (apre la porta, accetta le connessioni)

THixServer:Stop()
   │
   ├─ HIX_UserExit()        ← invoca USEREXIT() se hb_IsFunction("USEREXIT")
   │
   └─ (chiude i socket, ferma i worker)
```

`USERINIT` viene eseguito **prima** che il server accetti la prima request:
tutto ciò che prepari lì sarà disponibile quando arriva traffico.
`USEREXIT` viene eseguito **prima** di chiudere i socket, quindi puoi ancora usare la rete se necessario
(per esempio, per inviare una notifica di shutdown).

---

## Hook `USERINIT` / `USEREXIT`

### Come dichiararli

Sono dichiarati come **FUNCTION di primo livello** (mai `STATIC`) in qualsiasi
file `.prg` in `www/loaders/`. Devono essere globali così che `hb_IsFunction()`
le risolva.

```harbour
// www/loaders/00_bootstrap.prg

FUNCTION USERINIT()

   l( "Inizializzazione dell'applicazione..." )
   _OpenDbConnection()
   _LoadCachesIntoMemory()

RETURN NIL

FUNCTION USEREXIT()

   l( "Spegnimento dell'applicazione..." )
   _CloseDbConnection()

RETURN NIL
```

### Regole critiche

- **Devono essere non bloccanti.** Un loop infinito, un socket senza timeout,
  o un lock che non si rilascia **ritarda l'avvio** (in `USERINIT`) o
  **blocca lo shutdown** (in `USEREXIT`).
- **Le eccezioni sono contenute.** HIX wrappa entrambi gli hook in un `TRY/CATCH` interno:
  se `USERINIT` lancia, l'errore viene tracciato e il
  server continua ad avviarsi. Lo stesso vale per `USEREXIT`.
- **Sono rientranti.** Se per qualsiasi ragione chiami `HIX_UserInit()` più volte,
  `USERINIT()` viene eseguito ogni volta. Non c'è un guard per "esegui solo una volta".
- **`USERINIT` gira sul thread principale del server**, prima del
  loop di accept. Qualsiasi `STATIC` che assegni diventa accessibile dai worker
  tramite accessor pubblici.

### Esempio - Pool di connessioni DB

```harbour
// www/loaders/00_bootstrap.prg

STATIC s_oDbPool := NIL

FUNCTION UserDbPool()
RETURN s_oDbPool

FUNCTION USERINIT()

   LOCAL oErr

   TRY
      s_oDbPool := MyDbPool():New( "postgres://…", 8 )
      s_oDbPool:Warmup()
      l( "Pool DB pronto (8 connessioni)" )
   CATCH oErr
      le( "Impossibile inizializzare il pool DB: " + oErr:description )
      // non rilanciare - il server parte comunque
   END

RETURN NIL

FUNCTION USEREXIT()

   IF s_oDbPool != NIL
      s_oDbPool:CloseAll()
      s_oDbPool := NIL
   ENDIF

RETURN NIL
```

Da qualsiasi route:

```harbour
oSrv:AddRouteGet( "users", "/users", {||
   LOCAL oDb := UserDbPool()
   USendJson( oDb:Query( "SELECT id, name FROM users" ) )
} )
```

---

## API pubblica

```harbour
HIX_Loaders()        // compila e carica www/loaders/*.prg. Ritorna .T. se tutto ok
HIX_GetLoaders()     // array con lo stato di ogni modulo caricato
HIX_UserInit()       // invoca USERINIT() se esiste. TRY/CATCH interno
HIX_UserExit()       // invoca USEREXIT() se esiste. TRY/CATCH interno
```

HIX chiama queste funzioni automaticamente durante `Start()` / `Stop()`.
Di solito non vengono chiamate manualmente - ma sono pubbliche nel caso tu abbia bisogno
di fare warmup manuale da un test o una CLI.

### Struttura di un modulo (`HIX_GetLoaders()`)

Ogni entry nell'array ritornato è un hash con questi campi:

| Campo     | Tipo | Significato                                |
|-----------|------|----------------------------------------------|
| `file`    | `C`  | Nome file (es., `tcustomers.hrb`)       |
| `loaded`  | `L`  | `.T.` se `hb_hrbLoad` ha avuto successo       |
| `error`   | `L`  | `.T.` se compilazione o caricamento falliti  |
| `msg`     | `C`  | Descrizione errore se `error == .T.`         |
| `oError`  | `O`  | Oggetto errore Harbour (o `NIL`)             |
| `oHrb`    | `C`  | Contenuto binario del `.hrb`                  |
| `pSym`    | `P`  | Puntatore simbolico al modulo caricato        |
| `process` | `L`  | `.T.` se il `.prg` è stato (ri)compilato ora |

---

## Diagnosi

Se qualcosa non si carica come previsto:
1. **Controlla il Boot Log:** `HIX_BootLogShow()` su console, o
   `HIX_BootLogSection( "loaders" )` da codice. Ogni `.prg` appare con
   OK/ERR e, in caso di errore, la descrizione esatta.
2. **Verifica che l'hook sia pubblicato:** `hb_IsFunction( "USERINIT" )`
   dovrebbe ritornare `.T.`. Se ritorna `.F.`, controlla che la funzione sia
   dichiarata come `FUNCTION` di primo livello (non `STATIC`) in qualche file `.prg`
   in `www/loaders/`.
3. **Gli errori in `USERINIT` non crashano il server:** anche se il server
   continua ad avviarsi, l'eccezione viene registrata nel trace (`_t()`). Vedi
   [Tracciamento](traceando.md) per leggerla.
4. **Rigenera l'`.hrb`:** se sospetti che l'`.hrb` cached sia
   corrotto, cancellalo - HIX lo ricompilerà dal `.prg` al prossimo
   boot.
