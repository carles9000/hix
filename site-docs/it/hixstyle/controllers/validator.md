# ✔️ HIX Validator - Tutorial completo

Il **validator** di **HIX** permette di validare e pulire i dati di input HTTP in tre fasi ordinate:
**cast** (conversione di tipo), **validazione** (regole) e **sanitizzazione** (trasformazioni di pulizia).
Tutto si concatena con una sintassi di regole in stringa separate da `|`.

---

## 1. Concetto base

```clipper
LOCAL oVal := UValidateOrFail( {
   "name"  => "required|string|max:100",
   "email" => "required|string|email",
   "age"   => "required|integer|min:18"
} )
IF oVal == NIL ; RETURN NIL ; ENDIF   // ha già risposto 422

cName  := oVal:Get( "name" )
cEmail := oVal:Get( "email" )
nAge   := oVal:Get( "age" )           // tipo N, non stringa
```

`UValidateOrFail` è la via più breve: esegue `Make()`, e se ci sono errori invia
automaticamente un JSON 422 e ritorna `NIL`. Se passa, ritorna l'oggetto validator con i valori
già convertiti al tipo corretto.

---

## 2. Sorgenti di input

Ogni helper cattura i dati di input da una sorgente diversa della request corrente.

| Funzione | Sorgente primaria | Parametri di route `:var` |
|---|---|---|
| `UValidatePost(hRules)` | Body POST: form-urlencoded prima, JSON come fallback | inclusi |
| `UValidateGet(hRules)` | Query string (`?key=val`) | inclusi |
| `UValidateJson(hRules)` | Solo body JSON | inclusi |
| `UValidateOrFail(hRules)` | Body POST - esegue Make() e risponde 422 se fallisce | inclusi |
| `UValidateParams(hRules)` | Alias di `UValidateGet` (compatibilità) | inclusi |

Tutti accettano un secondo parametro opzionale `hSanitate` (vedi sezione 6).

Tutti gli helper uniscono sempre le variabili di route (`:id`, `:slug`...) in `hInput`
dopo aver letto la sorgente primaria. Se la stessa chiave esiste in entrambe le sorgenti viene
sollevato un errore 500 per far emergere subito il conflitto di naming.

### UValidatePost vs UValidateJson

`UValidatePost` rileva automaticamente il formato: prova prima form-urlencoded e, se
vuoto, fa fallback su JSON. È l'helper universale per endpoint che accettano
entrambi i formati.

`UValidateJson` legge il body come JSON esclusivamente. Se il body non è JSON valido,
`hInput` resta vuoto e ogni campo `required` fallisce con un normale 422.
Usalo quando l'endpoint è una pura API che richiede JSON.

```clipper
// Endpoint che accetta form E json
oVal := UValidatePost( hRules )

// Pura API — solo JSON
oVal := UValidateJson( hRules )
IF ! oVal:Make()
   USendJson( { "errors" => oVal:GetErrors() }, 422 )
   RETURN NIL
ENDIF
```

### UValidateGet — query string e parametri di route

`UValidateGet` unisce la query string con le variabili di route in un unico hash,
coprendo tutti gli scenari di endpoint GET in una sola chiamata:

```clipper
// GET /products?page=2&q=book  (no :vars)
oVal := UValidateGet( { "page" => "optional|integer|min:1", "q" => "optional|string" } )

// GET /users/:id?expand=roles  (query + :id combinati)
oVal := UValidateGet( { "id" => "required|integer|positive", "expand" => "optional|string" } )

// POST /resource/:id con body JSON  (body + :id combinati)
oVal := UValidatePost( { "id" => "required|integer", "name" => "required|string" } )
```

---

## 3. Flusso completo con Make()

Quando hai bisogno di controllare manualmente la risposta di errore:

