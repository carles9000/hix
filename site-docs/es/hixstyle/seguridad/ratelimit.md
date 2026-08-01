# 🚦 Rate Limit

Un **rate limiter** cuenta cuántos requests llegan desde cada IP en una
ventana de tiempo. Si una IP supera el límite → **429 Too Many Requests**.

Sirve para:

- **Cortar fuerza bruta** en `/login` (atacante probando passwords).
- **Proteger APIs públicas** de scrappers / bots.
- **Estabilizar el servidor** ante un cliente que se desboca.

```
IP 1.2.3.4    100 req en 60s   -> contador <= 100  -> ✅ pasa
IP 1.2.3.4    101 req en 60s   -> contador > 100   -> ❌ 429 Too Many Requests
                 ⏱ ventana se reinicia a los 60s
```

---

## Algoritmo

HIX usa **fixed window per IP** - el contador se resetea de golpe al
expirar la ventana:

```
00:00 ─────────────── 01:00 ─────────────── 02:00 ─────
  IP X = 0              IP X reset            IP X reset
  ↓ requests ↑          ↓ requests ↑          ↓ requests ↑
  cuenta 1..100         vuelve a 1..100       vuelve a 1..100
```

| Característica | Detalle |
|---|---|
| Por qué se agrupa | IP (`oReq:cIP`) |
| Cuenta de qué | Cualquier request, sin distinguir ruta |
| Cuándo resetea | Al cumplirse `nWindowSecs` desde el primer request de esa IP |
| Penalización | **429** inmediato, sin esperar al final de la ventana |

> ⚠️ Limitación del fixed window: justo en el cambio de ventana, una IP
> puede meter `2 × nMax` requests (al final de la ventana N y al
> principio de la N+1). Para tráfico normal es irrelevante; si necesitas
> precisión exacta, implementa sliding window aparte.

---

## Setup

```clipper
HIX_MwRateLimitSetup( ;
   100,    ;   // nMax - máximo de requests
   60 )        // nWindowSecs - segundos de la ventana
```

Defaults: **60 req / 60 s** (1 req/segundo de media).

Llamar antes de `oSrv:Start()`. La llamada inicializa el hash compartido
y el mutex que lo protege.

---

## Activación

### Global - toda la app

```clipper
HIX_MwRateLimitSetup( 100, 60 )
oSrv:Use( "HIX_MwRateLimit" )
```

Cada request entra por aquí, sea de la ruta que sea.

### Por ruta

```clipper
oSrv:AddRouteGet( "api", "/api/data", bAction, "HIX_MwRateLimit" )
```

```json
{ "name": "api.data", "url": "/api/data", "method": "GET",
  "action": "controllers/api/data.prg",
  "middleware": "HIX_MwRateLimit" }
```

> En modo "global + por ruta", la **misma cuenta** se incrementa en ambos
> sitios. Si quieres contadores separados (por ej. global 100/min pero
> login 5/min) usa el factory.

---

## Factory - límite por ruta independiente

`HIX_MwRateLimitFactory( nMax, nWindowSecs )` devuelve un codeblock con
su propia configuración:

```clipper
LOCAL bMwLogin := HIX_MwRateLimitFactory( 5, 60 )    // 5 intentos/min

oSrv:AddRoutePost( "login", "/login", bActionLogin, bMwLogin )
```

> ⚠️ Internamente todos los factories y el global **comparten** el hash
> de contadores. Lo que cambia es `nMax`/`nWindowSecs` por llamada.
> Cada incremento de cualquier middleware suma al mismo contador de IP.
> Para contadores totalmente independientes hay que escribir un MW propio.

---

## Comportamiento al rechazar

Cuando una IP supera el límite:

```clipper
HIX_HttpError( oCtx:oReq, 429 )      // 429 Too Many Requests
oCtx:lHandled := .T.
RETURN .F.                            // corta el pipeline
```

El controller **no llega a ejecutarse**.

---

## Leer el contador en el controller

`HIX_MwRateLimit` deja la cuenta actual en `oCtx:hData["rate_count"]`,
útil para devolverla en cabeceras informativas:

```clipper
LOCAL nCount := UContext():hData[ "rate_count" ]
USetHeader( "X-RateLimit-Remaining", hb_NToS( 100 - nCount ) )
```

---

## Patrones de uso

### Endpoint de login - protección anti-bruteforce

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "memory" )

LOCAL bMwLogin := HIX_MwRateLimitFactory( 5, 60 )    // 5 intentos/min

oSrv:AddRoutePost( "login", "/login", ;
   {|| _LoginAction() }, ;
   { "HIX_MwSession", "HIX_MwCsrfCheck", bMwLogin } )
```

Después de 5 POSTs fallidos en 1 minuto desde la misma IP → 429 durante
~60s.

### API pública

```clipper
HIX_MwRateLimitSetup( 1000, 60 )    // 1000 req/min generosos
oSrv:Use( { "HIX_MwCors", "HIX_MwRateLimit" } )
```

### Distintos tiers por header

Para clientes "premium" identificados por un header puedes saltarte el
rate limit con un middleware previo:

```clipper
FUNCTION MyAppSkipRateLimit( oCtx )
   IF oCtx:oReq:Header( "x-premium-key", "" ) == "SECRET"
      oCtx:lHandled := .T.        // marca handled... no, mejor:
      RETURN .T.                  // simplemente sigue, no aplicará el siguiente MW
   ENDIF
RETURN .T.
```

> Para tiers reales lo más limpio es un MW propio que use una clave
> distinta por tier en el hash de contadores.

---

## Buenas prácticas

1. **Combina con CORS y auth.** Rate limit es la **primera línea**, no
   sustituye autenticación.
2. **Límites estrictos en endpoints críticos.** `/login`, `/password-reset`,
   `/2fa-verify` - 5-10 intentos por minuto bastan.
3. **Devuelve `Retry-After`.** Acompaña el 429 con un header que diga
   cuántos segundos quedan para reintentar. Útil para clientes bien
   programados.
4. **Cuidado detrás de proxies.** Si tu HIX está detrás de un balanceador,
   `oReq:cIP` puede ser la IP del proxy (todos iguales). Configura el
   modo `proxied` para que respete `X-Forwarded-For`.
5. **Memoria proporcional al tráfico.** El hash de contadores crece con
   IPs únicas vistas en la ventana. Para volúmenes muy altos, añade un
   GC periódico que limpie entradas expiradas.
6. **No te juegues solo a esto.** Un atacante con muchas IPs (botnet)
   atraviesa cualquier rate limit por IP. Combínalo con
   [Firewall](firewall.md) y CAPTCHA donde toque.

