# ❔ Request

Una **request** è l'insieme dei dati che il client invia al server in ogni chiamata HTTP: l'URL,
il metodo (GET/POST/PUT/...), gli header, i cookie, i parametri della query string,
il body (form, JSON, multipart), i file caricati, l'IP del client...

In HIX, la request è rappresentata internamente con un oggetto `THixRequest`, ma il
modo **idiomatico** per leggerla dentro un controller non è accedere direttamente all'oggetto:
è usare gli helper `U*`.

> ✨ **Regola d'oro**: dentro un controller, **usa sempre** gli helper `U*` per leggere qualsiasi
> dato della request. Non hai bisogno (e non dovresti) catturare `oReq` nel codeblock - il
> dispatcher rende automaticamente disponibile la request del thread corrente agli helper.

```clipper
// CORRETTO - usa gli helper U*
oSrv:AddRouteGet( "user", "/user/:id", {|| USendJson( { "id" => UParam("id") } ) } )

// ERRATO - oReq non è disponibile nella closure
oSrv:AddRouteGet( "user", "/user/:id", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )
```

---

## Anatomia di una request HTTP

```
POST /customer/update?lang=it HTTP/1.1           ← metodo + path + query + versione
Host: app.example.com                            ← header
Content-Type: application/x-www-form-urlencoded  ←
Cookie: session_id=abc123; pref=dark             ←
X-Requested-With: XMLHttpRequest                 ←
Content-Length: 42                               ←
                                                 ← riga vuota = fine degli header
first=Carles&last=Aubia&age=42                   ← body
```

Ognuna di queste parti ha un helper corrispondente:

| Parte della request | Helper |
|---|---|
| Metodo (`POST`) | `UMethod()` |
| Path (`/customer/update`) | `UPath()` |
| Query string grezza (`lang=it`) | `UQuery()` |
| Header (`Content-Type`) | `UHeader( "content-type" )` |
| Cookie (`session_id`) | `UCookie( "session_id" )` |
| Body grezzo | `UBody()` |
| Body analizzato (form/JSON) | `UPost( "first" )` / `UJson()` |

---

## 1. Riga di request

### Metodo HTTP

```clipper
UMethod()           // -> "GET", "POST", "PUT", "DELETE", "PATCH"
UIsGet()            // -> .T. se GET
UIsPost()           // -> .T. se POST
```

Utile per action che accettano più metodi sulla stessa route:

```clipper
oSrv:AddRoute( "form", "/contact", {||
   IF UIsPost()
      _ProcessForm()
   ELSE
      USendView( "contact.view.html" )
   ENDIF
}, "GET,POST" )
```

### Path e query string

```clipper
UPath()             // -> "/customer/update"
UQuery()            // -> "lang=it&page=2"     (grezza, non analizzata)
```

`UPath()` ritorna l'URL **senza** la query string. Per leggere la query, usa `UGet`.

### Scheme, host e porta

```clipper
UScheme()           // -> "http" / "https"
UIsHttps()          // -> .T. / .F.
UHost()             // -> "app.example.com"   (header Host)
UPort()             // -> 443
UIP()               // -> "192.168.1.10" (rispetta X-Forwarded-For se mode=proxied)
```

---

## 2. Variabili di route - `UParam`

Quando una route dichiara segmenti variabili con `:name`, catturi il valore con
`UParam`.

```clipper
oSrv:AddRouteGet( "user.show", "/users/:id", {||
   LOCAL nId := Val( UParam( "id" ) )
   USendJson( _UserRepoFind( nId ) )
} )
```

| Forma | Comportamento |
|---|---|
| `UParam( cKey )` | Legge la variabile; se non esiste **solleva errore 400** |
| `UParam( cKey, xDef )` | Legge con un valore di default se non esiste |
| `UParam( 1 )` | Cattura dal wildcard `*` (equivalente a `UParam("_1")`) |
| `UParam()` | Hash con tutte le variabili di route |

