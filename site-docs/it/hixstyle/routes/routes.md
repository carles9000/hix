# 🗺️ Route

## 📂 `<root>/routes`

Una route è l'associazione tra un pattern di URL, un metodo HTTP e l'action che deve essere eseguita
quando arriva una request che corrisponde.

Quando, ad esempio, specifichiamo nell'URL `https://mio_dominio/hello`, diciamo al server di eseguire
un'action identificata come `hello`.

Quando **HIX** riceve una request, il dispatcher attraversa le route registrate **in ordine di specificità**
(la più concreta prima), cercandone una che corrisponda all'URL e al metodo.

Un segmento letterale (`/users`) vale 10; un parametro variabile (`:id`) vale 1.
    `/users/profile` verrà valutato prima di `/users/:id`.

Una volta trovata una corrispondenza:

1. Esegue la catena di **middleware** assegnata a quella route (opzionale).
2. Se il middleware approva, esegue l'**action**.

---

## Definizione delle route

**HIX** permette di definire le route in 2 modi diversi:

- Definendole a livello di programma (Server)

- Definendole a livello di file che verranno letti quando il server si inizializza (data-driven)

L'uso dell'uno o dell'altro metodo è a scelta del programmatore e non cambia il comportamento

### Nel codice — server

Per definire le route a livello di codice dell'applicazione, una volta istanziato l'oggetto server
con `THixServer():New()`, possiamo definire le route usando i seguenti metodi.


| Metodo | Verbo HTTP |
|--------|-----------|
| `AddRouteGet` | GET |
| `AddRoutePost` | POST |
| `AddRoutePut` | PUT |
| `AddRouteDelete` | DELETE |
| `AddRoute` | Qualsiasi — passa il metodo come quinto parametro |

Creare una route ha i seguenti parametri:

