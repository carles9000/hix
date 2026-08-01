# 🛡️ Middleware - Introducción

El apartado de los middleare es quizás uno de los mas importantes a la hora de 
diseñar una aplicación web, porque es el encargado de la seguridad. 
Muchos ya conocereis el tema pero es vital estudiarlo con atención para entender 
como debemos de diseñarlos. Es un poco extenso pero necesario para poder encajar 
todas las piezas.

Imagina que tienes una tienda con una sola entrada. Antes de que un cliente llegue al
mostrador, pasa por un guardia de seguridad, después por un detector de metales y, si
lleva una tarjeta VIP, por un acceso preferente. Solo entonces llega al dependiente.

El **middleware** es simplemente una función que devuelve un valor lógico .T./.F. 
Esta función recibe un parámetro `oCtx`  que es el contexto de la llamada, peropodermos usar UHelpers 
para acceder mas facilmente a ellos.

En este ejemplo comprobamos que la petición lleva una API Key válida en el
header `X-Api-Key`:

```clipper
FUNCTION MW_ApiKey()

   LOCAL cKey := UHeader( "X-Api-Key", "" )

   IF cKey != "clave-secreta-123"
      USendError( 401, "API Key invalida" )
      RETURN .F.
   ENDIF

RETURN .T.
```

En este caso el middleware recupera del la cabecera para comprobar que la petición tiene una 
cabecera 'X-Api-Key' y validamos su clave.






### Contenedor - UMiddleware()

`UMiddleware` es el contenedor que HIX usa internamente para ejecutar cualquier
middleware, ya sea una función por nombre o un codeblock. Esta clase nos devolverá 
un objeto que será el encargado de ejecutar nuestra funcion y manejarla.
Siguiendo nuestro ejemplo definiariamos asi nuestro MW.

```clipper
UMiddleware():New( "MW_ApiKey", "apikey" )
```

El segundo parámetro es un nombre descriptivo que aparece en los logs cuando el
middleware corta la cadena y nos sirve para tracear. 

### Relación Ruta <-> Middleware 

Cuando definimos nuestra ruta, la asociamos a nuestro middleware (MW). Solo en el caso de 
superar la capa de seguridad del MW, el servidor ejecuta la ruta. 
En caso contrario el middleware ya se encargará en función de como le definamos lo 
que debe hacer.


Ex: Definimos una ruta que usará el middleware que hemos diseñado `MW_ApiKey`

```clipper
oSrv:AddRouteGet( "data", "/data", 'mydata.prg', "MW_ApiKey" )
```

Definimos `mydata.prg`, una simple funcion que devuelve una respuesta, pero que solo 
se ejecutara si ha pasado con éxito el control del middleware. 

```clipper
FUNCTION MyData()
   USendJson( { "info" => "solo para clientes con API Key", "ok" => .T. } )
RETURN NIL
```

### Flujo en tiempo de ejecución

```
GET /data  (sin cabecera X-Api-Key)
     │
     ▼
[MW_ApiKey]
  Header X-Api-Key presente y correcto?
  No → USendError(401) → RETURN .F. → corta
     │ Sí
     ▼
  MyData()  ← solo llega si la clave es válida
```

**NOTA** Con middleware defines las reglas **una vez** y las aplicas a las rutas que necesiten,
de forma declarativa y consistente.

### Setup (parametros)

El último detalle a conocer es que nosotros podemos crear un  middleare estático o 
dinámico. En caso de que queramos reutilizar un middleware tendremos de definir de 
alguna manera su `setup`. Esto implica que a la hora de definir en nuestro sistema 
que vamos a utilizar el middleware MW_A() tambien podemos decirle que funcionará 
con los parámetros que necesite. 

Imaginemos que tenemos un MW que controla las veces que una IP hace una petición y  
queremos que en nuestro endpoint NO se pueda ejecutar mas de 10 veces por minuto. 
En este caso definimos nuestro MW de uso general y lo configuramos con un setup de 10.

Cada MW lleva su propio setup si asi esta definido.

## Varios middlewares - UBaseMiddleware

Pero no es tan facil el tema de los middleware y ahora vamos a dar un pequeño salto.
Podemos tener fácilemente muchos middleware que son necesarios para poder gestionar 
nuestra seguridad. El sistema ha de gestionar la llegada de la petición HTTP y 
el momento en que tu código de negocio la procesa. 

Como funcionaria nuestro sistema ?

