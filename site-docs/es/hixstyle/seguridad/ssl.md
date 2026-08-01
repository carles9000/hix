# 🔒 SSL / TLS


**SSL/TLS** cifra el canal entre el navegador y el servidor. Sin él, todo
viaja en claro - y eso incluye:

- Las cookies de sesión (`HIXSID=abc123`) → un intermediario puede
  capturarlas y suplantar al usuario.
- Las credenciales del login (`username=demo&password=1234`).
- Los tokens JWT (`Authorization: Bearer eyJ...`).
- El cuerpo de cada response (datos sensibles del usuario).

Con HTTPS, todo eso viaja **encriptado** y firmado. Un atacante en mitad
de la red solo ve bytes opacos.

```
http://app.com   ─────▶  texto plano  ─────▶  servidor  (cualquiera lee)
https://app.com  ─────▶  TLS encrypt  ─────▶  servidor  (solo el servidor descifra)
```

> En producción **HTTPS no es opcional**. Cualquier cosa con login,
> sesión, JWT o pago **tiene que** ir por HTTPS. Los navegadores
> modernos marcan los sitios HTTP como "No seguro" y bloquean APIs
> nuevas (geolocation, service workers, fetch a credenciales, ...) sin TLS.

---

## Activación en HIX

### Desde `hix.json`

```json
{
  "paths": {
    "certs": "certs"
  },
  "server": {
    "host":         "0.0.0.0",
    "port":         443,
    "ssl":          true,
    "cert_private": "hix.key",
    "cert_public":  "hix.crt"
  }
}
```

| Clave | Valor |
|---|---|
| `paths.certs` | Directorio donde residen los ficheros de certificado (default: `certs`) |
| `ssl` | `true` activa TLS, `false` (default) lo desactiva |
| `cert_private` | Nombre del fichero `.key` dentro de `paths.certs` |
| `cert_public` | Nombre del fichero `.crt` dentro de `paths.certs` |
| `port` | Convención: **443** para HTTPS, 80 para HTTP |

### Desde código

```clipper
LOCAL oCfg := THixConfig():New()
oCfg:lSSL          := .T.
oCfg:cCertPrivate  := "certs/hix.key"
oCfg:cCertPublic   := "certs/hix.crt"
oCfg:nPort         := 443

oSrv := THixServer():New( oCfg )
```

> Al arrancar, `oCfg:Validate()` comprueba que los dos ficheros existen.
> Si no, el servidor escribe error en log y **no arranca**.

---

## Obtener un certificado

### Producción - Let's Encrypt (gratis y automático)

