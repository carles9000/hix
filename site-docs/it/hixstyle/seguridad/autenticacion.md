# 🛡️ Autenticazione

L'**autenticazione** identifica il client che fa la richiesta (login) e verifica che abbia il permesso di accedere a una specifica risorsa (autorizzazione per ruolo/operazione).

In HIX ci sono due stack che coprono i due scenari principali:

| Stack | Stato | Uso tipico |
|---|---|---|
| **Sessione + middleware di auth** | stateful (cookie + storage server) | App web tradizionale, pannello admin |
| **JWT** | stateless (token firmato) | API REST, mobile, microservizi |

Questa pagina copre lo stack **basato su sessione** - il pattern che usa Fenix. Per lo stack JWT, vedi [JWT](jwt.md).

---

## I pezzi del puzzle

```
┌──────────────────────────────────────────────────────────────┐
│  HIX_MwSession   carica/crea la sessione (cookie HIXSID)    │
│        │                                                     │
│        ▼                                                     │
│  HIX_MwIsAuth    legge session["_auth_user"]                 │
│                  - esiste -> hData["user"] := hUser          │
│                  - NIL    -> 302 /login                      │
│        │                                                     │
│        ▼                                                     │
│  HIX_MwHasRole   confronta oCtx:cScope con user["roles"]     │
│                  - permette -> continua                       │
│                  - nega     -> 403                            │
│        │                                                     │
│        ▼                                                     │
│  Controller      hData["user"] disponibile via URequest()   │
└──────────────────────────────────────────────────────────────┘
```

I tre pezzi sono middleware indipendenti che si combinano in un'unica catena riutilizzabile.

---

## Setup

### Convenzione Fenix - `www/middlewares/config.json`

```json
{
  "setup": {
    "auth": {
      "session_user_key": "_auth_user",
      "roles_key":        "roles",
      "redirect_login":   "/login",
      "redirect_accept":  "/main"
    },
    "session": {
      "cookie":  "FENIXSID",
      "ttl":     3600,
      "storage": "memory"
    }
  }
}
```

| Chiave | Scopo |
|---|---|
| `session_user_key` | Chiave dentro l'hash di sessione dove viene memorizzato l'utente |
| `roles_key` | Chiave dentro l'hash utente che contiene i ruoli |
| `redirect_login` | URL a cui reindirizzare se non c'è una sessione attiva (302) |
| `redirect_accept` | URL dopo un login riuscito |

Questi valori si leggono con `UMwConfig( "auth", "session_user_key" )` da qualsiasi controller o middleware.

---

## Definire i gruppi di middleware

In Fenix vengono definiti **una sola volta** e riutilizzati in tutte le route:

```clipper
// www/middlewares/myappauth.prg
FUNCTION MyAppAuth( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
RETURN o:Run()

FUNCTION MyAppAuthRole( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole" ) )
RETURN o:Run()
```

E in `config.json` vengono caricati all'avvio:

```json
{
  "load": [
    "myappauth.prg",
    "myapplogin.prg",
    "myappauthedit.prg"
  ]
}
```

---

## Applicare alle route

```json
[
  { "name": "main",
    "url": "/main", "method": "GET",
    "action": "controllers/main.prg",
    "middleware": "MyAppAuth" },

  { "name": "customer.show",
    "url": "/customer/:id", "method": "GET",
    "action": "controllers/masters/show@customer.prg",
    "middleware": "MyAppAuthRole", "scope": "customers:show" },

  { "name": "customer.delete",
    "url": "/customer/:id([0-9]+)/delete", "method": "POST",
    "action": "controllers/masters/delete@customer.prg",
    "middleware": "MyAppAuthRole", "scope": "customers:delete" }
]
```

> Il campo `"scope"` viene mappato su `oCtx:cScope` ed è consumato da `HIX_MwHasRole`.

---

## L'hash utente

`HIX_MwIsAuth` si aspetta che la sessione contenga un hash con questa forma:

```clipper
{ "id"    => "1",
  "name"  => "Admin Demo",
  "roles" => { "customers" => "show;edit;delete;create",
               "sales"     => "",
               "purchases" => "" } }
```

Regole dell'hash `roles`:

| Valore | Significato |
|---|---|
| `""` | L'utente ha **accesso completo** a quel ruolo (qualsiasi operazione passa) |
| `"op1;op2;op3"` | Sono permesse solo quelle operazioni |
| _(ruolo assente)_ | L'utente **non ha** quel ruolo → 403 |

---

## Sintassi dello scope

`oCtx:cScope` viene confrontato con l'hash dei ruoli dell'utente:

| Scope | Passa se... |
|---|---|
| `""` | Sempre (nessun controllo ruolo) |
| `"customers"` | L'utente ha il ruolo `customers` (con qualsiasi op) |
| `"customers:show"` | L'utente ha `customers` con `""` **oppure** con `"show"` nella lista |
| `"customers:delete"` | L'utente ha `customers` con `""` **oppure** con `"delete"` nella lista |

