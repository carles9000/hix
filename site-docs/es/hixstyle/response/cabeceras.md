# 📨 Cabeceras HTTP

Cada response HTTP lleva una serie de **headers** que el cliente lee antes
del cuerpo: tipo de contenido, cache, redirecciones, cookies, seguridad,
... HIX las gestiona en `oReq:hExtraHeaders` y las helpers `U*` te
permiten leerlas y escribirlas sin tocar el objeto.

```
Browser  ──── GET /api/users ────▶ HIX
                                    │
                                    │  USetHeader( "Cache-Control", "no-store" )
                                    │  USetHeader( "X-Request-Id", "abc123" )
                                    │  USendJson( hData )
                                    ▼
         <──── 200 OK ──────────────┤
            Content-Type: application/json
            Cache-Control: no-store
            X-Request-Id: abc123
            ...
```

---

## Leer cabeceras del request

```clipper
UHeader( cKey, xDef )    // case-insensitive
```

| Llamada | Devuelve |
|---|---|
| `UHeader( "user-agent" )` | Texto del UA o `""` |
| `UHeader( "x-api-key", "" )` | Valor del header o `""` |
| `UHeader( "authorization" )` | `"Bearer eyJ..."` |
| `UHeader( "accept" )` | `"application/json, text/html;q=0.9"` |

```clipper
FUNCTION _ApiHandler()
   LOCAL cKey := UHeader( "x-api-key", "" )

   IF Empty( cKey )
      RETURN USendError( 401, "Falta API key" )
   ENDIF

   USendJson( { "ok" => .T. } )
RETURN NIL
```

> Los nombres son **case-insensitive** - `UHeader("X-Api-Key")` y
> `UHeader("x-api-key")` devuelven lo mismo.

---

## Escribir cabeceras en la response

```clipper
USetHeader( cKey, cVal )
```

Acumula la cabecera en `oReq:hExtraHeaders`; al enviar la respuesta, HIX
las añade al output:

```clipper
USetHeader( "Cache-Control", "no-store" )
USetHeader( "X-Request-Id",  "abc123" )
USetHeader( "X-Frame-Options", "DENY" )

USendJson( hData )
```

Si llamas dos veces al mismo header, **el último gana**:

```clipper
USetHeader( "X-Version", "1" )
USetHeader( "X-Version", "2" )    // gana "2"
```

### Acceso directo a `hExtraHeaders`

Desde un middleware con `oCtx:oReq`:

```clipper
oCtx:oReq:hExtraHeaders[ "X-Custom" ] := "valor"
```

Equivalente al helper, pero solo cuando no estás en una acción de ruta.

---

## Cabeceras comunes

### Tipo de contenido y encoding

| Header | Valor típico |
|---|---|
| `Content-Type` | `application/json; charset=utf-8` |
| `Content-Type` | `text/html; charset=utf-8` |
| `Content-Type` | `text/plain; charset=utf-8` |
| `Content-Encoding` | `gzip` (lo gestiona el dispatcher) |

HIX pone `Content-Type` automáticamente según el helper que uses
(`USendJson` → json, `USendHtml` → html, ...). Solo lo sobrescribes si
quieres algo no estándar:

```clipper
USetHeader( "Content-Type", "application/xml; charset=utf-8" )
USendText( cXml )
```

### Cache

| Header | Para qué |
|---|---|
| `Cache-Control: no-store` | Nunca cachear (login, datos sensibles) |
| `Cache-Control: no-cache` | Cachear, pero revalidar siempre |
| `Cache-Control: max-age=3600` | Cachear 1 hora |
| `Cache-Control: public, max-age=31536000, immutable` | Assets versionados |
| `ETag` | HIX lo calcula automático para ficheros estáticos |

```clipper
USetHeader( "Cache-Control", "no-store, no-cache, must-revalidate" )
USetHeader( "Pragma", "no-cache" )
USendJson( hUserPrivateData )
```

### Redirecciones y location

| Header | Cuándo |
|---|---|
| `Location: /new-url` | Acompaña al 301/302/307 |
| `Refresh: 5; url=/home` | Redirect del navegador tras N segundos |

Mejor usar `URedirect("/new", 302)` que setear `Location` a mano.

### Seguridad