| Parametro | Tipo | Descrizione |
|-----------|------|-------------|
| `cName` | Stringa | Identificativo logico unico. Prefisso `hix.` riservato al sistema. |
| `cPattern` | Stringa | Pattern di URL (vedi sezione [Pattern di URL](#pattern-di-url)). |
| `bAction` | Blocco/Stringa | Action da eseguire (vedi sezione [Cosa può eseguire una route](#cosa-può-eseguire-una-route)). |
| `cMiddleware` | Stringa | Nome della funzione middleware (opzionale). |
| `cScope` | Stringa | Metadati liberi accessibili da `oCtx:cScope` (opzionale). |
| `uCargo` | Qualsiasi | Dato arbitrario allegato al contesto della route (opzionale). |

Abbiamo una struttura che potrebbe essere:

```harbour
oSrv:AddRouteGet( cName, cPattern, bAction [, cMiddleware [, cScope [, uCargo]]] )
```


La modalità usuale in free mode è registrare le route sull'oggetto `THixServer` prima di chiamare
`Start()`.

```harbour
LOCAL oSrv := THixServer():New()

   oSrv:AddRouteGet(    "users.list",   "/api/users",     {|| _UserList()   } )
   oSrv:AddRouteGet(    "users.one",    "/api/users/:id", {|| _UserGet()    } )
   oSrv:AddRoutePost(   "users.create", "/api/users",     {|| _UserCreate() } )
   oSrv:AddRoutePut(    "users.update", "/api/users/:id", {|| _UserUpdate() } )
   oSrv:AddRouteDelete( "users.delete", "/api/users/:id", {|| _UserDelete() } )

oSrv:Start()
```

Una route può avere più metodi se lo si desidera, separati da virgola.

```harbour
// Route che accetta più metodi contemporaneamente
oSrv:AddRoute( "hook", "/webhook", {|| _Webhook() }, "GET,POST" )
```

### Da file JSON — HixStyle

Quando HixStyle è attivo, HIX carica automaticamente tutti i file `*.json` dalla cartella
`<root>/routes/` quando si avvia. Ogni file è un **array** di hash di route. Seguono la stessa
struttura definita prima.

```json
[
  {
    "name":       "users.list",
    "url":        "/api/users",
    "method":     "GET",
    "action":     "controllers/users.prg",
    "middleware": "HixMwJwt",
    "scope":      "api"
  },
  {
    "name":    "users.one",
    "url":     "/api/users/:id",
    "method":  "GET",
    "action":  "controllers/users.prg"
  },
  {
    "name":    "home",
    "url":     "/",
    "method":  "GET",
    "action":  "views/home.html"
  }
]
```

Campi dell'oggetto JSON:

| Campo | Obbligatorio | Descrizione |
|-------|----------|-------------|
| `name` | Sì | Identificativo unico. `hix.*` è riservato. |
| `url` | Sì | Pattern di URL. |
| `method` | No | `"GET"`, `"POST"`, `"GET,POST"`, `"*"` (default: `"*"`). |
| `action` | Sì | File o funzione da eseguire. |
| `middleware` | No | Nome della funzione middleware. |
| `scope` | No | Metadati liberi. |

## Modalità sviluppatore

In modalità sviluppo, le route JSON possono essere ricaricate al volo senza riavviare il server
via API.

```
GET /hix-routes/reload
```

---

## Cosa può eseguire una route

### Codeblock

La via più diretta. Usa gli helper `U*` per leggere la request e inviare la risposta.

```harbour
oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )

oSrv:AddRouteGet( "greet", "/hello/:name", {||
   USendJson( { "msg" => "Ciao, " + UParam("name") } )
} )
```

### Nome di funzione

Se l'action è una stringa **senza estensione**, HIX la tratta come un nome di funzione Harbour
e la chiama, passandole l'oggetto request.

```harbour
oSrv:AddRouteGet( "users.list", "/api/users", "UserListAction" )

// In qualsiasi .prg nella libreria:
FUNCTION UserListAction( oReq )
   USendJson( { "users" => {} } )
RETURN NIL
```

### File `.prg`

Un file `.prg` relativo a `<root>/`. HIX lo compila e lo esegue.

```harbour
// Nel codice:
oSrv:AddRouteGet( "home", "/", "views/home.prg" )

// In JSON:
{ "name": "home", "url": "/", "action": "views/home.prg" }
```

Il file deve essere un `.prg` compilabile. Il risultato restituito da `Main()` o
l'output accumulato con `UWrite()` viene inviato come risposta HTML.

### File `.hrb`

Come `.prg` ma già precompilato. Più veloce in produzione.

```harbour
{ "name": "api.data", "url": "/api/data", "action": "controllers/data.hrb" }
```

### Metodo di classe — `method@class.prg`

Questo è il modo più professionale per definire un'action perché permette di definire diverse action
all'interno dello stesso modulo, come un CRUD.

```harbour
// Chiama il metodo "index" della classe "CustomerController" in customer.prg
{ "name": "customer.index", "url": "/customers",     "action": "index@customer.prg"  }
{ "name": "customer.show",  "url": "/customers/:id", "action": "show@customer.prg"   }
{ "name": "customer.save",  "url": "/customers",     "action": "save@customer.prg"   }
```

Il file `customer.prg` definisce una classe con quei metodi:

```harbour
CLASS CustomerController
   METHOD index( oReq )
   METHOD show( oReq )
   METHOD save( oReq )
ENDCLASS

METHOD index( oReq ) CLASS CustomerController
   USendJson( { "customers" => {} } )
RETURN NIL
```

### File `.html`

Renderizza il file HTML con il view engine interno di HIX, Mambo.

```harbour
{ "name": "home",    "url": "/",     "action": "views/home.html"      }
{ "name": "profile", "url": "/user", "action": "views/profile.view.html" }
```

---

## Pattern di URL

### Segmento letterale

```
/ping
/api/v1/status
```

### Parametro variabile - `:name`

Cattura qualsiasi valore tranne `/`. Accessibile con `UParam("name")`.

```
/users/:id              → /users/42        → UParam("id") = "42"
/posts/:slug/comments   → /posts/hello/comments
```

### Parametro con vincolo regex - `:name(expr)`

Corrisponde solo se il valore soddisfa l'espressione regolare.

```
/users/:id([0-9]+)      → /users/42   ✓     /users/abc  ✗
/files/:name([a-z_]+)   → /files/foto ✓     /files/123  ✗
```

### Parametro opzionale - `:name!`

Il segmento è opzionale. Se non presente, `UParam("name")` ritorna `""`.

```
/docs/:section!         → /docs/intro  ✓    /docs  ✓
```

### Wildcard

```
/static/*               → corrisponde a qualsiasi route che inizia con /static
```

---

## Gruppi di route

Permettono di applicare un prefisso di URL e un middleware comune a un insieme di route.

```harbour
oSrv:AddRouteGroup( "/api/v1", "HixMwJwt", "api", {|o|
   o:AddRouteGet(    "items.list",   "/items",     {|| _ItemList()          } )
   o:AddRoutePost(   "items.create", "/items",     {|| _ItemCreate()        } )
   o:AddRouteGet(    "items.one",    "/items/:id", {|| _ItemGet()           } )
   o:AddRoutePut(    "items.update", "/items/:id", {|| _ItemUpdate()        } )
   o:AddRouteDelete( "items.delete", "/items/:id", {|| _ItemDelete()        } )
} )
```

Le route nel blocco ereditano il prefisso `/api/v1` e il middleware `HixMwJwt`.
Una route con un suo middleware lo mantiene; il middleware del gruppo si applica solo se non ne ha uno.

---

## Generazione di URL

`URoute` genera l'URL di una route in base al suo nome, sostituendo i parametri in ordine.

```harbour
URoute( "customer.show", 42 )       // → "/customers/42"
URoute( "customer.index" )          // → "/customers"
```

Utile per evitare URL hardcoded nelle view e nei redirect:

```harbour
URedirect( URoute( "customer.show", nId ) )
```

---

## Gestori di errore

Di default, HIX risponde con un JSON standard quando non trova una route (404)
o il metodo non è consentito (405). Possono essere sostituiti:

```harbour
oSrv:SetRouteHandler( "404", {|| USendError( 404, "Pagina non trovata" ) } )
oSrv:SetRouteHandler( "405", {|| USendError( 405, "Metodo non consentito"  ) } )
```

---

## Middleware

Un middleware è una funzione che viene eseguita **prima** dell'action della route.
Può validare token JWT, controllare le sessioni, applicare rate limit, ecc. Se il middleware
rifiuta la request, l'action non viene eseguita.

```harbour
oSrv:AddRouteGet( "dashboard", "/dashboard", {|| _Dashboard() }, "HixMwRequireAuth" )
```

Vedi il capitolo **[Middleware](../middleware/middleware.md)** per il riferimento completo.

