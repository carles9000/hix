# 📘 HIX - Riferimento completo degli helper U*

Gli helper `U*` sono funzioni globali accessibili da qualsiasi route, controller o
file `.hrb` senza bisogno di passare `oReq` come parametro. Il dispatcher chiama
`HIX_SetRequest(oReq)` prima di eseguire ogni action, così gli helper hanno
sempre accesso alla request del thread corrente.


---

## 1. Lettura della request

### Dati di input

| Funzione | Ritorna | Descrizione |
|---|---|---|
| `UMethod()` | `C` | Metodo HTTP in maiuscolo: `"GET"`, `"POST"`, `"PUT"`, `"DELETE"`, `"PATCH"` |
| `UPath()` | `C` | Path senza query string: `"/api/users/42"` |
| `UQuery()` | `C` | Query string grezza: `"page=1&limit=10"` |
| `UGet(cKey, xDef)` | `X` | Parametro della query string. Senza argomenti ritorna l'hash completo |
| `UPost(cKey, xDef)` | `X` | Campo del body POST (form o JSON). Senza argomenti ritorna l'hash completo |
| `UParam(cKey, xDef)` | `C` | Variabile di route `:var`. Senza default restituisce errore 400 se mancante |
| `UHeader(cKey, xDef)` | `C` | Header HTTP (case-insensitive) |
| `UCookie(cName, xDef)` | `C` | Cookie della request (analizzato una volta, lazy) |
| `UBody()` | `C` | Body grezzo come stringa |
| `UJson()` | `H`/`A` | Body analizzato come JSON; `NIL` se il body non è JSON valido |
| `UContentType()` | `C` | Content-Type in minuscolo: `"application/json"` |
| `UContentLength()` | `N` | Lunghezza del body in byte |
| `UFiles()` | `A` | Array di hash dei file caricati (multipart). Vedi sezione upload |
| `URequest()` | `O` | Oggetto `THixRequest` del thread corrente (accesso low-level) |
| `UContext()` | `O` | `THixContext` della catena middleware corrente (accesso a `oCtx:hData`); `NIL` se non in catena MW |

**UGet / UPost senza argomenti**: ritornano un hash con tutti i campi.

```clipper
// Ottieni tutti i parametri GET in una volta
hParams := UGet()   // { "page" => "1", "limit" => "10" }

// Ottieni un campo con default
cNome := UPost( "nome", "Anonimo" )

// Variabile di route con default sicuro
nId := Val( UParam( "id", "0" ) )

// Variabile di route senza default - genera errore 400 se mancante
cSlug := UParam( "slug" )
```

**UParam con indice numerico**: quando la route usa `*`, il wildcard viene catturato come `_1`.

```clipper
oSrv:AddRouteGet( "static", "/static/*", {||
   cFile := UParam( 1 )   // equivalente a UParam("_1")
} )
```

### Content type e negoziazione

| Funzione | Ritorna | Descrizione |
|---|---|---|
| `UIsGet()` | `L` | `.T.` se il metodo è GET |
| `UIsPost()` | `L` | `.T.` se il metodo è POST |
| `UIsAjax()` | `L` | `.T.` se `X-Requested-With: XMLHttpRequest` |
| `UIsHttps()` | `L` | `.T.` se la connessione è HTTPS |
| `UScheme()` | `C` | `"http"` o `"https"` |
| `UIsJson()` | `L` | `.T.` se il Content-Type è `application/json` |
| `UIsForm()` | `L` | `.T.` se il Content-Type è `application/x-www-form-urlencoded` |
| `UIsMultipart()` | `L` | `.T.` se il Content-Type è `multipart/form-data` |
| `UWantsJson()` | `L` | `.T.` se il client preferisce JSON (header Accept o AJAX) |

### Dati del client

| Funzione | Ritorna | Descrizione |
|---|---|---|
| `UIP()` | `C` | IP reale del client (rispetta `X-Forwarded-For` se `mode=proxied`) |
| `UHost()` | `C` | Hostname della request (header Host) |
| `UPort()` | `N` | Porta del server |

### Upload multipart

```clipper
aFiles := UFiles()
FOR EACH hFile IN aFiles
   // hFile["name"]  -> nome del campo
   // hFile["data"]  -> contenuto binario
   // hFile["mime"]  -> Content-Type del file
   // hFile["size"]  -> dimensione in byte
   hb_MemoWrit( "uploads/" + hFile["name"], hFile["data"] )
NEXT
```

---

## 2. Invio delle risposte

### Risposte dirette

