# ❔ Requests

El **request** es el conjunto de datos que el cliente envía al servidor en cada
llamada HTTP: la URL, el método (GET/POST/PUT/...), las cabeceras, las cookies, los
parámetros de query string, el cuerpo (form, JSON, multipart), los ficheros subidos,
la IP del cliente...

En HIX el request se representa internamente con un objeto `THixRequest`, pero la
forma **idiomática** de leerlo dentro de un controller no es acceder al objeto:
es usar los helpers `U*`.

> ✨ **Regla de oro**: dentro de un controller usa **siempre** los helpers `U*` para
> leer cualquier dato del request. No necesitas (ni debes) capturar `oReq` en el
> codeblock - el dispatcher deja el request del hilo actual disponible para los
> helpers automáticamente.

```clipper
// CORRECTO - usa helpers U*
oSrv:AddRouteGet( "user", "/user/:id", {|| USendJson( { "id" => UParam("id") } ) } )

// INCORRECTO - oReq no está disponible en el closure
oSrv:AddRouteGet( "user", "/user/:id", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )
```

---

## Anatomía de un request HTTP

```
POST /customer/update?lang=es HTTP/1.1           ← método + path + query + versión
Host: app.example.com                            ← cabeceras
Content-Type: application/x-www-form-urlencoded  ←
Cookie: session_id=abc123; pref=dark             ←
X-Requested-With: XMLHttpRequest                 ←
Content-Length: 42                               ←
                                                 ← línea en blanco = fin de cabeceras
first=Carles&last=Aubia&age=42                   ← cuerpo (body)
```

A cada una de estas piezas le corresponde un helper:

| Pieza del request | Helper |
|---|---|
| Método (`POST`) | `UMethod()` |
| Path (`/customer/update`) | `UPath()` |
| Query string raw (`lang=es`) | `UQuery()` |
| Cabecera (`Content-Type`) | `UHeader( "content-type" )` |
| Cookie (`session_id`) | `UCookie( "session_id" )` |
| Body raw | `UBody()` |
| Body parseado (form/JSON) | `UPost( "first" )` / `UJson()` |

---

## 1. Línea de petición

### Método HTTP

```clipper
UMethod()           // -> "GET", "POST", "PUT", "DELETE", "PATCH"
UIsGet()            // -> .T. si es GET
UIsPost()           // -> .T. si es POST
```

Útil para acciones que aceptan varios métodos en la misma ruta:

```clipper
oSrv:AddRoute( "form", "/contact", {||
   IF UIsPost()
      _ProcessForm()
   ELSE
      USendView( "contact.view.html" )
   ENDIF
}, "GET,POST" )
```

### Path y query string

```clipper
UPath()             // -> "/customer/update"
UQuery()            // -> "lang=es&page=2"     (raw, sin parsear)
```

`UPath()` devuelve la URL **sin** el query string. Para leer el query, usa `UGet`.

### Esquema, host y puerto

```clipper
UScheme()           // -> "http" / "https"
UIsHttps()          // -> .T. / .F.
UHost()             // -> "app.example.com"   (cabecera Host)
UPort()             // -> 443
UIP()               // -> "192.168.1.10" (respeta X-Forwarded-For si mode=proxied)
```

---

## 2. Variables de ruta - `UParam`

Cuando una ruta declara segmentos variables con `:nombre`, capturas el valor con
`UParam`.

```clipper
oSrv:AddRouteGet( "user.show", "/users/:id", {||
   LOCAL nId := Val( UParam( "id" ) )
   USendJson( _UserRepoFind( nId ) )
} )
```

| Forma | Comportamiento |
|---|---|
| `UParam( cKey )` | Lee la variable; si no existe **lanza error 400** |
| `UParam( cKey, xDef )` | Lee con valor por defecto si no existe |
| `UParam( 1 )` | Captura del comodín `*` (equivale a `UParam("_1")`) |
| `UParam()` | Hash con todas las variables de ruta |