```clipper
// Route: /products/:id([0-9]+)/edit
nId := Val( UParam( "id", "0" ) )         // con default sicuro

// Route: /docs/:section!  (opzionale)
cSection := UParam( "section", "intro" )

// Route: /static/*
cFile := UParam( 1 )                       // equivalente a UParam("_1")
```

> 📖 Pattern URL completi in [Route](../routes/routes.md).

---

## 3. Query string - `UGet`

Legge parametri dalla query string (`?key=value&...`).

```clipper
// URL: /search?q=carles&page=2&limit=20

cQ     := UGet( "q" )                     // "carles"
nPage  := Val( UGet( "page",  "1"  ) )    // 2
nLimit := Val( UGet( "limit", "20" ) )    // 20

// Senza argomenti -> hash completo
hAll := UGet()                            // { "q"=>"carles", "page"=>"2", "limit"=>"20" }
```

Ritorna sempre una **stringa**. Per gli interi, converti con `Val()`.

### Valida la query string in blocco

Quando ci sono più variabili, valida con `UValidateGet` o `UValidateParams`
(query + variabili di route unite).

```clipper
oVal := UValidateParams( { ;
   "id"   => { "required|number|min:0", "Id"   }, ;
   "lang" => { "in:it,en,es",           "Lang" } ;
} )
IF ! oVal:Make()
   RETU URedirect( URoute( 'home' ) )
ENDIF
nId   := oVal:Get( "id" )
cLang := oVal:Get( "lang" )
```

---

## 4. Body POST

### Form HTML - `UPost`

Quando il client invia `application/x-www-form-urlencoded` o `multipart/form-data`:

```clipper
// POST /login   first=Carles&password=secret

cUser := UPost( "username" )
cPass := UPost( "password" )

// Con default
cRole := UPost( "role", "viewer" )

// Hash completo
hAll := UPost()
```

`UPost` legge anche dal body se arriva come JSON (auto-rileva il `Content-Type`).

### Body JSON grezzo - `UJson`

Quando il client invia `Content-Type: application/json`:

```clipper
// POST /api/users  Content-Type: application/json
// Body: { "name": "Carles", "email": "x@y.com", "tags": ["admin","editor"] }

LOCAL hData := UJson()

IF hData == NIL
   RETURN USendError( 400, "JSON non valido" )
ENDIF

cName := hb_HGetDef( hData, "name", "" )
aTags := hb_HGetDef( hData, "tags", {} )
```

`UJson()` ritorna un hash, un array, o `NIL` se il body non è JSON valido.

### Body grezzo - `UBody`

Per integrazioni speciali (webhook firmati, payload binari, XML...):

```clipper
LOCAL cRaw  := UBody()
LOCAL cSig  := UHeader( "X-Signature" )

IF ! _VerifyHmac( cRaw, cSig, cSecret )
   RETURN USendError( 401, "Firma non valida" )
ENDIF

_ProcessWebhook( cRaw )
```

### Dimensione e tipo del body

```clipper
UContentType()      // "application/json"
UContentLength()    // 42 (byte)
UIsJson()           // .T. se Content-Type è application/json
UIsForm()           // .T. se application/x-www-form-urlencoded
UIsMultipart()      // .T. se multipart/form-data
```

---

## 5. Header - `UHeader`

Lettura **case-insensitive** di qualsiasi header HTTP.

```clipper
cAuth   := UHeader( "Authorization", "" )         // "Bearer abc123"
cAccept := UHeader( "Accept",        "" )         // "application/json"
cUA     := UHeader( "User-Agent",    "" )

// Content negotiation
UWantsJson()        // .T. se il client preferisce JSON (Accept o AJAX)
UIsAjax()           // .T. se X-Requested-With: XMLHttpRequest
```

Pattern tipico per rispondere con JSON o HTML a seconda del client:

```clipper
IF UWantsJson() .OR. UIsAjax()
   USendJson( { "error" => "Non autenticato" }, 401 )
ELSE
   URedirect( "/login" )
ENDIF
```

