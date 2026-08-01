# 🎫 JWT - JSON Web Token

## ¿Qué es?

Un **JWT** es un token autocontenido y firmado que el servidor emite al
hacer login y el cliente envía en cada request siguiente.

- **Autocontenido**: lleva dentro toda la información del usuario
  (`user_id`, `role`, etc.). El servidor **no guarda nada** entre requests.
- **Firmado**: HIX usa **HMAC-SHA256** con una clave secreta. Si el cliente
  altera un solo byte, la firma deja de cuadrar y se rechaza.
- **Stateless**: dos servidores con la misma clave validan el mismo token
  → escala horizontalmente sin storage compartido.

```
header.payload.signature

eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9   {"typ":"JWT","alg":"HS256"}
.eyJ1c2VyX2lkIjoiNDIiLCJyb2xlIjoi...    {"user_id":"42","role":"admin","exp":...}
.aBcD3f9eGgHhIi...                      HMAC-SHA256(header.payload, secret)
```

---

## Cuándo usarlo

| Caso de uso | JWT |
|---|---|
| API REST stateless | ✅ Sí - patrón canónico |
| App móvil que llama a una API | ✅ Sí |
| Microservicios con tokens compartidos | ✅ Sí |
| SPA llamando a un backend separado | ✅ Sí |
| App web tradicional con login form | ❌ Usa [Sesiones](sesiones.md) |
| Tokens de un solo uso (descarga, reset password) | ⚠️ Sí, con `exp` cortito |

> JWT vs Sesión: el JWT no necesita storage en el servidor pero **no se
> puede invalidar** antes de que expire. Sesión es lo contrario:
> requiere storage pero puedes destruir el SID y echar al cliente al
> instante.

---

## Setup

```clipper
HIX_MwJwtSetup( ;
   "clave_super_secreta_y_larga",  ;   // cKey - HMAC secret
   3600 )                              // nExpSecs - TTL del token (1h)
```

Llamarlo **antes** de `oSrv:Start()`. Si no lo configuras, HIX usa
`hix-secret-key` por defecto (⚠️ **inseguro**).

---

## Emitir un token en /login

```clipper
// POST /api/login
FUNCTION Main()
   LOCAL oVal, hUser, cToken

   oVal := UValidateOrFail( { ;
      "username" => "required|string", ;
      "password" => "required|string"  ;
   } )
   IF oVal == NIL ; RETURN ; ENDIF

   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   IF ValType( hUser ) != "H"
      USendJson( { "error" => "invalid_credentials" }, 401 )
      RETURN
   ENDIF

   cToken := HIX_JwtEncode( { ;
      "user_id" => hUser[ "id"   ], ;
      "name"    => hUser[ "name" ], ;
      "scope"   => "read:products write:orders" ;
   } )

   USendJson( { "token" => cToken, "expires_in" => 3600 } )
RETURN
```

`HIX_JwtEncode` añade automáticamente las claims estándar:

| Claim | Valor |
|---|---|
| `iss` | `"HIX"` |
| `iat` | timestamp Unix de emisión |
| `exp` | `iat + nExpSecs` |

Lo que añadas tú (`user_id`, `scope`, `role`, ...) viaja junto.

---

## Proteger una ruta

```clipper
// Pipeline: validación JWT -> handler
oSrv:AddRouteGet( "me", "/api/me", ;
   {|| USendJson( UContext():hData["jwt"] ) }, ;
   "HIX_MwJwt" )
```

```json
{ "name": "me", "url": "/api/me", "method": "GET",
  "action": "controllers/me.prg",
  "middleware": "HIX_MwJwt" }
```

El cliente debe enviar:

```http
GET /api/me HTTP/1.1
Authorization: Bearer eyJ0eXAiOiJKV1Qi...aBcD3f
```

`HIX_MwJwt` valida la firma + `exp`, deja el payload en
`oCtx:hData["jwt"]` y continúa. Si el token falta o es inválido →
**401**.

---

## Leer el payload en el controller

```clipper
PROCEDURE Main(...)
   LOCAL oCtx  := UContext()
   LOCAL hJwt  := oCtx:hData[ "jwt" ]
   LOCAL cUser := hJwt[ "user_id" ]
   LOCAL cRole := hb_HGetDef( hJwt, "role", "" )

   USendJson( { "user_id" => cUser, "role" => cRole } )
RETURN
```

---

## Scopes - autorización por operación

`HIX_MwJwtScope` exige que la claim `scope` del token contenga todos los
tokens (separados por espacio) que la ruta declara como necesarios:

```json
{ "name": "products.list",   "url": "/api/products",        "method": "GET",
  "middleware": "HIX_MwJwt,HIX_MwJwtScope", "scope": "read:products" }

{ "name": "products.delete", "url": "/api/products/:id",    "method": "DELETE",
  "middleware": "HIX_MwJwt,HIX_MwJwtScope", "scope": "delete:products" }
```

Con un token que lleve `"scope" => "read:products write:orders"`:

| Ruta | Resultado |
|---|---|
| `GET /api/products` (`read:products`) | ✅ permite |
| `POST /api/orders` (`write:orders`) | ✅ permite |
| `DELETE /api/products/42` (`delete:products`) | ❌ 403 - falta el scope |

> El orden importa: **`HIX_MwJwt` primero** (deja el payload en hData),
> **`HIX_MwJwtScope` después** (lo lee).