```clipper
// Ruta: /products/:id([0-9]+)/edit
nId := Val( UParam( "id", "0" ) )         // con default seguro

// Ruta: /docs/:section!  (opcional)
cSection := UParam( "section", "intro" )

// Ruta: /static/*
cFile := UParam( 1 )                       // equivale a UParam("_1")
```

> 📖 Patrones de URL completos en [Rutas](../routes/routes.md).

---

## 3. Query string - `UGet`

Lee parámetros del query string (`?clave=valor&...`).

```clipper
// URL: /search?q=carles&page=2&limit=20

cQ     := UGet( "q" )                     // "carles"
nPage  := Val( UGet( "page",  "1"  ) )    // 2
nLimit := Val( UGet( "limit", "20" ) )    // 20

// Sin argumento -> hash completo
hAll := UGet()                            // { "q"=>"carles", "page"=>"2", "limit"=>"20" }
```

Devuelve siempre **string**. Para enteros convierte con `Val()`.

### Validar query string en bloque

Cuando hay varias variables, valida con `UValidateGet` o `UValidateParams`
(query + variables de ruta fusionadas).

```clipper
oVal := UValidateParams( { ;
   "id"   => { "required|number|min:0", "Id"   }, ;
   "lang" => { "in:es,en,ca",           "Lang" } ;
} )
IF ! oVal:Make()
   RETU URedirect( URoute( 'home' ) )
ENDIF
nId   := oVal:Get( "id" )
cLang := oVal:Get( "lang" )
```

---

## 4. Body POST

### Formularios HTML - `UPost`

Cuando el cliente envía `application/x-www-form-urlencoded` o `multipart/form-data`:

```clipper
// POST /login   first=Carles&password=secret

cUser := UPost( "username" )
cPass := UPost( "password" )

// Con default
cRole := UPost( "role", "viewer" )

// Hash completo
hAll := UPost()
```

`UPost` también lee del cuerpo si llega como JSON (auto-detecta el `Content-Type`).

### Body JSON crudo - `UJson`

Cuando el cliente envía `Content-Type: application/json`:

```clipper
// POST /api/users  Content-Type: application/json
// Body: { "name": "Carles", "email": "x@y.com", "tags": ["admin","editor"] }

LOCAL hData := UJson()

IF hData == NIL
   RETURN USendError( 400, "JSON invalido" )
ENDIF

cName := hb_HGetDef( hData, "name", "" )
aTags := hb_HGetDef( hData, "tags", {} )
```

`UJson()` devuelve un hash, un array o `NIL` si el body no es JSON válido.

### Body raw - `UBody`

Para integraciones especiales (webhooks firmados, payloads binarios, XML...):

```clipper
LOCAL cRaw  := UBody()
LOCAL cSig  := UHeader( "X-Signature" )

IF ! _VerifyHmac( cRaw, cSig, cSecret )
   RETURN USendError( 401, "Firma invalida" )
ENDIF

_ProcessWebhook( cRaw )
```

### Tamaño y tipo del body

```clipper
UContentType()      // "application/json"
UContentLength()    // 42 (bytes)
UIsJson()           // .T. si Content-Type es application/json
UIsForm()           // .T. si application/x-www-form-urlencoded
UIsMultipart()      // .T. si multipart/form-data
```

---

## 5. Cabeceras - `UHeader`

Lectura **case-insensitive** de cualquier cabecera HTTP.

```clipper
cAuth   := UHeader( "Authorization", "" )         // "Bearer abc123"
cAccept := UHeader( "Accept",        "" )         // "application/json"
cUA     := UHeader( "User-Agent",    "" )

// Negociación de contenido
UWantsJson()        // .T. si cliente prefiere JSON (Accept o AJAX)
UIsAjax()           // .T. si X-Requested-With: XMLHttpRequest
```

Patrón típico para responder JSON o HTML según el cliente:

```clipper
IF UWantsJson() .OR. UIsAjax()
   USendJson( { "error" => "Not authenticated" }, 401 )
ELSE
   URedirect( "/login" )
ENDIF
```

---

## 6. Cookies - `UCookie`

```clipper
cSid   := UCookie( "session_id", "" )
cTheme := UCookie( "pref_theme", "light" )
```

Las cookies se parsean **una sola vez** y se cachean en el request (lazy). Llamar
repetidamente a `UCookie` no penaliza.

> 📖 Cómo escribir cookies en la respuesta (`USetCookie`) en
> [Response > Cookies](../response/cookies.md).

---

## 7. Uploads multipart - `UFiles`

Cuando un formulario sube ficheros con `enctype="multipart/form-data"`:

```clipper
LOCAL aFiles := UFiles()
LOCAL hFile

FOR EACH hFile IN aFiles
   // hFile["name"]  -> nombre del campo del form
   // hFile["data"]  -> contenido binario
   // hFile["mime"]  -> Content-Type del fichero
   // hFile["size"]  -> tamano en bytes

   IF hFile["size"] > 5 * 1024 * 1024
      RETURN USendError( 413, "Archivo demasiado grande" )
   ENDIF

   hb_MemoWrit( "uploads/" + hFile["name"], hFile["data"] )
NEXT
```

Los campos de texto del mismo formulario se leen con `UPost` normal.

---

## 8. Datos del cliente y sesión

### Identidad del cliente

```clipper
UIP()              // IP real (respeta X-Forwarded-For en modo proxy)
UHost()            // Cabecera Host
UScheme()          // "http" / "https"
UIsHttps()         // .T. si la conexión es segura
```

### Sesión y usuario autenticado

Cuando hay middleware de sesión y/o autenticación activo:

```clipper
// Sesión
cUser := USession( "user" )                  // valor o NIL
USession():Set( "role", "admin" )
USession():Save()

// Usuario autenticado (middleware HIX_MwAuth)
hUser := UAuthUser()                          // hash completo del usuario
cMail := UAuthUser( "email", "" )

IF ! UHasRole( "admin" )
   USendError( 403, "Solo admins" )
   RETURN
ENDIF

// JWT (middleware HixMwJwt)
cSub := UJwt( "sub" )
IF ! UHasScope( "read:products" )
   USendError( 403, "Scope insuficiente" )
   RETURN
ENDIF
```

> 📖 Detalles en [Sesiones](../seguridad/sesiones.md), [Autenticación](../seguridad/autenticacion.md)
> y [JWT](../seguridad/jwt.md).

---

## 9. Acceso de bajo nivel - `URequest` y `UContext`

Para casos especiales puedes obtener el objeto request o el contexto del middleware.

### `URequest()` - el objeto `THixRequest`

```clipper
LOCAL oReq := URequest()

// Acceso directo a hData (datos compartidos entre middlewares y controller)
hUser := hb_HGetDef( oReq:hData, "user", NIL )

// Propiedades crudas
? oReq:cMethod, oReq:cPath, oReq:cQuery
```

Ejemplo real (Fenix `main.prg`):

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown", "roles" => {=>} } )
   LOCAL cName := hUser['name']

   // ... usar hUser para construir la vista
RETU UView( 'main.view.html', cName, hUser )
```

### `UContext()` - el contexto del middleware

Cuando hay middleware activo, los MWs pasan datos al controller vía
`oCtx:hData["clave"]`. Desde el controller los lees con `UContext()`:

```clipper
LOCAL oCtx := UContext()
LOCAL hJwt := oCtx:hData[ "jwt" ]              // payload puesto por HixMwJwt
LOCAL cSid := oCtx:hData[ "_sid" ]             // SID puesto por HixMwSession
```

En la mayoría de casos no necesitas tocar `oCtx` directamente: los helpers
`USession()`, `UJwt()`, `UAuthUser()` ya leen de ahí.

---

## 10. Validación del request

Una vez recolectados los datos, el siguiente paso es **validarlos** con el
validador integrado.

| Helper | Fuente de datos |
|---|---|
| `UValidate( hRules )` | POST (form o JSON) |
| `UValidatePost( hRules )` | POST explícito |
| `UValidateGet( hRules )` | Query string |
| `UValidateParams( hRules )` | Query string + variables de ruta |
| `UValidateJson( hRules )` | Body JSON explícito |
| `UValidateOrFail( hRules )` | POST - auto-responde 422 si falla y devuelve `NIL` |

Patrón típico **PRG** (Post / Redirect / Get) para formularios web:

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

// Datos validados disponibles vía oVal:Get( cKey ) o oVal:DataFields()
```

