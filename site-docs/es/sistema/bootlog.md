# 📝 Boot Log

**HIX** captura en un **hash estático thread-safe** todo lo que ocurre durante
el arranque del servidor: ficheros de configuración cargados, subsistemas
inicializados, loaders compilados, middlewares aplicados y rutas registradas.
Ese registro queda accesible en runtime para inspección, diagnóstico o para
mostrarlo en una UI de administración.

Cada evento se guarda como un array de **4 elementos**:

```harbour
{ cAction, lStatus, cValue, xCargo }
```

| Campo     | Tipo | Significado                                                       |
|-----------|------|-------------------------------------------------------------------|
| `cAction` | `C`  | Tipo de acción: `"file"`, `"config"`, `"init"`, `"route"`, ...    |
| `lStatus` | `L`  | `.T.` si la operación tuvo éxito, `.F.` si falló                  |
| `cValue`  | `C`  | Identificador legible del recurso (`myapp.prg`, `users.list`, ...)|
| `xCargo`  | `X`  | Payload libre (descripción del error, metadatos, `NIL` por defecto)|

---

## ¿Cuándo lo necesitas?

- Para **diagnosticar** por qué un módulo, middleware o ruta no se cargó.
- Para exponer el **estado del arranque** al equipo como JSON o vista.
- Para verificar de un vistazo que **todos los subsistemas** (logger, proxy,
  firewall, access log, métricas, socket) arrancaron sin errores.

---

## Secciones

El hash está organizado por **procesos de carga**. Las secciones estándar son:

| Sección       | Contenido                                                             |
|---------------|-----------------------------------------------------------------------|
| `config`      | Ficheros de configuración cargados (`hix.json`, `www/config.json`, …) |
| `server`      | Subsistemas iniciados: logger, proxy, firewall, access log, métricas… |
| `loaders`     | `.prg` compilados y cargados desde `www/loaders/`                     |
| `middlewares` | Middlewares cargados desde `www/middlewares/config.json`              |
| `routes`      | Rutas registradas (JSON o programáticas; excluye las internas `hix.*`)|

Puedes añadir tus propias secciones desde código llamando a `HIX_BootLogAdd`.

---

## API pública

```harbour
HIX_BootLog()                                          // hash completo (clonado)
HIX_BootLogSection( cKey )                             // array de una sección
HIX_BootLogAdd( cKey, cAction, lStatus, cValue, xCargo ) // añade evento
HIX_BootLogReset()                                     // vacía el hash
HIX_BootLogShow()                                      // dump por consola formateado
HIX_BootLogAction( bAction )                           // callback en cada Add
HIX_BootLogVerbose( lOn )                              // activa/desactiva verbose
HIX_BootLogIsVerbose()                                 // consulta el flag verbose
```

### `HIX_BootLog()`

Devuelve una **copia clonada** del hash completo, thread-safe. Ideal para
enviar como JSON:

```harbour
oSrv:AddRouteGet( "hix.boot", "/hix-boot", {|| USendJson( HIX_BootLog() ) } )
```

### `HIX_BootLogSection( cKey )`

Devuelve el array de una sección concreta (o `{}` si no existe):

```harbour
aRoutes := HIX_BootLogSection( "routes" )
FOR EACH aItem IN aRoutes
   ? aItem[3], aItem[4]     // cValue, xCargo
NEXT
```

### `HIX_BootLogAdd( cKey, cAction, lStatus, cValue, xCargo )`

Añade una entrada. `lStatus` es `.T.` por defecto; `xCargo` es `NIL` por
defecto. Si `lStatus == .F.` y `xCargo == NIL`, se sustituye por el placeholder
localizado (`BOOT_ERR_NO_DESC`) para que la UI no vea `NIL` en errores.

```harbour
HIX_BootLogAdd( "loaders", "file", .T., "myapp.prg" )
HIX_BootLogAdd( "loaders", "file", .F., "bad.prg", oErr:description )
```

### `HIX_BootLogReset()`

Vacía el hash. Se llama automáticamente al inicio de `_Init()` si el proceso
es dueño de los globales.

### `HIX_BootLogShow()`

Vuelca el contenido por consola con formato humano, en orden lógico
(`config → server → loaders → middlewares → routes`):

```
=== HIX Boot Log ===
[config]
  OK  file     hix.json
  OK  file     www/config.json
[server]
  OK  init     logger level=info console=T
  OK  init     access_log enabled=T file=access.log
  OK  init     metrics
  OK  init     socket ssl=F
[loaders]
  OK  file     myapp.prg
  ERR file     bad.prg  -> Unterminated string 'x, HB_COMPILEFROMBUF
[middlewares]
  OK  file     cors.prg
  OK  config   session: cookie=hix_sess ttl=3600 storage=memory
[routes]
  OK  init     users.list  -> type:compiled, route=[/users], method[GET,OPTIONS], context:[]
  OK  init     admin.edit  -> type:file[api.json], route=[/admin/:id], method[GET,POST,OPTIONS], context:[admin]
====================
```

