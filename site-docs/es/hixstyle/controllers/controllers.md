# 🎮 Controllers

## 📂 `<root>/controllers`

Un **controller** en HIX es la unidad de código que recibe un request HTTP, lo procesa
y devuelve una respuesta. Es el puente entre una **ruta** (la URL) y la **lógica de
negocio** (modelos, base de datos, servicios externos).

Mientras una ruta dice *"cuando llegue `GET /customer/:id` hay que hacer algo"*, el
controller es el *"algo"* - el código real que ejecuta esa intención.

> Un controller en HIX **no es una clase obligatoria**. Puede ser desde un codeblock
> de una sola línea hasta un fichero `.prg` con clase y métodos para implementar un
> CRUD completo. Usa el formato que mejor se adapte al tamaño del endpoint.

---

## Ciclo de vida de un request

Cuando llega un request HTTP, HIX ejecuta esta secuencia:

```
HTTP Request
   │
   ▼
┌──────────────────┐
│      Router      │  busca ruta que case con URL + método
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    Middleware    │  cadena de MWs (auth, CORS, RateLimit, Session...)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    Controller    │  ← tú estás aquí
│  ─────────────   │
│  1. Recolección  │  UGet, UPost, UParam, UHeader, UCookie, UJson...
│  2. Validación   │  UValidate, UValidatePost, UValidateParams...
│  3. Proceso      │  modelos (TCustomers, TStates...), lógica de negocio
│  4. Output       │  UView, USendJson, URedirect, USendError
└────────┬─────────┘
         │
         ▼
HTTP Response
```

El controller es la **etapa 3**: el código que se ejecuta una vez que la ruta ha
sido identificada y los middlewares han dado el visto bueno.

---

## Cómo se invoca un controller desde una ruta

El tercer parámetro de `AddRouteXxx` (`bAction`) define **qué controller** se ejecuta.
HIX acepta varios formatos:

### 1. Codeblock inline

Para endpoints triviales.

```clipper
oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )
```

### 2. Fichero `.prg` con `Main()`

Ruta relativa al web root (`www/`). HIX compila al vuelo y ejecuta `Main()`.

```clipper
oSrv:AddRouteGet( "main", "/main", "controllers/main.prg" )
```

En el fichero de configuracion de rutas dentro de `/routes`
```json
{ "name": "logout", "url": "/logout", "action": "controllers/logout.prg" }
```

### 3. Método de clase - `metodo@clase.prg`

Variante más profesional para agrupar acciones de un mismo recurso (CRUD).

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

> 📖 Patrones de ruta completos en [Rutas](../routes/routes.md).

---

## Formato simple - `Main()`

Un fichero `.prg` con una función `Main()` que ejecuta toda la acción. Ejemplo real:
el **login**.

### `controllers/login.prg` - pintar el formulario

```clipper
/*-----------------------------------------------------------
  File ......: login.prg
  Description: GET /login - loads flash error/username set by
               auth.prg on failed login.
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

### `controllers/auth.prg` - procesar el POST

Patrón **PRG** (Post / Redirect / Get): un POST nunca devuelve HTML, siempre
redirige. Esto evita que un F5 re-envíe el formulario.

```clipper
/*-----------------------------------------------------------
  File ......: auth.prg
  Description: Login controller - validates credentials and
               starts a session.
  Usage      : POST /login  (form fields: username, password)
 -----------------------------------------------------------*/

#include "hbclass.ch"

FUNCTION Main()
   LOCAL oVal, oSess, hUser

   // 1. Validate input
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

   // 2. Buscar usuario en el modelo
   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   // 3. Respuesta - siempre redirect
   IF ValType( hUser ) == "H"
      oSess := USession()
      oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
      oSess:Save()
      URedirect( UMwConfig( "auth", "redirect_accept" ) )
   ELSE
      UFlash( "login" ):Set( { ;
         "error" => "Usuario o contrasena incorrectos", ;
         "user"  => oVal:Get( "username" )              ;
      } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )
   ENDIF

RETURN