Patrón típico para APIs JSON:

```clipper
oVal := UValidateOrFail( {                  ;
   "name"  => "required|string|max:100",    ;
   "email" => "required|string|email",      ;
   "age"   => "required|integer|min:18"     ;
} )
IF oVal == NIL ; RETURN NIL ; ENDIF        // ya respondió 422

USendJson( _UserCreate( oVal:DataFields() ), 201 )
```

> 📖 Reglas, modificadores y casos avanzados en [Validator](validator.md).

---

## 11. Tabla rápida de helpers

### Lectura del request

```
UMethod()            UPath()            UQuery()
UGet(k,d)            UPost(k,d)         UParam(k,d)
UHeader(k,d)         UCookie(k,d)       UBody()
UJson()              UContentType()     UContentLength()
UFiles()             URequest()         UContext()
```

### Detectar tipo de petición

```
UIsGet()   UIsPost()   UIsAjax()   UIsHttps()
UIsJson()  UIsForm()   UIsMultipart()   UWantsJson()
UScheme()  UIP()       UHost()          UPort()
```

### Validar input

```
UValidate(h)        UValidatePost(h)   UValidateGet(h)
UValidateParams(h)  UValidateJson(h)   UValidateOrFail(h)
UIsMail(s)  UIsNumeric(v)  UIsInteger(v)  UIsUrl(s)  UIsIp(s)
```

### Identidad / sesión

```
USession()  USession(k)  USession(k,d)
UAuthUser(k,d)  UCurrentUser()  UHasRole(r,op)  UGetRoles()
UJwt(k,d)   UHasScope(s)
```

---

## Anti-patrones - qué evitar

### ❌ Capturar `oReq` en el codeblock

```clipper
// NO - oReq no está en el closure
oSrv:AddRouteGet( "x", "/x", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )

// SÍ - usa helpers U*
oSrv:AddRouteGet( "x", "/x", {|| USendJson( {=>} ) } )
```

### ❌ Mezclar lectura y validación manual

```clipper
// NO - verboso, errores 400 inconsistentes
cName := UPost( "name", "" )
IF Empty( cName ) ; USendError( 422, "name requerido" ) ; RETURN ; ENDIF
IF Len( cName ) > 100 ; USendError( 422, "name muy largo" ) ; RETURN ; ENDIF

// SÍ - declarativo, errores agrupados, sintaxis estándar
oVal := UValidateOrFail( { "name" => "required|string|max:100" } )
IF oVal == NIL ; RETURN NIL ; ENDIF
cName := oVal:Get( "name" )
```

### ❌ Comparar strings con `!=`

Harbour usa `SET EXACT OFF` por defecto - `!=` compara hasta la longitud del más
corto. Usa **siempre** `==`.

```clipper
IF UPath() != "/login"       // ⚠️ falso match con "/lo"
IF UPath() == "/login"       // ✅ correcto
```

### ❌ Convertir todo a `Val()` sin default

```clipper
// NO - Val("") es 0 pero puede ocultar bugs si el parámetro es obligatorio
nId := Val( UParam( "id" ) )

// SÍ - con default explícito o validación
nId := Val( UParam( "id", "0" ) )

// O mejor:
oVal := UValidateParams( { "id" => "required|number|min:0" } )
```

