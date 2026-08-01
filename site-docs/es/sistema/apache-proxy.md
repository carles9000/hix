# 🖥️ Apache / Nginx reverse proxy

HIX puede correr en dos topologías:

- **Standalone** - HIX escucha directamente en el puerto 80/443 y atiende
  el tráfico de internet sin intermediarios.
- **Detrás de un reverse proxy** (Apache, Nginx, Cloudflare Tunnel,
  Traefik...) - el proxy termina SSL, balancea, comprime, y reenvía la
  petición a HIX por HTTP plano en un puerto interno.

Cuando trabajas tras un proxy, **HIX necesita saberlo** para reconstruir
correctamente la IP real del cliente, el esquema (`http` vs `https`) y el
host original. Esa configuración es el **modo `proxied`**.

---

## ¿Cuándo lo necesitas?

- Para servir **HTTPS con Let's Encrypt** sin manejar certificados en HIX.
- Para colocar HIX detrás de **Apache/Nginx existente** que ya sirve otros
  sitios.
- Para usar **Cloudflare** como CDN/WAF delante de HIX.
- Para **balancear** varias instancias de HIX detrás de un único frontend.
- Para liberar a HIX de **TLS y compresión** y dedicarlo a lógica de
  aplicación.

---

## Setup en `hix.json`

### Sección `server`

`host = 127.0.0.1` -> sólo escucha local, el proxy es el único cliente.
`port = 8080` -> puerto interno.
`mode = "proxied"` -> HIX se sabe detrás de un proxy y lee `X-Forwarded-*` / `Forwarded`.

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 8080,
    "mode": "proxied"
  }
}
```

### Sección `server` - lista de proxies de confianza

```json
{
  "server": {
    "trusted_proxies": "127.0.0.1 ::1 10.0.0.0/8"
  }
}
```

`trusted_proxies` es una lista (separada por espacios) de IPs o rangos
CIDR cuyas cabeceras `X-Forwarded-*` HIX aceptará. **Sin esta lista, HIX
ignora las cabeceras** y usa la IP de conexión TCP (la del proxy, no la
del cliente real).

> ⚠️ **Nunca pongas `0.0.0.0/0` como trusted_proxy**. Eso permitiría a
> cualquier cliente externo falsificar su IP enviando un `X-Forwarded-For`
> manipulado. Lista sólo IPs que controlas.

---

## Cabeceras soportadas

HIX detecta la IP real del cliente mirando, en orden:

1. `CF-Connecting-IP` (Cloudflare)
2. `X-Forwarded-For` (primer valor público de la cadena)
3. `X-Real-IP` (Nginx clásico)
4. `Client-IP` (legacy)
5. La IP de la conexión TCP (fallback)

También entiende **RFC 7239 `Forwarded:`** (estándar moderno):

```
Forwarded: for=203.0.113.5;proto=https;host=miapp.com
```

`HIX_ParseForwarded()` extrae `for`, `proto`, `host`, `by`, `port` del
primer salto (el más cercano al cliente).

---

## Configuración Apache

### Reverse proxy básico

```apache
<VirtualHost *:443>
   ServerName miapp.com

   SSLEngine on
   SSLCertificateFile      /etc/letsencrypt/live/miapp.com/fullchain.pem
   SSLCertificateKeyFile   /etc/letsencrypt/live/miapp.com/privkey.pem

   ProxyPreserveHost On
   ProxyRequests     Off

   # HTTP - todas las peticiones a HIX
   ProxyPass        / http://127.0.0.1:8080/
   ProxyPassReverse / http://127.0.0.1:8080/

   # Cabeceras para HIX
   RequestHeader set X-Forwarded-Proto "https"
   RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"
   # X-Forwarded-For lo añade Apache automáticamente

   # Para WebSockets (pool_ws)
   RewriteEngine on
   RewriteCond %{HTTP:Upgrade} =websocket [NC]
   RewriteRule /(.*) ws://127.0.0.1:8080/$1 [P,L]
</VirtualHost>
```

Módulos necesarios: `proxy`, `proxy_http`, `proxy_wstunnel`, `rewrite`,
`headers`, `ssl`.

### Healthcheck

Apache puede probar HIX con el endpoint público `/hix-ping`:

```apache
<Proxy "balancer://hix">
   BalancerMember "http://127.0.0.1:8080" route=hix1
   ProxySet hcmethod=GET hcuri=/hix-ping hcinterval=10