```clipper
FUNCTION _UpdateUser()
   LOCAL oVal, hData

   oVal := UValidatePost( {
      "name"  => "required|string|max:100",
      "email" => "required|string|email"
   } )

   IF ! oVal:Make()
      // opzione A - risposta JSON standard
      USendJson( { "errors" => oVal:GetErrors() }, 422 )
      RETURN NIL

      // opzione B - solo il primo errore
      USendError( 422, oVal:GetFirstError() )
      RETURN NIL
   ENDIF

   hData := oVal:Validated()   // hash con tutti i campi validati
   // ... salva hData ...
   USendJson( { "ok" => .T. } )
RETURN NIL
```

---

## 4. Regole di validazione

Le regole si scrivono separate da `|` in una stringa. L'ordine conta: le regole sono valutate
da sinistra a destra e si fermano al primo errore sul campo.

### Presenza

| Regola | Descrizione |
|---|---|
| `required` | Il campo deve esistere e non essere vuoto |
| `optional` | Se il campo è vuoto, viene omesso senza errore. Deve venire prima |

```clipper
// Campo obbligatorio
"name" => "required|string"

// Campo opzionale - valida solo se fornito
"nickname" => "optional|string|max:50"
```

### Tipi (eseguono anche il cast, vedi sezione 5)

| Regola | Descrizione |
|---|---|
| `string` | Converte in stringa ed esegue `AllTrim` |
| `integer` | Converte in intero; fallisce se non è un numero intero |
| `numeric` / `decimal` | Converte in numero; accetta decimali |
| `boolean` / `bool` | Converte in logico `.T.`/`.F.` |
| `date` | Converte in data Harbour da `YYYY-MM-DD` |
| `positive` | Il valore deve essere `N > 0` |

### Lunghezza e range

| Regola | Si applica a | Descrizione |
|---|---|---|
| `min:N` | stringa: length >= N / numero: valore >= N | |
| `max:N` | stringa: length <= N / numero: valore <= N | |
| `minlen:N` | stringa | length >= N (indipendente dal tipo) |
| `maxlen:N` | stringa | length <= N |
| `between:N,M` | stringa o numero | tra N e M (lunghezza o valore) |

```clipper
"title"    => "required|string|min:3|max:200"
"price"    => "required|numeric|min:0|max:9999"
"score"    => "required|integer|between:1,10"
```

### Formato

| Regola | Descrizione |
|---|---|
| `email` | Formato email valido |
| `url` | Inizia con `http://` o `https://` |
| `ip` | IPv4 valido (quattro ottetti 0-255) |
| `regex:PATTERN` | Il valore deve corrispondere all'espressione regolare Harbour |

```clipper
"email"    => "required|string|email"
"web"      => "optional|string|url"
"subnet"   => "required|ip"
"code"     => "required|regex:[A-Z]{3}[0-9]{4}"
```

### Liste

| Regola | Descrizione |
|---|---|
| `in:a,b,c` | Il valore deve essere nella lista |
| `notin:a,b,c` | Il valore non deve essere nella lista |

```clipper
"role"     => "required|string|in:admin,editor,viewer"
"status"   => "required|string|notin:deleted,banned"
```

### Date

| Regola | Descrizione |
|---|---|
| `mindate:YYYY-MM-DD` | La data deve essere >= la data indicata |
| `maxdate:YYYY-MM-DD` | La data deve essere <= la data indicata |

```clipper
"birthday" => "required|date|maxdate:2010-01-01"
"start"    => "required|date|mindate:2026-01-01"
```

### Conferma

| Regola | Descrizione |
|---|---|
| `confirmed` | Cerca un campo `<field>_confirmation` nell'input e lo confronta |

```clipper
// Il form deve inviare "password" e "password_confirmation"
"password" => "required|string|min:8|confirmed"
```

### Regole con codeblock personalizzato

Quando nessuna regola standard va bene, puoi passare direttamente un codeblock:

```clipper
oVal := UValidatePost( {
   "username" => { "required|string",
                   "Username",   // etichetta per il messaggio d'errore
                   "",           // valore di default
                   {|v| iif( _UserExists(v), "Utente già esistente", .T. ) }
                 }
} )
```

