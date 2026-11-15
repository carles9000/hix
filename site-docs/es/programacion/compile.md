# ⚙️ Compile subsystem — `HIX_Compile*`

HIX expone un subsistema unificado para compilar y ejecutar código Harbour
dinámico desde dentro de tu aplicación. Es la vía que utiliza internamente
el dispatcher (`.prg` cargados dinámicamente), los loaders, los middlewares
y el motor de vistas. Lo tienes disponible también para tus propios
controllers cuando necesites compilar o ejecutar un `.prg` o un HRB
precompilado en tiempo de respuesta.

> 🧭 **Introducido en v2.3.12**, consolidado en **v2.4.0** como única vía
> de compilación de la lib. La antigua `HIX_CompileFile` fue eliminada
> en v2.4.0.

---

## Por qué un subsistema

Antes de v2.3.12 había dos caminos distintos: uno para compile puro
(`HIX_CompileFile` + `hb_CompileFromBuf`) y otro para compile+run, con
contratos de error diferentes y stack walkers específicos de cada caller.
Resultado: código duplicado, errores difíciles de propagar y boot logs
asimétricos entre loaders y dispatcher.

v2.4.0 consolida todos esos caminos (dispatcher, loaders, middleware
loader, motor de vistas) sobre un **único contrato hash**:

```
{ ok, phase, hrb, err, diagnostics, preambleLines, where }
```

- `ok` — booleano, `.T.` si la fase final no produjo error.
- `phase` — en qué fase quedó la ejecución: `"compile"`, `"load"`, `"run"`.
- `hrb` — bytes del HRB resultante del compile (si la fase compile pasó).
- `err` — hash normalizado del error (ver más abajo). `NIL` si `ok=.T.`.
- `diagnostics` — array de diagnósticos secundarios (warnings, lines,...).
- `preambleLines` — nº de líneas de preamble inyectadas (ajusta `line` del `err`).
- `where` — info de localización del compile (filename, etc).

---

## API pública

Todas las funciones **nunca propagan `Break`**: devuelven el hash con
`ok=.F.` y `err` poblado si algo falla. Nunca hay que envolverlas en
`TRY/CATCH`.

### `HIX_CompileCode( cSource [, hOpts] [, cFilename] )`

Compila una fuente `.prg` en memoria. Opciones típicas en `hOpts`:
`{ "virtualName" => "my_module", "runtime" => .F. }`. `cFilename`
etiqueta el error cuando el compile falla.

```clipper
LOCAL hRes := HIX_CompileCode( "FUNCTION Foo() ; RETURN 42" )
IF ! hRes["ok"]
   le( "Compile failed: " + hRes["err"]["description"] )
   RETURN NIL
ENDIF
// hRes["hrb"] contiene el HRB listo para ejecutar
```

### `HIX_CompileCodeFromFile( cPath )`

Wrapper compile-only desde disco. Devuelve el mismo hash. Es la vía que
usan el dispatcher y los loaders para compilar `.prg` persistidos.

```clipper
LOCAL hRes := HIX_CompileCodeFromFile( "www/controllers/my_action.prg" )
IF ! hRes["ok"]
   USendError( 500, "Compile: " + hRes["err"]["description"] )
   RETURN NIL
ENDIF
```

### `HIX_CompileRunPrg( cPath [, ...args] )`

Compile + ejecuta en un paso. Captura también el error runtime, no solo
el de compile. Devuelve el mismo contrato hash — `phase` será `"compile"`
si cayó compilando y `"run"` si cayó ejecutando.

```clipper
LOCAL hRes := HIX_CompileRunPrg( "scripts/report.prg", nUserId, cPeriod )
IF ! hRes["ok"]
   // Da igual si fue compile error o runtime error — es el mismo shape
   USendError( 500, hRes["err"]["description"] )
   RETURN NIL
ENDIF
```

### `HIX_CompileRunHrb( cHrbBytes [, cVirtualName [, ...args]] )`

Ejecuta un HRB ya compilado (bytes). Útil cuando ya tienes el `.hrb` en
caché o lo generaste con `HIX_CompileCode` y lo guardaste en disco.
Internamente usa `HB_HRB_BIND_FORCELOCAL` para evitar colisiones con
otros HRBs cargados.

```clipper
LOCAL cHrb := hb_MemoRead( "cache/report.hrb" )
LOCAL hRes := HIX_CompileRunHrb( cHrb, "report", nUserId )
```

### `HIX_CompileLastError()`

Devuelve un snapshot del último error runtime capturado por el
subsistema. **`THREAD STATIC`** — un hilo solo ve sus propios errores.
Útil cuando has llamado a `HIX_CompileRunPrg` y necesitas la stack
completa aparte del `err` que ya trae el hash.

