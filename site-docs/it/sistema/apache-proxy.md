# 🖥️ Apache / Nginx reverse proxy

HIX può girare in due topologie:
- **Standalone** — HIX ascolta direttamente sulla porta 80/443 e gestisce il traffico internet
  senza intermediari.
- **Dietro un reverse proxy** (Apache, Nginx, Cloudflare Tunnel, Traefik...) —
  il proxy termina SSL, fa load balancing, comprime, e inoltra la richiesta
  a HIX su HTTP puro su una porta interna.

Quando lavori dietro un proxy, **HIX deve saperlo** per ricostruire correttamente
l'IP reale del client, lo scheme (`http` vs `https`), e l'host originale. Questa configurazione è la **modalità `proxied`**.

---

## Quando ti serve?

- Per servire **HTTPS con Let's Encrypt** senza gestire certificati in HIX.
- Per mettere HIX dietro **Apache/Nginx esistenti** che già servono altri siti.
- Per usare **Cloudflare** come CDN/WAF davanti a HIX.
- Per fare **load balancing** di più istanze HIX dietro un singolo frontend.
- Per scaricare **TLS e compressione** da HIX e dedicarlo alla logica applicativa.

---

## Setup in `hix.json`

### Sezione `server`

`host = 127.0.0.1` → ascolta solo localmente, il proxy è l'unico client.
`port = 8080` → porta interna.
`mode = "proxied"` → HIX sa di essere dietro un proxy e legge `X-Forwarded-*` / `Forwarded`.

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 8080,
    "mode": "proxied"
  }
}
```

### Sezione `server` — lista proxy fidati

```json
{
  "server": {
    "trusted_proxies": "127.0.0.1 ::1 10.0.0.0/8"
  }
}
```

`trusted_proxies` è una lista separata da spazi di IP o range CIDR i cui
header `X-Forwarded-*` HIX accetterà. **Senza questa lista, HIX ignora gli
header** e usa l'IP della connessione TCP (quello del proxy, non del client).

> ⚠️ **Non usare mai `0.0.0.0/0` come trusted_proxy**. Questo permetterebbe a qualsiasi client
> esterno di falsificare il proprio IP inviando un `X-Forwarded-For` contraffatto. Elenca solo gli IP
> che controlli.

---

## Header supportati

HIX rileva l'IP reale del client guardando, in ordine:
1. `CF-Connecting-IP` (Cloudflare)
2. `X-Forwarded-For` (primo valore pubblico nella catena)
3. `X-Real-IP` (Nginx classico)
4. `Client-IP` (legacy)
5. L'IP della connessione TCP (fallback)

Capisce anche il **`Forwarded:` RFC 7239** (standard moderno):

```
Forwarded: for=203.0.113.5;proto=https;host=myapp.com
```

`HIX_ParseForwarded()` estrae `for`, `proto`, `host`, `by`, `port` dal
primo hop (più vicino al client).

---

## Configurazione Apache

### Reverse proxy base

```apache
<VirtualHost *:443>
   ServerName myapp.com

   SSLEngine on
   SSLCertificateFile      /etc/letsencrypt/live/myapp.com/fullchain.pem
   SSLCertificateKeyFile   /etc/letsencrypt/live/myapp.com/privkey.pem

   ProxyPreserveHost On
   ProxyRequests     Off

   # HTTP - tutte le richieste a HIX
   ProxyPass        / http://127.0.0.1:8080/
   ProxyPassReverse / http://127.0.0.1:8080/

   # Header per HIX
   RequestHeader set X-Forwarded-Proto "https"
   RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"
   # X-Forwarded-For aggiunto da Apache automaticamente

   # Per WebSocket (pool_ws)
   RewriteEngine on
   RewriteCond %{HTTP:Upgrade} =websocket [NC]
   RewriteRule /(.*) ws://127.0.0.1:8080/$1 [P,L]
</VirtualHost>
```

Moduli richiesti: `proxy`, `proxy_http`, `proxy_wstunnel`, `rewrite`, `headers`,
`ssl`.

### Healthcheck

Apache può testare HIX con l'endpoint pubblico `/hix-ping`:

```apache
<Proxy "balancer://hix">
   BalancerMember "http://127.0.0.1:8080" route=hix1
   ProxySet hcmethod=GET hcuri=/hix-ping hcinterval=10
</Proxy>
```

---

## Configurazione Nginx

```nginx
upstream hix {
   server 127.0.0.1:8080;
}

