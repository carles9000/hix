# 🌐 CORS — Cross-Origin Resource Sharing


Por defecto, el navegador **bloquea** que JavaScript en `https://app.com`
haga `fetch()` contra `https://api.otrodominio.com`. Es la **Same-Origin
Policy**, una defensa básica contra ataques cross-site.

**CORS** es el mecanismo por el que el servidor le dice al navegador
"sí, acepto requests desde este origen, con estos métodos y estas
cabeceras". Lo hace con un puñado de headers `Access-Control-*`.

```
Browser (app.com)                     Servidor (api.com)
   │                                       │
   │ OPTIONS /v1/users  (preflight)        │
   │ Origin: https://app.com               │
   │ Access-Control-Request-Method: PUT    │
   ├──────────────────────────────────────>│  HIX_MwCors detecta OPTIONS
   │                                       │  Responde 204 con headers CORS
   │ 204 No Content                        │
   │ Access-Control-Allow-Origin: app.com  │
   │ Access-Control-Allow-Methods: PUT,... │
   │<──────────────────────────────────────┤
   │                                       │
   │ PUT /v1/users/42  (real)              │
   │ Origin: https://app.com               │
   ├──────────────────────────────────────>│  HIX_MwCors inyecta headers
   │ 200 OK + datos                        │  Resto del pipeline procesa
   │<──────────────────────────────────────┤
```

> El **preflight OPTIONS** lo lanza el navegador automáticamente cada vez
> que un request cross-origin usa un método "no simple" (PUT, DELETE,
> PATCH) o cabeceras custom (`Authorization`, `Content-Type: application/json`).

---

## Cuándo usarlo

| Caso | CORS |
|---|---|
| API consumida por SPA en otro dominio | ✅ Sí — imprescindible |
| API pública para integraciones | ✅ Sí |
| Móvil consumiendo la API | ❌ No — no hay navegador, no aplica |
| Backend mismo dominio que el frontend | ❌ No — same-origin |
| Webhook que recibe POSTs de servicios externos | ❌ No — los servidores no respetan CORS |

> CORS protege al **usuario**, no al servidor. Un atacante con `curl` o
> un servidor propio no sufre CORS — la regla la aplica solo el navegador.

---

## Setup

```clipper
HIX_MwCorsSetup( ;
   "https://app.com",                                 ;   // cOrigin
   "GET,POST,PUT,DELETE,OPTIONS,PATCH",               ;   // cMethods
   "Content-Type,Authorization,X-Requested-With" )        // cHeaders
```

Valores por defecto si no llamas a `HIX_MwCorsSetup`:

| Parámetro | Default |
|---|---|
| `cOrigin` | `"*"` (cualquier origen — laxo, solo para desarrollo) |
| `cMethods` | `"GET,POST,PUT,DELETE,OPTIONS,PATCH"` |
| `cHeaders` | `"Content-Type,Authorization,X-Requested-With"` |

Llamar **antes** de `oSrv:Start()`.

---

## Activación

`HIX_MwCors` es un middleware **global** — lo normal es aplicarlo a todo
el servidor con `oSrv:Use()` para que cada response salga con los headers:

```clipper
oSrv:Use( "HIX_MwCors" )
```

O por ruta concreta:

```clipper
oSrv:AddRouteGet( "api", "/api/users", bAction, "HIX_MwCors" )
```

```json
{ "name": "api.users", "url": "/api/users", "method": "GET",
  "action": "controllers/api/users.prg",
  "middleware": "HIX_MwCors" }
```

---

## Cómo funciona

```clipper
FUNCTION HIX_MwCors( oCtx )
   LOCAL hCors := { ;
      "Access-Control-Allow-Origin"  => s_cCorsOrigin,  ;
      "Access-Control-Allow-Methods" => s_cCorsMethods, ;
      "Access-Control-Allow-Headers" => s_cCorsHeaders, ;
      "Access-Control-Max-Age"       => "86400"          ;
   }

   IF oCtx:oReq:cMethod == "OPTIONS"
      oCtx:oReq:Respond( "", 204, "text", hCors )   // preflight
      oCtx:lHandled := .T.
      RETURN .F.                                     // corta la cadena
   ENDIF

   hb_HMerge( oCtx:oReq:hExtraHeaders, hCors )      // inyecta en respuesta
RETURN .T.
```

