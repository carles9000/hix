# 📘 HIX - Referencia completa de helpers U*

Los helpers `U*` son funciones globales accesibles desde cualquier ruta, controlador o
archivo `.hrb` sin necesidad de pasar `oReq` como parámetro. El dispatcher llama
`HIX_SetRequest(oReq)` antes de ejecutar cada acción, de modo que los helpers siempre
tienen acceso al request del hilo actual.


---

## 1. Lectura del request

### Datos de entrada

| Funcion | Retorna | Descripcion |
|---|---|---|
| `UMethod()` | `C` | Metodo HTTP en mayusculas: `"GET"`, `"POST"`, `"PUT"`, `"DELETE"`, `"PATCH"` |
| `UPath()` | `C` | Path sin query string: `"/api/users/42"` |
| `UQuery()` | `C` | Query string raw: `"page=1&limit=10"` |
| `UGet(cKey, xDef)` | `X` | Parametro de query string. Sin argumentos devuelve hash completo |
| `UPost(cKey, xDef)` | `X` | Campo de body POST (form o JSON). Sin argumentos devuelve hash completo |
| `UParam(cKey, xDef)` | `C` | Variable de ruta `:var`. Sin default lanza error 400 si no existe |
| `UHeader(cKey, xDef)` | `C` | Cabecera HTTP (case-insensitive) |
| `UCookie(cName, xDef)` | `C` | Cookie del request (parseada una sola vez, lazy) |
| `UBody()` | `C` | Body raw como string |
| `UJson()` | `H`/`A` | Body parseado como JSON; `NIL` si el body no es JSON valido |
| `UContentType()` | `C` | Content-Type en minusculas: `"application/json"` |
| `UContentLength()` | `N` | Longitud en bytes del body |
| `UFiles()` | `A` | Array de hashes de archivos subidos (multipart). Ver seccion uploads |
| `URequest()` | `O` | Objeto `THixRequest` del hilo actual (acceso de bajo nivel) |
| `UContext()` | `O` | `THixContext` del middleware actual (acceso a `oCtx:hData`); `NIL` si no esta en cadena MW |

**UGet / UPost sin argumentos**: devuelven un hash con todos los campos.

```clipper
// Obtener todos los parametros GET de una vez
hParams := UGet()   // { "page" => "1", "limit" => "10" }

// Obtener un campo con default
cNombre := UPost( "nombre", "Anonimo" )

// Variable de ruta con default seguro
nId := Val( UParam( "id", "0" ) )

// Variable de ruta sin default — lanza 400 si falta
cSlug := UParam( "slug" )
```

**UParam con indice numerico**: cuando la ruta usa `*` el comodin se captura como `_1`.

```clipper
oSrv:AddRouteGet( "static", "/static/*", {||
   cFile := UParam( 1 )   // equivale a UParam("_1")
} )
```

### Tipo y negociacion de contenido

| Funcion | Retorna | Descripcion |
|---|---|---|
| `UIsGet()` | `L` | `.T.` si el metodo es GET |
| `UIsPost()` | `L` | `.T.` si el metodo es POST |
| `UIsAjax()` | `L` | `.T.` si `X-Requested-With: XMLHttpRequest` |
| `UIsHttps()` | `L` | `.T.` si la conexion es HTTPS |
| `UScheme()` | `C` | `"http"` o `"https"` |
| `UIsJson()` | `L` | `.T.` si el Content-Type es `application/json` |
| `UIsForm()` | `L` | `.T.` si el Content-Type es `application/x-www-form-urlencoded` |
| `UIsMultipart()` | `L` | `.T.` si el Content-Type es `multipart/form-data` |
| `UWantsJson()` | `L` | `.T.` si el cliente prefiere JSON (cabecera Accept o AJAX) |

### Datos del cliente

| Funcion | Retorna | Descripcion |
|---|---|---|
| `UIP()` | `C` | IP real del cliente (respeta `X-Forwarded-For` si `mode=proxied`) |
| `UHost()` | `C` | Hostname del request (cabecera `Host`) |
| `UPort()` | `N` | Puerto del servidor |

### Uploads multipart

```clipper
aFiles := UFiles()
FOR EACH hFile IN aFiles
   // hFile["name"]  -> nombre del campo
   // hFile["data"]  -> contenido binario
   // hFile["mime"]  -> Content-Type del archivo
   // hFile["size"]  -> tamano en bytes
   hb_MemoWrit( "uploads/" + hFile["name"], hFile["data"] )
NEXT
```