server {
   listen 443 ssl http2;
   server_name myapp.com;

   ssl_certificate     /etc/letsencrypt/live/myapp.com/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/myapp.com/privkey.pem;

   location / {
      proxy_pass         http://hix;
      proxy_http_version 1.1;

      # Header forwarded (HIX li legge se l'IP è in trusted_proxies)
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Host  $host;

      # WebSocket - HIX pool_ws
      proxy_set_header Upgrade    $http_upgrade;
      proxy_set_header Connection "upgrade";

      # SSE - HIX pool_rest
      proxy_buffering off;
      proxy_read_timeout 3600s;
   }
}
```

> 💡 Per SSE (`/events`), **`proxy_buffering off`** è **obbligatorio**. Senza,
> Nginx bufferizza lo stream e nulla raggiunge il client.

---

## Lettura dal codice

Con `server.mode = "proxied"`, gli helper di HIX ritornano valori "visti" dal client
reale, non dal proxy:

```clipper
UIP()       // -> "203.0.113.5"   (IP reale del client, non del proxy)
UScheme()   // -> "https"          (legge X-Forwarded-Proto)
UIsHttps()  // -> .T.
UHost()     // -> "myapp.com"      (legge X-Forwarded-Host)
```

Senza `server.mode = "proxied"`:

```clipper
UIP()       // -> "127.0.0.1"      (IP TCP del proxy)
UScheme()   // -> "http"
UIsHttps()  // -> .F.
```

> 🔍 La funzione `HIX_GetClientIP(oReq)` applica inoltre un filtro
> **`HIX_IsPublicIP()`** sulla catena di `X-Forwarded-For` per scartare
> gli IP privati iniettati. Prende il primo IP **pubblico** nella catena.

---

## Cloudflare

Se HIX è dietro Cloudflare (Tunnel, orange proxy, R2):
1. Aggiungi i range di Cloudflare a `trusted_proxies`:

   ```json
   {
     "server": {
       "trusted_proxies": "173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 ..."
     }
   }
   ```

   Lista aggiornata: https://www.cloudflare.com/ips/

2. Attiva `server.mode = "proxied"`.

3. HIX rileverà automaticamente l'header `CF-Connecting-IP` che Cloudflare
   aggiunge con l'IP reale del client, anche se non invii `X-Forwarded-For`.

---

## Errori comuni

| Sintomo                                  | Causa                                                | Fix                                                  |
|------------------------------------------|------------------------------------------------------|------------------------------------------------------|
| `UIP()` ritorna l'IP del proxy           | `server.mode != "proxied"`                           | Configura correttamente                              |
| `UIP()` falsificabile dall'esterno       | `trusted_proxies` vuoto o `0.0.0.0/0`               | Limita agli IP reali dei proxy                       |
| WebSocket non si connette dopo Apache     | Manca `proxy_wstunnel` o regola `Upgrade`            | Aggiungi `RewriteRule [P]` con `ws://`               |
| SSE non raggiunge il client               | Nginx sta bufferizzando                              | `proxy_buffering off; proxy_read_timeout 3600s;`     |
| I redirect vanno a `http://` non `https`| HIX non vede `X-Forwarded-Proto`                     | `proxy_set_header X-Forwarded-Proto $scheme;`        |
| I cookie perdono `Secure`                 | HIX pensa di essere in HTTP puro                     | Attiva `server.mode = "proxied"` così `UIsHttps()` è `.T.` |

---

## Best practice

- **`host = 127.0.0.1`** quando HIX è dietro un proxy locale: nessun utente esterno
  può bypassare il proxy parlando direttamente con HIX.
- **`trusted_proxies` il più restrittivo possibile**: solo gli IP reali dei proxy,
  mai range pubblici interi.
- **Termina TLS al proxy**, non in HIX. Sfrutti l'ecosistema certbot/Let's
  Encrypt senza spostare nulla lato HIX.
- Per i WebSocket, mantieni `proxy_read_timeout` ≥ `ping_interval_s` di HIX più un
  margine, o le connessioni inattive verranno tagliate.
- Usa l'endpoint pubblico `/hix-ping` come **healthcheck** per il tuo bilanciatore.
- In topologie multi-HIX, usa le **sticky session** se ti basi su sessioni in memoria
  (`session.storage = "memory"`). Se passi a `"file"`, tutte le istanze HIX devono condividere
  la cartella `paths.session`.