Il codeblock riceve il valore e deve ritornare:
- `.T.` se la validazione passa
- `.F.` se fallisce (messaggio generico)
- `C` con il messaggio di errore se fallisce (messaggio personalizzato)

---

## 5. Cast di tipo (fase 1)

Il cast converte il valore da stringa HTTP al tipo Harbour corretto **prima** di validare.
Questo significa che dopo `Make()`, `oVal:Get("age")` ritorna un `N`, non un `C`.

| Regola di cast | Conversione |
|---|---|
| `string` | `AllTrim( UStr(v) )` |
| `integer` | `Val(v)` troncato a intero |
| `numeric` / `decimal` | `Val(v)` con punto decimale |
| `boolean` / `bool` | `"1","true","yes","on",".t."` → `.T.`; resto → `.F.` |
| `date` | `"YYYY-MM-DD"` o `"YYYY/MM/DD"` → data Harbour |

**Cast e validazione possono essere combinati**:

```clipper
// "integer" converte E valida che sia un intero
"qty"  => "required|integer|min:1|max:999"

// "boolean" converte; senza required, una checkbox non spuntata sarà .F.
"active" => "boolean"
```

---

## 6. Sanitizzazione (fase 3)

La sanitizzazione viene eseguita **dopo** che tutte le validazioni sono passate. Si definisce
nel secondo parametro dell'helper (`hSanitate`):

```clipper
oVal := UValidatePost(
   { "name" => "required|string", "bio" => "optional|string" },
   { "name" => "trim|upper",      "bio" => "trim|strip_tags" }
)
```

> **Nota:** I token di sanitizzazione scritti inline nella stringa di regole
> (`"required|string|trim|upper"`) vengono silenziosamente ignorati dal motore.
> L'unico modo per applicare la sanitizzazione è tramite il secondo parametro `hSanitate`.
> Il cast `string` applica `AllTrim()` internamente, ma `upper`/`lower`/ecc. richiedono
> `hSanitate`.

### Trasformazioni disponibili

| Regola | Descrizione |
|---|---|
| `trim` | `AllTrim()` - rimuove gli spazi all'inizio e alla fine |
| `ltrim` | `LTrim()` - solo gli spazi a sinistra |
| `rtrim` | `RTrim()` - solo gli spazi a destra |
| `upper` | `Upper()` |
| `lower` | `Lower()` |
| `strip_tags` | Rimuove i tag HTML (`<tag>` → `""`) |
| `slug` | Converte in slug URL-safe: `"Mio Titolo"` → `"mio-titolo"` |
| `nl2br` | Converte le interruzioni di riga in `<br>` |
| `escape` | Codifica i caratteri HTML (`<`, `>`, `&`, `"`) |
| `abs` | Valore assoluto di un numero |
| `round:N` | Arrotonda un numero a N decimali |

```clipper
"title"   => "required|string|trim|slug"      // "Mio Articolo!" -> "mio-articolo"
"content" => "required|string|trim|strip_tags"
"price"   => "required|numeric|abs|round:2"
"email"   => "required|string|trim|lower|email"
```

---

## 7. Marker speciali

### `field` e `escapedfield`

Segnano i campi che devono essere inclusi in `oVal:DataFields()`. Utili per ripopolare
i form HTML dopo un errore di validazione.

```clipper
oVal := UValidatePost( {
   "name"  => "required|string|max:100|field",
   "email" => "required|string|email|escapedfield"   // codificato in HTML
} )

// Se la validazione fallisce, i dati originali sono disponibili
hData := oVal:DataFields()  // { "name" => "Carles", "email" => "c&lt;a&gt;@..." }
```

### `resume`

Segna i campi che devono essere inclusi in `oVal:Resume()`. Usato per ripopolare i form
restituendo i dati (già castati) al template anche in caso di errore.

```clipper
"name"  => "required|string|max:100|resume"
"email" => "required|string|email|resume"

// Resume include i campi marcati con il valore già convertito al tipo corretto.
// Senza marker resume, Resume() ritorna l'hash di input originale non tradotto.
hResume := oVal:Resume()
```

