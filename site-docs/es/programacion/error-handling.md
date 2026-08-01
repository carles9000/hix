# 🧨 Manejo de errores

Todo lo que puede fallar (un acceso a BD, un parse JSON, una división por
cero, un fichero ausente) termina en un **error de Harbour** (un objeto
`oError` con `description`, `subSystem`, `operation`, ...). Sin un manejo
explícito, el worker que ejecuta la acción muere y el cliente recibe una
respuesta vacía o el servidor entero cae.

HIX expone **dos niveles** de defensa:

1. **TRY / CATCH** local — dentro de una acción concreta, para fallos que
   sabes que pueden pasar (BD, network, parseo).
2. **Handler global** (`bOnError`) — red de seguridad que captura cualquier
   error no atrapado, envía un response HTTP coherente al cliente y
   escribe en `errors.log`.

```
GET /api/users/42
      │
      ▼
   action _UserGet()
      │
      ├─── TRY ──── error BD ──── CATCH ────────── USendError(500, ...)
      │                                                  │
      └─── otros errores no controlados                  ▼
              │                                    cliente recibe JSON
              ▼
        worker protect ─── bOnError(oErr, oReq) ─── HIX_ShowError
              │                                          │
              ▼                                          ▼
        loggea + responde 500                   errors.log + render
```

---

## TRY / CATCH / FINALLY

Definidos en `include/hix_const.ch`:

```clipper
TRY
   // código que puede fallar
CATCH oError
   // tratamiento del error
FINALLY
   // se ejecuta siempre (con o sin error)
END
```

`oError` se declara siempre como `LOCAL` al inicio de la función:

```clipper
FUNCTION _DbInsert( hData )
   LOCAL oError, lOk := .F.
   LOCAL oDbf

   TRY
      oDbf := UDbf():New( "customers" )
      
      oDbf:Append()
      oDbf:Save( hData )
      lOk := .T.
   CATCH oError
      le( "DB insert failed: " + oError:description )
      lOk := .F.
   FINALLY
      oDbf:Close()
   END

RETURN lOk
```

### Campos típicos de `oError`

| Campo | Contenido |
|---|---|
| `oError:description` | Mensaje principal del error |
| `oError:operation` | Función / operación que falló (`OPEN`, `JSONDECODE`, ...) |
| `oError:subSystem` | Subsistema (`DBFCDX`, `BASE`, `MEMIO`, ...) |
| `oError:subCode` | Código numérico — útil como status HTTP si está en rango |
| `oError:filename` | Fichero implicado |
| `oError:procName` | Función donde se disparó |
| `oError:procLine` | Línea de la función |
| `oError:args` | Argumentos pasados a la función fallida |
| `oError:cargo` | Hash libre — HIX lo usa para context extra (view code, line code, ...) |

---

## Patrones en acciones

### Validación + DB con error controlado

```clipper
FUNCTION _UserCreate()
   LOCAL oVal, oUsers, oError, nId := 0, cMsg := ""

   oVal := UValidateOrFail( { ;
      "name"  => "required|string|max:50",  ;
      "email" => "required|string|email"    ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   TRY
      oUsers := TUsers()
      nId    := oUsers:Insert( oVal:DataFields(), @cMsg )
   CATCH oError
      le( "Insert error: " + oError:description )
      RETURN USendError( 500, oError:description )
   END

   IF nId == 0
      RETURN USendError( 422, cMsg )
   ENDIF

   USendJson( { "id" => nId }, 201 )
RETURN NIL
```

### Parse de JSON entrante

```clipper
LOCAL hBody := UJson()
IF hBody == NIL
   RETURN USendError( 400, "Body no es JSON válido" )
ENDIF
```

`UJson` ya devuelve `NIL` si falla — no necesitas TRY/CATCH explícito.

### Acceso a fichero opcional

```clipper
LOCAL oError, cContent := ""

TRY
   cContent := hb_MemoRead( cPath )
CATCH oError
   cContent := "(fichero no disponible)"
END

USendText( cContent )
```


---

## Handler global (`bOnError`)

Cualquier error que **no** atrapes con TRY/CATCH cae aquí. El servidor
lo invoca con `(oError, oReq)`:

```clipper
oSrv:bOnError := {|oErr, oReq|
   le( "Uncaught error: " + oErr:description )
   HIX_HttpError( oReq, 500, oErr:description )
}
```

Si no defines `bOnError`, HIX usa su renderer interno (`HIX_ShowError` /
`HIX_ErrorSys`) que:

- **dev**: muestra HTML detallado con stack, línea fuente y context.
- **prod**: muestra HTML genérico 500 sin detalle interno.

Ver [Errorsys](errorsys.md) para personalizar el template.

### Diferenciar JSON / HTML automáticamente

```clipper
oSrv:bOnError := {|oErr, oReq|
   IF HIX_WantsJson( oReq )
      oReq:Respond( { "error" => oErr:description }, 500, "json" )
   ELSE
      HIX_ShowError( oErr, oReq )    // delega al renderer interno
   ENDIF
}
```

> `HIX_ShowError` ya hace este split por dentro: si el `Accept` pide
> JSON, responde JSON; si pide HTML, renderiza el template errorsys.

---

## Errores HTTP explícitos

No todo error es excepción. Muchos son situaciones esperadas:

```clipper
USendError( 404, "Usuario no existe" )
USendError( 403, "Sin permiso" )
USendError( 422, "Datos inválidos" )
USendError( 429, "Demasiados intentos" )
```

`USendError` envía el status + cuerpo JSON o HTML según el `Accept`. Es
**la** forma de responder errores controlados desde la acción.

### Equivalente directo

`HIX_HttpError( oReq, nStatus, cMsg )` — recibe el `oReq` explícito,
útil dentro de middlewares.

---

## Worker protect

Bajo el capó, cada worker HTTP envuelve la ejecución del controller en
`HixWorkerProtect`: si la acción suelta una excepción no atrapada, el
protect:

1. Llama a `bOnError` si está definido.
2. Si no, llama a `HIX_ShowError`.
3. Loggea la entrada en `errors.log`.
4. Cierra la conexión limpiamente — no mata el worker, solo el request.

Es lo que evita que un error en una sola URL tumbe el servidor entero.

---

## Logging del error

`HIX_ShowError` siempre llama a `_HixWriteErrorLog` antes de renderizar.
El fichero `errors.log` (configurado con `HIX_ErrorLogInit` o vía
`[server] errors=.logs`) acumula cada error con timestamp + secuencia.

```clipper
HIX_ErrorLogInit( ".logs" )      // dir donde escribir errors.log
```

Para logging libre fuera del flujo error usa los helpers de log:

```clipper
ld( "Debug detail" )       // DEBUG
l(  "Info" )               // INFO
lw( "Warning" )            // WARN
le( "Error description" )  // ERROR
```

Ver el módulo Logger.