| Funzione | Descrizione |
|---|---|
| `USendJson(xData [, nStatus])` | JSON 200. `xData` può essere hash, array o stringa |
| `USendHtml(cHtml [, nStatus])` | HTML 200 |
| `USendText(cText [, nStatus])` | `text/plain` 200 |
| `USendView(cView [, hVars])` | Renderizza il template e invia HTML |
| `USendEmpty()` | 204 No Content |
| `USendError(nStatus, cDetail)` | Errore HTTP con messaggio di dettaglio |
| `URedirect(cUrl [, nStatus])` | Redirect (302 di default) |

```clipper
// Risposta JSON semplice
USendJson( { "ok" => .T. } )

// Con status personalizzato
USendJson( { "id" => 42, "name" => "Test" }, 201 )

// Redirect permanente
URedirect( "/new-url", 301 )

// Errore HTTP
USendError( 403, "Permessi insufficienti" )
```

### Controllo fine del buffer

Quando hai bisogno di costruire la risposta passo dopo passo prima di inviarla:

| Funzione | Descrizione |
|---|---|
| `UWrite(cText)` | Accumula testo nel buffer di risposta |
| `UEcho(cText)` | Alias di `UWrite` |
| `USetStatus(nStatus)` | Imposta lo status HTTP del buffer |
| `USetMime(cMime)` | Imposta il MIME del buffer (`"json"`, `"html"`, `"text"` o MIME completo) |
| `UGetMime()` | Ritorna il MIME attualmente configurato |
| `USetHeader(cKey, cVal)` | Aggiunge un header extra alla risposta |
| `UFlush()` | Invia il buffer accumulato come chunk (avvia lo streaming se è la prima volta) |

```clipper
// Costruisci JSON manualmente
USetStatus( 201 )
USetMime( "json" )
USetHeader( "X-Request-Id", "abc123" )
UWrite( hb_jsonEncode( { "created" => .T. } ) )
// Il dispatcher invia il buffer quando l'action termina
```

### Cookie nella risposta

| Funzione | Descrizione |
|---|---|
| `USetCookie(cName, cVal, nMaxAge)` | Scrive `Set-Cookie` nella risposta |

`nMaxAge`:
- `0` - cookie di sessione (senza `Max-Age`)
- `-1` - scade immediatamente (`Max-Age=0`)
- `> 0` - durata in secondi

I flag `HttpOnly; SameSite=Lax; Path=/` vengono aggiunti automaticamente.

```clipper
USetCookie( "session_id", cSid, 3600 )   // 1 ora
USetCookie( "pref", "dark", 0 )          // sessione
USetCookie( "old_cookie", "", -1 )       // scadenza
```

---

## 3. Streaming a chunk

Per SSE, download progressivi o risposte di lunga durata:

| Funzione | Descrizione |
|---|---|
| `USendStreamStart(cMime, nStatus, hExtra)` | Avvia una risposta a chunk; header extra in `hExtra` |
| `USendChunk(cData)` | Invia un chunk di dati |
| `USendStreamEnd()` | Chiude lo stream (chunk di lunghezza zero) |

```clipper
// SSE - Server-Sent Events
oSrv:AddRouteGet( "events", "/events", {||
   LOCAL i := 0
   USendStreamStart( "text/event-stream", 200, ;
      { "Cache-Control" => "no-cache", "X-Accel-Buffering" => "no" } )
   DO WHILE i < 10
      i++
      USendChunk( "data: " + hb_jsonEncode( { "n" => i } ) + hb_eol() + hb_eol() )
      hb_idleSleep( 1 )
   ENDDO
   USendStreamEnd()
} )
```

---

## 4. Sessione

| Funzione | Descrizione |
|---|---|
| `USession()` | Ritorna un oggetto proxy con metodi `Get/Set/Save/Destroy` |
| `USession(cKey)` | Legge un valore di sessione; `NIL` se non esiste |
| `USession(cKey, xDef)` | Legge un valore con default |

```clipper
// Leggi un campo
cUser := USession( "user" )

// Scrivi e salva
USession():Set( "user", "carles" )
USession():Set( "role", "admin" )
USession():Save()   // rinnova il TTL ed emette il Set-Cookie

// Distruggi la sessione
USession():Destroy()
```

> Richiede che `HIX_MwSession` sia registrato come middleware sulla route.

---

## 5. JWT

| Funzione | Descrizione |
|---|---|
| `UJwt()` | Ritorna l'hash completo del payload JWT; `NIL` se non c'è JWT |
| `UJwt(cKey)` | Ritorna un claim dal payload; `NIL` se non esiste |
| `UJwt(cKey, xDef)` | Ritorna un claim con default |
| `UHasScope(cScope)` | `.T.` se il JWT include lo scope nel campo `scope` |