---

## 2. Enviar respuestas

### Respuestas directas

| Funcion | Descripcion |
|---|---|
| `USendJson(xData [, nStatus])` | JSON 200. `xData` puede ser hash, array o string |
| `USendHtml(cHtml [, nStatus])` | HTML 200 |
| `USendText(cText [, nStatus])` | `text/plain` 200 |
| `USendView(cView [, hVars])` | Renderiza template y envia HTML |
| `USendEmpty()` | 204 No Content |
| `USendError(nStatus, cDetail)` | Error HTTP con mensaje de detalle |
| `URedirect(cUrl [, nStatus])` | Redireccion (302 por defecto) |

```clipper
// Respuesta JSON simple
USendJson( { "ok" => .T. } )

// Con status custom
USendJson( { "id" => 42, "name" => "Test" }, 201 )

// Redireccion permanente
URedirect( "/nueva-url", 301 )

// Error HTTP
USendError( 403, "Sin permisos" )
```

### Control fino del buffer

Cuando necesitas construir la respuesta paso a paso antes de enviarla:

| Funcion | Descripcion |
|---|---|
| `UWrite(cText)` | Acumula texto en el buffer de respuesta |
| `UEcho(cText)` | Alias de `UWrite` |
| `USetStatus(nStatus)` | Fija el status HTTP del buffer |
| `USetMime(cMime)` | Fija el MIME del buffer (`"json"`, `"html"`, `"text"` o MIME completo) |
| `UGetMime()` | Retorna el MIME configurado actualmente |
| `USetHeader(cKey, cVal)` | Agrega cabecera extra a la respuesta |
| `UFlush()` | Envia el buffer acumulado como chunk (inicia streaming si es la primera vez) |

```clipper
// Construir JSON manualmente
USetStatus( 201 )
USetMime( "json" )
USetHeader( "X-Request-Id", "abc123" )
UWrite( hb_jsonEncode( { "created" => .T. } ) )
// El dispatcher envia el buffer al terminar la accion
```

### Cookies en respuesta

| Funcion | Descripcion |
|---|---|
| `USetCookie(cName, cVal, nMaxAge)` | Escribe `Set-Cookie` en la respuesta |

`nMaxAge`:
- `0` — cookie de sesion (sin `Max-Age`)
- `-1` — expirar inmediatamente (`Max-Age=0`)
- `> 0` — duracion en segundos

Los flags `HttpOnly; SameSite=Lax; Path=/` se agregan automaticamente.

```clipper
USetCookie( "session_id", cSid, 3600 )   // 1 hora
USetCookie( "pref", "dark", 0 )          // sesion
USetCookie( "old_cookie", "", -1 )       // expirar
```

---

## 3. Streaming chunked

Para SSE, descargas progresivas o respuestas de larga duracion:

| Funcion | Descripcion |
|---|---|
| `USendStreamStart(cMime, nStatus, hExtra)` | Inicia respuesta chunked; cabeceras extras en `hExtra` |
| `USendChunk(cData)` | Envia un fragmento de datos |
| `USendStreamEnd()` | Cierra el stream (chunk de longitud cero) |

```clipper
// SSE — Server-Sent Events
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

## 4. Sesion

| Funcion | Descripcion |
|---|---|
| `USession()` | Devuelve un objeto proxy con metodos `Get/Set/Save/Destroy` |
| `USession(cKey)` | Lee un valor de la sesion; `NIL` si no existe |
| `USession(cKey, xDef)` | Lee un valor con default |

```clipper
// Leer un campo
cUser := USession( "user" )

// Escribir y guardar
USession():Set( "user", "carles" )
USession():Set( "role", "admin" )
USession():Save()   // renueva TTL y emite Set-Cookie

// Destruir sesion
USession():Destroy()
```

> Requiere que `HIX_MwSession` este registrado como middleware en la ruta.

---

## 5. JWT

| Funcion | Descripcion |
|---|---|
| `UJwt()` | Devuelve el hash completo del payload JWT; `NIL` si no hay JWT |
| `UJwt(cKey)` | Devuelve un claim del payload; `NIL` si no existe |
| `UJwt(cKey, xDef)` | Devuelve un claim con default |
| `UHasScope(cScope)` | `.T.` si el JWT incluye el scope indicado en el campo `scope` |

```clipper
// Leer claim
cSub  := UJwt( "sub" )
nExp  := UJwt( "exp", 0 )

