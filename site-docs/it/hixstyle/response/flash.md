# ⚡ Messaggi flash

Un **flash** è un messaggio che vive per **una singola request**: viene memorizzato
nella sessione durante un POST, sopravvive a un redirect, e viene consumato (auto-cancellato)
quando letto nel successivo GET.

È il pezzo che completa il pattern **PRG (Post / Redirect / Get)**: l'utente
invia un POST, il server lo processa, reindirizza, e il successivo GET
mostra il risultato — senza reinviare il form se la pagina viene rinfrescata.

```
POST /customer/update
      │
      │  oVal:Make()   → fallisce
      │  UFlash("customer"):Set({ errors, input })
      │  URedirect( "/customer/edit/42" )
      ▼
GET /customer/edit/42
      │
      │  oFlash := UFlash("customer")
      │  hErrors := oFlash:Get("errors")   ← legge e cancella
      │  hInput  := oFlash:Get("input")    ← legge e cancella
      │  USendView( "edit.html", hRow, hErrors, hInput )
      ▼
HTML con errori + valori che l'utente aveva inserito
```

> Se l'utente rinfresca il GET, i flash **non ci sono più** - il browser
> non reinvia il POST e il banner "Cliente aggiornato!"
> non viene mostrato due volte.

---

## Quando usarlo

| Caso | Flash |
|---|---|
| Messaggio "✅ Cliente creato" dopo redirect | ✅ Sì |
| Mostra errori di validazione tornando al form | ✅ Sì |
| Ripopolare il form con `oVal:Resume()` dopo un errore | ✅ Sì |
| Dati persistenti (preferenze) | ❌ No - usa cookie o database |
| Dati condivisi tra tab | ❌ No - il flash è per sessione |
| Messaggio informativo nella stessa request | ❌ No - passa direttamente alla view |

---

## API di base

```clipper
UFlash( cFormId )   // ritorna un TFlash
```

`cFormId` è il namespace dentro la sessione: ogni form / modulo
ha il suo "sacchetto", così due flussi aperti in tab diverse non interferiscono.

```clipper
LOCAL oFlash := UFlash( "customer" )

oFlash:Set( "type",    "success" )
oFlash:Set( "message", "Cliente aggiornato" )
oFlash:Save()
```

Se chiami con un **hash completo**, esegue `merge` e **auto-Save**:

```clipper
UFlash("customer"):Set( { ;
   "type"    => "success",                     ;
   "message" => "Cliente aggiornato"           ;
} )
// Save() implicito - già in sessione
```

Se chiami con `(cKey, xVal)`, marca dirty ma **non salva** fino a
`Save()`. Quando l'oggetto esce dallo scope, il distruttore chiama `Save()`
automaticamente se ci sono modifiche pendenti.

---

## Metodi

### `Set( cKey, xVal )` / `Set( hHash )`

```clipper
oFlash:Set( "name", "Carles" )
oFlash:Set( "age",  42 )
oFlash:Save()    // esplicito

// Oppure tutto in una riga - auto-save
UFlash("login"):Set( { "error" => "Password errata", "input" => { "user" => cUser } } )
```

### `Get( cKey, xDef )` - **one-shot**

Ritorna il valore e **lo cancella** dal sacchetto. La prossima chiamata → `xDef`.

```clipper
cMessage := oFlash:Get( "message", "" )    // prima volta → testo
cMessage := oFlash:Get( "message", "" )    // seconda volta → ""
```

> `Get` lascia il sacchetto `dirty` così il distruttore lo persiste vuoto - il
> messaggio è definitivamente consumato anche se c'è un altro flusso di lettura/scrittura.

### `Has( cKey )`

Controlla se c'è un valore **senza** consumarlo:

```clipper
IF oFlash:Has( "message" )
   USetHeader( "X-Has-Notice", "1" )
ENDIF
```

### `Delete( cKey )`

Cancella esplicitamente senza leggere:

```clipper
oFlash:Delete( "old_state" )
```

