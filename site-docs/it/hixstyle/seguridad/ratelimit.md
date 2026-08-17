# 🚦 Rate Limit

Un **rate limiter** conta quante richieste arrivano da ogni IP in una
finestra temporale. Se un IP supera il limite → **429 Too Many Requests**.

Aiuta a:
- **Tagliare il brute force** su `/login` (attaccante che prova password).
- **Proteggere le API pubbliche** da scraper / bot.
- **Stabilizzare il server** quando un client si comporta male.

```
IP 1.2.3.4    100 req in 60s   -> counter <= 100  -> ✅ passa
IP 1.2.3.4    101 req in 60s   -> counter > 100   -> ❌ 429 Too Many Requests
                  ⏱ la finestra si resetta dopo 60s
```

---

## Algoritmo

HIX usa **finestra fissa per IP** - il counter si resetta completamente quando
la finestra scade:

```
00:00 ─────────────── 01:00 ─────────────── 02:00 ─────
   IP X = 0              IP X reset            IP X reset
   ↓ richieste ↑         ↓ richieste ↑         ↓ richieste ↑
   count 1..100          torna a 1..100        torna a 1..100
```

| Caratteristica | Dettaglio |
|---|---|
| Raggruppato per | IP (`oReq:cIP`) |
| Conta | Qualsiasi richiesta, indipendentemente dalla route |
| Si resetta quando | `nWindowSecs` scade dalla prima richiesta di quell'IP |
| Penalità | **429** immediato, niente attesa |

> ⚠️ Limitazione della finestra fissa: proprio al cambio di finestra, un IP può infilare
> `2 × nMax` richieste (fine della finestra N e inizio di N+1). Per traffico normale
> è irrilevante; se ti serve precisione esatta, implementa lo sliding window separatamente.

---

## Setup

```clipper
HIX_MwRateLimitSetup( ;
   100,    ;   // nMax - richieste massime
   60 )        // nWindowSecs - secondi della finestra
```

Default: **60 req / 60 s** (1 req/secondo medi).

Chiamalo prima di `oSrv:Start()`. La chiamata inizializza l'hash condiviso
e il mutex che lo protegge.

---

## Attivazione

### Globale - intera app

```clipper
HIX_MwRateLimitSetup( 100, 60 )
oSrv:Use( "HIX_MwRateLimit" )
```

Ogni richiesta passa di qui, qualunque route.

### Per route

```clipper
oSrv:AddRouteGet( "api", "/api/data", bAction, "HIX_MwRateLimit" )
```

```json
{ "name": "api.data", "url": "/api/data", "method": "GET",
  "action": "controllers/api/data.prg",
  "middleware": "HIX_MwRateLimit" }
```

> In modalità "globale + per route", lo **stesso counter** incrementa in entrambi i
> posti. Se vuoi counter separati (es. globale 100/min ma
> login 5/min) usa la factory.

---

## Factory - limite indipendente per route

`HIX_MwRateLimitFactory( nMax, nWindowSecs )` ritorna un codeblock con
la sua configurazione:

```clipper
LOCAL bMwLogin := HIX_MwRateLimitFactory( 5, 60 )    // 5 tentativi/min

oSrv:AddRoutePost( "login", "/login", bActionLogin, bMwLogin )
```

> ⚠️ Internamente tutte le factory e il globale **condividono** l'hash dei counter.
> Ciò che cambia sono `nMax`/`nWindowSecs` per chiamata. Ogni incremento da qualsiasi
> middleware si aggiunge allo stesso counter per IP. Per counter completamente indipendenti
> devi scrivere il tuo middleware.

---

## Comportamento al rifiuto

Quando un IP supera il limite:

```clipper
HIX_HttpError( oCtx:oReq, 429 )      // 429 Too Many Requests
oCtx:lHandled := .T.
RETURN .F.                            // interrompe la pipeline
```

Il controller **non viene mai eseguito**.

---

## Leggere il counter nel controller

`HIX_MwRateLimit` lascia il conteggio corrente in `oCtx:hData["rate_count"]`,
utile per restituirlo in header informativi:

```clipper
LOCAL nCount := UContext():hData[ "rate_count" ]
USetHeader( "X-RateLimit-Remaining", hb_NToS( 100 - nCount ) )
```

---

## Pattern d'uso

### Endpoint di login - protezione anti-bruteforce

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "memory" )

LOCAL bMwLogin := HIX_MwRateLimitFactory( 5, 60 )    // 5 tentativi/min

oSrv:AddRoutePost( "login", "/login", ;
   {|| _LoginAction() }, ;
   { "HIX_MwSession", "HIX_MwCsrfCheck", bMwLogin } )
```

Dopo 5 POST falliti in 1 minuto dallo stesso IP → 429 per ~60s.

### API pubblica

```clipper
HIX_MwRateLimitSetup( 1000, 60 )    // 1000 req/min generoso
oSrv:Use( { "HIX_MwCors", "HIX_MwRateLimit" } )
```

### Tier diversi per header

Per client "premium" identificati da un header puoi skippare il
rate limit con un middleware che gira prima:

```clipper
FUNCTION MyAppSkipRateLimit( oCtx )
   IF oCtx:oReq:Header( "x-premium-key", "" ) == "SECRET"
      oCtx:lHandled := .T.        // marca handled... no, meglio:
      RETURN .T.                  // continua, il prossimo MW non si applica
   ENDIF
RETURN .T.
```

> Per tier reali l'approccio più pulito è un MW custom che usa una chiave diversa per tier nell'hash dei counter.

---

## Best practice

1. **Combina con CORS e auth.** Il rate limit è la **prima linea**, non
   un sostituto dell'autenticazione.
2. **Limiti stretti sugli endpoint critici.** `/login`, `/password-reset`,
   `/2fa-verify` - 5-10 tentativi al minuto sono sufficienti.
3. **Ritorna `Retry-After`.** Accompagna il 429 con un header che dice quanti
   secondi mancano al retry. Utile per client ben educati.
4. **Occhio dietro i proxy.** Se il tuo HIX è dietro un load balancer,
   `oReq:cIP` potrebbe essere l'IP del proxy (tutti uguali). Configura la modalità `proxied`
   così rispetta `X-Forwarded-For`.
5. **Memoria proporzionale al traffico.** L'hash dei counter cresce con gli IP unici
   visti nella finestra. Per volumi molto alti, aggiungi una GC periodica che pulisce le entry scadute.
6. **Non fare affidamento solo su questo.** Un attaccante con molti IP (botnet) bypassa
   qualsiasi rate limit per IP. Combina con
   [Firewall](firewall.md) e CAPTCHA dove necessario.
