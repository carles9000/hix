# Loaders y hooks de usuario

**HIX** puede cargar dinámicamente código de usuario al arrancar el servidor.
Todo `.prg` situado en `www/loaders/` se compila a `.hrb`, se carga en memoria
y sus funciones quedan **globalmente accesibles** desde cualquier ruta,
middleware, controller o vista.

Además de la carga, HIX define dos **hooks de ciclo de vida**:

| Hook       | Cuándo se ejecuta                                | Se usa para                          |
|------------|--------------------------------------------------|--------------------------------------|
| `USERINIT` | Tras cargar los loaders, antes de aceptar tráfico | Abrir conexiones, cachear datos, etc. |
| `USEREXIT` | Al parar el servidor, antes de cerrar sockets     | Cerrar conexiones, volcar buffers    |

Ambos son opcionales: si no existen, HIX no hace nada. Si existen, se
invocan automáticamente.

---

## ¿Cuándo lo necesitas?

- Para **cargar código de aplicación** sin recompilar la lib de HIX.
- Para **inicializar recursos** que la app necesita disponibles el primer
  request (pool DB, cachés en memoria, warmup de índices, etc.).
- Para **liberar recursos** de forma limpia cuando el servidor para
  (cerrar handles, flushar logs propios, cerrar sockets abiertos).

---

## Directorio `www/loaders/`

```
www/
└─ loaders/
   ├─ 00_bootstrap.prg     ← definiciones de USERINIT / USEREXIT
   ├─ helpers.prg          ← funciones utilitarias
   ├─ tcustomers.prg       ← modelos, clases, etc.
   └─ …
```

Reglas:

- Cada `.prg` se compila **una única vez** a `.hrb` (que se guarda en el
  mismo directorio junto al `.prg`).
- En arranques posteriores HIX **recompila solo** los `.prg` cuyo mtime es
  posterior al del `.hrb` correspondiente. Los `.hrb` ya al día se cargan
  directamente.
- El orden alfabético del nombre de fichero define el orden de intento de
  carga. Si hay **dependencias cruzadas** entre módulos, HIX itera varias
  pasadas hasta resolverlas todas.
- Los símbolos se publican con `hb_hrbLoad( 0x2, ... )` (BIND_LAZY), de
  modo que quedan disponibles para el resto del servidor.

Cada intento (éxito o fallo) queda registrado en el **Boot Log** bajo la
sección `"loaders"`:

```
[loaders]
  OK  file     00_bootstrap.prg
  OK  file     tcustomers.prg
  ERR file     bad.prg  -> Unterminated string 'x, HB_COMPILEFROMBUF
```

Consulta [Boot Log](bootlog.md) para inspeccionar los resultados desde
código o exponerlos como JSON.

---

## Ciclo de vida completo

Este es el orden exacto de eventos al arrancar y parar el servidor:

```
THixServer:Start()
   │
   ├─ HIX_Loaders()        ← compila y carga www/loaders/*.prg
   │
   ├─ Eval( ::bInit, SELF ) ← callback opcional del programador (bInit)
   │
   ├─ HIX_UserInit()        ← invoca USERINIT() si hb_IsFunction("USERINIT")
   │
   └─ (abre puerto, acepta conexiones)

THixServer:Stop()
   │
   ├─ HIX_UserExit()        ← invoca USEREXIT() si hb_IsFunction("USEREXIT")
   │
   └─ (cierra sockets, para workers)
```

`USERINIT` se ejecuta **antes** de que el servidor acepte el primer request:
todo lo que dejes preparado ahí estará disponible cuando llegue tráfico.
`USEREXIT` corre **antes** de cerrar sockets, así que aún puedes usar la
red si lo necesitas (por ejemplo, enviar una notificación de shutdown).

---

## Hooks `USERINIT` / `USEREXIT`

### Cómo declararlos

Se declaran como **FUNCTION top-level** (nunca `STATIC`) en cualquier
`.prg` de `www/loaders/`. Deben ser globales para que `hb_IsFunction()`
las resuelva.

```harbour
// www/loaders/00_bootstrap.prg

FUNCTION USERINIT()

   l( "Aplicación inicializando..." )
   _AbrirConexionDB()
   _CargarCachesEnMemoria()

RETURN NIL

FUNCTION USEREXIT()

   l( "Aplicación cerrando..." )
   _CerrarConexionDB()

RETURN NIL
```

