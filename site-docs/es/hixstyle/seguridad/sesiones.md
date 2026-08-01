# 🔑 Sesiones

Una **sesión** es un espacio de almacenamiento en el servidor donde HIX guarda
datos asociados a un cliente concreto (típicamente el usuario logueado). Lo que
une al cliente con su sesión es una **cookie** que viaja en cada request y
contiene un identificador opaco (SID).

```
Cliente                              Servidor
   │                                    │
   │  GET /login                        │
   ├───────────────────────────────────>│  no hay SID -> crea sesión nueva
   │                                    │  SID = "abc...123"
   │  Set-Cookie: HIXSID=abc...123      │
   │<───────────────────────────────────┤
   │                                    │
   │  POST /auth                        │
   │  Cookie: HIXSID=abc...123          │  reconoce SID -> recupera datos
   ├───────────────────────────────────>│  USession():Set("user", hUser)
```

Las sesiones de HIX son **idempotentes**: tocar `oCtx:hData["session"]` desde un
middleware o llamar a `USession():Set()` desde un controller modifica el mismo
hash de datos del cliente.

---

## Cuándo usarlas

| Caso de uso | Sesiones |
|---|---|
| Aplicación web tradicional con login | ✅ Sí - patrón canónico |
| SPA con autenticación por cookie | ✅ Sí |
| API REST stateless | ❌ No - usa [JWT](jwt.md) |
| Microservicios / aplicaciones móviles | ❌ No - usa [JWT](jwt.md) |
| Carrito de compra, wizards multipantalla | ✅ Sí |
| Mensajes flash entre redirects | ✅ Sí (`UFlash`) |

> Las sesiones son **statefull**: el servidor recuerda al cliente entre requests.
> Facilitan programar pero acoplan el cliente a una instancia (o requieren
> session affinity / storage compartido en cluster).

---

## Setup

### Desde `hix.json`

`storage`: `"memory"` | `"file"`.
`lifetime`: vida de la cookie de sesion en minutos (`0` = indefinido).
`gc_days`: dias para GC de ficheros huerfanos (solo `storage="file"`).
`seed`: clave secreta para encriptado (obligatoria si `crypt=true`).

```json
{
  "session": {
    "storage":  "memory",
    "prefix":   "sess_",
    "crypt":    false,
    "seed":     "",
    "lifetime": 60,
    "gc_days":  3
  }
}
```

### Desde código

```clipper
HIX_MwSessionSetup( ;
   "HIXSID",     ;   // nombre de la cookie
   3600,         ;   // TTL en segundos (1 hora)
   60,           ;   // GC: limpiar caducadas cada N llamadas
   "memory",     ;   // storage: "memory" | "file"
   "sessions/",  ;   // path (solo si storage="file")
   "sess_",      ;   // prefijo de fichero
   .F.,          ;   // encriptar
   "",           ;   // seed de encriptación
   7 )               // días de vida de la cookie
```

### Desde la app - convención Fenix

Fenix expone los parámetros en `www/middlewares/config.json` para mantenerlos
cerca de la lógica de la app:

```json
{
  "setup": {
    "session": {
      "cookie":  "FENIXSID",
      "ttl":     3600,
      "max":     100,
      "storage": "memory"
    }
  }
}
```

Esos valores se leen con `UMwConfig("session", "cookie")` desde cualquier
controller o middleware.

---

## Activar la sesión en una ruta

`HIX_MwSession` es el middleware que carga/crea la sesión. Se añade a la cadena
de middleware de la ruta - directamente o dentro de un grupo de middleware de la
app.

### Ruta individual

```clipper
oSrv:AddRouteGet( "dash", "/dashboard", bAction, "HIX_MwSession" )
```

```json
{ "name": "dashboard", "url": "/dashboard", "action": "controllers/dash.prg",
  "middleware": "HIX_MwSession" }
```

### Patrón Fenix - grupo de middleware reusable

En Fenix se define **una sola vez** un grupo que combina sesión + autenticación y
se aplica a todas las rutas que lo necesitan:

```clipper
// www/middlewares/myappauth.prg
FUNCTION MyAppAuth( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
RETURN o:Run()
```

```json
{ "name": "main", "url": "/main", "action": "controllers/main.prg",
  "middleware": "MyAppAuth" }
```

> 📖 Detalles del patrón en [Middleware](../middleware/middleware.md).

---

## Leer y escribir desde un controller