---

## 6. Cookie - `UCookie`

```clipper
cSid   := UCookie( "session_id", "" )
cTheme := UCookie( "pref_theme", "light" )
```

I cookie vengono analizzati **una sola volta** e messi in cache nella request (lazy). Chiamare
`UCookie` ripetutamente non comporta penalità.

> 📖 Come scrivere cookie nella risposta (`USetCookie`) in
> [Response > Cookies](../response/cookies.md).

---

## 7. Upload multipart - `UFiles`

Quando un form carica file con `enctype="multipart/form-data"`:

```clipper
LOCAL aFiles := UFiles()
LOCAL hFile

FOR EACH hFile IN aFiles
   // hFile["name"]  -> nome del campo form
   // hFile["data"]  -> contenuto binario
   // hFile["mime"]  -> Content-Type del file
   // hFile["size"]  -> dimensione in byte

   IF hFile["size"] > 5 * 1024 * 1024
      RETURN USendError( 413, "File troppo grande" )
   ENDIF

   hb_MemoWrit( "uploads/" + hFile["name"], hFile["data"] )
NEXT
```

I campi di testo dello stesso form si leggono con il normale `UPost`.

---

## 8. Dati del client e della sessione

### Identità del client

```clipper
UIP()              // IP reale (rispetta X-Forwarded-For in modalità proxy)
UHost()            // header Host
UScheme()          // "http" / "https"
UIsHttps()         // .T. se la connessione è sicura
```

### Sessione e utente autenticato

Quando il middleware di sessione e/o autenticazione è attivo:

```clipper
// Sessione
cUser := USession( "user" )                  // valore o NIL
USession():Set( "role", "admin" )
USession():Save()

// Utente autenticato (middleware HIX_MwAuth)
hUser := UAuthUser()                          // hash utente completo
cMail := UAuthUser( "email", "" )

IF ! UHasRole( "admin" )
   USendError( 403, "Solo admin" )
   RETURN
ENDIF

// JWT (middleware HixMwJwt)
cSub := UJwt( "sub" )
IF ! UHasScope( "read:products" )
   USendError( 403, "Scope insufficiente" )
   RETURN
ENDIF
```

> 📖 Dettagli in [Sessioni](../seguridad/sesiones.md), [Autenticazione](../seguridad/autenticacion.md)
> e [JWT](../seguridad/jwt.md).

---

## 9. Accesso low-level - `URequest` e `UContext`

Per casi speciali, puoi ottenere l'oggetto request o il contesto middleware.

### `URequest()` - l'oggetto `THixRequest`

```clipper
LOCAL oReq := URequest()

// Accesso diretto a hData (dati condivisi tra middleware e controller)
hUser := hb_HGetDef( oReq:hData, "user", NIL )

// Proprietà grezze
? oReq:cMethod, oReq:cPath, oReq:cQuery
```

Esempio reale (Fenix `main.prg`):

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Sconosciuto", "roles" => {=>} } )
   LOCAL cName := hUser['name']

   // ... usa hUser per costruire la view
RETU UView( 'main.view.html', cName, hUser )
```

### `UContext()` - il contesto middleware

Quando il middleware è attivo, i MW passano i dati al controller tramite `oCtx:hData["key"]`.
Dal controller, li leggi con `UContext()`:

```clipper
LOCAL oCtx := UContext()
LOCAL hJwt := oCtx:hData[ "jwt" ]              // payload impostato da HixMwJwt
LOCAL cSid := oCtx:hData[ "_sid" ]             // SID impostato da HixMwSession
```

Nella maggior parte dei casi, non hai bisogno di toccare `oCtx` direttamente: gli helper
`USession()`, `UJwt()`, `UAuthUser()` leggono già da lì.

---

## 10. Validazione della request

Una volta raccolti i dati, il passo successivo è **validarli** con il validator integrato.

| Helper | Fonte dati |
|---|---|
| `UValidate( hRules )` | POST (form o JSON) |
| `UValidatePost( hRules )` | POST esplicito |
| `UValidateGet( hRules )` | Query string |
| `UValidateParams( hRules )` | Query string + variabili di route |
| `UValidateJson( hRules )` | Body JSON esplicito |
| `UValidateOrFail( hRules )` | POST - risponde automaticamente 422 se fallisce e ritorna `NIL` |

Pattern **PRG** (Post / Redirect / Get) tipico per form web:

```clipper
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