---

## 8. Leggere i dati validati

Dopo un `Make()` riuscito:

| Metodo | Descrizione |
|---|---|
| `oVal:Get(cKey)` | Valore di un campo; `NIL` se non esiste |
| `oVal:Get(cKey, xDef)` | Valore di un campo con default |
| `oVal:Validated()` | Hash completo con tutti i campi validati |
| `oVal:Validated(aFields)` | Hash filtrato ai campi indicati |
| `oVal:DataFields()` | Hash dei campi marcati con `field`/`escapedfield` |
| `oVal:Resume()` | Hash per ripopolare i form (vedi marker `resume`) |

```clipper
// Ottieni singoli campi
cName  := oVal:Get( "name" )
nAge   := oVal:Get( "age", 0 )

// Ottieni tutti i campi validati
hAll   := oVal:Validated()

// Ottieni solo i campi di interesse
hSaved := oVal:Validated( { "name", "email", "age" } )
```

---

## 9. Gestione degli errori

| Metodo | Ritorna | Descrizione |
|---|---|---|
| `oVal:Passes()` | `L` | `.T.` se non ci sono errori |
| `oVal:Fails()` | `L` | `.T.` se ci sono errori |
| `oVal:IsValid()` | `L` | Alias di `Passes()` |
| `oVal:GetErrors()` | `H` | Hash `{ "field" => "messaggio" }` |
| `oVal:GetFirstError()` | `C` | Messaggio del primo errore |
| `oVal:GetErrorsJson()` | `C` | `GetErrors()` serializzato come JSON |
| `oVal:GetErrorsTxt()` | `C` | Tabella HTML con gli errori |
| `oVal:SendErrors(nStatus)` | - | Risponde JSON `{ errors }` con lo status indicato |
| `oVal:Formatter()` | `H` | Hash `{ "success", "errors" }` pronto per JSON |

```clipper
// Risposta JSON di errore standard
IF oVal:Fails()
   USendJson( oVal:Formatter(), 422 )
   RETURN NIL
ENDIF

// Solo il primo errore (per risposte semplici)
IF oVal:Fails()
   USendError( 422, oVal:GetFirstError() )
   RETURN NIL
ENDIF

// Errori per campo (per AJAX con feedback per campo)
IF oVal:Fails()
   USendJson( { "errors" => oVal:GetErrors() }, 422 )
   RETURN NIL
ENDIF
```

---

## 10. Etichette e default sui campi

La regola di un campo può essere un array di fino a 4 elementi:

```
{ "regole", "Etichetta", valoreDefault, codeblock }
```

```clipper
oVal := UValidatePost( {
   "name"  => { "required|string|max:100", "Nome completo" },
   "age"   => { "required|integer|min:18", "Età", 0 },
   "token" => { "required|string", "Token", NIL,
                {|v| iif( HIX_TokenValid(v, 3600), .T., "Token scaduto" ) }
              }
} )
```

- Il secondo elemento è l'etichetta che appare nei messaggi di errore.
- Il terzo è il valore di default quando il campo non esiste nell'input.
- Il quarto è un codeblock di validazione personalizzato.

---

## 11. Validare un singolo valore

`UValidatorOne` valida un singolo valore senza bisogno di costruire un hash:

```clipper
oVal := UValidatorOne( "Email", cEmail, "required|string|email" )
IF oVal:Fails()
   USendError( 422, oVal:GetFirstError() )
   RETURN NIL
ENDIF
```

---

## 12. Aggiungere campi al volo

Puoi arricchire un validator dopo averlo creato con `Add()`:

```clipper
oVal := UValidatePost( { "name" => "required|string" } )
oVal:Add( { "extra" => "optional|integer" }, UGet("extra") )
oVal:Make()
```

---

## 13. Pattern completi

### API REST - creazione risorsa

