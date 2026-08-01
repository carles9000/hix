# 🔍 Traceando

Durante el desarrollo, lo más rápido para entender qué pasa en tu código
no es un debugger paso a paso, sino **soltar una traza**. **HIX** expone una
familia de funciones `_d()`, `_t()`, `_w()` que aceptan
**cualquier tipo de variable** (escalar, hash, array, objeto) y lo vuelcan
formateado, con tipo y context.

Las funciones _d() y _t() usan para dbgView, dbwin, ... para Windows y esta utilidad 
nos permite rápidamente poder consultar los que pasa por nuestro código

```clipper
function main() 

   LOCAL hData := { "user" => "Carles", "roles" => { "admin", "ops" } }

   _t( 'My trace system...' )    // Only message 
   
   _d( hData )

retu nil 
```

![image](../../../assets/images/manual/sistema/_d.jpg)


La función _w() és la misma que _d() pero convierte el resultado en formato 
web y si deseamos podemos sacar por el navegador la traza 

```clipper
function main() 

   LOCAL hData := { "user" => "Carles", "roles" => { "admin", "ops" } }   
   
   ? _w( hData )

retu nil 
```

![image](../../../assets/images/manual/sistema/_w.jpg)

---

## Las funciones

| Función | Destino | Cuándo |
|---|---|---|
| `_d(...)` | OutputDebugString (Windows) o TraceLog (Linux/Mac) | Trazas de desarrollo, ven en DebugView |
| `_t(...)` | Igual que `_d` pero sin prefijo de procedure | Trazas "limpias" para volcado masivo |
| `_w(...)` | Devuelve string HTML con `<br>` | Inyectar trazas en una página HTML |


Las funciones aceptan **N argumentos** de cualquier tipo:

```clipper
_d( "Antes del query", hParams, nResultados )
_d( "Después:", oUser )
```

---

## Ejemplo trazas

### Traceo en un proceso...

```clipper
FUNCTION _ProcessOrder( nId )
   LOCAL hOrder, lOk

   _d( "→ _ProcessOrder", nId )

   hOrder := _LoadOrder( nId )
   
   _d( "loaded:", hOrder )

   lOk := _Save( hOrder )
   _d( "← _ProcessOrder", lOk )

RETURN lOk
```

### Solo en dev

```clipper
IF UIsDev()
   _d( "Query:", cSql, "Params:", aParams )
ENDIF
```

### Inspeccionar un objeto / hash desconocido

```clipper
FUNCTION _Dump( xValue, cLabel )
   _d( cLabel + ":", xValue )
RETURN NIL

// ...
_Dump( oReq, "request" )
_Dump( UContext():hData, "context.data" )
```

### Después de cada middleware

Para entender por qué un middleware falla:

```clipper
FUNCTION HixMwMiAuth( oCtx )
   _d( "session:", USession("user") )
   _d( "headers:", oCtx:oReq:hHeaders )

   IF Empty( USession("user") )
      _d( "Auth FAIL — sin sesión" )
      oCtx:lHandled := .T.
      oCtx:oReq:Redirect( "/login", 302 )
      RETURN .F.
   ENDIF

   _d( "Auth OK" )
RETURN .T.
```

### Salida limpia con `_t()`

Cuando ya sabes dónde estás y solo quieres el valor (sin
`MYFUNC (42) Type (H)`):

```clipper
_t( "Result:", nTotal )
// → "Result: 42" en vez de "MYFUNC (50) Type (N) 42"
```

---

## Diferencia con el Logger

| | `_d()` / `_t()` | `l()` / `ld()` / `le()` |
|---|---|---|
| Destino | OutputDebugString / TraceLog | `hix.log` (fichero) |
| Persistente | ❌ (volátil — se ve en DebugView, no se guarda) | ✅ (rotación + niveles) |
| Formato | Bloque con tipo + indentación | Línea con timestamp + nivel |
| Producción | Quitarlo — no aporta nada visible | Mantenerlo — base del troubleshooting prod |
| Cantidad recomendada | Lo que necesites en dev | Solo eventos significativos (start, error, ...) |

Cuando una función está estable, **migra las trazas útiles a `l()`/`le()`**
y borra los `_d()` que solo te sirvieron en el momento.

---


## Buenas prácticas

1. **`_d()` es desechable.** Lo añades para entender un bug, lo quitas al
   resolverlo. Si quieres que sobreviva, conviértelo en `l()` o `ld()`.
2. **No traces secretos.** Tokens, passwords, JWTs — nunca a través de
   `_d()`. Aunque solo se vea en dev, los logs de DebugView pueden
   acabar en un screenshot.
3. **Envuelve en `UIsDev()` lo que pueda llegar a prod por error.**
4. **Una traza al entrar, una al salir.** Para funciones que sospechas
   problemáticas, marca entrada con args y salida con resultado.
5. **No dejes trazas en código compartido.** Si tu PR mete `_d()` en
   archivos del framework HIX, no aprueba revisión — son ruido para
   otros.
---