| Método | Comportamiento |
|---|---|
| `OPTIONS` | Responde **204 No Content** con headers CORS — preflight resuelto |
| Cualquier otro | Inyecta los headers `Access-Control-*` en la respuesta final |

`Access-Control-Max-Age: 86400` indica al navegador que cachee la
respuesta del preflight 24h, evitando un OPTIONS extra por cada request.

---

## Combinar con otros middlewares

CORS suele ir **primero** en la pila, antes de auth, para que el
preflight se resuelva sin tropezar con un 401:

```clipper
oSrv:Use( { "HIX_MwCors", "HIX_MwSession" } )

oSrv:AddRouteGet( "api.me", "/api/me", bAction, ;
   "HIX_MwCors,HIX_MwJwt" )
```

> Si `HIX_MwJwt` corriera antes que CORS, el OPTIONS sin Bearer recibiría
> un 401 y el navegador no llegaría a hacer el request real.

---

## Patrones útiles

### CORS abierto solo en desarrollo

```clipper
IF HIX_Config( "env" ) == "dev"
   HIX_MwCorsSetup( "*" )
ELSE
   HIX_MwCorsSetup( "https://app.com" )
ENDIF
```

### Múltiples orígenes (no soportado nativamente)

`HIX_MwCorsSetup` acepta **un solo** `cOrigin`. Para varios, escribe un
middleware propio que mire el `Origin` del request y devuelva el header
adecuado:

```clipper
FUNCTION MyAppCors( oCtx )
   LOCAL aAllowed := { "https://app.com", "https://admin.app.com" }
   LOCAL cOrigin  := oCtx:oReq:Header( "origin", "" )

   IF AScan( aAllowed, cOrigin ) > 0
      oCtx:oReq:hExtraHeaders[ "Access-Control-Allow-Origin" ] := cOrigin
   ENDIF

RETURN HIX_MwCors( oCtx )   // delega el resto al middleware estándar
```

### Cookies cross-origin

Si la API envía cookies (sesión) y el frontend está en otro dominio,
añade `Access-Control-Allow-Credentials: true` y especifica un origen
concreto (`*` no es compatible con credentials):

```clipper
oReq:hExtraHeaders[ "Access-Control-Allow-Credentials" ] := "true"
```

---

## Errores típicos

| Síntoma | Causa |
|---|---|
| `CORS policy: No 'Access-Control-Allow-Origin'` | Falta `HIX_MwCors` en la ruta — o no se aplicó a OPTIONS |
| `Origin not allowed` | `s_cCorsOrigin` no coincide con el `Origin` del cliente |
| `Method PUT is not allowed` | `s_cCorsMethods` no incluye PUT |
| `Header authorization is not allowed` | `s_cCorsHeaders` no incluye Authorization |
| Preflight devuelve 401 | CORS configurado **después** del middleware de auth |

---

## Buenas prácticas

1. **`"*"` solo en desarrollo.** En producción, lista los orígenes
   concretos que pueden consumir tu API.
2. **CORS no es autenticación.** Solo le dice al navegador qué requests
   pueden completarse — no autentica nada. Combínalo siempre con
   [JWT](jwt.md) o [Sesiones](sesiones.md).
3. **Aplica con `oSrv:Use`.** El preflight OPTIONS llega a cualquier URL,
   incluso a las que no existen — registrarlo globalmente evita
   sorpresas con 405/404 en OPTIONS.
4. **Pon CORS antes que auth en el pipeline.** El OPTIONS no lleva
   credenciales y un middleware de auth lo rechazaría.
5. **Limita métodos y headers.** No publiques todo si no lo usas.