```clipper
LOCAL hLast := HIX_CompileLastError()
IF hLast != NIL
   ld( "aStack: " + hb_ValToExp( hLast["aStack"] ) )
ENDIF
```

---

## Shape de `err` normalizado

El hash de error dentro de `hRes["err"]` tiene siempre las mismas claves,
sea de compile o runtime. **Compile** produce el subset:

| Clave         | Significado                                      |
|---------------|--------------------------------------------------|
| `kind`        | `"compile"` o `"runtime"`                         |
| `severity`    | `"error"`, `"warning"`                            |
| `code`        | Código numérico (preprocesador, parser)           |
| `description` | Mensaje principal — listo para mostrar al usuario |
| `file`        | Fichero fuente donde se detectó el error          |
| `line`        | Línea (ya ajustada por `preambleLines`)           |
| `lineCode`    | Snippet exacto de la línea culpable               |

**Runtime** añade todo el contexto Harbour:

| Clave adicional | Significado                                        |
|-----------------|----------------------------------------------------|
| `operation`     | Función/operación que falló                        |
| `args`          | Argumentos pasados cuando petó                     |
| `subsystem`     | `oError:subSystem`                                 |
| `genCode`       | `oError:genCode` (código genérico Harbour)         |
| `subCode`       | `oError:subCode`                                   |
| `osCode`        | Código de OS si aplica                             |
| `filename`      | Fichero del error runtime                          |
| `stack`         | Stack trace en formato texto                       |
| `aStack`        | Stack trace como array estructurado                |

---

## Ejemplo — controller que ejecuta un script dinámico

```clipper
FUNCTION _RunUserScript()
   LOCAL cPath := "www/scripts/" + UParam( "name" ) + ".prg"
   LOCAL hRes

   IF ! hb_FileExists( cPath )
      RETURN USendError( 404, "Script no encontrado" )
   ENDIF

   hRes := HIX_CompileRunPrg( cPath, USession( "user_id" ) )

   IF ! hRes["ok"]
      le( "Script failed [" + hRes["phase"] + "]: " + hRes["err"]["description"] )
      RETURN USendJson( { ;
         "ok"    => .F.,                       ;
         "phase" => hRes["phase"],             ;
         "error" => hRes["err"]["description"],;
         "line"  => hRes["err"]["line"]        ;
      }, 500 )
   ENDIF

   USendJson( { "ok" => .T. } )
RETURN NIL
```

---

## Boot log enriquecido

A partir de v2.4.0, cuando un **loader** o un **middleware** falla al
compilar durante el arranque, el boot log vuelca línea, código y snippet
en lugar de solo el mensaje. Esto no requiere configuración — es
automático porque el loader usa `HIX_CompileCodeFromFile` y traduce su
hash directamente al logger.

Formato típico:

```
[loader] fail: www/loaders/stats.prg
   line: 42  (code: 2007)
   >>  LOCAL x = y + z        // = en lugar de :=
   description: Error de sintaxis
```

---

## Dónde no usarlo

- **No** llames a `HIX_CompileRunPrg` en tu hot path para scripts que no
  cambian — compila cada vez. Guarda el HRB con `HIX_CompileCode` + un
  `.md5` como caché y usa `HIX_CompileRunHrb` después. Es exactamente
  lo que hace el motor de vistas internamente.
- **No** uses este subsistema para evaluar expresiones simples. Para eso
  Harbour ya tiene `&(cExpr)` (macro-eval). Compile está pensado para
  bloques `.prg` enteros con `FUNCTION`/`PROCEDURE`.
- **No** confíes en que `err` traiga `aStack` cuando `kind=="compile"`.
  La stack solo tiene sentido para errores runtime.

---

## Cambios respecto a versiones anteriores

| Antes de v2.3.12                     | A partir de v2.4.0                              |
|--------------------------------------|-------------------------------------------------|
| `HIX_CompileFile( cPath )`           | **Eliminada.** Usar `HIX_CompileCodeFromFile( cPath )` para compile-only o `HIX_CompileRunPrg( cPath )` para compile+run. |
| `hb_CompileFromBuf` directo          | Encapsulado en `HIX_CompileFromBuf` (low-level, uso interno de `HIX_CompileCode`) |
| `oError:operation == "line:N"`       | `oError:operation == "line N"`. La fuente oficial es `oErr:cargo["line"]` |
| `src/hix_prepro.prg`                 | Eliminado. Las directivas `TRY/CATCH/FINALLY` viven ya en `src/include/hix_const.ch`. |

Ver [changes/2.4.0.md](https://github.com/carles9000/hix.pro/blob/main/changes/2.4.0.md)
para la lista completa de breaking changes y el audit trail de la
migración.