| Header | Valor recomendado |
|---|---|
| `X-Frame-Options` | `DENY` o `SAMEORIGIN` - anti-clickjacking |
| `X-Content-Type-Options` | `nosniff` - desactiva MIME sniffing |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` (solo HTTPS) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Content-Security-Policy` | `default-src 'self'` (CSP - requiere ajuste por app) |
| `Permissions-Policy` | `geolocation=(), camera=()` (deshabilita APIs) |

```clipper
PROCEDURE _ApplySecurityHeaders()
   USetHeader( "X-Frame-Options",        "DENY" )
   USetHeader( "X-Content-Type-Options", "nosniff" )
   USetHeader( "Referrer-Policy",        "strict-origin-when-cross-origin" )

   IF UIsHttps()
      USetHeader( "Strict-Transport-Security", "max-age=31536000; includeSubDomains" )
   ENDIF
RETURN
```

Mejor convertirlo en middleware global:

```clipper
FUNCTION MyAppSecurityHeaders( oCtx )
   _ApplySecurityHeaders()
RETURN .T.

oSrv:Use( "MyAppSecurityHeaders" )
```

### CORS

Los headers `Access-Control-*` los gestiona el middleware
[`HIX_MwCors`](../seguridad/cors.md). No los seteas a mano:

```clipper
oSrv:Use( "HIX_MwCors" )    // inyecta Allow-Origin / Allow-Methods / etc.
```

### Cookies

`Set-Cookie` es especial: puede aparecer **varias veces** en una misma
response (una por cookie). Usar `USetCookie` en vez de `USetHeader`:

```clipper
USetCookie( "session", cSid, 3600 )
USetCookie( "lang",    "es",  86400 * 30 )
// → dos Set-Cookie en la respuesta
```

Ver [Cookies](cookies.md).

### Custom de aplicación

| Convención | Uso |
|---|---|
| `X-Request-Id: abc123` | Identificador del request - útil para logs |
| `X-RateLimit-Remaining: 42` | Cuántos requests quedan en la ventana |
| `X-RateLimit-Reset: 1735689600` | Cuándo se reinicia la ventana |
| `X-Powered-By: HIX` | Sello opcional (mejor no exponer) |

```clipper
LOCAL nCount := UContext():hData[ "rate_count" ]
USetHeader( "X-RateLimit-Limit",     "100" )
USetHeader( "X-RateLimit-Remaining", hb_NToS( 100 - nCount ) )
```

---

## Patrones útiles

### Forzar descarga de fichero

```clipper
USetHeader( "Content-Type",        "application/octet-stream" )
USetHeader( "Content-Disposition", 'attachment; filename="export.csv"' )
USendText( cCsv )
```

### Stream SSE - desactivar buffering

```clipper
USendStreamStart( "text/event-stream", 200, { ;
   "Cache-Control"     => "no-cache",    ;
   "X-Accel-Buffering" => "no"           ;   // nginx no buferea
} )
```

### Pasar request-id entre frontend y backend

```clipper
FUNCTION MyAppRequestId( oCtx )
   LOCAL cId := UHeader( "X-Request-Id", "" )

   IF Empty( cId )
      cId := hb_MD5( hb_NToS( Int( hb_TToSec( hb_DateTime() ) ) ) + ;
                     hb_NToS( hb_Random() ) )
      cId := Left( cId, 16 )
   ENDIF

   oCtx:hData[ "request_id" ] := cId
   USetHeader( "X-Request-Id", cId )
RETURN .T.
```

---

## Buenas prácticas

1. **No expongas información sensible.** Sin `Server: HIX 1.2.3` ni
   `X-Powered-By` ni stack-traces en headers. Cuanto menos sepa el
   atacante, mejor.
2. **Seguridad por defecto.** `X-Frame-Options`, `nosniff`, `Referrer-Policy`
   y CSP deberían ir en un middleware global de toda la app.
3. **No metas datos en headers.** Headers son para metadatos; el cuerpo
   es para datos. Cabeceras > 8KB pueden ser rechazadas por proxies.
4. **Case-insensitive al leer, canónico al escribir.** HTTP define los
   headers como case-insensitive, pero los proxies prefieren la forma
   canónica: `Content-Type`, no `content-type`.
5. **No dupliques `Set-Cookie` a mano.** Usa siempre `USetCookie` - sabe
   cómo manejar la lista de cookies sin pisarlas.

