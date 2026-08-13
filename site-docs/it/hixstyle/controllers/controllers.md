# 🎮 Controller

## 📂 `<root>/controllers`

Un **controller** in HIX è l'unità di codice che riceve una request HTTP, la elabora
e restituisce una risposta. È il ponte tra una **route** (l'URL) e la **logica di business**
(model, database, servizi esterni).

Mentre una route dice *"quando arriva `GET /customer/:id`, fai qualcosa"*, il
controller è il *"qualcosa"* - il codice effettivo che esegue quell'intento.

> Un controller in HIX **non è obbligatoriamente una classe**. Può andare da un codeblock
> di una sola riga fino a un file `.prg` con classi e metodi per implementare un CRUD
> completo. Usa il formato più adatto alla dimensione dell'endpoint.

---

## Ciclo di vita di una request

Quando arriva una request HTTP, HIX esegue questa sequenza:

```
HTTP Request
   │
   ▼
┌──────────────────┐
│      Router      │  cerca la route che corrisponde a URL + metodo
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    Middleware    │  catena di MW (auth, CORS, RateLimit, Session...)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    Controller    │  ← sei qui
│  ─────────────   │
│  1. Raccolta     │  UGet, UPost, UParam, UHeader, UCookie, UJson...
│     dati         │
│  2. Validazione  │  UValidate, UValidatePost, UValidateParams...
│  3. Elaborazione │  model (TCustomers, TStates...), logica di business
│  4. Output       │  UView, USendJson, URedirect, USendError
└────────┬─────────┘
         │
         ▼
HTTP Response
```

Il controller è la **fase 3**: il codice che viene eseguito una volta identificata la route
e ottenuto il via libera dai middleware.

---

## Come viene invocato un controller da una route

Il terzo parametro di `AddRouteXxx` (`bAction`) definisce **quale controller** viene eseguito.
HIX accetta diversi formati:

### 1. Codeblock inline

Per endpoint banali.

```clipper
oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )
```

### 2. File `.prg` con `Main()`

Path relativo alla web root (`www/`). HIX compila al volo ed esegue `Main()`.

```clipper
oSrv:AddRouteGet( "main", "/main", "controllers/main.prg" )
```

Nel file di configurazione delle route in `/routes`
```json
{ "name": "logout", "url": "/logout", "action": "controllers/logout.prg" }
```

### 3. Metodo di classe - `method@class.prg`

Variante più professionale per raggruppare le action della stessa risorsa (CRUD).

```json
[
   { "name": "customer.search", "url": "/customer/search",     "method": "GET",  "action": "search@customer.prg" },
   { "name": "customer.show",   "url": "/customer/:id",        "method": "GET",  "action": "show@customer.prg"   },
   { "name": "customer.edit",   "url": "/customer/:id/edit",   "method": "GET",  "action": "edit@customer.prg"   },
   { "name": "customer.update", "url": "/customer/update",     "method": "POST", "action": "update@customer.prg" },
   { "name": "customer.create", "url": "/customer/create",     "method": "GET",  "action": "create@customer.prg" },
   { "name": "customer.store",  "url": "/customer",            "method": "POST", "action": "store@customer.prg"  },
   { "name": "customer.delete", "url": "/customer/delete",     "method": "POST", "action": "delete@customer.prg" }
]
```

> 📖 Pattern completi di route in [Route](../routes/routes.md).

---

## Formato semplice - `Main()`

Un file `.prg` con una funzione `Main()` che esegue l'intera action. Esempio reale: il
**login**.

### `controllers/login.prg` - mostra il form

```clipper
/*-----------------------------------------------------------
  File ......: login.prg
  Description: GET /login - carica l'errore/username flash
                impostato da auth.prg in caso di login fallito.
  Usage      : GET /login
 -----------------------------------------------------------*/

FUNCTION Main()
   LOCAL oFlash
   LOCAL cError
   LOCAL cUser

   oFlash := UFlash( "login" )
   cError := oFlash:Get( "error" )
   cUser  := oFlash:Get( "user"  )
   oFlash:Save()

RETURN UView( "sys/login.view.html", cUser, cError )
```

### `controllers/auth.prg` - processa il POST

Pattern **PRG** (Post / Redirect / Get): un POST non restituisce mai HTML, reindirizza
sempre. Questo impedisce che premendo F5 il form venga reinviato.

```clipper
/*-----------------------------------------------------------
  File ......: auth.prg
  Description: Controller di login - valida le credenziali e
                avvia una sessione.
  Usage      : POST /login  (campi form: username, password)
 -----------------------------------------------------------*/

#include "hbclass.ch"

FUNCTION Main()
   LOCAL oVal, oSess, hUser

   // 1. Valida input
   oVal := UValidatePost( { ;
      "username" => { "required|min:3|max:30", "Username", "" }, ;
      "password" => { "required|min:4",        "Password", "" }  ;
   } )

   IF ! oVal:Make()
      UFlash( "login" ):Set( { ;
         "error" => oVal:GetFirstError(),  ;
         "user"  => oVal:Get( "username" ) ;
      } )
      URedirect( "/login" )
      RETURN
   ENDIF

   // 2. Cerca l'utente nel model
   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   // 3. Risposta - reindirizza sempre
   IF ValType( hUser ) == "H"
      oSess := USession()
      oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
      oSess:Save()
      URedirect( UMwConfig( "auth", "redirect_accept" ) )
   ELSE
      UFlash( "login" ):Set( { ;
         "error" => "Username o password non validi", ;
         "user"  => oVal:Get( "username" )           ;
      } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )
   ENDIF

RETURN

#include '/models/modeluser.prg'
```

### `controllers/logout.prg` - distruggi la sessione

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

> 💡 **Pattern PRG**: dopo un `POST` non restituire mai HTML - fai sempre `URedirect` con
> messaggi flash. Nelle API JSON è diverso: lì rispondi direttamente con JSON.

---

## Formato CRUD - `method@class.prg`

Quando una risorsa ha più action (search, edit, create, delete, ecc.), vengono tutte
raggruppate in una classe. HIX chiama il metodo indicato nella route.

Header tipico con la tabella di routing per la risorsa:

```clipper
/*
 | Nome Route      | URL              | Metodo | Funzione         | Descrizione   |
 | --------------- | ---------------- | ------ | ---------------- | ------------- |
 | customer.search | /customer/search | GET    | search@customer  | Ricerca       |
 | customer.show   | /customer/:id    | GET    | show@customer    | Mostra uno    |
 | customer.edit   | /customer/:id/edit | GET  | edit@customer    | Form modifica |
 | customer.update | /customer/update | POST   | update@customer  | Aggiorna      |
 | customer.create | /customer/create | GET    | create@customer  | Form creazione|
 | customer.store  | /customer        | POST   | store@customer   | Salva nuovo   |
 | customer.delete | /customer/delete | POST   | delete@customer  | Elimina       |
*/

#include 'hbclass.ch'

CLASS Customer

   METHOD New()        CONSTRUCTOR
   METHOD End()

   METHOD Search()
   METHOD Show()
   METHOD Edit()
   METHOD Update()
   METHOD Create()
   METHOD Store()
   METHOD Delete()
   METHOD Destroy()

ENDCLASS

METHOD New() CLASS Customer
RETU Self

METHOD End() CLASS Customer
RETU Self
```

---

## 1. Raccolta dati dalla request

Dentro il controller usi gli helper `U*` per leggere qualsiasi dato della request
senza bisogno di passare `oReq`: il dispatcher lo lascia nel thread corrente.

| Sorgente | Helper | Esempio |
|---|---|---|
| Variabile di route `:var` | `UParam(k, def)` | `UParam("id")` |
| Query string `?k=v` | `UGet(k, def)` | `UGet("page", "1")` |
| Body POST (form o JSON) | `UPost(k, def)` | `UPost("first")` |
| Body JSON analizzato | `UJson()` | `hData := UJson()` |
| Body grezzo | `UBody()` | `cRaw := UBody()` |
| Header HTTP | `UHeader(k, def)` | `UHeader("X-Api-Key")` |
| Cookie | `UCookie(name, def)` | `UCookie("auth_token")` |
| Upload multipart | `UFiles()` | `aFiles := UFiles()` |
| Sessione | `USession(k, def)` | `USession("user")` |
| ID risorsa firmato | `UGetResource()` | `cId := UGetResource()` |
| Metodo HTTP | `UMethod()` | `IF UMethod() == "POST"` |
| URL request | `UPath()`, `UQuery()` | |
| IP / host client | `UIP()`, `UHost()` | |

Esempio dal controller Fenix `main.prg`, che legge l'utente dalla sessione tramite
`URequest():hData`:

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Sconosciuto", "roles" => {=>} } )
   LOCAL cName := hUser['name']
   LOCAL cKey, cRoles := ''

   FOR EACH cKey IN hUser["roles"]
      cRoles += cKey:__enumKey() + " "
   NEXT

   IF Empty( cRoles ) ; cRoles := "(nessuno)" ; ENDIF

RETU UView( 'main.view.html', cName, hUser, cRoles )
```

> 📖 Catalogo completo degli helper in
> [Mappa helper U*](../../programacion/mapa-helpers.md).

---

## 2. Validazione

Prima di elaborare qualsiasi dato, devi validarlo. HIX include un validator integrato
con sintassi dichiarativa e formato esteso `{ "regole", "Etichetta", "default" }`.

### Formato esteso delle regole

```clipper
oVal := UValidatePost( { ;
   "username" => { "required|min:3|max:30", "Username", "" }, ;
   "password" => { "required|min:4",        "Password", "" }  ;
} )
```

- `"required|min:3|max:30"` - stringa di regole separate da `|`
- `"Username"` - etichetta umana usata nei messaggi di errore
- `""` - valore di default se non fornito

### Pattern tipico - Validate + Flash + Redirect

```clipper
METHOD Update() CLASS Customer

   LOCAL cId := UGetResource()        // ID firmato del record
   LOCAL oVal, nId, cError, lSuccess
   LOCAL oCustomers

   // Valida il resource_id (validator single-field)
   IF Empty( cId )
      RETU URedirect( URoute( 'main' ) )
   ENDIF

   oVal := UValidatorOne( 'Id', cId, "required|number|min:0" )
   IF oVal:Fails()
      RETU URedirect( URoute( 'customer.search' ) )
   ENDIF
   nId := oVal:Get()

   // Valida i campi del form
   oVal := UValidatePost( {                                    ;
      "_deleted" => "required|logic|resume",                   ;
      "first"    => "required|string|max:20|field",            ;
      "last"     => "required|string|max:20|field",            ;
      "street"   => "required|string|max:30|field",            ;
      "city"     => "required|string|max:30|field",            ;
      "state"    => "required|string|max:2|field",             ;
      "zip"      => "required|string|max:10|field",            ;
      "hiredate" => "required|date|field",                     ;
      "married"  => "logic|field",                             ;
      "age"      => "required|numeric|max:70|field",           ;
      "notes"    => "string|escapedfield"                      ;
   }, { 'dummy' => 'upper|trim', 'first' => 'lower' } )

   IF ! oVal:Make()
      UFlash( "customer" ):Set( {                ;
         "type"    => 'danger',                  ;
         "message" => 'Errore di validazione',    ;
         "errors"  => oVal:GetErrors(),          ;
         "input"   => oVal:Resume()              ;
      } )
      RETU URedirect( URoute( 'customer.edit', nId ) )
   ENDIF

   // ... continua con l'elaborazione
```

### Modificatori utili delle regole

| Suffisso | Effetto |
|---|---|
| `\|field` | Include il campo in `oVal:DataFields()` (hash pronto per insert/update) |
| `\|escapedfield` | Come sopra + fa l'escape HTML del valore |
| `\|resume` | Lo include in `oVal:Resume()` (per ripopolare il form in caso di errore) |

### Metodi chiave di `oVal`

| Metodo | Scopo |
|---|---|
| `Make()` | Esegue la validazione; ritorna `.T./.F.` |
| `Fails()` | `.T.` se ci sono errori |
| `Get(k)` | Valore validato di un campo |
| `GetErrors()` | Hash con gli errori per campo |
| `GetFirstError()` | Primo errore come stringa (utile per flash nei login) |
| `DataFields()` | Hash con i campi marcati `\|field` (per `Insert/Update`) |
| `Resume()` | Hash con tutti i campi (per ripopolare il form al ritorno) |

> 📖 Regole complete, sanificazione e casi avanzati in [Validator](validator.md).

---

## 3. Elaborazione - logica di business

Il controller orchestra, non implementa. Chiama i **model** (`TCustomers`, `TStates`,
`ModelUser`, ecc.) che incapsulano tutta la logica sui dati.

```clipper
METHOD Show() CLASS Customer

   LOCAL oVal, oCustomers, oStates, oFlash
   LOCAL hRow      := {=>}
   LOCAL hMessage  := {=>}
   LOCAL lFound

   // 1. Valida l'id
   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      UFlash( "customer" ):Set( {                ;
         "errors"  => oVal:GetErrors(),          ;
         "message" => "Errore di validazione",   ;
         "input"   => oVal:Resume()              ;
      } )
      RETURN URedirect( URoute( 'customer.search' ) )
   ENDIF

   // 2. Cerca nel model
   oCustomers := TCustomers()
   lFound := oCustomers:GetRecno( oVal:Get( 'id' ), @hRow, NIL, .T. )

   IF lFound
      // Arricchisci con dati correlati
      oStates := TStates()
      oStates:Seek( hRow[ 'state' ], NIL, 'code' )
      hRow[ 'state_txt' ] := oStates:FieldGet( 'name' )

      // Recupera il flash da operazioni precedenti
      oFlash := UFlash( 'customer' )
      hMessage[ 'type'    ] := oFlash:Get( 'type'    )
      hMessage[ 'message' ] := oFlash:Get( 'message' )
   ELSE
      hRow := oCustomers:Blank( .T. )
      hRow[ 'state_txt' ] := ''
   ENDIF

   // 3. Output - renderizza la view
RETU UView( 'masters/customer/show.html', lFound, hRow, hMessage )
```

Best practice:

- **Controller sottile, model grasso.** Persistenza e regole complesse vivono nel
  model (`TCustomers:Insert`, `:Update`, `:Delete`, ...), non nel controller.
- **Una action = un intento HTTP.** Se un metodo fa tre cose, di solito sono
  tre action distinte.
- **Errori con `URedirect` + flash** nei form HTML; **`USendError(n, txt)`
  + `RETURN`** nelle API JSON.
- **Carica i model alla fine**: `#include 'models/tcustomers.prg'` alla chiusura del
  file così vengono compilati insieme al controller.

---

## 4. Output - invio della risposta

L'ultimo passo del controller invia la risposta al client.

### Strategia per tipo di endpoint

| Tipo di endpoint | Pattern |
|---|---|
| GET che renderizza HTML | `RETURN UView( "path/view.html", arg1, arg2, ... )` |
| POST che modifica dati | `URedirect( URoute( "destinazione" ) )` + flash |
| API REST | `USendJson( hash [, nStatus] )` |
| DELETE riuscito (API) | `USendEmpty()` (204) |
| Errore HTTP (API) | `USendError( nStatus, cDetail )` |

### View - `UView`

`UView` renderizza un template `.html` con il motore Mambo. Gli argomenti posizionali
vengono passati così come sono al template (dichiarati con `@args`).

```clipper
// GET /customer/:id/edit
METHOD Edit() CLASS Customer

   LOCAL oVal, oCustomers, oStates, lFound, oFlash
   LOCAL aStates  := {}
   LOCAL hMessage := {=>}
   LOCAL hRow     := {=>}
   LOCAL hErrors  := {=>}
   LOCAL hInput

   oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" } } )
   IF ! oVal:Make()
      RETU URedirect( URoute( 'customer.search' ) )
   ENDIF

   // Recupera il flash se arriviamo da un POST con errore
   oFlash := UFlash( 'customer' )
   hMessage[ 'type'    ] := oFlash:Get( 'type'    )
   hMessage[ 'message' ] := oFlash:Get( 'message' )
   hInput                := oFlash:Get( 'input'   )
   hErrors               := oFlash:Get( 'errors', {=>} )

   // Carica le combo
   oStates := TStates()
   aStates := oStates:LoadAll()

   // Se c'è input (arriviamo da un Update con errore), ridisegna il form con i dati
   IF ! Empty( hInput )
      RETU UView( 'masters/customer/edit.html', 'edit', .T., hInput, aStates, hMessage, hErrors )
   ENDIF

   oCustomers := TCustomers()
   lFound := oCustomers:GetRecno( oVal:Get( 'id' ), @hRow, NIL, .T. )

   IF ! lFound
      hRow := oCustomers:Blank( .T. )
   ENDIF

RETU UView( 'masters/customer/edit.html', 'edit', lFound, hRow, aStates, hMessage, hErrors )
```

### Redirect con `URoute`

Usa sempre `URoute( cName, ... )` invece di literal - così se l'URL cambia
lo tocchi solo nella definizione della route.

```clipper
URedirect( URoute( 'customer.show', nId ) )       // -> /customer/42
URedirect( URoute( 'customer.search' ) )          // -> /customer/search
```

### Messaggi flash

Messaggi che vengono salvati in sessione e consumati solo una volta nella request successiva.
Essenziali per mantenere messaggi attraverso un `URedirect`.

```clipper
// Dopo un POST riuscito
UFlash( "customer" ):Set( { ;
   "type"    => 'success',                                       ;
   "message" => 'Cliente ' + LTrim( Str( nId ) ) + ' aggiornato!' ;
} )
RETU URedirect( URoute( 'customer.show', nId ) )
```

### API JSON

Quando l'endpoint è una API REST invece di un form web:

```clipper
// Risposta JSON semplice
USendJson( { "id" => 42, "name" => "Carles" } )

// Con status personalizzato
USendJson( { "id" => nNewId }, 201 )

// Errore
USendError( 404, "Prodotto non trovato" )

// DELETE riuscito
USendEmpty()
```

### Streaming a chunk (SSE, download)

```clipper
USendStreamStart( "text/event-stream", 200, ;
   { "Cache-Control" => "no-cache", "X-Accel-Buffering" => "no" } )

DO WHILE lRunning
   USendChunk( "data: " + hb_jsonEncode( hMsg ) + hb_eol() + hb_eol() )
   hb_idleSleep( 1 )
ENDDO

USendStreamEnd()
```

---

## Pattern completo - CRUD Customer

Combina tutto: validazione, model, flash, redirect, view. Implementazione reale del
metodo **`Store`** (creazione) di Fenix:

```clipper
METHOD Store() CLASS Customer

   LOCAL oVal, oCustomers, oStates, cError, lSuccess, nRecno

   // 1. Validazione
   oVal := UValidatePost( {                                ;
      "first"    => "required|string|max:20|field",        ;
      "last"     => "required|string|max:20|field",        ;
      "street"   => "required|string|max:30|field",        ;
      "city"     => "required|string|max:30|field",        ;
      "state"    => "required|string|max:2|field",         ;
      "zip"      => "required|string|max:10|field",        ;
      "hiredate" => "required|date|field",                 ;
      "married"  => "logic|field",                         ;
      "age"      => "required|numeric|max:70|field",       ;
      "notes"    => "string|escapedfield"                  ;
   }, { 'first' => 'lower' } )

   IF ! oVal:Make()
      UFlash( "customer" ):Set( {              ;
         "type"    => 'danger',                ;
         "message" => 'Errore di validazione',  ;
         "errors"  => oVal:GetErrors(),        ;
         "input"   => oVal:Resume()            ;
      } )
      RETU URedirect( URoute( 'customer.create' ) )
   ENDIF

   // 2. Elaborazione - insert nel model
   oCustomers := TCustomers()
   lSuccess := oCustomers:Insert( oVal:DataFields(), @cError, @nRecno )

   // 3. Output - redirect in base al risultato
   IF lSuccess
      UFlash( "customer" ):Set( {                                            ;
         "type"    => 'success',                                             ;
         "message" => 'Cliente ' + LTrim( Str( nRecno ) ) + ' creato!'        ;
      } )
      RETU URedirect( URoute( 'customer.show', nRecno ) )
   ENDIF

   UFlash( "customer" ):Set( {              ;
      "type"    => 'danger',                ;
      "message" => cError,                  ;
      "errors"  => {=>},                    ;
      "input"   => oVal:Resume()            ;
   } )
RETU URedirect( URoute( 'customer.create' ) )
```

E alla fine del file, i model che il controller usa:

```clipper
#include 'models/tcustomers.prg'
#include 'models/tstates.prg'
```

---

## Best practice

1. **Un file per risorsa.** `customer.prg` raggruppa tutte le action per la
   risorsa `customer`. Nomi metodi RESTful: `Search`, `Show`, `Edit`, `Update`,
   `Create`, `Store`, `Delete`.

2. **Pattern PRG (Post / Redirect / Get).** Un POST non restituisce mai HTML - reindirizza
   sempre (successo o fallimento). Questo impedisce i reinvii quando si preme F5.

3. **Flash + URoute per mantenere lo stato.** Messaggi, errori e input passano
   tra le request con `UFlash(formId):Set({...})` prima del `URedirect( URoute(...) )`.

4. **ID risorsa firmati.** Nei form di edit/delete usa `UGetResource()`
   invece di passare ID in chiaro - impedisce modifiche manuali dell'HTML.

5. **`LOCAL` all'inizio.** Harbour richiede tutte le dichiarazioni `LOCAL` prima
   di qualsiasi statement eseguibile. Non dichiarare LOCAL dentro gli IF.

6. **Prima valida, poi elabora.** Se la validazione fallisce, flash + redirect
   (web) o `USendJson(...,422)` (API). Interrompi il prima possibile.

7. **Tabella di routing nell'header del controller.** Il blocco di commento
   all'inizio della classe documenta tutti gli URL della risorsa a colpo d'occhio.

8. **Logica fuori dal controller.** Le classi `Txxx` (model) implementano
   `:Insert`, `:Update`, `:Delete`, `:GetRecno`, `:Blank`, ecc. Il controller le
   orchestra soltanto.

9. **Centralizza URL e redirect nella configurazione.** `UMwConfig( "auth", "redirect_login" )`
   permette di cambiare le destinazioni senza toccare il codice.

10. **`#include 'models/xxx.prg'`** alla fine del controller così i model vengono
    compilati insieme al file.