### Reglas críticas

- **Deben ser NO bloqueantes.** Un bucle infinito, un socket sin timeout
  o un lock que no libere **retrasa el arranque** (en `USERINIT`) o
  **cuelga el shutdown** (en `USEREXIT`).
- **Las excepciones quedan contenidas.** HIX envuelve ambos hooks en un
  `TRY/CATCH` interno: si `USERINIT` lanza, el error se traza y el
  servidor continúa arrancando. Lo mismo con `USEREXIT`.
- **Son reentrantes.** Si por lo que sea llamas `HIX_UserInit()` varias
  veces, `USERINIT()` se ejecuta cada vez. No hay guarda de "una sola
  ejecución".
- **`USERINIT` corre en el hilo principal del servidor**, antes del
  accept loop. Cualquier `STATIC` que asigne queda accesible desde los
  workers a través de accesores públicos.

### Ejemplo - pool de conexiones DB

```harbour
// www/loaders/00_bootstrap.prg

STATIC s_oDbPool := NIL

FUNCTION UserDbPool()
RETURN s_oDbPool

FUNCTION USERINIT()

   LOCAL oErr

   TRY
      s_oDbPool := MyDbPool():New( "postgres://…", 8 )
      s_oDbPool:Warmup()
      l( "DB pool listo (8 conexiones)" )
   CATCH oErr
      le( "No se pudo inicializar DB pool: " + oErr:description )
      // no relanzar - el servidor arranca igual
   END

RETURN NIL

FUNCTION USEREXIT()

   IF s_oDbPool != NIL
      s_oDbPool:CloseAll()
      s_oDbPool := NIL
   ENDIF

RETURN NIL
```

Desde cualquier ruta:

```harbour
oSrv:AddRouteGet( "users", "/users", {||
   LOCAL oDb := UserDbPool()
   USendJson( oDb:Query( "SELECT id, name FROM users" ) )
} )
```

---

## API pública

```harbour
HIX_Loaders()        // compila y carga www/loaders/*.prg. Devuelve .T. si todos ok
HIX_GetLoaders()     // array con el estado de cada módulo cargado
HIX_UserInit()       // invoca USERINIT() si existe. TRY/CATCH interno
HIX_UserExit()       // invoca USEREXIT() si existe. TRY/CATCH interno
```

Estas funciones las llama HIX automáticamente durante `Start()` / `Stop()`.
No suelen invocarse a mano - pero son públicas por si necesitas hacer
warm-up manual desde un test o un CLI.

### Estructura de un módulo (`HIX_GetLoaders()`)

Cada entrada del array devuelto es un hash con estos campos:

| Campo     | Tipo | Significado                                |
|-----------|------|--------------------------------------------|
| `file`    | `C`  | Nombre del fichero (ej. `tcustomers.hrb`)  |
| `loaded`  | `L`  | `.T.` si `hb_hrbLoad` tuvo éxito           |
| `error`   | `L`  | `.T.` si falló compilación o carga         |
| `msg`     | `C`  | Descripción del error si `error == .T.`    |
| `oError`  | `O`  | Objeto de error de Harbour (o `NIL`)       |
| `oHrb`    | `C`  | Contenido binario del `.hrb`               |
| `pSym`    | `P`  | Puntero simbólico al módulo cargado        |
| `process` | `L`  | `.T.` si el `.prg` fue (re)compilado ahora |

---

## Diagnóstico

Si algo no se carga como esperas:

1. **Comprueba el Boot Log:** `HIX_BootLogShow()` por consola, o
   `HIX_BootLogSection( "loaders" )` desde código. Cada `.prg` aparece con
   OK/ERR y, en caso de error, la descripción exacta.
2. **Verifica que el hook está publicado:** `hb_IsFunction( "USERINIT" )`
   debe devolver `.T.`. Si devuelve `.F.`, revisa que la función esté
   declarada como `FUNCTION` top-level (no `STATIC`) en algún `.prg`
   de `www/loaders/`.
3. **Errores en `USERINIT` no crashean el servidor:** aunque el servidor
   siga arrancando, la excepción queda en el trace (`_t()`). Consulta
   [Traceando](traceando.md) para leerlo.
4. **Regenerar `.hrb`:** si sospechas que el `.hrb` cacheado está
   corrupto, bórralo - HIX lo recompila desde el `.prg` en el siguiente
   arranque.