```clipper
FUNCTION _ProductCreate()
   LOCAL oVal, hProd

   oVal := UValidateOrFail( {
      "name"        => { "required|string|max:200|trim",     "Nome" },
      "price"       => { "required|numeric|min:0|round:2",   "Prezzo" },
      "stock"       => { "required|integer|min:0",           "Stock" },
      "category_id" => { "required|integer|positive",        "Categoria" },
      "active"      => { "boolean",                          "Attivo" }
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   hProd := oVal:Validated( { "name", "price", "stock", "category_id", "active" } )
   // ... insert hProd nel DB ...

   USendJson( { "id" => nNewId }, 201 )
RETURN NIL
```

### Form HTML con re-fill

```clipper
FUNCTION _RegisterPost()
   LOCAL oVal

   oVal := UValidatePost( {
      "username" => "required|string|min:3|max:50|trim|lower|resume",
      "email"    => "required|string|email|trim|lower|resume",
      "password" => "required|string|min:8|confirmed"
   } )

   IF ! oVal:Make()
      // salva il flash con errori e dati del form
      LOCAL oFlash := UFlash( "register" )
      oFlash:Set( "errors",  oVal:GetErrors() )
      oFlash:Set( "data",    oVal:Resume() )
      oFlash:Save()
      URedirect( "/register" )
      RETURN NIL
   ENDIF

   // ... crea utente ...
   URedirect( "/dashboard" )
RETURN NIL
```

```clipper
FUNCTION _RegisterGet()
   LOCAL oFlash  := UFlash( "register" )
   LOCAL hErrors := oFlash:Get( "errors", {=>} )
   LOCAL hData   := oFlash:Get( "data",   {=>} )
   USendView( "auth/register.view.html", {
      "hErrors"   => hErrors,
      "cUsername" => hb_HGetDef( hData, "username", "" ),
      "cEmail"    => hb_HGetDef( hData, "email",    "" )
   } )
RETURN NIL
```

### Validazione query string per ricerca paginata

```clipper
FUNCTION _ProductList()
   LOCAL oVal, nPage, nLimit, cQ

   oVal := UValidateGet( {
      "page"  => { "optional|integer|min:1",    "Pagina",  1 },
      "limit" => { "optional|integer|between:1,100", "Limite", 20 },
      "q"     => { "optional|string|max:200|trim", "Ricerca", "" }
   } )
   oVal:Make()   // non fallisce mai (tutti opzionali con default)

   nPage  := oVal:Get( "page" )
   nLimit := oVal:Get( "limit" )
   cQ     := oVal:Get( "q" )

   // ... query DB ...
   USendJson( { "page" => nPage, "limit" => nLimit, "results" => aResults } )
RETURN NIL
```

### Validazione con regola personalizzata contro DB

```clipper
FUNCTION _ChangeEmail()
   LOCAL oVal

   oVal := UValidateOrFail( {
      "email" => { "required|string|email|trim|lower",
                   "Email",
                   "",
                   {|v| iif( _EmailTaken(v), "L'email è già registrata", .T. ) }
                 }
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   cEmail := oVal:Get( "email" )
   // ... aggiorna email ...
   USendJson( { "ok" => .T. } )
RETURN NIL

STATIC FUNCTION _EmailTaken( cEmail )
   // query al DB e ritorna .T. se l'email è già usata
RETURN .F.
```

---

## 14. Riferimento rapido regole

```
-- Presenza --
required       optional

-- Tipi / cast --
string         integer        numeric/decimal
boolean/bool   date           positive

-- Range --
min:N          max:N
minlen:N       maxlen:N
between:N,M

-- Formato --
email          url            ip
regex:PATTERN

-- Liste --
in:a,b,c       notin:a,b,c

-- Date --
mindate:YYYY-MM-DD   maxdate:YYYY-MM-DD

-- Cross-field --
confirmed      (field_confirmation deve corrispondere)

-- Sanitizzazione (inline o in hSanitate) --
trim    ltrim   rtrim   upper   lower
strip_tags      slug    nl2br   escape
abs             round:N

-- Marker --
field          escapedfield   resume
```