// Verificar scope
IF ! UHasScope( "read:products" )
   USendError( 403, "Scope insuficiente" )
   RETURN
ENDIF
```

> Requiere que `HixMwJwt` este registrado como middleware en la ruta.

---

## 6. Autenticacion y roles

Disponibles cuando el middleware `HIX_MwAuth` o `HIX_MwIsAuth` esta activo.

| Funcion | Descripcion |
|---|---|
| `UCurrentUser()` | Hash completo del usuario autenticado; `NIL` si no hay sesion |
| `UAuthUser()` | Hash del usuario del request (set por middleware); `NIL` si no autenticado |
| `UAuthUser(cKey)` | Campo del hash del usuario |
| `UAuthUser(cKey, xDef)` | Campo del hash con default |
| `UHasRole(cRole)` | `.T.` si el usuario tiene el rol (acceso completo) |
| `UHasRole(cRole, cOp)` | `.T.` si el usuario tiene el rol con la operacion indicada |
| `UGetRoles()` | Hash de roles del usuario: `{ "admin" => "", "editor" => "read;write" }` |
| `UAuthLogout()` | Destruye la sesion y limpia el usuario actual |

```clipper
// Verificar rol
IF ! UHasRole( "admin" )
   USendError( 403, "Solo administradores" )
   RETURN
ENDIF

// Verificar rol con operacion granular
IF ! UHasRole( "products", "delete" )
   USendError( 403, "Sin permiso de borrado" )
   RETURN
ENDIF

// Leer datos del usuario
hUser := UAuthUser()
cEmail := UAuthUser( "email", "" )