[Let's Encrypt](https://letsencrypt.org/) es una CA gratuita que emite
certificados con la herramienta **`certbot`**:

```bash
certbot certonly --standalone -d app.example.com
```

Esto genera dos ficheros en `/etc/letsencrypt/live/app.example.com/`:

- `privkey.pem` → `cert_private`
- `fullchain.pem` → `cert_public`

Los certificados caducan a los 90 días - `certbot` se programa para
renovarlos automáticamente.

### Desarrollo - certificado autofirmado

Para `localhost`:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 ;
  -keyout certs/hix.key -out certs/hix.crt ;
  -subj "/CN=localhost"
```

El navegador mostrará un warning de "certificado no confiable" - es lo
esperado. Para test local está bien; nunca para producción.

---

## Helpers de detección

Desde un controller puedes saber si el request llegó por HTTPS:

```clipper
UIsHttps()        // .T. / .F.
UScheme()         // "http" / "https"
```

Útil para forzar la cookie como `Secure`, o para redirigir tráfico
HTTP→HTTPS:

```clipper
FUNCTION HixMwForceHttps( oCtx )
   IF ! UIsHttps()
      oCtx:lHandled := .T.
      URedirect( "https://" + UHost() + UPath(), 301 )
      RETURN .F.
   ENDIF
RETURN .T.
```

---

## HIX directo vs detrás de proxy

### HIX directo (autocontenido)

```json
{
  "paths": {
    "certs": "certs"
  },
  "server": {
    "host":         "0.0.0.0",
    "port":         443,
    "ssl":          true,
    "cert_private": "hix.key",
    "cert_public":  "hix.crt"
  }
}
```

HIX termina TLS y sirve HTTPS directamente. Ideal para apps pequeñas o
self-hosted.

### Detrás de proxy (Apache / Nginx / Cloudflare)

Lo habitual en producción: el **proxy** termina TLS y reenvía HTTP plano
a HIX en la red interna:

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 8080,
    "ssl":  false,
    "mode": "proxied"
  }
}
```

`server.ssl = false` -> HIX habla HTTP plano con el proxy. `server.mode = "proxied"`
activa la lectura de `X-Forwarded-*`.

```apache
# Apache reverse proxy
<VirtualHost *:443>
   ServerName app.example.com
   SSLEngine on
   SSLCertificateFile      /etc/letsencrypt/live/app.example.com/fullchain.pem
   SSLCertificateKeyFile   /etc/letsencrypt/live/app.example.com/privkey.pem

   ProxyPass        / http://127.0.0.1:8080/
   ProxyPassReverse / http://127.0.0.1:8080/
   RequestHeader set X-Forwarded-Proto "https"
   RequestHeader set X-Forwarded-For   "%{REMOTE_ADDR}s"
</VirtualHost>
```

| | HIX directo | Detrás de proxy |
|---|---|---|
| Termina TLS | HIX | Proxy |
| Certificado | En HIX | En proxy |
| Renovación | Manual o cron | Lo gestiona el proxy |
| Múltiples backends | ❌ | ✅ Load balancing |
| Adecuado para | Apps pequeñas, dev | Producción seria |

---

## Cookies seguras con HTTPS

Cuando todo va por TLS, las cookies de sesión deberían marcarse como
**Secure** para que el navegador no las envíe nunca por HTTP:

```clipper
// Cookie marcada como Secure (solo por HTTPS)
USetCookie( "session_id", cSid, 3600 )
// HIX añade automáticamente HttpOnly + SameSite=Lax
// Pendiente: flag Secure en versiones nuevas - verifica si está expuesto
```

> Las cookies HIX ya llevan `HttpOnly; SameSite=Lax` por defecto, lo que
> filtra parte de los ataques. El flag `Secure` lo añade el proxy si
> termina TLS allí, o necesita activarse explícitamente con TLS local.

---

## Errores comunes

| Síntoma | Causa |
|---|---|
| `SSL: cert_private not found` al arrancar | Ruta a `.key` mal escrita o fichero ausente |
| `SSL: cert_public not found` | Igual con el `.crt` |
| Navegador: `NET::ERR_CERT_AUTHORITY_INVALID` | Certificado autofirmado o CA no reconocida |
| `ERR_CERT_DATE_INVALID` | Certificado caducado - renovar con `certbot renew` |
| `ERR_SSL_PROTOCOL_ERROR` | El servidor no habla TLS pero el cliente pidió `https://` |
| Mixed content warnings | Tu HTML `https://` carga `<img src="http://...">` - usa URLs relativas o `https://` |

---

## Buenas prácticas

1. **HTTPS en producción siempre.** Sin excepciones. Let's Encrypt es
   gratis.
2. **HTTP → HTTPS redirect.** El puerto 80 solo sirve para redirigir 301
   a `https://` (o para el challenge de certbot).
3. **Renovación automática.** `certbot renew` en cron + reload del
   servidor. Si no, el certificado caduca a los 90 días y la app cae.
4. **Detrás de proxy en prod.** Termina TLS en Apache/Nginx o un CDN.
   HIX se queda en red interna sirviendo HTTP plano.
5. **HSTS.** Una vez todo en HTTPS, envía la cabecera
   `Strict-Transport-Security: max-age=31536000; includeSubDomains` para
   que el navegador rechace HTTP en futuras visitas.
6. **No commits de claves.** `certs/*.key` jamás al repo. Añádelos al
   `.gitignore`.