#include '/models/modeluser.prg'
```

### `controllers/logout.prg` - destruir sesión

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

> 💡 **Patrón PRG**: tras un `POST` nunca devuelvas HTML - siempre `URedirect` con
> mensajes flash. En APIs JSON es distinto: ahí sí respondes con JSON directo.

---

## Formato CRUD - `metodo@clase.prg`

Cuando un recurso tiene varias acciones (búsqueda, edición, alta, baja, etc.), todas
se agrupan en una clase. HIX llama al método indicado en la ruta.

Cabecera típica con la tabla de rutas del recurso:

```clipper
/*
 | Nom Ruta        | URL              | Método | Función          | Descripción    |
 | --------------- | ---------------- | ------ | ---------------- | -------------- |
 | customer.search | /customer/search | GET    | search@customer  | Buscar         |
 | customer.show   | /customer/:id    | GET    | show@customer    | Mostrar uno    |
 | customer.edit   | /customer/:id/edit | GET  | edit@customer    | Form editar    |
 | customer.update | /customer/update | POST   | update@customer  | Actualizar     |
 | customer.create | /customer/create | GET    | create@customer  | Form crear     |
 | customer.store  | /customer        | POST   | store@customer   | Guardar nuevo  |
 | customer.delete | /customer/delete | POST   | delete@customer  | Eliminar       |
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

## 1. Recolección de datos del request

Dentro del controller usas los helpers `U*` para leer cualquier dato del request
sin necesidad de pasar `oReq`: el dispatcher lo deja en el hilo actual.

| Fuente | Helper | Ejemplo |
|---|---|---|
| Variable de ruta `:var` | `UParam(k, def)` | `UParam("id")` |
| Query string `?k=v` | `UGet(k, def)` | `UGet("page", "1")` |
| Body POST (form o JSON) | `UPost(k, def)` | `UPost("first")` |
| Body JSON parseado | `UJson()` | `hData := UJson()` |
| Body raw | `UBody()` | `cRaw := UBody()` |
| Cabecera HTTP | `UHeader(k, def)` | `UHeader("X-Api-Key")` |
| Cookie | `UCookie(name, def)` | `UCookie("auth_token")` |
| Uploads multipart | `UFiles()` | `aFiles := UFiles()` |
| Sesión | `USession(k, def)` | `USession("user")` |
| Resource ID firmado | `UGetResource()` | `cId := UGetResource()` |
| Método HTTP | `UMethod()` | `IF UMethod() == "POST"` |
| URL del request | `UPath()`, `UQuery()` | |
| IP / host del cliente | `UIP()`, `UHost()` | |

Ejemplo del controller `main.prg` de Fenix, que lee el usuario de la sesión vía
`URequest():hData`:

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown", "roles" => {=>} } )
   LOCAL cName := hUser['name']
   LOCAL cKey, cRoles := ''

   FOR EACH cKey IN hUser["roles"]
      cRoles += cKey:__enumKey() + " "
   NEXT

   IF Empty( cRoles ) ; cRoles := "(none)" ; ENDIF

RETU UView( 'main.view.html', cName, hUser, cRoles )
```

> 📖 Catálogo completo de helpers en
> [Mapa de helpers U*](../../programacion/mapa-helpers.md).

---

## 2. Validación

Antes de procesar cualquier dato hay que validarlo. HIX trae un validador integrado
con sintaxis declarativa y formato extendido `{ "reglas", "Label", "default" }`.

### Formato extendido de reglas

```clipper
oVal := UValidatePost( { ;
   "username" => { "required|min:3|max:30", "Username", "" }, ;
   "password" => { "required|min:4",        "Password", "" }  ;
} )
```

- `"required|min:3|max:30"` - cadena de reglas separadas por `|`
- `"Username"` - etiqueta humana usada en los mensajes de error
- `""` - valor por defecto si no llega

### Patrón típico - Validar + Flash + Redirect

```clipper
METHOD Update() CLASS Customer

   LOCAL cId := UGetResource()        // ID firmado del registro
   LOCAL oVal, nId, cError, lSuccess
   LOCAL oCustomers

   // Validar el resource_id (single-field validator)
   IF Empty( cId )
      RETU URedirect( URoute( 'main' ) )
   ENDIF

   oVal := UValidatorOne( 'Id', cId, "required|number|min:0" )
   IF oVal:Fails()
      RETU URedirect( URoute( 'customer.search' ) )
   ENDIF
   nId := oVal:Get()

   // Validar campos del formulario
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
         "message" => 'Error validacion',        ;
         "errors"  => oVal:GetErrors(),          ;
         "input"   => oVal:Resume()              ;
      } )
      RETU URedirect( URoute( 'customer.edit', nId ) )
   ENDIF

   // ... continúa con el proceso
```

### Modificadores de regla útiles

| Sufijo | Efecto |
|---|---|
| `\|field` | Incluye el campo en `oVal:DataFields()` (hash listo para insertar/update) |
| `\|escapedfield` | Igual + escapa HTML del valor |
| `\|resume` | Lo incluye en `oVal:Resume()` (para rellenar el form si hay error) |

### Métodos clave de `oVal`

| Método | Para qué |
|---|---|
| `Make()` | Lanza la validación; devuelve `.T./.F.` |
| `Fails()` | `.T.` si falló |
| `Get(k)` | Valor validado de un campo |
| `GetErrors()` | Hash con los errores por campo |
| `GetFirstError()` | Primer error como string (útil para flash en logins) |
| `DataFields()` | Hash con campos marcados `\|field` (para `Insert/Update`) |
| `Resume()` | Hash con todos los campos (para rellenar el form al volver) |

> 📖 Reglas completas, sanitización y casos avanzados en [Validator](validator.md).

---

## 3. Proceso - lógica de negocio

El controller orquesta, no implementa. Llama a **modelos** (`TCustomers`, `TStates`,
`ModelUser`, etc.) que encapsulan toda la lógica de datos.

```clipper
METHOD Show() CLASS Customer

   LOCAL oVal, oCustomers, oStates, oFlash
   LOCAL hRow      := {=>}
   LOCAL hMessage  := {=>}
   LOCAL lFound

   // 1. Validar el id
   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      UFlash( "customer" ):Set( {                ;
         "errors"  => oVal:GetErrors(),          ;
         "message" => "Error validacion",        ;
         "input"   => oVal:Resume()              ;
      } )
      RETURN URedirect( URoute( 'customer.search' ) )
   ENDIF

   // 2. Buscar en el modelo
   oCustomers := TCustomers()
   lFound := oCustomers:GetRecno( oVal:Get( 'id' ), @hRow, NIL, .T. )

   IF lFound
      // Enriquecer con datos relacionados
      oStates := TStates()
      oStates:Seek( hRow[ 'state' ], NIL, 'code' )
      hRow[ 'state_txt' ] := oStates:FieldGet( 'name' )

      // Recuperar flash de operaciones previas
      oFlash := UFlash( 'customer' )
      hMessage[ 'type'    ] := oFlash:Get( 'type'    )
      hMessage[ 'message' ] := oFlash:Get( 'message' )
   ELSE
      hRow := oCustomers:Blank( .T. )
      hRow[ 'state_txt' ] := ''
   ENDIF

   // 3. Output - renderizar vista
RETU UView( 'masters/customer/show.html', lFound, hRow, hMessage )
```

Buenas prácticas:

- **Controller fino, modelo gordo.** Persistencia y reglas complejas viven en el
  modelo (`TCustomers:Insert`, `:Update`, `:Delete`, ...), no en el controller.
- **Una acción = una intención HTTP.** Si un método hace tres cosas, suelen ser
  tres acciones distintas.
- **Errores con `URedirect` + flash** en formularios HTML; **`USendError(n, txt)`
  + `RETURN`** en APIs JSON.
- **Carga de modelos al final**: `#include 'models/tcustomers.prg'` al cierre del
  fichero para que se compilen junto al controller.

---

## 4. Output - enviar la respuesta

El último paso del controller envía la respuesta al cliente.

### Estrategia según el tipo de endpoint

| Tipo de endpoint | Patrón |
|---|---|
| GET que pinta HTML | `RETURN UView( "ruta/vista.html", arg1, arg2, ... )` |
| POST que modifica datos | `URedirect( URoute( "destino" ) )` + flash |
| API REST | `USendJson( hash [, nStatus] )` |
| DELETE exitoso (API) | `USendEmpty()` (204) |
| Error HTTP (API) | `USendError( nStatus, cDetail )` |

### Vistas - `UView`

`UView` renderiza un template `.html` con el motor Mambo. Los argumentos
posicionales se pasan tal cual al template (declarados con `@args`).

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

   // Recuperar flash si venimos de un POST con error
   oFlash := UFlash( 'customer' )
   hMessage[ 'type'    ] := oFlash:Get( 'type'    )
   hMessage[ 'message' ] := oFlash:Get( 'message' )
   hInput                := oFlash:Get( 'input'   )
   hErrors               := oFlash:Get( 'errors', {=>} )

   // Cargar combos
   oStates := TStates()
   aStates := oStates:LoadAll()

   // Si hay input (venimos de un Update con error), repintar el form con los datos
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

### Redirects con `URoute`

Siempre se usa `URoute( cName, ... )` en lugar de literales - así si cambia la URL
solo lo tocas en la definición de la ruta.

```clipper
URedirect( URoute( 'customer.show', nId ) )       // -> /customer/42
URedirect( URoute( 'customer.search' ) )          // -> /customer/search
```

### Flash messages

Mensajes que se guardan en sesión y se consumen una sola vez en el siguiente request.
Imprescindibles para mantener mensajes a través de un `URedirect`.

```clipper
// Tras un POST con éxito
UFlash( "customer" ):Set( { ;
   "type"    => 'success',                                        ;
   "message" => 'Customer ' + LTrim( Str( nId ) ) + ' was updated!' ;
} )
RETU URedirect( URoute( 'customer.show', nId ) )
```

### APIs JSON

Cuando el endpoint es una API REST en lugar de un formulario web:

```clipper
// Respuesta JSON simple
USendJson( { "id" => 42, "name" => "Carles" } )

// Con status custom
USendJson( { "id" => nNewId }, 201 )

// Error
USendError( 404, "Producto no encontrado" )

// DELETE exitoso
USendEmpty()
```

### Streaming chunked (SSE, descargas)

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

## Patrón completo - CRUD Customer

Combina todo: validación, modelo, flash, redirect, vistas. Implementación real del
método **`Store`** (alta) de Fenix:

```clipper
METHOD Store() CLASS Customer

   LOCAL oVal, oCustomers, oStates, cError, lSuccess, nRecno

   // 1. Validación
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
         "message" => 'Error validacion',      ;
         "errors"  => oVal:GetErrors(),        ;
         "input"   => oVal:Resume()            ;
      } )
      RETU URedirect( URoute( 'customer.create' ) )
   ENDIF

   // 2. Proceso - insertar en el modelo
   oCustomers := TCustomers()
   lSuccess := oCustomers:Insert( oVal:DataFields(), @cError, @nRecno )

   // 3. Output - redirect según resultado
   IF lSuccess
      UFlash( "customer" ):Set( {                                            ;
         "type"    => 'success',                                             ;
         "message" => 'Customer ' + LTrim( Str( nRecno ) ) + ' was created!' ;
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

Y al cierre del fichero, los modelos que el controller usa:

```clipper
#include 'models/tcustomers.prg'
#include 'models/tstates.prg'
```

---

## Buenas prácticas

1. **Un fichero por recurso.** `customer.prg` agrupa todas las acciones del recurso
   `customer`. Nombres de método RESTful: `Search`, `Show`, `Edit`, `Update`,
   `Create`, `Store`, `Delete`.

2. **Patrón PRG (Post / Redirect / Get).** Un POST nunca devuelve HTML - siempre
   redirige (éxito o fallo). Evita re-envíos al pulsar F5.

3. **Flash + URoute para arrastrar estado.** Mensajes, errores e input se pasan
   entre requests con `UFlash(formId):Set({...})` antes del `URedirect( URoute(...) )`.

4. **Resource IDs firmados.** En formularios de edición/borrado usa `UGetResource()`
   en vez de pasar IDs en claro - evita modificación manual del HTML.

5. **`LOCAL` al inicio.** Harbour exige todas las declaraciones `LOCAL` antes de
   cualquier instrucción ejecutable. No declares LOCAL dentro de IFs.

6. **Validar primero, procesar después.** Si falla la validación, flash + redirect
   (web) o `USendJson(...,422)` (API). Aborta cuanto antes.

7. **Tabla de rutas en la cabecera del controller.** El bloque comentado al
   principio de la clase documenta de un vistazo todas las URLs del recurso.

8. **Lógica de datos fuera del controller.** Las clases `Txxx` (modelos) implementan
   `:Insert`, `:Update`, `:Delete`, `:GetRecno`, `:Blank`, etc. El controller solo
   las orquesta.

9. **Centraliza URLs y redirects en config.** `UMwConfig( "auth", "redirect_login" )`
   permite cambiar destinos sin tocar código.

10. **`#include 'models/xxx.prg'`** al final del controller para que los modelos se
    compilen junto al fichero.