```clipper
// Lettura in HIX_MwHasRole
aScope := hb_ATokens( oCtx:cScope, ":" )
cRole  := aScope[1]                              // "customers"
cOp    := iif( Len( aScope ) > 1, aScope[2], "")  // "show"
cOps   := hb_HGetDef( hRoles, cRole, NIL )
```

---

## Login - `auth.prg` di Fenix

```clipper
// POST /auth  middleware: MyAppLogin (Session + CsrfCheck)
FUNCTION Main()
   LOCAL oVal, oSess, hUser

   oVal := UValidatePost( { ;
      "username" => { "required|min:3|max:30", "Username", "" }, ;
      "password" => { "required|min:4",        "Password", "" }  ;
   } )

   IF ! oVal:Make()
      UFlash( "login" ):Set( { ;
         "error" => oVal:GetFirstError(), ;
         "user"  => oVal:Get( "username" ) } )
      URedirect( "/login" )
      RETURN
   ENDIF

   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   IF ValType( hUser ) == "H"
      oSess := USession()
      oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
      oSess:Save()
      URedirect( UMwConfig( "auth", "redirect_accept" ) )       // -> /main
   ELSE
      UFlash( "login" ):Set( { ;
         "error" => "Username o password non validi", ;
         "user"  => oVal:Get( "username" ) } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )        // -> /login
   ENDIF
RETURN

#include '/models/modeluser.prg'
```

### Model utente - `modeluser.prg`

```clipper
FUNCTION ModelUser( cUser, cPass )
   LOCAL hStore, hEntry

   hStore := { ;
      "demo"   => { "id" => "1", "name" => "Admin Demo", "pass" => "1234", ;
                    "roles" => { "sales"     => "",                         ;
                                 "purchases" => "",                         ;
                                 "customers" => "show;edit;delete;create" } ;
                  }, ;
      "carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234", ;
                    "roles" => { "customers" => "show",                      ;
                                 "purchases" => "" } } ;
   }

   hEntry := hb_HGetDef( hStore, Lower( cUser ), NIL )

   IF hEntry == NIL .OR. ! ( hEntry["pass"] == cPass )
      RETURN NIL
   ENDIF

RETURN { "id"    => hEntry["id"],   ;
         "name"  => hEntry["name"], ;
         "roles" => hEntry["roles"] }
```

> In produzione, `ModelUser` interroga un database e confronta con `hb_BCrypt` o simili. La forma dell'hash ritornato **non cambia**.

---

## Logout - `logout.prg` di Fenix

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

`Destroy()` cancella tutto il contenuto della sessione ed emette un cookie con `Max-Age=0` così il browser lo elimina.

---

## Leggere l'utente da un controller

`HIX_MwIsAuth` lascia l'hash in `oCtx:hData["user"]` **e** in `oReq:hData["user"]`, così qualsiasi controller protetto può leggerlo senza toccare direttamente la sessione:

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Sconosciuto" } )

RETURN UView( "main.view.html", hUser["name"], hUser )
```

### Controllare i ruoli nel codice

```clipper
IF UHasRole( "customers" )            // ha il ruolo (qualsiasi op)
IF UHasRole( "customers", "delete" )  // ha il ruolo con quell'operazione
```

---

## Quando usare quale stack

| Caso d'uso | Stack |
|---|---|
| App web con form di login | ✅ Sessione + IsAuth |
| Pannello admin con permessi granulari | ✅ Sessione + IsAuth + HasRole |
| API REST consumata da SPA con cookie | ✅ Sessione |
| API REST stateless / mobile / microservizi | ❌ Usa [JWT](jwt.md) |
| Stesso endpoint accessibile da web + API | Combina entrambi i middleware |

---

## Best practice

1. **Unica fonte di verità per i ruoli.** L'hash `roles` viaggia nella
   sessione - se cambi i permessi dell'utente nel database, rinfresca la sessione
   o invalidala.
2. **`Destroy()` al logout.** Pulisci l'intera sessione, non solo la chiave utente,
   per prevenire la **session fixation**.
3. **CSRF obbligatorio sui form di auth POST.** Il login reindirizza tramite `URedirect` e lascia la sessione
   avviata - senza CSRF, un attaccante può forzare un login. Combina con [CSRF](csrf.md).
4. **HTTPS in produzione.** Il cookie viaggia in ogni richiesta - senza [SSL](ssl.md) un intermediario può rubarlo.
5. **Non mettere la password in sessione.** Solo `id`, `name`, `roles` e
   ciò che è strettamente necessario per autorizzare le richieste.
6. **Ruoli granulari con `""` per gli admin.** Il valore vuoto (`"customers" => ""`) significa "tutte le op" - usalo solo per i superuser.
