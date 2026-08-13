# 🔒 SSL / TLS

**SSL/TLS** cifra il canale tra il browser e il server. Senza, tutto viaggia in chiaro - e questo include:

- Cookie di sessione (`HIXSID=abc123`) - un intermediario può catturarli e impersonare l'utente.
- Credenziali di login (`username=demo&password=1234`).
- Token JWT (`Authorization: Bearer eyJ...`).
- Il body di ogni risposta (dati sensibili dell'utente).

Con HTTPS, tutto viaggia **cifrato** e firmato. Un attaccante nel mezzo della rete vede solo byte opachi.

```
http://app.com   ─────▶  plaintext  ─────▶  server  (chiunque legge)
https://app.com  ─────▶  TLS encrypt ─────▶  server  (solo il server decifra)
```

> In produzione, **HTTPS non è opzionale**. Qualsiasi cosa con login, sessione, JWT o pagamenti **deve** andare attraverso HTTPS. I browser moderni segnalano i siti HTTP come "Non sicuro" e bloccano nuove API (geolocation, service workers, fetch con credenziali, ...) senza TLS.

---

## Attivazione in HIX

### Da `hix.json`

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

| Chiave | Valore |
|---|---|
| `paths.certs` | Directory dove risiedono i file dei certificati (default: `certs`) |
| `ssl` | `true` abilita TLS, `false` (default) lo disabilita |
| `cert_private` | Nome del file `.key` dentro `paths.certs` |
| `cert_public` | Nome del file `.crt` dentro `paths.certs` |
| `port` | Convenzione: **443** per HTTPS, 80 per HTTP |

### Da codice

```clipper
LOCAL oCfg := THixConfig():New()
oCfg:lSSL          := .T.
oCfg:cCertPrivate  := "certs/hix.key"
oCfg:cCertPublic   := "certs/hix.crt"
oCfg:nPort         := 443

oSrv := THixServer():New( oCfg )
```

> All'avvio, `oCfg:Validate()` controlla che entrambi i file esistano. Se mancano, il server scrive un errore nel log e **non parte**.

---

## Ottenere un certificato

### Produzione - Let's Encrypt (gratuito e automatico)

[Let's Encrypt](https://letsencrypt.org/) è una CA gratuita che emette certificati con lo strumento **`certbot`**:

```bash
certbot certonly --standalone -d app.example.com
```

Questo genera due file in `/etc/letsencrypt/live/app.example.com/`:

- `privkey.pem` → `cert_private`
- `fullchain.pem` → `cert_public`

I certificati scadono dopo 90 giorni - `certbot` è programmato per rinnovarli automaticamente.

### Sviluppo - certificato self-signed

Per `localhost`:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 ;
  -keyout certs/hix.key -out certs/hix.crt ;
  -subj "/CN=localhost"
```

Il browser mostrerà un avviso "certificato non attendibile" - è normale. Ok per test locali; mai per la produzione.

---

## Helper di rilevamento

Da un controller puoi sapere se la richiesta è arrivata via HTTPS:

```clipper
UIsHttps()        // .T. / .F.
UScheme()         // "http" / "https"
```

Utile per forzare il cookie come `Secure`, o per reindirizzare il traffico HTTP→HTTPS:

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

## HIX direttamente vs dietro un proxy

### HIX direttamente (self-contained)

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

HIX termina TLS e serve HTTPS direttamente. Ideale per piccole app o self-hosted.

### Dietro un proxy (Apache / Nginx / Cloudflare)

Il solito in produzione: il **proxy** termina TLS e inoltra HTTP puro a HIX sulla rete interna:

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

`server.ssl = false` → HIX parla HTTP puro con il proxy. `server.mode = "proxied"` abilita la lettura di `X-Forwarded-*`.

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

| | HIX direttamente | Dietro proxy |
|---|---|---|
| Termina TLS | HIX | Proxy |
| Certificato | In HIX | Nel proxy |
| Rinnovo | Manuale o cron | Gestito dal proxy |
| Backend multipli | ❌ | ✅ Load balancing |
| Adatto per | Piccole app, dev | Produzione seria |

---

## Cookie sicuri con HTTPS

Quando tutto va attraverso TLS, i cookie di sessione dovrebbero essere marcati come **Secure** così il browser non li invia mai su HTTP:

```clipper
// Cookie marcato come Secure (solo HTTPS)
USetCookie( "session_id", cSid, 3600 )
// HIX aggiunge automaticamente HttpOnly + SameSite=Lax
// In sospeso: flag Secure nelle versioni più nuove - verificare se esposto
```

> I cookie HIX portano già `HttpOnly; SameSite=Lax` di default, che filtra alcuni attacchi. Il flag `Secure` viene aggiunto dal proxy se termina TLS lì, o va abilitato esplicitamente con TLS locale.

---

## Errori comuni

| Sintomo | Causa |
|---|---|
| `SSL: cert_private non trovato` all'avvio | Path al `.key` scritto male o file mancante |
| `SSL: cert_public non trovato` | Stessa cosa con il `.crt` |
| Browser: `NET::ERR_CERT_AUTHORITY_INVALID` | Certificato self-signed o CA non riconosciuta |
| `ERR_CERT_DATE_INVALID` | Certificato scaduto - rinnovare con `certbot renew` |
| `ERR_SSL_PROTOCOL_ERROR` | Il server non parla TLS ma il client ha richiesto `https://` |
| Warning di mixed content | Il tuo HTML `https://` carica `<img src="http://...">` - usa URL relativi o `https://` |

---

## Best practice

1. **HTTPS in produzione sempre.** Nessuna eccezione. Let's Encrypt è gratuito.
2. **HTTP → HTTPS redirect.** La porta 80 serve solo a reindirizzare con 301 verso `https://` (o per la challenge di certbot).
3. **Rinnovo automatico.** `certbot renew` in cron + reload del server. Se non lo fai, il certificato scade dopo 90 giorni e l'app va giù.
4. **Dietro un proxy in prod.** Termina TLS in Apache/Nginx o in una CDN. HIX resta sulla rete interna a servire HTTP puro.
5. **HSTS.** Una volta che tutto è HTTPS, invia l'header `Strict-Transport-Security: max-age=31536000; includeSubDomains` così il browser rifiuta l'HTTP nelle visite future.
6. **Niente chiavi committate.** `certs/*.key` mai nel repo. Aggiungili a `.gitignore`.