Con la sesión activa, los helpers `USession()` y `UFlash()` permiten acceder a
los datos sin tocar `oCtx`.

### Leer

```clipper
cUser := USession( "user" )              // valor o NIL
cRole := USession( "role", "viewer" )    // valor con default
```

### Escribir

```clipper
LOCAL oSess := USession()                // proxy con Set/Save/Destroy
oSess:Set( "user", hUser )
oSess:Set( "role", "admin" )
oSess:Save()                             // persiste + renueva TTL + emite cookie
```

### Destruir

```clipper
USession():Destroy()                     // borra datos + expira cookie
```

### Ejemplo real - `auth.prg` de Fenix

```clipper
// POST /auth - validación de credenciales y arranque de sesión
FUNCTION Main()
   LOCAL oVal, oSess, hUser

   oVal := UValidatePost( { ;
      "username" => { "required|min:3|max:30", "Username", "" }, ;
      "password" => { "required|min:4",        "Password", "" }  ;
   } )

   IF ! oVal:Make()
      UFlash( "login" ):Set( { "error" => oVal:GetFirstError() } )
      URedirect( "/login" )
      RETURN
   ENDIF

   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   IF ValType( hUser ) == "H"
      // Guardar el usuario con la clave configurada
      oSess := USession()
      oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
      oSess:Save()
      URedirect( UMwConfig( "auth", "redirect_accept" ) )
   ELSE
      UFlash( "login" ):Set( { "error" => "Usuario o contrasena incorrectos" } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )
   ENDIF
RETURN
```

### Ejemplo real - `logout.prg` de Fenix

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

---

## Storage: memoria vs fichero

| Storage | Persistencia | Cluster | Reinicio | Uso típico |
|---|---|---|---|---|
| `memory` | RAM del proceso | ❌ una instancia | Se pierden | Desarrollo, monolitos |
| `file` | Disco | ✅ con session affinity | Persisten | Producción, balanceador |

### Memoria

Sesiones rápidas, sin escritura a disco. Al reiniciar el servidor se pierden
todas. En cluster, el cliente perderá la sesión si el balanceador lo manda a
otra instancia.

### Fichero

Cada sesión es un fichero en `sessions/<prefijo><SID>.dat`. Sobreviven a
reinicios y permiten que varias instancias compartan el mismo storage.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "file", "sessions/", "sess_" )
```

### Cluster con Apache + stickysession

Cuando despliegas detrás de Apache balanceador, llama a `HIX_MwSessionSetRoute( "i1" )`
con el `route=` de tu `BalancerMember`. HIX añade el sufijo al SID para que
Apache pueda mantener al cliente pegado a la misma instancia con
`stickysession=HIXSID`.

---

## Encriptación opcional

Si `crypt=1` en la config (o `lCrypt=.T.` en `HIX_MwSessionSetup`), los ficheros
de sesión se cifran con la `seed`. Sin la seed correcta no se pueden leer.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "file", "sessions/", "sess_", ;
                    .T., "clave_secreta_de_app", 7 )
```

> ⚠️ Cambiar la seed invalida todas las sesiones existentes.

---

## Patrones útiles

### Recuperar el usuario en cualquier controller

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown" } )

   // hUser fue puesto por HIX_MwIsAuth tras leer la sesión
RETURN UView( "main.view.html", hUser["name"], hUser )
```

> Los middlewares de auth ya leen `USession( cKey )` por ti y dejan el hash del
> usuario en `oReq:hData["user"]`.

### Flash messages (mensajes de un solo uso)

`UFlash` usa la sesión por debajo. Imprescindible para arrastrar mensajes a
través de un `URedirect`.

```clipper
// POST con error -> flash + redirect
UFlash( "login" ):Set( { ;
   "error" => "Usuario o contrasena incorrectos", ;
   "user"  => cUserIntent ;
} )
URedirect( "/login" )

// GET /login -> consume el flash una sola vez
oFlash := UFlash( "login" )
cError := oFlash:Get( "error" )       // se borra al leerlo
cUser  := oFlash:Get( "user"  )
oFlash:Save()
```

### Sub-hashes para organizar la sesión

```clipper
USession():Set( "cart",  { "items" => aItems, "total" => nTotal } )
USession():Set( "prefs", { "theme" => "dark", "lang"  => "es"   } )
USession():Save()

hCart := USession( "cart" )
nTot  := hCart[ "total" ]
```

