# 📨 Header HTTP

Ogni response HTTP porta una serie di **header** che il client legge prima
del body: content type, cache, redirect, cookie, sicurezza, ...
HIX li gestisce in `oReq:hExtraHeaders` e gli helper `U*` permettono di
leggerli e scriverli senza toccare direttamente l'oggetto.

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

## Leggere gli header dalla request

```clipper
UHeader( cKey, xDef )    // case-insensitive
```

| Chiamata | Ritorna |
|---|---|
| `UHeader( "user-agent" )` | Testo dello user agent o `""` |
| `UHeader( "x-api-key", "" )` | Valore dell'header o `""` |
| `UHeader( "authorization" )` | `"Bearer eyJ..."` |
| `UHeader( "accept" )` | `"application/json, text/html;q=0.9"` |

```clipper
FUNCTION _ApiHandler()
   LOCAL cKey := UHeader( "x-api-key", "" )

   IF Empty( cKey )
      RETURN USendError( 401, "API key mancante" )
   ENDIF

   USendJson( { "ok" => .T. } )
RETURN NIL
```

> I nomi degli header sono **case-insensitive** - `UHeader("X-Api-Key")` e
> `UHeader("x-api-key")` ritornano lo stesso valore.

---

## Scrivere header nella response

```clipper
USetHeader( cKey, cVal )
```

Accumula l'header in `oReq:hExtraHeaders`; quando invia la response, HIX
li aggiunge all'output:

```clipper
USetHeader( "Cache-Control", "no-store" )
USetHeader( "X-Request-Id",  "abc123" )
USetHeader( "X-Frame-Options", "DENY" )

USendJson( hData )
```

Se chiami lo stesso header due volte, **vince l'ultimo**:

```clipper
USetHeader( "X-Version", "1" )
USetHeader( "X-Version", "2" )    // "2" vince
```

### Accesso diretto a `hExtraHeaders`

Da un middleware con `oCtx:oReq`:

```clipper
oCtx:oReq:hExtraHeaders[ "X-Custom" ] := "valore"
```

Equivalente all'helper, ma solo quando non sei in una action di route.

---

## Header comuni

### Content type ed encoding

| Header | Valore tipico |
|---|---|
| `Content-Type` | `application/json; charset=utf-8` |
| `Content-Type` | `text/html; charset=utf-8` |
| `Content-Type` | `text/plain; charset=utf-8` |
| `Content-Encoding` | `gzip` (gestito dal dispatcher) |

HIX imposta `Content-Type` automaticamente in base all'helper che usi
(`USendJson` → json, `USendHtml` → html, ...). Sovrascrivilo solo se
vuoi qualcosa di non standard:

```clipper
USetHeader( "Content-Type", "application/xml; charset=utf-8" )
USendText( cXml )
```

### Cache

| Header | Per cosa |
|---|---|
| `Cache-Control: no-store` | Mai in cache (login, dati sensibili) |
| `Cache-Control: no-cache` | In cache, ma rivalida sempre |
| `Cache-Control: max-age=3600` | In cache per 1 ora |
| `Cache-Control: public, max-age=31536000, immutable` | Asset versionati |
| `ETag` | HIX lo calcola automaticamente per i file statici |

```clipper
USetHeader( "Cache-Control", "no-store, no-cache, must-revalidate" )
USetHeader( "Pragma", "no-cache" )
USendJson( hUserPrivateData )
```

### Redirect e location

| Header | Quando |
|---|---|
| `Location: /new-url` | Accompagna 301/302/307 |
| `Refresh: 5; url=/home` | Redirect del browser dopo N secondi |

Meglio usare `URedirect("/new", 302)` che impostare `Location` a mano.

### Sicurezza

| Header | Valore consigliato |
|---|---|
| `X-Frame-Options` | `DENY` o `SAMEORIGIN` - anti-clickjacking |
| `X-Content-Type-Options` | `nosniff` - disabilita il MIME sniffing |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` (solo HTTPS) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Content-Security-Policy` | `default-src 'self'` (CSP - richiede tuning per app) |
| `Permissions-Policy` | `geolocation=(), camera=()` (disabilita API) |

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

Meglio trasformarlo in un middleware globale:

```clipper
FUNCTION MyAppSecurityHeaders( oCtx )
   _ApplySecurityHeaders()
RETURN .T.

oSrv:Use( "MyAppSecurityHeaders" )
```

### CORS

Gli header `Access-Control-*` sono gestiti dal middleware
[`HIX_MwCors`](../seguridad/cors.md). Non impostarli a mano:

```clipper
oSrv:Use( "HIX_MwCors" )    // inietta Allow-Origin / Allow-Methods / ecc.
```

### Cookie

`Set-Cookie` è speciale: può apparire **più volte** nella stessa
response (uno per cookie). Usa `USetCookie` invece di `USetHeader`:

```clipper
USetCookie( "session", cSid, 3600 )
USetCookie( "lang",    "es",  86400 * 30 )
// → due Set-Cookie nella response
```

Vedi [Cookie](cookies.md).

### Custom dell'applicazione

| Convenzione | Uso |
|---|---|
| `X-Request-Id: abc123` | Identificativo della request - utile per i log |
| `X-RateLimit-Remaining: 42` | Quante request rimangono nella finestra |
| `X-RateLimit-Reset: 1735689600` | Quando si resetta la finestra |
| `X-Powered-By: HIX` | Sigillo opzionale (meglio non esporlo) |

```clipper
LOCAL nCount := UContext():hData[ "rate_count" ]
USetHeader( "X-RateLimit-Limit",     "100" )
USetHeader( "X-RateLimit-Remaining", hb_NToS( 100 - nCount ) )
```

---

## Pattern utili

### Forza il download di un file

```clipper
USetHeader( "Content-Type",        "application/octet-stream" )
USetHeader( "Content-Disposition", 'attachment; filename="export.csv"' )
USendText( cCsv )
```

### Stream SSE - disabilita il buffering

```clipper
USendStreamStart( "text/event-stream", 200, { ;
   "Cache-Control"     => "no-cache",    ;
   "X-Accel-Buffering" => "no"           ;   // nginx non bufferizza
} )
```

### Passa il request-id tra frontend e backend

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

## Best practice

1. **Non esporre informazioni sensibili.** No `Server: HIX 1.2.3` o
   `X-Powered-By` o stack trace negli header. Meno sa un attaccante, meglio è.
2. **Sicurezza per default.** `X-Frame-Options`, `nosniff`, `Referrer-Policy`
   e CSP dovrebbero andare in un middleware globale in tutta l'app.
3. **Non mettere dati negli header.** Gli header sono per i metadati; il body
   è per i dati. Header > 8KB possono essere rifiutati dai proxy.
4. **Case-insensitive in lettura, canonico in scrittura.** HTTP definisce gli
   header come case-insensitive, ma i proxy preferiscono la forma canonica:
   `Content-Type`, non `content-type`.
5. **Non duplicare `Set-Cookie` a mano.** Usa sempre `USetCookie` - sa
   come gestire la lista dei cookie senza sovrascriverli.