// Dati validati disponibili via oVal:Get( cKey ) o oVal:DataFields()
```

Pattern tipico per API JSON:

```clipper
oVal := UValidateOrFail( {                  ;
   "name"  => "required|string|max:100",    ;
   "email" => "required|string|email",      ;
   "age"   => "required|integer|min:18"     ;
} )
IF oVal == NIL ; RETURN NIL ; ENDIF        // ha già risposto 422

USendJson( _UserCreate( oVal:DataFields() ), 201 )
```

> 📖 Regole, modificatori e casi avanzati in [Validator](validator.md).

---

## 11. Riferimento rapido helper

### Lettura della request

```
UMethod()            UPath()            UQuery()
UGet(k,d)            UPost(k,d)         UParam(k,d)
UHeader(k,d)         UCookie(k,d)       UBody()
UJson()              UContentType()     UContentLength()
UFiles()             URequest()         UContext()
```

### Rileva tipo di request

```
UIsGet()   UIsPost()   UIsAjax()   UIsHttps()
UIsJson()  UIsForm()   UIsMultipart()   UWantsJson()
UScheme()  UIP()       UHost()          UPort()
```

### Validazione input

```
UValidate(h)        UValidatePost(h)   UValidateGet(h)
UValidateParams(h)  UValidateJson(h)   UValidateOrFail(h)
UIsMail(s)  UIsNumeric(v)  UIsInteger(v)  UIsUrl(s)  UIsIp(s)
```

### Identità / sessione

```
USession()  USession(k)  USession(k,d)
UAuthUser(k,d)  UCurrentUser()  UHasRole(r,op)  UGetRoles()
UJwt(k,d)   UHasScope(s)
```

---

## Anti-pattern - cosa evitare

### ❌ Catturare `oReq` nel codeblock

```clipper
// NO - oReq non è nella closure
oSrv:AddRouteGet( "x", "/x", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )

// SÌ - usa gli helper U*
oSrv:AddRouteGet( "x", "/x", {|| USendJson( {=>} ) } )
```

### ❌ Mescolare lettura manuale e validazione

```clipper
// NO - verboso, errori 400 inconsistenti
cName := UPost( "name", "" )
IF Empty( cName ) ; USendError( 422, "name obbligatorio" ) ; RETURN ; ENDIF
IF Len( cName ) > 100 ; USendError( 422, "name troppo lungo" ) ; RETURN ; ENDIF

// SÌ - dichiarativo, errori raggruppati, sintassi standard
oVal := UValidateOrFail( { "name" => "required|string|max:100" } )
IF oVal == NIL ; RETURN NIL ; ENDIF
cName := oVal:Get( "name" )
```

### ❌ Confrontare stringhe con `!=`

Harbour usa `SET EXACT OFF` di default — `!=` confronta fino alla lunghezza della
stringa più corta. Usa sempre `==`.

```clipper
IF UPath() != "/login"       // ⚠️ match falso con "/lo"
IF UPath() == "/login"       // ✅ corretto
```

### ❌ Convertire tutto con `Val()` senza default

```clipper
// NO - Val("") è 0 ma può nascondere bug se il parametro è obbligatorio
nId := Val( UParam( "id" ) )

// SÌ - con default esplicito o validazione
nId := Val( UParam( "id", "0" ) )

// O meglio:
oVal := UValidateParams( { "id" => "required|number|min:0" } )
```