// Cerrar sesion
UAuthLogout()
URedirect( "/login" )
```

---

## 7. Validacion

### Construir un validador

| Funcion | Fuente de datos |
|---|---|
| `UValidate(hRules)` | POST (form o JSON) |
| `UValidatePost(hRules)` | POST explicito |
| `UValidateGet(hRules)` | Query string |
| `UValidateParams(hRules)` | Query string + variables de ruta fusionadas |
| `UValidateJson(hRules)` | Body JSON explicito |
| `UValidateInput(hRules)` | Equivalente a `UValidatePost` (form body POST) |
| `UValidateOrFail(hRules)` | POST — responde 422 automaticamente si falla; devuelve `NIL` |

Todas aceptan un segundo parametro opcional `hSanitate` con reglas de sanitizacion.

### Flujo tipico

```clipper
FUNCTION _CreateUser()
   LOCAL oVal := UValidateOrFail( { ;
      "name"  => "required|string|max:100", ;
      "email" => "required|string|email",   ;
      "age"   => "required|integer|min:18"  ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF   // ya respondio 422

   cName  := oVal:Get( "name" )
   cEmail := oVal:Get( "email" )
   nAge   := oVal:Get( "age" )
   // ...
   USendJson( { "ok" => .T. }, 201 )
RETURN NIL
```

### Manejo manual de errores

```clipper
LOCAL oVal := UValidatePost( hRules )
IF ! oVal:Make()
   USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
   RETURN
ENDIF
```

### Reglas disponibles

```
required            campo obligatorio (no vacio)
string              tipo string
integer             entero
numeric             numero (int o decimal)
boolean             logico
array               array
min:N               string: longitud >= N  /  numero: valor >= N
max:N               string: longitud <= N  /  numero: valor <= N
minlen:N            longitud string >= N
maxlen:N            longitud string <= N
between:N:M         numero entre N y M
email               formato email
url                 empieza por http:// o https://
ip                  IPv4 valida
regex:PATRON        expresion regular Harbour
in:a,b,c            valor en lista
notin:a,b           valor no en lista
field               incluye el campo en DataFields() si valido
```

Sanitizacion (se aplican antes de validar):

```
trim                AllTrim()
lower               Lower()
upper               Upper()
```

### Predicados rapidos

| Funcion | Descripcion |
|---|---|
| `UIsMail(cStr)` | `.T.` si `cStr` tiene formato de email |
| `UIsNumeric(uValue)` | `.T.` si el valor es numerico (numero o string numerico) |
| `UIsInteger(uValue)` | `.T.` si el valor es un entero |
| `UIsUrl(cStr)` | `.T.` si empieza por `http://` o `https://` |
| `UIsIp(cStr)` | `.T.` si es una IPv4 valida |

---

## 8. Vistas / Templates

| Funcion | Descripcion |
|---|---|
| `USendView(cView [, hVars])` | Renderiza el template y envia la respuesta HTML |
| `UView(cView [, hVars])` | Renderiza el template y devuelve el HTML como string |

Los templates se ubican en `www/views/` con extension `.html`.

```clipper
// Renderizar y enviar
USendView( "users/list.html" )

// Con variables
USendView( "users/edit.html", { ;
   "cName" => "Carles", ;
   "nAge"  => 42        ;
} )

// Solo obtener el HTML (para componer partials)
cPartial := UView( "partials/header.html", { "cTitle" => "Mi app" } )
USendHtml( cPartial + "<main>contenido</main>" )
```

Formato del template:

```html
@args cName, nAge

<html>
<body>
  <h1>Editar: {{ cName }}</h1>
  <p>Edad: {{ hb_NToS(nAge) }}</p>
</body>
</html>
```

---

## 9. Herramientas de vista

### Conversion de tipos

| Funcion | Descripcion |
|---|---|
| `UStr(u)` | Convierte cualquier tipo Harbour a string (C, N, L, D, A, H) |
| `UDateToHtml(dFecha)` | Fecha Harbour a string `"YYYY-MM-DD"` para inputs HTML |
| `ULogicToHtmlChecked(lValue)` | `.T.` → `"checked"`, `.F.` → `""` (para checkboxes) |
| `UHtmlEncode(cText)` | Escapa entidades HTML (`&`, `<`, `>`, `"`, `'`) en una pasada |
| `UOsFileName(cFileName)` | Normaliza separadores de path al separador del sistema operativo |

### Select HTML

```clipper
// UHashToHtmlSelect( aHash, cSelect, cKey, cValue )
// aHash: array de hashes con campos clave y valor
// cSelect: valor actualmente seleccionado
// cKey: nombre del campo clave en cada hash (default "key")
// cValue: nombre del campo valor en cada hash (default "value")

aItems := { { "key" => "es", "value" => "Espanol" }, ;
            { "key" => "en", "value" => "English" } }
cHtml := UHashToHtmlSelect( aItems, "es", "key", "value" )
// <option value="" ></option>
// <option value="es" selected>Espanol</option>
// <option value="en">English</option>
```

### Rutas nombradas

```clipper
// URoute( cName, param1, param2, ... )
cUrl := URoute( "user", 42 )       // -> "/users/42"
cUrl := URoute( "post", "mi-slug" ) // -> "/posts/mi-slug"
```

---

## 10. CSRF

Para proteger formularios HTML contra ataques Cross-Site Request Forgery.

| Funcion | Descripcion |
|---|---|
| `UCsrfToHtml([cToken])` | Genera `<input type="hidden" name="_csrf" value="...">` |
| `HIX_CsrfMakeToken([cData])` | Genera un token CSRF firmado con la clave `csrf` del store `HIX_Keys` |
| `HIX_CsrfValidToken(cToken [, nLapsus])` | `.T.` si el token es valido. `nLapsus` en segundos (0 = sin expiracion) |
| `HIX_CsrfGenRandom([nLen])` | Genera un string aleatorio de `nLen` bytes |

```clipper
// En la accion GET que sirve el formulario
USendView( "form.html", { "cCsrf" => UCsrfToHtml() } )

// En el template
// {{ cCsrf }}   -- emite el <input hidden>

// En la accion POST que procesa el formulario
IF ! HIX_CsrfValidToken( UPost( "_csrf" ), 3600 )
   USendError( 403, "Token CSRF invalido" )
   RETURN
ENDIF
```

---

## 11. Resource ID

Firma un ID opaco para que no sea predecible en formularios HTML.

| Funcion | Descripcion |
|---|---|
| `UResourceToHtml(cId)` | Genera `<input type="hidden" name="_resource_id" value="...">` con el ID firmado |
| `UGetResource([cToken])` | Valida el token y devuelve el ID original; `""` si invalido |

```clipper
// En la vista (lista de registros)
// {{ UResourceToHtml( hb_NToS(nId) ) }}

// En la accion POST (eliminar, editar, ...)
cId := UGetResource()   // lee _resource_id del POST automaticamente
IF Empty( cId )
   USendError( 400, "ID de recurso invalido" )
   RETURN
ENDIF
nId := Val( cId )
```

---

## 12. Flash messages

Mensajes temporales de validacion por formulario, almacenados en sesion y destruidos al leerlos.

| Metodo | Descripcion |
|---|---|
| `UFlash([cFormId])` | Crea un objeto `TFlash` para el formulario indicado |
| `oFlash:Set(cKey, xVal)` | Guarda un valor flash |
| `oFlash:Get(cKey [, xDef])` | Lee y elimina el valor flash |
| `oFlash:Has(cKey)` | `.T.` si existe el valor |
| `oFlash:Delete(cKey)` | Elimina un valor sin leerlo |
| `oFlash:Clear()` | Limpia todos los valores del formulario |
| `oFlash:Save()` | Persiste los cambios en sesion |
| `oFlash:Destroy()` | Destructor: guarda automaticamente al salir de scope |

```clipper
// Guardar error en el POST
oFlash := UFlash( "login-form" )
oFlash:Set( "error", "Credenciales incorrectas" )
oFlash:Set( "email", UPost( "email" ) )
oFlash:Save()
URedirect( "/login" )

// Leer en el GET siguiente
oFlash := UFlash( "login-form" )
cError := oFlash:Get( "error", "" )
cEmail := oFlash:Get( "email", "" )
```

---

## 13. Entorno y configuracion

| Funcion | Descripcion |
|---|---|
| `UEnv()` | Entorno actual: `"dev"` o `"prod"` |
| `UIsDev()` | `.T.` si `UEnv() == "dev"` |
| `UIsProd()` | `.T.` si `UEnv() == "prod"` |
| `UConfig(cKey [, xDef])` | Valor de `THixConfig` por nombre de campo |
| `UMwConfig(cSection, cKey [, xDef])` | Valor de `www/middlewares/config.json` seccion `setup` |
| `UNow()` | Timestamp actual como string `"YYYYMMDDHHmmss"` |
| `URoot()` | Nombre de la carpeta web root (por defecto `"www"`) |
| `URootPath()` | Path absoluto al web root con separador final |

```clipper
IF UIsDev()
   l( "Debug: " + hb_jsonEncode( hData ) )
ENDIF

cPort := UConfig( "nPort", "8080" )
cKey  := UMwConfig( "auth", "session_user_key", "_auth_user" )
```

---

## 14. Tabla rapida de referencia

### Leer request

```
UMethod()           UPath()             UQuery()
UGet(k,d)           UPost(k,d)          UParam(k,d)
UHeader(k,d)        UCookie(k,d)        UBody()
UJson()             UContentType()      UContentLength()
UFiles()            URequest()          UContext()
```

### Detectar tipo

```
UIsGet()    UIsPost()   UIsAjax()   UIsHttps()
UIsJson()   UIsForm()   UIsMultipart()  UWantsJson()
UScheme()   UIP()       UHost()         UPort()
```

### Enviar respuesta

```
USendJson(x,n)      USendHtml(c,n)      USendText(c,n)
USendView(v,h)      USendEmpty()        USendError(n,c)
URedirect(u,n)      USend(x,n,m,h)
```

### Controlar buffer

```
UWrite(c)   UEcho(c)    USetStatus(n)   USetMime(c)
UGetMime()  USetHeader(k,v)  USetCookie(k,v,n)  UFlush()
```

### Streaming

```
USendStreamStart(m,n,h)   USendChunk(c)   USendStreamEnd()
```

### Sesion y auth

```
USession()  USession(k)  USession(k,d)
UJwt()      UJwt(k)      UJwt(k,d)     UHasScope(s)
UCurrentUser()  UAuthUser(k,d)
UHasRole(r)     UHasRole(r,op)  UGetRoles()  UAuthLogout()
```

### Validacion

```
UValidate(h)    UValidatePost(h)  UValidateGet(h)
UValidateParams(h)  UValidateJson(h)  UValidateInput(h)  UValidateOrFail(h)
UIsMail(s)  UIsNumeric(v)  UIsInteger(v)  UIsUrl(s)  UIsIp(s)
```

### Vistas y herramientas

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
