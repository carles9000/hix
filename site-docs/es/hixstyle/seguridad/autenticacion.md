# 🛡️ Autenticación


La **autenticación** identifica al cliente que está haciendo el request
(login) y verifica que tiene permiso para acceder a un recurso concreto
(autorización por rol/operación).

En HIX hay dos pilas que cubren los dos grandes escenarios:

| Pila | Estado | Uso típico |
|---|---|---|
| **Sesión + middleware de auth** | statefull (cookie + storage servidor) | App web tradicional, panel admin |
| **JWT** | stateless (token firmado) | API REST, móvil, microservicios |

Esta página cubre la pila **session-based** - el patrón que usa Fenix. Para
la pila JWT consulta [JWT](jwt.md).

---

## Piezas del puzzle

```
┌──────────────────────────────────────────────────────────────┐
│  HIX_MwSession   carga/crea la sesión (cookie HIXSID)        │
│        │                                                     │
│        ▼                                                     │
│  HIX_MwIsAuth    lee session["_auth_user"]                   │
│                  - existe -> hData["user"] := hUser          │
│                  - NIL    -> 302 /login                      │
│        │                                                     │
│        ▼                                                     │
│  HIX_MwHasRole   compara oCtx:cScope con user["roles"]       │
│                  - permite -> continúa                       │
│                  - rechaza -> 403                            │
│        │                                                     │
│        ▼                                                     │
│  Controller      hData["user"] disponible vía URequest()     │
└──────────────────────────────────────────────────────────────┘
```

Las tres piezas son middlewares independientes que se combinan en una sola
cadena reusable.

---

## Setup

### Convención Fenix - `www/middlewares/config.json`

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

| Clave | Para qué sirve |
|---|---|
| `session_user_key` | Clave dentro del hash de sesión donde se guarda el usuario |
| `roles_key` | Clave dentro del hash de usuario que contiene los roles |
| `redirect_login` | URL a la que redirigir si no hay sesión activa (302) |
| `redirect_accept` | URL post-login OK |

Esos valores se leen con `UMwConfig( "auth", "session_user_key" )` desde
cualquier controller o middleware.

---

## Definir los grupos de middleware

En Fenix se definen **una sola vez** y se reutilizan en todas las rutas:

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

Y en el `config.json` se cargan al arranque:

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

## Aplicar a las rutas

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

> El campo `"scope"` se mapea a `oCtx:cScope` y lo consume `HIX_MwHasRole`.

---

## El hash de usuario

`HIX_MwIsAuth` espera que la sesión contenga un hash con esta forma:

```clipper
{ "id"    => "1",
  "name"  => "Admin Demo",
  "roles" => { "customers" => "show;edit;delete;create",
               "sales"     => "",
               "purchases" => "" } }
```

Reglas del hash `roles`:

| Valor | Significado |
|---|---|
| `""` | El usuario tiene **acceso total** a ese rol (cualquier operación pasa) |
| `"op1;op2;op3"` | Solo esas operaciones están permitidas |
| _(rol ausente)_ | El usuario **no tiene** ese rol → 403 |

---

## Sintaxis del scope

`oCtx:cScope` se compara contra el hash de roles del usuario:

| Scope | Pasa si... |
|---|---|
| `""` | Siempre (sin chequeo de rol) |
| `"customers"` | El usuario tiene el rol `customers` (con cualquier ops) |
| `"customers:show"` | El usuario tiene `customers` con `""` **o** con `"show"` dentro de la lista |
| `"customers:delete"` | El usuario tiene `customers` con `""` **o** con `"delete"` en la lista |

```clipper
// Lectura en HIX_MwHasRole
aScope := hb_ATokens( oCtx:cScope, ":" )
cRole  := aScope[1]                              // "customers"
cOp    := iif( Len( aScope ) > 1, aScope[2], "")  // "show"
cOps   := hb_HGetDef( hRoles, cRole, NIL )
```

---

## Login - `auth.prg` de Fenix

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
         "error" => "Usuario o contrasena incorrectos", ;
         "user"  => oVal:Get( "username" ) } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )        // -> /login
   ENDIF
RETURN

#include '/models/modeluser.prg'
```

### Modelo de usuario - `modeluser.prg`

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

> En producción `ModelUser` consulta una BD y compara con `hb_BCrypt` o
> similar. La forma del hash devuelto **no cambia**.

---

## Logout - `logout.prg` de Fenix

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

`Destroy()` borra todo el contenido de la sesión y emite una cookie con
`Max-Age=0` para que el navegador la elimine.

---

## Leer al usuario desde un controller

`HIX_MwIsAuth` deja el hash en `oCtx:hData["user"]` **y** en
`oReq:hData["user"]`, así que cualquier controller protegido puede leerlo
sin tocar la sesión directamente:

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown" } )

RETURN UView( "main.view.html", hUser["name"], hUser )
```

### Chequear roles en código

```clipper
IF UHasRole( "customers" )            // tiene el rol (cualquier op)
IF UHasRole( "customers", "delete" )  // tiene el rol con esa op
```

---

## Cuándo usar qué pila

| Caso de uso | Pila |
|---|---|
| App web con login form | ✅ Session + IsAuth |
| Panel admin con permisos finos | ✅ Session + IsAuth + HasRole |
| API REST consumida por SPA con cookie | ✅ Session |
| API REST stateless / móvil / microservicios | ❌ Usa [JWT](jwt.md) |
| Mismo endpoint accesible desde web + API | Combina ambos middlewares |

---

## Buenas prácticas

1. **Una sola fuente de verdad de roles.** El hash `roles` viaja en la
   sesión - si cambias los permisos del usuario en BD, refresca la sesión
   o invalídala.
2. **`Destroy()` en logout.** Borra toda la sesión, no solo la clave de
   usuario, para evitar **session fixation**.
3. **CSRF obligatorio en formularios POST de auth.** El login redirige por
   `URedirect` y deja la sesión iniciada - sin CSRF, un atacante puede
   forzar el login. Combina con [CSRF](csrf.md).
4. **HTTPS en producción.** La cookie viaja en cada request - sin
   [SSL](ssl.md) un intermediario la roba.
5. **No metas el password en la sesión.** Solo `id`, `name`, `roles` y lo
   estrictamente necesario para autorizar requests.
6. **Roles granulares con `""` para admin.** El valor vacío
   (`"customers" => ""`) significa "todas las ops" - úsalo solo para
   superusers.