```
 Petición HTTP
       │
       ▼
┌──────────────┐
│ Middleware 1 │  ← ¿Pasa? ──No──▶  Responde 401/403/429...
└──────┬───────┘
       │ Sí
       ▼
┌──────────────┐
│ Middleware 2 │  ← ¿Pasa? ──No──▶  Responde 503/413...
└──────┬───────┘
       │ Sí
       ▼
┌──────────────────────────────┐
│   Tu función de negocio      │  ← Solo llega lo que debe llegar
└──────────────────────────────┘
```

Este grupo de middleare lo llamaremos **pipeline** o **stack de middleware**. 

Cuando una ruta necesita varios controles encadenados, se crea una función de
middleware compuesta. `UBaseMiddleware` ejecuta la lista en orden y corta en el
primer fallo.

En este ejemplo protegemos un endpoint de administración que requiere:

1. **Rate limiting** - máximo 60 peticiones por minuto por IP
2. **JWT válido** - token Bearer verificado
3. **Rol `admin`** - el token debe incluir ese rol

Solo y si solo pasa estos controles, podrá ejecutar la ruta !

```clipper
// ============================================================
// Grupo MW_Admin — rate limit + JWT + rol admin
// ============================================================
FUNCTION MW_Admin( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HixMwRateLimit", "rate"  ) )
   o:Add( UMiddleware():New( "HixMwJwt"      , "jwt"   ) )
   o:Add( UMiddleware():New( "MW_ApiKey"     , "roles" ) )

RETURN o:Run()
```

Con este sistema de seguridad  que hemos diseñado, ahora lo podriamos aplicar a 
diferentes rutas.

Si definimos el sistema desde código para compilar todo:

```clipper
...
	LOCAL oSrv := THixServer():New()

	// --- Configuración (antes de Start) ---
	HIX_MwRateLimitSetup( 60, 60 )          // 60 req/min por IP
	HIX_MwJwtSetup( "mi-clave-secreta", 3600 )

...

	// --- Rutas del panel de admin ---
	oSrv:AddRouteGet(    "admin.users",   "/admin/users",     'users.prg'      , "MW_Admin" )
	oSrv:AddRouteDelete( "admin.user",    "/admin/users/:id", 'users_del.prg'  , "MW_Admin" )
	oSrv:AddRouteGet(    "admin.metrics", "/admin/metrics",   'metrics.prg'    , "MW_Admin" )
	
...
	
	oSrv:Start()	
```

Flujo en tiempo de ejecución para cualquiera de esas rutas:

```
GET /admin/users
     │
     ▼
[HixMwRateLimit]
  ¿IP ha superado 60 req/min?
  No → .T.
  Sí → 429 Too Many Requests → .F. → corta
     │
     ▼
[HixMwJwt]
  ¿Token Bearer válido?
  Sí → deposita payload en oCtx:hData["jwt"] → .T.
  No → 401 Unauthorized → .F. → corta
     │
     ▼
[MW_ApiKey]
  ¿oCtx:hData["jwt"]["role"] == "admin"?
  Sí → .T.
  No → 403 Forbidden → .F. → corta
     │
     ▼
  _AdminUsers()  ← solo llega aquí si pasa los tres controles
```

La ventaja de agrupar en `MW_Admin` es que las tres rutas comparten exactamente el
mismo pipeline. Si mañana hay que añadir un cuarto control (por ejemplo, logging de
auditoría), se añade una línea en `MW_Admin` y las tres rutas quedan protegidas
automáticamente, y el mantenimiento se hace solo en 1 fichero !!!

```clipper
// Añadir auditoría a todas las rutas admin — un solo cambio
FUNCTION MW_Admin( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HixMwRateLimit", "rate"    ) )
   o:Add( UMiddleware():New( "HixMwJwt"      , "jwt"     ) )
   o:Add( UMiddleware():New( "MW_ApiKey"     , "roles"   ) )
   o:Add( UMiddleware():New( "MW_AuditLog"   , "audit"   ) )  // nuevo

RETURN o:Run()
```

El middleware es un componente estructural que actúa como capa intermedia entre 
el sistema operativo y las aplicaciones, permitiendo la comunicación entre sistemas 
distribuidos. En una arquitectura, su rol es desacoplar los componentes, permitiendo 
que se intercambien información y funciones sin que necesiten conocer los detalles 
técnicos internos de cada uno.


**RESUMEN**  
El tema middleware es importante para poder controlar nuestra seguridad en 
la aplicación. Podemos no usarlos y la aplicación funcionará igual pero segun que 
tipo de módulo ejecutemos podrá estar expuesto. 

Vale la pena invertir en hacer algunas pruebas y entender y aprender a como usar este 
mecanismo que nos ayudará a evitar posibles intrusiones o accesos no permitidos.

!!! info "Próximo capítulo" Como hemos de diseñar una capa de middleware.