### `HIX_BootLogAction( bAction )`

Registra un **codeblock** que se ejecuta **cada vez** que se añade una entrada
al boot log. El codeblock recibe los cinco campos de la entrada recién
insertada:

```harbour
{| cKey, cAction, lStatus, cValue, xCargo | ... }
```

Es útil para:

- **Reenviar** cada evento al logger (`l()`/`lw()`/`le()`) en tiempo real.
- **Reportar** errores a un sistema externo (Sentry, webhook, e-mail).
- **Actualizar una UI** en vivo durante el arranque (barra de progreso,
  panel de admin).

Pasa `NIL` para desactivarlo. Devuelve el codeblock anterior por si necesitas
restaurarlo.

**Ejemplo - reenviar al logger con una función auxiliar:**

```harbour
// Al arrancar el servidor
HIX_BootLogAction( {|cKey, cAction, lStatus, cValue, xCargo| ;
   MyBootLog( cKey, cAction, lStatus, cValue, xCargo ) } )

// Funcion auxiliar en tu app
FUNCTION MyBootLog( cKey, cAction, lStatus, cValue, xCargo )
   _t( "[BOOT/" + cKey + "] " + cAction + " " + ;
       iif( lStatus, "OK", "ERR" ) + " " + cValue + ;
       iif( xCargo == NIL, "", " -> " + hb_CStr( xCargo ) ) )
RETURN NIL
```

Cada entrada añadida al boot log dispara `MyBootLog()` con los datos del
evento; la función los formatea y los envía a `_t()` (traza), que puede
volcarlos a consola, fichero, o donde tú decidas.

> El callback se invoca **fuera del mutex** interno para no bloquear otras
> escrituras. Aun así, mantén el codeblock **rápido** - se ejecuta síncronamente
> durante el arranque.

### `HIX_BootLogVerbose( lOn )` / `HIX_BootLogIsVerbose()`

Activa o consulta el modo detallado (reservado para registros extensos como
ruta a ruta). Devuelve el valor anterior.

---

## Formato del `xCargo` según sección

### Loaders (errores)

Cuando un `.prg`/`.hrb` falla, `xCargo` contiene:

```
<oError:description>, <oError:operation>
```

Ejemplo real:

```
ERR file     no_symbol.hrb  -> Unknown or unregistered function symbol, ZDUMMY
```

Si el error no tiene `operation`, solo aparece la descripción. Si no hay
excepción capturable, se cae al mensaje interno (`BOOT_LOADER_LOAD_FAIL_NX`).

### Middlewares

- `file` con éxito → `xCargo` = `NIL`
- `file` con error → `xCargo` = `"compile failed"`, `"handle NIL"` o
  `oErr:description`
- `config` (setup de session/csrf) → `xCargo` = `NIL` y la descripción va en
  `cValue`

### Routes

Cada ruta registrada (excepto las internas `hix.*`) genera:

```
type:<tipo>, route=[<url>], method[<metodos>], context:[<scope>]
```

Donde `tipo` es:

- `compiled` - la ruta fue registrada desde código (por ejemplo con
  `AddRouteGet`).
- `file[<nombre.json>]` - la ruta se cargó desde `www/routes/<nombre.json>`.

### Server

Los subsistemas se registran como `cAction = "init"` y `cValue` describe el
recurso con sus parámetros clave (`logger level=info console=T`,
`firewall mode=blacklist filter=…`, `socket ssl=T`, etc.).

---

## Exponer el boot log al usuario

Como el hash es serializable, la forma más directa es una ruta HTTP:

```harbour
// Endpoint JSON crudo
oSrv:AddRouteGet( "hix.boot", "/hix-boot", ;
   {|| USendJson( HIX_BootLog() ) } )

// Sección concreta
oSrv:AddRouteGet( "hix.boot.routes", "/hix-boot/routes", ;
   {|| USendJson( HIX_BootLogSection( "routes" ) ) } )

// Vista HTML tabulada
oSrv:AddRouteGet( "hix.boot.html", "/hix-boot.html", ;
   {|| USendView( "hix/bootlog.html", { "hLog" => HIX_BootLog() } ) } )
```

Estas rutas conviene protegerlas con `HixMwAdmin` o el middleware de sesión
que uses en tu panel de administración.

---

## Ejemplo - sección custom

Puedes usar tu propia sección para registrar eventos del arranque de tu
aplicación:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()

   oSrv:bInit := {||
      HIX_BootLogAdd( "app", "init", .T., "warmup cache" )
      IF ! _LoadCatalog()
         HIX_BootLogAdd( "app", "init", .F., "catalog", "fichero corrupto" )
      ENDIF
   }

   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
RETURN
```

Tu sección `app` aparecerá al final del dump y también en el hash devuelto
por `HIX_BootLog()`.