```clipper
// Leggi un claim
cSub  := UJwt( "sub" )
nExp  := UJwt( "exp", 0 )

// Controlla lo scope
IF ! UHasScope( "read:products" )
   USendError( 403, "Scope insufficiente" )
   RETURN
ENDIF
```

> Richiede che `HixMwJwt` sia registrato come middleware sulla route.

---

## 6. Autenticazione e ruoli

Disponibile quando il middleware `HIX_MwAuth` o `HIX_MwIsAuth` è attivo.

| Funzione | Descrizione |
|---|---|
| `UCurrentUser()` | Hash completo dell'utente autenticato; `NIL` se non c'è sessione |
| `UAuthUser()` | Hash dell'utente della request (impostato dal middleware); `NIL` se non autenticato |
| `UAuthUser(cKey)` | Campo dell'hash utente |
| `UAuthUser(cKey, xDef)` | Campo dell'hash con default |
| `UHasRole(cRole)` | `.T.` se l'utente ha il ruolo (accesso completo) |
| `UHasRole(cRole, cOp)` | `.T.` se l'utente ha il ruolo con l'operazione specificata |
| `UGetRoles()` | Hash dei ruoli utente: `{ "admin" => "", "editor" => "read;write" }` |
| `UAuthLogout()` | Distrugge la sessione e azzera l'utente corrente |

```clipper
// Controlla il ruolo
IF ! UHasRole( "admin" )
   USendError( 403, "Solo amministratori" )
   RETURN
ENDIF

// Controlla il ruolo con operazione granulare
IF ! UHasRole( "products", "delete" )
   USendError( 403, "Nessun permesso di eliminazione" )
   RETURN
ENDIF

// Leggi i dati utente
hUser := UAuthUser()
cEmail := UAuthUser( "email", "" )

// Logout
UAuthLogout()
URedirect( "/login" )
```

---

## 7. Validazione

### Costruire un validator

| Funzione | Fonte dei dati |
|---|---|
| `UValidate(hRules)` | POST (form o JSON) |
| `UValidatePost(hRules)` | POST esplicito |
| `UValidateGet(hRules)` | Query string |
| `UValidateParams(hRules)` | Query string + variabili di route unite |
| `UValidateJson(hRules)` | Body JSON esplicito |
| `UValidateInput(hRules)` | Equivalente a `UValidatePost` (body form POST) |
| `UValidateOrFail(hRules)` | POST - risponde automaticamente 422 se fallisce; ritorna `NIL` |

Tutte accettano un secondo parametro opzionale `hSanitate` con regole di sanificazione.

### Flusso tipico

```clipper
FUNCTION _CreateUser()
   LOCAL oVal := UValidateOrFail( { ;
      "name"  => "required|string|max:100", ;
      "email" => "required|string|email",   ;
      "age"   => "required|integer|min:18"  ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF   // ha già risposto 422

   cName  := oVal:Get( "name" )
   cEmail := oVal:Get( "email" )
   nAge   := oVal:Get( "age" )
   // ...
   USendJson( { "ok" => .T. }, 201 )
RETURN NIL
```

### Gestione manuale degli errori

```clipper
LOCAL oVal := UValidatePost( hRules )
IF ! oVal:Make()
   USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
   RETURN
ENDIF
```

### Regole disponibili

```
required            campo obbligatorio (non vuoto)
string              tipo stringa
integer             intero
numeric             numero (int o decimale)
boolean             logico
array               array
min:N               stringa: lunghezza >= N  /  numero: valore >= N
max:N               stringa: lunghezza <= N  /  numero: valore <= N
minlen:N            lunghezza stringa >= N
maxlen:N            lunghezza stringa <= N
between:N:M         numero compreso tra N e M
email               formato email
url                 inizia con http:// o https://
ip                  IPv4 valido
regex:PATTERN       espressione regolare Harbour
in:a,b,c            valore nella lista
notin:a,b           valore non nella lista
field               include il campo in DataFields() se valido
```

Sanificazione (applicata prima della validazione):

```
trim                AllTrim()
lower               Lower()
upper               Upper()
```

### Predicati rapidi

| Funzione | Descrizione |
|---|---|
| `UIsMail(cStr)` | `.T.` se `cStr` ha formato email |
| `UIsNumeric(uValue)` | `.T.` se il valore è numerico (numero o stringa numerica) |
| `UIsInteger(uValue)` | `.T.` se il valore è un intero |
| `UIsUrl(cStr)` | `.T.` se inizia con `http://` o `https://` |
| `UIsIp(cStr)` | `.T.` se è un IPv4 valido |

