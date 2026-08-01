# 🗺️ Rutas

## 📂 `<root>/routes`

Una ruta es la asociación entre un patrón de URL, un método HTTP y la acción que debe ejecutarse 
cuando llega una petición que coincide.

Cuando por ejemplo especificamos en la url `https://mi_dominio/hello` indicamos al servidor a ejecutar 
en este caso una accion identificada como `hello`.

Cuando **HIX** recibe un request, el dispatcher recorre las rutas registradas **por orden de especificidad** 
(las más concretas primero) buscando una que case con la URL y el método. 

Un segmento literal (`/users`) puntúa 10; un parámetro variable (`:id`) puntúa 1.
    `/users/profile` se evaluará antes que `/users/:id`.

En cuanto encuentra una:

1. Ejecuta la cadena de **middleware** asignada a esa ruta (opcional).
2. Si el middleware aprueba, ejecuta la **acción**.

---

## Definición de rutas

**HIX** permite manejar las rutas de 2 maneras distintas:  
 
- Definiéndolas a nivel programa (Servidor)

- Definiéndolas a nivel fichero que se leerá cuando se inicialice el servidor (data-driven)

El uso de cualquiera de estas maneras es elección del programador y no varia el comportamiento

### En código — servidor

Para definir las rutas a nivel código de aplicación, una vez tengamos instanciado el objeto server 
con `THixServer():New()` podremos definir las rutas usando los siguiente métodos.


| Método | Verbo HTTP |
|--------|------------|
| `AddRouteGet` | GET |
| `AddRoutePost` | POST |
| `AddRoutePut` | PUT |
| `AddRouteDelete` | DELETE |
| `AddRoute` | Cualquiera — se pasa el método como quinto parámetro |