---

## Múltiples claves - `HIX_MwJwtFactory`

Si distintas rutas usan distintas claves de firma (por ejemplo, un set
para API pública y otro para API interna):

```clipper
LOCAL bMwApi    := HIX_MwJwtFactory( "clave_publica"  )
LOCAL bMwIntern := HIX_MwJwtFactory( "clave_interna"  )

oSrv:AddRouteGet( "pub",     "/api/pub",     bAction, bMwApi    )
oSrv:AddRouteGet( "intern",  "/admin/data",  bAction, bMwIntern )
```

---

## Validar / decodificar a mano

Útil para tokens fuera del pipeline (por ejemplo, validar uno recibido
por WebSocket):

```clipper
LOCAL hPayload := HIX_JwtValidate( cToken )

IF hPayload == NIL
   // firma inválida o expirado
   RETURN .F.
ENDIF

? hPayload[ "user_id" ], hPayload[ "exp" ]
```

---

## Refresh tokens - patrón básico

JWT no se puede invalidar antes de `exp`. Para tokens de larga duración
sin perder seguridad, usa **dos tokens**:

| Token | TTL | Uso |
|---|---|---|
| Access token | corto (15 min) | Va en cada request `Authorization: Bearer ...` |
| Refresh token | largo (7-30 días) | Solo viaja al endpoint `/refresh` para emitir un nuevo access |

```clipper
// POST /api/refresh
FUNCTION Main()
   LOCAL cRefresh := UPost( "refresh_token", "" )
   LOCAL hPayload := HIX_JwtValidate( cRefresh, "clave_refresh" )

   IF hPayload == NIL
      RETURN USendJson( { "error" => "invalid_refresh" }, 401 )
   ENDIF

   USendJson( { ;
      "token" => HIX_JwtEncode( { "user_id" => hPayload["user_id"] } ) ;
   } )
RETURN
```

---

## JWT vs Sesión - tabla rápida

| | JWT | Sesión |
|---|---|---|
| Storage en servidor | ❌ No | ✅ Sí (memoria/fichero) |
| Invalidación inmediata | ❌ Espera `exp` o lista negra | ✅ `Destroy()` |
| Escalado horizontal | ✅ Sin estado compartido | ⚠️ Necesita storage o session affinity |
| Cross-domain / móvil | ✅ Bearer header | ❌ Cookie atada al dominio |
| CSRF | ❌ No aplica (no es cookie) | ⚠️ Obligatorio |
| Tamaño por request | ~500-1000 bytes | ~50 bytes (solo SID) |
| Revocar tokens emitidos | ❌ Difícil sin lista negra | ✅ Fácil |

---

## Buenas prácticas

1. **Clave secreta larga y rotable.** Mínimo 32 bytes aleatorios.
   Cámbiala por entornos (`dev` / `prod`).
2. **Expiración corta.** 15-60 min para acceso, refresh largo aparte.
   JWT eternos son un agujero de seguridad.
3. **No metas datos sensibles en el payload.** El payload es base64,
   **no encriptado** - cualquiera puede leerlo. Solo es a prueba de
   manipulación.
4. **HTTPS siempre.** El Bearer viaja en cada request - sin
   [SSL](ssl.md) cualquiera lo intercepta.
5. **No mezcles JWT con cookies.** Si vas a JWT, usa solo el header
   `Authorization` - meter el token en cookie te trae los problemas
   de CSRF que el JWT evitaba.
6. **Lista negra para logout.** Si necesitas invalidar antes de `exp`,
   guarda en Redis los `jti` (JWT ID) revocados y compruébalos en el
   middleware.

---

## Arquitectura interna

Desde la versión 2026-07-14 el código JWT está separado en dos ficheros con
responsabilidades bien definidas:

| Fichero | Capa | Contenido |
|---|---|---|
| `src/hix_jwt.prg` | **Engine** (puro) | `HIX_JwtEncode`, `HIX_JwtValidate`, `HIX_MwJwtSetup`, `HIX_JwtDefaultKey`, `HIX_JwtDefaultExp` y helpers privados de firma HMAC-SHA256 y Base64Url. Sin dependencias del router. |
| `src/mw/hix_mw_jwt.prg` | **Middleware** | `HIX_MwJwt`, `HIX_MwJwtFactory`, `HIX_MwJwtScope`. Solo pipeline: extrae Bearer, invoca el engine y escribe `oCtx:hData["jwt"]`. |

Ventajas del split:

- El engine se puede reutilizar fuera del pipeline (CLI, workers, validar
  tokens recibidos por WebSocket) sin cargar el middleware.
- Los STATIC de configuración (`s_cJwtKey`, `s_nJwtExpSec`) viven en el
  engine. El middleware los consulta vía `HIX_JwtDefaultKey()` /
  `HIX_JwtDefaultExp()` (los STATIC en Harbour son de scope por fichero).
- Cambios en el pipeline (403/401 handling, telemetría) no obligan a
  recompilar el engine y viceversa.

> La API pública no cambia: `HIX_MwJwtSetup`, `HIX_JwtEncode`,
> `HIX_JwtValidate`, `HIX_MwJwt`, `HIX_MwJwtFactory` y `HIX_MwJwtScope`
> mantienen el mismo nombre y firma que antes del split.