---

## 8. View / Template

| Funzione | Descrizione |
|---|---|
| `USendView(cView [, hVars])` | Renderizza il template e invia la risposta HTML |
| `UView(cView [, hVars])` | Renderizza il template e ritorna l'HTML come stringa |

I template si trovano in `www/views/` con estensione `.html`.

```clipper
// Renderizza e invia
USendView( "users/list.html" )

// Con variabili
USendView( "users/edit.html", { ;
   "cName" => "Carles", ;
   "nAge"  => 42        ;
} )

// Ottieni solo l'HTML (per comporre partial)
cPartial := UView( "partials/header.html", { "cTitle" => "My app" } )
USendHtml( cPartial + "<main>content</main>" )
```

Formato del template:

```html
@args cName, nAge

<html>
<body>
  <h1>Edit: {{ cName }}</h1>
  <p>Age: {{ hb_NToS(nAge) }}</p>
</body>
</html>
```

---

## 9. Helper per le view

### Conversione di tipo

| Funzione | Descrizione |
|---|---|
| `UStr(u)` | Converte qualsiasi tipo Harbour in stringa (C, N, L, D, A, H) |
| `UDateToHtml(dData)` | Data Harbour in stringa `"YYYY-MM-DD"` per input HTML |
| `ULogicToHtmlChecked(lValue)` | `.T.` → `"checked"`, `.F.` → `""` (per checkbox) |
| `UHtmlEncode(cText)` | Effettua l'escape delle entità HTML (`&`, `<`, `>`, `"`, `'`) in un passaggio |
| `UOsFileName(cFileName)` | Normalizza i separatori di path al separatore del sistema operativo |

### Select HTML

```clipper
// UHashToHtmlSelect( aHash, cSelect, cKey, cValue )
// aHash: array di hash con campi key e value
// cSelect: valore attualmente selezionato
// cKey: nome del campo chiave in ogni hash (default "key")
// cValue: nome del campo valore in ogni hash (default "value")

aItems := { { "key" => "es", "value" => "Spagnolo" }, ;
            { "key" => "en", "value" => "Inglese" } }
cHtml := UHashToHtmlSelect( aItems, "es", "key", "value" )
// <option value="" ></option>
// <option value="es" selected>Spagnolo</option>
// <option value="en">Inglese</option>
```

### Route con nome

```clipper
// URoute( cName, param1, param2, ... )
cUrl := URoute( "user", 42 )       // -> "/users/42"
cUrl := URoute( "post", "my-slug" ) // -> "/posts/my-slug"
```

---

## 10. CSRF

Protezione dei form HTML contro attacchi Cross-Site Request Forgery.

| Funzione | Descrizione |
|---|---|
| `UCsrfToHtml([cToken])` | Genera `<input type="hidden" name="_csrf" value="...">` |
| `HIX_CsrfMakeToken([cData])` | Genera un token CSRF firmato con la chiave `csrf` del `HIX_Keys` store |
| `HIX_CsrfValidToken(cToken [, nLapsus])` | `.T.` se il token è valido. `nLapsus` in secondi (0 = nessuna scadenza) |
| `HIX_CsrfGenRandom([nLen])` | Genera una stringa casuale di `nLen` byte |

```clipper
// Nell'action GET che serve il form
USendView( "form.html", { "cCsrf" => UCsrfToHtml() } )

// Nel template
// {{ cCsrf }}   -- emette l'<input hidden>

// Nell'action POST che processa il form
IF ! HIX_CsrfValidToken( UPost( "_csrf" ), 3600 )
   USendError( 403, "Token CSRF non valido" )
   RETURN
ENDIF
```

---

## 11. Resource ID

Firma un ID opaco così che non sia prevedibile nei form HTML.

| Funzione | Descrizione |
|---|---|
| `UResourceToHtml(cId)` | Genera `<input type="hidden" name="_resource_id" value="...">` con ID firmato |
| `UGetResource([cToken])` | Valida il token e ritorna l'ID originale; `""` se non valido |

```clipper
// Nella view (lista record)
// {{ UResourceToHtml( hb_NToS(nId) ) }}

// Nell'action POST (delete, edit, ...)
cId := UGetResource()   // legge _resource_id dal POST automaticamente
IF Empty( cId )
   USendError( 400, "Resource ID non valido" )
   RETURN