La creación de una ruta tiene los siguientes parámetros

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `cName` | String | Identificador lógico único. Prefijo `hix.` reservado al sistema. |
| `cPattern` | String | Patrón de URL (ver sección [Patrones de URL](#patrones-de-url)). |
| `bAction` | Block/String | Acción a ejecutar (ver sección [Qué puede ejecutar una ruta](#que-puede-ejecutar-una-ruta)). |
| `cMiddleware` | String | Nombre de la función middleware (opcional). |
| `cScope` | String | Metadato libre accesible desde `oCtx:cScope` (opcional). |
| `uCargo` | Any | Dato arbitrario adjunto al contexto de la ruta (opcional). |

Tenemos una estructura que podria ser algo parecido a:

```harbour
oSrv:AddRouteGet( cName, cPattern, bAction [, cMiddleware [, cScope [, uCargo]]] )
```


La forma habitual en modo libre es registrar las rutas sobre el objeto `THixServer` antes de llamar 
a `Start()`.

```harbour
LOCAL oSrv := THixServer():New()

   oSrv:AddRouteGet(    "users.list",   "/api/users",     {|| _UserList()   } )
   oSrv:AddRouteGet(    "users.one",    "/api/users/:id", {|| _UserGet()    } )
   oSrv:AddRoutePost(   "users.create", "/api/users",     {|| _UserCreate() } )
   oSrv:AddRoutePut(    "users.update", "/api/users/:id", {|| _UserUpdate() } )
   oSrv:AddRouteDelete( "users.delete", "/api/users/:id", {|| _UserDelete() } )

oSrv:Start()
```

Una ruta puede tener si deseamos varios métodos que estaran separados por una , 

```harbour
// Ruta que acepta varios métodos a la vez
oSrv:AddRoute( "hook", "/webhook", {|| _Webhook() }, "GET,POST" )
```

### Desde ficheros JSON — HixStyle

Cuando HixStyle está activo, HIX carga automáticamente todos los ficheros `*.json` de la carpeta 
`<root>/routes/` al arrancar. Cada fichero es un **array** de hash de ruta. Siguen la misma 
estructura que se ha definido antes 

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

Campos del objeto JSON:

| Campo | Obligatorio | Descripción |
|-------|-------------|-------------|
| `name` | Sí | Identificador único. `hix.*` está reservado. |
| `url` | Sí | Patrón de URL. |
| `method` | No | `"GET"`, `"POST"`, `"GET,POST"`, `"*"` (defecto: `"*"`). |
| `action` | Sí | Fichero o función a ejecutar. |
| `middleware` | No | Nombre de la función middleware. |
| `scope` | No | Metadato libre. |

## Mode Developer. 

En modo de desarrollo las rutas JSON se pueden recargar en caliente sin reiniciar el servidor 
via api.

```
GET /hix-routes/reload
```

---

## Qué puede ejecutar una ruta

### Codeblock

La forma más directa. Usa los helpers `U*` para leer el request y enviar la respuesta.

```harbour
oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )

oSrv:AddRouteGet( "greet", "/hello/:name", {||
   USendJson( { "msg" => "Hola, " + UParam("name") } )
} )
```

### Nombre de función

Si la acción es un string **sin extensión**, HIX lo trata como nombre de función Harbour 
y la llama pasándole el objeto request.

```harbour
oSrv:AddRouteGet( "users.list", "/api/users", "UserListAction" )

// En cualquier .prg de la librería:
FUNCTION UserListAction( oReq )
   USendJson( { "users" => {} } )
RETURN NIL
```

### Fichero `.prg`

Un fichero `.prg` relativo a `<root>/`. HIX lo compila y ejecuta.

```harbour
// En código:
oSrv:AddRouteGet( "home", "/", "views/home.prg" )

// En JSON:
{ "name": "home", "url": "/", "action": "views/home.prg" }
```

El fichero debe ser un `.prg` compilable. El resultado que devuelva `Main()` o 
la salida acumulada con `UWrite()` se envía como respuesta HTML. 

### Fichero `.hrb`

Igual que `.prg` pero ya precompilado. Más rápido en producción. 

```harbour
{ "name": "api.data", "url": "/api/data", "action": "controllers/data.hrb" }
```

### Método de clase — `metodo@clase.prg`

Esta es la manera mas profesional de definir una accion porque te permite definir dentro de un 
mismo módulo diferentes acciones, como el caso de un CRUD

```harbour
// Llama al método "index" de la clase "CustomerController" en customer.prg
{ "name": "customer.index", "url": "/customers",     "action": "index@customer.prg"  }
{ "name": "customer.show",  "url": "/customers/:id", "action": "show@customer.prg"   }
{ "name": "customer.save",  "url": "/customers",     "action": "save@customer.prg"   }
```

El fichero `customer.prg` define una clase con esos métodos:

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

### Fichero `.html` 

Renderiza el fichero html con el motor de vistas interno de HIX, Mambo

```harbour
{ "name": "home",    "url": "/",     "action": "views/home.html"      }
{ "name": "profile", "url": "/user", "action": "views/profile.view.html" }
```

---

## Patrones de URL

### Segmento literal

```
/ping
/api/v1/status
```

### Parámetro variable - `:nombre`

Captura cualquier valor excepto `/`. Accesible con `UParam("nombre")`.

```
/users/:id              → /users/42        → UParam("id") = "42"
/posts/:slug/comments   → /posts/hello/comments
```

### Parámetro con restricción regex - `:nombre(expr)`

Solo casa si el valor cumple la expresión regular.

```
/users/:id([0-9]+)      → /users/42   ✓     /users/abc  ✗
/files/:name([a-z_]+)   → /files/foto ✓     /files/123  ✗
```

### Parámetro opcional - `:nombre!`

El segmento es opcional. Si no aparece, `UParam("nombre")` devuelve `""`.

```
/docs/:section!         → /docs/intro  ✓    /docs  ✓
```

### Comodín

```
/static/*               → casa con cualquier ruta que empiece por /static
```

---

## Grupos de rutas

Permite aplicar un prefijo de URL y un middleware común a un conjunto de rutas.

```harbour
oSrv:AddRouteGroup( "/api/v1", "HixMwJwt", "api", {|o|
   o:AddRouteGet(    "items.list",   "/items",     {|| _ItemList()          } )
   o:AddRoutePost(   "items.create", "/items",     {|| _ItemCreate()        } )
   o:AddRouteGet(    "items.one",    "/items/:id", {|| _ItemGet()           } )
   o:AddRoutePut(    "items.update", "/items/:id", {|| _ItemUpdate()        } )
   o:AddRouteDelete( "items.delete", "/items/:id", {|| _ItemDelete()        } )
} )
```

Las rutas del bloque heredan el prefijo `/api/v1` y el middleware `HixMwJwt`.
Una ruta con middleware propio lo mantiene; el del grupo solo aplica si no tiene ninguno.

---

## Generación de URL

`URoute` genera la URL de una ruta a partir de su nombre, sustituyendo los parámetros en orden.

```harbour
URoute( "customer.show", 42 )       // → "/customers/42"
URoute( "customer.index" )          // → "/customers"
```

Útil para evitar URLs hardcoded en vistas y redirects:

```harbour
URedirect( URoute( "customer.show", nId ) )
```

---

## Handlers de error

Por defecto HIX responde con un JSON estándar cuando no encuentra ruta (404) 
o el método no está permitido (405). Se pueden sustituir:

```harbour
oSrv:SetRouteHandler( "404", {|| USendError( 404, "Página no encontrada" ) } )
oSrv:SetRouteHandler( "405", {|| USendError( 405, "Método no permitido"  ) } )
```

---

## Middleware

El middleware es una función que se ejecuta **antes** de la acción de la ruta. 
Puede validar tokens JWT, comprobar sesión, aplicar rate limiting, etc. Si el middleware 
rechaza la petición, la acción no llega a ejecutarse.

```harbour
oSrv:AddRouteGet( "dashboard", "/dashboard", {|| _Dashboard() }, "HixMwRequireAuth" )
```

Ver capítulo **[Middleware](../middleware/middleware.md)** para la referencia completa.