</Proxy>
```

---

## Configuración Nginx

```nginx
upstream hix {
   server 127.0.0.1:8080;
}

server {
   listen 443 ssl http2;
   server_name miapp.com;

   ssl_certificate     /etc/letsencrypt/live/miapp.com/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/miapp.com/privkey.pem;

   location / {
      proxy_pass         http://hix;
      proxy_http_version 1.1;

      # Forwarded headers (HIX las lee si IP está en trusted_proxies)
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Host  $host;

      # WebSockets - HIX pool_ws
      proxy_set_header Upgrade    $http_upgrade;
      proxy_set_header Connection "upgrade";

      # SSE - HIX pool_rest
      proxy_buffering off;
      proxy_read_timeout 3600s;
   }
}
```

> 💡 Para SSE (`/eventos`), **`proxy_buffering off`** es **obligatorio**.
> Sin ello, Nginx acumula el stream y no llega nada al cliente.

---

## Lectura desde código

Con `server.mode = "proxied"`, los helpers de HIX devuelven valores
"vistos" desde el cliente real, no desde el proxy:

```clipper
UIP()       // -> "203.0.113.5"   (IP real del cliente, no la del proxy)
UScheme()   // -> "https"          (lee X-Forwarded-Proto)
UIsHttps()  // -> .T.
UHost()     // -> "miapp.com"      (lee X-Forwarded-Host)
```

Sin `server.mode = "proxied"`:

```clipper
UIP()       // -> "127.0.0.1"      (IP TCP del proxy)
UScheme()   // -> "http"
UIsHttps()  // -> .F.
```

> 🔍 La función `HIX_GetClientIP(oReq)` aplica además un filtro
> **`HIX_IsPublicIP()`** sobre la cadena `X-Forwarded-For` para descartar
> IPs privadas inyectadas. Toma la primera IP **pública** de la cadena.

---

## Cloudflare

Si HIX está detrás de Cloudflare (Tunnel, proxy naranja, R2):

1. Añade los rangos de Cloudflare a `trusted_proxies`:

   ```json
   {
     "server": {
       "trusted_proxies": "173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 ..."
     }
   }
   ```

   Lista actualizada: https://www.cloudflare.com/ips/

2. Activa `server.mode = "proxied"`.

3. HIX detectará automáticamente la cabecera `CF-Connecting-IP` que
   Cloudflare añade con la IP del cliente real, incluso si no envías
   `X-Forwarded-For`.

---

## Errores típicos

| Síntoma                                | Causa                                                  | Fix                                                     |
|----------------------------------------|--------------------------------------------------------|---------------------------------------------------------|
| `UIP()` devuelve la IP del proxy       | `server.mode != "proxied"`                             | Configurar correctamente                                |
| `UIP()` falsificable desde fuera       | `trusted_proxies` vacío o `0.0.0.0/0`                  | Limitar a IPs reales del proxy                          |
| WebSocket no conecta tras Apache       | Falta `proxy_wstunnel` o regla `Upgrade`               | Añadir `RewriteRule [P]` con `ws://`                    |
| SSE no llega al cliente                | Nginx hace buffering                                   | `proxy_buffering off; proxy_read_timeout 3600s;`        |
| Redirects van a `http://` y no `https` | HIX no ve `X-Forwarded-Proto`                          | `proxy_set_header X-Forwarded-Proto $scheme;`           |
| Cookies pierden `Secure`               | HIX se cree HTTP plano                                 | Activar `server.mode = "proxied"` para que `UIsHttps()` sea `.T.` |

---

## Buenas prácticas

- **`host = 127.0.0.1`** cuando HIX está detrás de un proxy local: nadie
  externo puede saltarse el proxy hablando directamente con HIX.
- **`trusted_proxies` lo más restrictivo posible**: sólo las IPs reales
  del proxy, nunca rangos enteros públicos.
- **Termina TLS en el proxy**, no en HIX. Aprovechas el ecosistema de
  certbot/Let's Encrypt sin mover nada del lado HIX.
- Para WebSockets, mantén `proxy_read_timeout` ≥ el `ping_interval_s` de
  HIX más un margen, o las conexiones inactivas se cortarán.
- Usa el endpoint público `/hix-ping` como **healthcheck** del balancer.
- En topologías con varios HIX, usa **sticky sessions** si confías en la
  sesión en memoria (`session.storage = "memory"`). Si pasas a `"file"`,
  todos los HIX deben compartir la carpeta `paths.session`.