### `Clear()`

Svuota l'intero sacchetto per quel `cFormId`:

```clipper
UFlash("customer"):Clear()
```

### `Save()`

Persiste il sacchetto in sessione. **Non necessario** chiamarlo se:

- Hai usato `Set(hHash)` (auto-save).
- L'oggetto esce dallo scope (il distruttore lo chiama se `lDirty`).

### `GetId()`

Ritorna il `cFormId` di questo flash:

```clipper
oFlash:GetId()   // "customer"
```

---

## Storage

- Il flash è memorizzato nella **sessione**, sotto la chiave `_flash`.
- `_flash` è un hash `{ cFormId => hBag }` - ogni form ha il
  suo sacchetto.
- Sacchetto vuoto → la entry in `_flash` viene rimossa al `Save()` - la sessione
  non si riempie di spazzatura.
- **Richiede `HIX_MwSession`** attivo sulla route. Senza sessione, niente flash.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "memory" )
oSrv:Use( "HIX_MwSession" )

// Ora puoi usare UFlash() in qualsiasi action
```

---

## Pattern PRG completo (Fenix)

### POST → Update con flash

```clipper
METHOD Update() CLASS Customer

   LOCAL oVal, oCustomers, lSuccess, nId, cError := ""

   nId := Val( UParam( "id", "0" ) )

   oVal := UValidatePost( { ;
      "first" => "required|string|max:20|field", ;
      "last"  => "required|string|max:20|field", ;
      "city"  => "required|string|max:30|field"  ;
   } )

   IF ! oVal:Make()
      // Validazione fallita - flash errori + input + redirect alla modifica
      UFlash("customer"):Set( { ;
         "type"   => "danger",          ;
         "errors" => oVal:GetErrors(),  ;
         "input"  => oVal:Resume()      ;
      } )
      RETURN URedirect( URoute( "customer.edit", nId ) )
   ENDIF

   oCustomers := TCustomers()
   lSuccess   := oCustomers:Update( nId, oVal:DataFields(), @cError )

   IF lSuccess
      UFlash("customer"):Set( { ;
         "type"    => "success",                                       ;
         "message" => "Cliente " + LTrim( Str( nId ) ) + " aggiornato!" ;
      } )
      RETURN URedirect( URoute( "customer.show", nId ) )
   ELSE
      // Errore database - flash errore + input (non perdere ciò che era stato scritto)
      UFlash("customer"):Set( { ;
         "type"    => "danger",        ;
         "message" => cError,          ;
         "input"   => oVal:Resume()    ;
      } )
      RETURN URedirect( URoute( "customer.edit", nId ) )
   ENDIF

RETURN NIL
```

### GET → Edit consuma il flash

```clipper
METHOD Edit() CLASS Customer

   LOCAL oVal, oCustomers, lFound, oFlash, hInput, nId
   LOCAL hRow     := {=>}
   LOCAL hMessage := {=>}
   LOCAL hErrors  := {=>}

   oVal := UValidateParams( { "id" => "required|numeric" } )
   IF ! oVal:Make()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF
   nId := oVal:Get( "id" )

   oCustomers := TCustomers()
   lFound     := oCustomers:GetRecno( nId, @hRow, NIL, .T. )

   IF ! lFound
      hRow := oCustomers:Blank( .T. )
   ENDIF

   // Consuma il flash nel controller, la view solo disegna
   oFlash := UFlash( "customer" )

   hMessage[ "type" ]    := oFlash:Get( "type" )
   hMessage[ "message" ] := oFlash:Get( "message" )
   hErrors               := oFlash:Get( "errors" )

   // Se c'è un input flashato → ha priorità sul database (ripopola il form)
   hInput := oFlash:Get( "input" )
   IF hb_IsHash( hInput )
      hRow := hInput
   ENDIF

RETURN USendView( "views/masters/customer/edit.html", ;
                  lFound, hRow, hMessage, hErrors )
