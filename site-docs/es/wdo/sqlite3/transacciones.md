# WDO SQLite3 — Transacciones

WDO soporta transacciones explícitas con `BeginTrans / Commit / Rollback` y un método de conveniencia `Transaction(bCode)` que gestiona el commit/rollback automáticamente.

## Concurrencia en SQLite3 — una diferencia clave

!!! warning "SQLite serializa las escrituras"
    A diferencia de MySQL o PostgreSQL, SQLite permite **un solo writer** a la vez. En modo WAL, múltiples lectores pueden coexistir con ese writer, pero si dos hilos intentan iniciar una transacción de escritura simultáneamente, el segundo espera hasta que el primero libere el lock.

    Si la espera supera `busy_timeout_ms`, SQLite retorna `SQLITE_BUSY`. Configura `busy_timeout_ms >= 5000` en producción para absorber picos de escritura concurrente.

## Aislamiento de transacciones

El driver opera en dos modos según `pool_size` ([config](config.md#pool_size)). Cada modo da garantías de aislamiento distintas:

### Singleton (`pool_size: 1`, default)

Una sola conexión compartida entre todos los hilos. El mutex interno protege **operaciones sueltas** pero **no mantiene el lock entre `BeginTrans()` y `Commit()`** — entre ambas llamadas otros hilos pueden intercalar `Exec` / `Query` sobre la misma conexión. SQLite documenta que *una única conexión no aísla operaciones propias* ([sqlite.org/isolation](https://www.sqlite.org/isolation.html)).

Consecuencia práctica: si dos handlers concurrentes ejecutan `Transaction()` a la vez, los `BEGIN` del segundo chocan con `::lInTrans = .T.` del primero y retornan `.F.` silenciosamente, o peor — un `SELECT` del hilo B puede leer estado intermedio no commitado del hilo A.

Este modo es válido para apps con un worker, scripts CLI, o cargas donde la concurrencia sobre la BD es nula.

### Pool (`pool_size: N > 1`, recomendado para HIX multi-worker)

Cada hilo reserva su propia conexión al entrar al handler. `BEGIN/COMMIT` operan sobre handles independientes; SQLite coordina los writes a nivel de fichero vía `busy_timeout_ms`.

- **Aislamiento real:** las transacciones de distintos hilos nunca interleavan.
- **`SQLITE_BUSY` posible:** dos `Transaction()` de escritura concurrentes sobre el mismo fichero compiten por el lock a nivel de SQLite. Con `busy_timeout_ms: 5000` SQLite reintenta durante 5 segundos antes de rendirse.
- **Reads en paralelo:** modo WAL permite múltiples lectores simultáneos.
- **Cifrado compatible:** SQLCipher aplica el mismo `PRAGMA key` a cada conexión del pool; la DLL se carga una sola vez compartida vía refcount.

Configuración recomendada para producción multi-worker:

```json
"databases": {
   "APP": {
      "driver":          "sqlite3",
      "file":            "www/data/app.db",
      "journal_mode":    "WAL",
      "busy_timeout_ms": 5000,
      "pool_size":       4
   }
}
```

!!! tip "Elige `pool_size` según workers HTTP"
    Como regla práctica, `pool_size` ≈ número de workers HTTP que pueden tocar la BD simultáneamente. 4-8 es suficiente para la mayoría de apps; subir por encima de eso raramente ayuda porque SQLite igualmente serializa writes a nivel de fichero.

Añadido en v2.5.3 (Claim 2 — aislamiento transaccional).

## BeginTrans / Commit

El patrón básico para un flujo que siempre tiene éxito:

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oConn:BeginTrans()

oConn:Exec( "UPDATE cuentas SET saldo = saldo - 200 WHERE propietario = 'alice'" )
oConn:Exec( "UPDATE cuentas SET saldo = saldo + 200 WHERE propietario = 'bob'"   )

oConn:Commit()

oConn:Close()
```

## BeginTrans / Rollback

Cuando hay una condición de negocio que obliga a deshacer:

```harbour
oConn:BeginTrans()

oConn:Exec( "UPDATE cuentas SET saldo = saldo - 5000 WHERE propietario = 'alice'" )

LOCAL oStmt := oConn:Query( "SELECT saldo FROM cuentas WHERE propietario = 'alice'" )
LOCAL hRow  := oStmt:Fetch_Assoc()
oStmt:Free()

IF Val( hRow[ "saldo" ] ) < 0
   oConn:Rollback()   // deshacer el UPDATE
   RETURN USendError( 422, "Saldo insuficiente" )
ELSE
   oConn:Commit()
ENDIF

oConn:Close()
```

## TRY / FINALLY — patrón recomendado

En handlers reales, combina `BeginTrans` con `TRY / FINALLY` para garantizar que la transacción siempre se cierra aunque salte una excepción:

```harbour
FUNCTION TransferirFondos()

   LOCAL oConn   := WDO_Get( "APP" )
   LOCAL nOrigen := Val( UPost( "from_id", "0" ) )
   LOCAL nDestino:= Val( UPost( "to_id",   "0" ) )
   LOCAL nImporte:= Val( UPost( "importe",  "0" ) )
   LOCAL oErr    := NIL
   LOCAL lOk     := .F.

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   oConn:BeginTrans()

   TRY
      oConn:Exec( "UPDATE cuentas SET saldo = saldo - " + ;
                  hb_NToS( nImporte ) + " WHERE id = " + hb_NToS( nOrigen )  )

      oConn:Exec( "UPDATE cuentas SET saldo = saldo + " + ;
                  hb_NToS( nImporte ) + " WHERE id = " + hb_NToS( nDestino ) )

      oConn:Commit()
      lOk := .T.

   CATCH oErr
      oConn:Rollback()
      le( "TransferirFondos: " + oErr:description )
   FINALLY
      oConn:Close()
   END

   IF ! lOk
      RETURN USendError( 500, "Transferencia fallida" )
   ENDIF

RETURN USendJson( { "ok" => .T. } )
```

## Transaction(bCode) — azúcar sintáctico

`oConn:Transaction(bCode)` hace todo el ciclo automáticamente:

- Llama `BeginTrans`.
- Evalúa el codeblock.
- Si termina sin excepción → `Commit` y retorna `.T.`.
- Si se lanza una excepción → `Rollback`, deja la descripción
  original en `oConn:cError` (formato `"SQLite3 Transaction
  aborted: <descripción>"`) y retorna `.F.`. La excepción **no**
  se re-lanza — el caller decide qué hacer leyendo el `.F.`.

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

IF ! oConn:Transaction( {| o | ;
      o:Exec( "UPDATE cuentas SET saldo = saldo - 200 WHERE propietario = 'alice'" ), ;
      o:Exec( "UPDATE cuentas SET saldo = saldo + 200 WHERE propietario = 'bob'"   ) ;
   } )
   RETURN USendError( 500, oConn:cError )
ENDIF

USendJson( { "ok" => .T. } )
```

## Transacciones con Prepared Statements

Los prepared statements son completamente compatibles con transacciones — operan sobre la misma conexión reservada por el request:

```harbour
oConn:BeginTrans()

TRY
   LOCAL oStmt := oConn:Prepare( "INSERT INTO pedidos (uid, total) VALUES (?, ?)" )
   oStmt:BindParam( 1, nUid,   "i" )
   oStmt:BindParam( 2, nTotal, "n" )
   oStmt:Execute()
   LOCAL nPedidoId := oConn:Last_Insert_Id()
   oStmt:Free()

   oStmt := oConn:Prepare( "INSERT INTO lineas_pedido (pedido_id, sku) VALUES (?, ?)" )
   FOR EACH cSku IN aSkus
      oStmt:BindParam( 1, nPedidoId, "i" )
      oStmt:BindParam( 2, cSku,      "s" )
      oStmt:Execute()
      oStmt:Reset()
   NEXT
   oStmt:Free()

   oConn:Commit()

CATCH oErr
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Rollback()
END

oConn:Close()
```

## INSERT masivo — las transacciones son críticas

!!! tip "Velocidad: 100× con transacción explícita"
    Por defecto SQLite opera en modo autocommit: cada `INSERT` es una transacción implícita con un fsync al disco. Para insertar 10 000 filas sin transacción explícita se producen 10 000 fsyncs.

    Con una transacción explícita solo hay **un fsync** al hacer `Commit()`. La diferencia en velocidad es de dos órdenes de magnitud:

    ```harbour
    oConn:BeginTrans()

    oStmt := oConn:Prepare( "INSERT INTO datos (a, b) VALUES (?, ?)" )
    FOR i := 1 TO 10000
       oStmt:BindParam( 1, aA[ i ], "s" )
       oStmt:BindParam( 2, aB[ i ], "n" )
       oStmt:Execute()
       oStmt:Reset()
    NEXT
    oStmt:Free()

    oConn:Commit()   // un solo fsync
    ```

## Estado de la transacción

```harbour
oConn:InTransaction()   // .T. si hay una transacción abierta
```

Útil en handlers que pueden ser llamados desde dentro o fuera de un contexto transaccional.

## SQLITE_BUSY — qué hacer

Si una transacción de escritura no puede adquirir el lock en `busy_timeout_ms` milisegundos, el driver lanza un error con código SQLite `SQLITE_BUSY` (5) o `SQLITE_LOCKED` (6):

```harbour
TRY
   oConn:BeginTrans()
   // ...
   oConn:Commit()
CATCH oErr
   IF "busy" $ Lower( oErr:description ) .OR. "locked" $ Lower( oErr:description )
      RETURN USendError( 503, "Base de datos ocupada. Reintenta en un momento." )
   ENDIF
   RETURN USendError( 500, oErr:description )
END
```

!!! info "busy_timeout_ms por defecto"
    El driver configura `PRAGMA busy_timeout = 5000` al abrir la conexión (configurable en `config.json`). Con este valor, SQLite reintenta automáticamente durante 5 segundos antes de retornar `SQLITE_BUSY`. Para la mayoría de apps esto es suficiente.

## Referencia rápida

| Método | Descripción |
|--------|-------------|
| `oConn:BeginTrans()` | Inicia la transacción (`BEGIN`) |
| `oConn:Commit()` | Confirma los cambios (`COMMIT`) |
| `oConn:Rollback()` | Deshace los cambios (`ROLLBACK`) |
| `oConn:Transaction(bCode)` | Azúcar: begin + eval + commit/rollback automático |
| `oConn:InTransaction()` | `.T.` si hay transacción abierta |
