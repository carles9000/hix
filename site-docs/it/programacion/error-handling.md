# 🧨 Gestione degli errori

Tutto ciò che può fallire (un accesso al database, il parsing di JSON, una divisione per zero, un
file mancante) finisce in un **errore Harbour** (un oggetto `oError` con
`description`, `subSystem`, `operation`, ...). Senza gestione esplicita, il
worker che esegue l'action muore e il client riceve una risposta vuota o
l'intero server va in crash.

HIX espone **due livelli** di difesa:

1. **TRY / CATCH** locale — all'interno di una specifica action, per i fallimenti che sai che possono
   accadere (database, rete, parsing).
2. **Global handler** (`bOnError`) — rete di sicurezza che cattura ogni errore non catturato,
   invia una risposta HTTP coerente al client e scrive su `errors.log`.

```
GET /api/users/42
      │
      ▼
   action _UserGet()
      │
      ├─── TRY ──── errore DB ──── CATCH ────────── USendError(500, ...)
      │                                                  │
      └─── altri errori non catturati                     ▼
              │                                    client riceve JSON
              ▼
         worker protect ─── bOnError(oErr, oReq) ─── HIX_ShowError
              │                                          │
              ▼                                          ▼
         log + risponde 500                   errors.log + render
```

---

## TRY / CATCH / FINALLY

Definiti in `include/hix_const.ch`:

```clipper
TRY
   // codice che può fallire
CATCH oError
   // gestione dell'errore
FINALLY
   // sempre eseguito (con o senza errore)
END
```

`oError` va sempre dichiarato come `LOCAL` all'inizio della funzione:

```clipper
FUNCTION _DbInsert( hData )
   LOCAL oError, lOk := .F.
   LOCAL oDbf

   TRY
      oDbf := UDbf():New( "customers" )
      
      oDbf:Append()
      oDbf:Save( hData )
      lOk := .T.
   CATCH oError
      le( "Insert DB fallito: " + oError:description )
      lOk := .F.
   FINALLY
      oDbf:Close()
   END

RETURN lOk
```

### Campi tipici di `oError`

| Campo | Contenuto |
|---|---|
| `oError:description` | Messaggio principale dell'errore |
| `oError:operation` | Funzione o operazione che è fallita (`OPEN`, `JSONDECODE`, ...) |
| `oError:subSystem` | Subsystem (`DBFCDX`, `BASE`, `MEMIO`, ...) |
| `oError:subCode` | Codice numerico — utile come status HTTP se nell'intervallo |
| `oError:filename` | File coinvolto |
| `oError:procName` | Funzione in cui è stato generato |
| `oError:procLine` | Riga nella funzione |
| `oError:args` | Argomenti passati alla funzione fallita |
| `oError:cargo` | Hash libero — HIX lo usa per contesto extra (codice view, codice riga, ...) |

---

## Pattern nelle action

### Validazione + database con errore controllato

```clipper
FUNCTION _UserCreate()
   LOCAL oVal, oUsers, oError, nId := 0, cMsg := ""

   oVal := UValidateOrFail( { ;
      "name"  => "required|string|max:50",  ;
      "email" => "required|string|email"    ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   TRY
      oUsers := TUsers()
      nId    := oUsers:Insert( oVal:DataFields(), @cMsg )
   CATCH oError
      le( "Errore di insert: " + oError:description )
      RETURN USendError( 500, oError:description )
   END

   IF nId == 0
      RETURN USendError( 422, cMsg )
   ENDIF

   USendJson( { "id" => nId }, 201 )
RETURN NIL
```

### Parsing del JSON in ingresso

```clipper
LOCAL hBody := UJson()
IF hBody == NIL
   RETURN USendError( 400, "Il body non è un JSON valido" )
ENDIF
```

`UJson` ritorna già `NIL` se fallisce — non serve un TRY/CATCH esplicito.

### Accesso a file opzionale

```clipper
LOCAL oError, cContent := ""

TRY
   cContent := hb_MemoRead( cPath )
CATCH oError
   cContent := "(file non disponibile)"
END

USendText( cContent )
```


---

## Global handler (`bOnError`)

Qualsiasi errore che **non** catturi con TRY/CATCH finisce qui. Il server lo invoca
con `(oError, oReq)`:

```clipper
oSrv:bOnError := {|oErr, oReq|
   le( "Errore non catturato: " + oErr:description )
   HIX_HttpError( oReq, 500, oErr:description )
}
```

Se non definisci `bOnError`, HIX usa il suo renderer interno (`HIX_ShowError` /
`HIX_ErrorSys`) che:

- **dev**: mostra HTML dettagliato con stack, riga sorgente e contesto.
- **prod**: mostra HTML 500 generico senza dettagli interni.

Vedi [Errorsys](errorsys.md) per personalizzare il template.

### Distinguere automaticamente JSON / HTML

```clipper
oSrv:bOnError := {|oErr, oReq|
   IF HIX_WantsJson( oReq )
      oReq:Respond( { "error" => oErr:description }, 500, "json" )
   ELSE
      HIX_ShowError( oErr, oReq )    // delega al renderer interno
   ENDIF
}
```

> `HIX_ShowError` fa già internamente questa divisione: se `Accept` chiede
> JSON, risponde con JSON; se chiede HTML, renderizza il template errorsys.

---

## Errori HTTP espliciti

Non ogni errore è un'eccezione. Molti sono situazioni attese:

```clipper
USendError( 404, "L'utente non esiste" )
USendError( 403, "Nessun permesso" )
USendError( 422, "Dati non validi" )
USendError( 429, "Troppi tentativi" )
```

`USendError` invia lo status e il body come JSON o HTML in base a `Accept`.
È **il** modo per rispondere con errori controllati dall'action.

### Equivalente diretto

`HIX_HttpError( oReq, nStatus, cMsg )` — riceve l'`oReq` esplicito, utile
all'interno dei middleware.

---

## Worker protect

Sotto il cofano, ogni worker HTTP avvolge l'esecuzione del controller in
`HixWorkerProtect`: se l'action genera un'eccezione non catturata, protect:

1. Chiama `bOnError` se definito.
2. Altrimenti chiama `HIX_ShowError`.
3. Scrive l'entry su `errors.log`.
4. Chiude la connessione in modo pulito — non uccide il worker, solo la request.

Questo è ciò che impedisce che un errore su un singolo URL porti giù l'intero
server.

---

## Logging degli errori

`HIX_ShowError` chiama sempre `_HixWriteErrorLog` prima di renderizzare. Il
file `errors.log` (configurato con `HIX_ErrorLogInit` o tramite
`[server] errors=.logs`) accumula ogni errore con timestamp e sequenza.

```clipper
HIX_ErrorLogInit( ".logs" )      // dir dove viene scritto errors.log
```

Per logging libero al di fuori del flusso di errore, usa gli helper di log:

```clipper
ld( "Dettaglio debug" )       // DEBUG
l(  "Info" )                  // INFO
lw( "Avvertimento" )          // WARN
le( "Descrizione errore" )    // ERROR
```

Vedi il modulo Logger.