```

> **Elabora il flash nel controller, non nella view.** La view è
> "stupida": riceve `hRow`, `hMessage` e `hErrors` già preparati. Questo
> permette allo stesso template di servire sia CREATE (senza flash) che EDIT
> (con o senza flash) senza che la view sappia nulla.

---

## Pattern utili

### Banner di successo dopo il login

```clipper
FUNCTION _LoginAction()
   LOCAL hUser := _CheckCredentials( UPost("user"), UPost("pass") )

   IF hUser == NIL
      UFlash("login"):Set( { ;
         "type"    => "danger",                ;
         "message" => "Credenziali non valide"  ;
      } )
      RETURN URedirect( URoute( "auth.login" ) )
   ENDIF

   USession():Set( "user_id", hUser["id"] )
   USession():Save()

   UFlash("dashboard"):Set( { ;
      "type"    => "success",                                ;
      "message" => "Ciao " + hUser["name"] + ", benvenuto!"  ;
   } )

   RETURN URedirect( URoute( "dashboard" ) )
```

### Flash tra domini diversi

Ogni form / modulo usa il suo `cFormId` per evitare interferenze:

```clipper
UFlash("customer"):Set( { "message" => "Cliente OK" } )
UFlash("invoice"):Set(  { "message" => "Fattura OK" } )

// Il controller del cliente legge solo "customer", quello della fattura solo "invoice"
```

### Flash multi-step (wizard)

Preserva l'input attraverso più step passando `_HixCheckpoint` tra di essi:

```clipper
// Step 1
UFlash("wizard"):Set( { "step1" => oVal:Resume() } )
URedirect( "/wizard/step2" )

// Step 2 - leggi step1 e aggiungi step2
LOCAL hStep1 := UFlash("wizard"):Get( "step1" )
UFlash("wizard"):Set( { "step1" => hStep1, "step2" => oVal:Resume() } )
URedirect( "/wizard/step3" )
```

> Ogni `Get` consuma - se vuoi mantenerlo, flashalo di nuovo. Alcuni framework
> hanno `keep()` / `reflash()`; in HIX il pattern è leggi + set di nuovo.

---

## Errori comuni

| Sintomo | Causa |
|---|---|
| Il flash non appare dopo il redirect | Manca `HIX_MwSession` sulla route GET di destinazione |
| Il messaggio appare due volte | Hai chiamato `Get()` e poi `USendView` senza salvare in una variabile; lo hai consumato senza inviarlo |
| I dati persistono tra login diversi | Hai usato lo stesso `cFormId` in entrambi - le sessioni sono isolate ma il sacchetto viene riutilizzato se non lo pulisci |
| `Get()` ritorna `""` anche se hai appena fatto `Set()` | Il `Set` è stato fatto in un altro thread / processo; il flash vive nella sessione della request corrente |
| Il cookie `HIXSID` non arriva al GET | Dopo `Save()` la sessione è serializzata, ma se fai `URedirect` senza return, il Set-Cookie non viene inviato |

---

## Best practice

1. **Un `cFormId` per contesto.** `"customer"`, `"invoice"`, `"login"` —
   nomi semantici, non generici come `"main"`.
2. **Elabora il flash nel controller.** La view disegna solo ciò che riceve;
   se legge il flash direttamente, non è più riutilizzabile.
3. **Fai sempre il flash dell'input sugli errori.** Insieme a `errors`, flasha
   `oVal:Resume()` per ripopolare il form. Niente di peggio che un utente
   che riscrive 20 campi.
4. **Messaggi brevi e tipati.** Convenzione `{ "type" => "success|danger|warning|info", "message" => "..." }` - la view disegna il banner in base a `type`.
5. **Non abusarne.** Il flash è per "una singola lettura". Se devi mostrare
   un messaggio molte volte, memorizzalo in sessione / cookie / database direttamente.
6. **Il logout pulisce.** Quando chiudi la sessione, chiama `USession():Destroy()` -
   il flash scompare con la sessione.