ENDIF
nId := Val( cId )
```

---

## 12. Messaggi flash

Messaggi di validazione temporanei per form, memorizzati in sessione e distrutti quando letti.

| Metodo | Descrizione |
|---|---|
| `UFlash([cFormId])` | Crea un oggetto `TFlash` per il form specificato |
| `oFlash:Set(cKey, xVal)` | Salva un valore flash |
| `oFlash:Get(cKey [, xDef])` | Legge e cancella il valore flash |
| `oFlash:Has(cKey)` | `.T.` se il valore esiste |
| `oFlash:Delete(cKey)` | Cancella un valore senza leggerlo |
| `oFlash:Clear()` | Cancella tutti i valori per il form |
| `oFlash:Save()` | Persiste le modifiche nella sessione |
| `oFlash:Destroy()` | Distruttore: salva automaticamente all'uscita dallo scope |

```clipper
// Salva errore nel POST
oFlash := UFlash( "login-form" )
oFlash:Set( "error", "Credenziali errate" )
oFlash:Set( "email", UPost( "email" ) )
oFlash:Save()
URedirect( "/login" )

// Leggi nel successivo GET
oFlash := UFlash( "login-form" )
cError := oFlash:Get( "error", "" )
cEmail := oFlash:Get( "email", "" )
```

---

## 13. Ambiente e configurazione

| Funzione | Descrizione |
|---|---|
| `UEnv()` | Ambiente corrente: `"dev"` o `"prod"` |
| `UIsDev()` | `.T.` se `UEnv() == "dev"` |
| `UIsProd()` | `.T.` se `UEnv() == "prod"` |
| `UConfig(cKey [, xDef])` | Valore da `THixConfig` per nome campo |
| `UMwConfig(cSection, cKey [, xDef])` | Valore dalla sezione `setup` di `www/middlewares/config.json` |
| `UNow()` | Timestamp corrente come stringa `"YYYYMMDDHHmmss"` |
| `URoot()` | Nome della cartella web root (default `"www"`) |
| `URootPath()` | Percorso assoluto alla web root con separatore finale |

```clipper
IF UIsDev()
   l( "Debug: " + hb_jsonEncode( hData ) )
ENDIF

cPort := UConfig( "nPort", "8080" )
cKey  := UMwConfig( "auth", "session_user_key", "_auth_user" )
```

---

## 14. Tabella di riferimento rapido

### Lettura della request

```
UMethod()           UPath()             UQuery()
UGet(k,d)           UPost(k,d)          UParam(k,d)
UHeader(k,d)        UCookie(k,d)        UBody()
UJson()             UContentType()      UContentLength()
UFiles()            URequest()          UContext()
```

### Rileva tipo

```
UIsGet()    UIsPost()   UIsAjax()   UIsHttps()
UIsJson()   UIsForm()   UIsMultipart()  UWantsJson()
UScheme()   UIP()       UHost()         UPort()
```

### Invio risposta

```
USendJson(x,n)      USendHtml(c,n)      USendText(c,n)
USendView(v,h)      USendEmpty()        USendError(n,c)
URedirect(u,n)      USend(x,n,m,h)
```

### Controllo buffer

```
UWrite(c)   UEcho(c)    USetStatus(n)   USetMime(c)
UGetMime()  USetHeader(k,v)  USetCookie(k,v,n)  UFlush()
```

### Streaming

```
USendStreamStart(m,n,h)   USendChunk(c)   USendStreamEnd()
```

### Sessione e autenticazione

```
USession()  USession(k)  USession(k,d)
UJwt()      UJwt(k)      UJwt(k,d)     UHasScope(s)
UCurrentUser()  UAuthUser(k,d)
UHasRole(r)     UHasRole(r,op)  UGetRoles()  UAuthLogout()
```

### Validazione

```
UValidate(h)    UValidatePost(h)  UValidateGet(h)
UValidateParams(h)  UValidateJson(h)  UValidateInput(h)  UValidateOrFail(h)
UIsMail(s)  UIsNumeric(v)  UIsInteger(v)  UIsUrl(s)  UIsIp(s)
```

### View e helper

```
USendView(v,h)  UView(v,h)
UStr(u)  UDateToHtml(d)  ULogicToHtmlChecked(l)  UHtmlEncode(c)
UHashToHtmlSelect(a,s,k,v)  URoute(name, ...)  UOsFileName(f)
```

### CSRF, Resource, Flash, Config

```
UCsrfToHtml()       HIX_CsrfValidToken(t,n)
UResourceToHtml(id) UGetResource()
UFlash(id)
UEnv()  UIsDev()  UIsProd()  UConfig(k,d)  UMwConfig(s,k,d)
UNow()  URoot()   URootPath()
```
