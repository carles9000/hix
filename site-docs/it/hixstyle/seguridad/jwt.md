# 🎫 JWT - JSON Web Token

## Cos'è?

Un **JWT** è un token auto-contenuto e firmato che il server emette al login e il client invia con ogni richiesta successiva.

- **Auto-contenuto**: porta con sé tutte le informazioni dell'utente (`user_id`, `role`, ecc.). Il server **non memorizza nulla** tra le richieste.
- **Firmato**: HIX usa **HMAC-SHA256** con una chiave segreta. Se il client altera anche solo un byte, la firma non corrisponde più e il token viene rifiutato.
- **Stateless**: due server con la stessa chiave validano lo stesso token → scala orizzontalmente senza storage condiviso.

```
header.payload.signature

eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9   {"typ":"JWT","alg":"HS256"}
.eyJ1c2VyX2lkIjoiNDIiLCJyb2xlIjoi...    {"user_id":"42","role":"admin","exp":...}
.aBcD3f9eGgHhIi...                      HMAC-SHA256(header.payload, secret)
```

---

## Quando usarlo

| Caso d'uso | JWT |
|---|---|
| API REST stateless | ✅ Sì - pattern canonico |
| App mobile che chiama un'API | ✅ Sì |
| Microservizi con token condivisi | ✅ Sì |
| SPA che chiama un backend separato | ✅ Sì |
| App web tradizionale con form di login | ❌ Usa [Sessioni](sesiones.md) |
| Token monouso (download, reset password) | ⚠️ Sì, con `exp` breve |

> JWT vs Sessione: il JWT non richiede storage server ma **non può essere invalidato** prima della scadenza. La sessione è l'opposto: richiede storage ma puoi distruggere il SID e fare logout immediato.

---

## Setup

```clipper
HIX_MwJwtSetup( ;
   "chiave_segreta_lunga_e_random",  ;   // cKey - segreto HMAC
   3600 )                             // nExpSecs - TTL del token (1h)
```

Chiamalo **prima** di `oSrv:Start()`. Se non lo configuri, HIX usa
`hix-secret-key` di default (⚠️ **insicuro**).

---

## Emettere un token al /login

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
      USendJson( { "error" => "credenziali_non_valide" }, 401 )
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

`HIX_JwtEncode` aggiunge automaticamente i claim standard:

| Claim | Valore |
|---|---|
| `iss` | `"HIX"` |
| `iat` | Timestamp Unix di emissione |
| `exp` | `iat + nExpSecs` |

Quello che aggiungi tu (`user_id`, `scope`, `role`, ...) viaggia insieme.

---

## Proteggere una route

```clipper
// Pipeline: validazione JWT -> handler
oSrv:AddRouteGet( "me", "/api/me", ;
   {|| USendJson( UContext():hData["jwt"] ) }, ;
   "HIX_MwJwt" )
```

```json
{ "name": "me", "url": "/api/me", "method": "GET",
  "action": "controllers/me.prg",
  "middleware": "HIX_MwJwt" }
```

Il client deve inviare:

```http
GET /api/me HTTP/1.1
Authorization: Bearer eyJ0eXAiOiJKV1Qi...aBcD3f
```

`HIX_MwJwt` valida la firma + `exp`, lascia il payload in
`oCtx:hData["jwt"]` e continua. Se il token manca o non è valido →
**401**.

---

## Leggere il payload nel controller

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

## Scope - autorizzazione per operazione

`HIX_MwJwtScope` richiede che il claim `scope` del token contenga tutti i token (separati da spazio) che la route dichiara necessari:

```json
{ "name": "products.list",   "url": "/api/products",        "method": "GET",
  "middleware": "HIX_MwJwt,HIX_MwJwtScope", "scope": "read:products" }

{ "name": "products.delete", "url": "/api/products/:id",    "method": "DELETE",
  "middleware": "HIX_MwJwt,HIX_MwJwtScope", "scope": "delete:products" }
```

Con un token che porta `"scope" => "read:products write:orders"`:

| Route | Risultato |
|---|---|
| `GET /api/products` (`read:products`) | ✅ permesso |
| `POST /api/orders` (`write:orders`) | ✅ permesso |
| `DELETE /api/products/42` (`delete:products`) | ❌ 403 - scope mancante |

> L'ordine conta: **`HIX_MwJwt` prima** (lascia il payload in hData), **`HIX_MwJwtScope` dopo** (lo legge).

---

## Più chiavi - `HIX_MwJwtFactory`

Se route diverse usano chiavi di firma diverse (per esempio, una per l'API pubblica e un'altra per quella interna):

```clipper
LOCAL bMwApi    := HIX_MwJwtFactory( "chiave_pubblica"   )
LOCAL bMwIntern := HIX_MwJwtFactory( "chiave_interna"  )

oSrv:AddRouteGet( "pub",     "/api/pub",     bAction, bMwApi    )
oSrv:AddRouteGet( "intern",  "/admin/data",  bAction, bMwIntern )
```

---

## Validare / decodificare manualmente

Utile per token fuori dalla pipeline (per esempio, validarne uno ricevuto via WebSocket):

```clipper
LOCAL hPayload := HIX_JwtValidate( cToken )

IF hPayload == NIL
   // firma non valida o scaduto
   RETURN .F.
ENDIF

? hPayload[ "user_id" ], hPayload[ "exp" ]
```

---

## Refresh token - pattern base

Il JWT non può essere invalidato prima di `exp`. Per token di lunga durata senza perdere sicurezza, usa **due token**:

| Token | TTL | Uso |
|---|---|---|
| Access token | breve (15 min) | Va in ogni richiesta `Authorization: Bearer ...` |
| Refresh token | lungo (7-30 giorni) | Va solo all'endpoint `/refresh` per emettere un nuovo access token |

```clipper
// POST /api/refresh
FUNCTION Main()
   LOCAL cRefresh := UPost( "refresh_token", "" )
   LOCAL hPayload := HIX_JwtValidate( cRefresh, "chiave_refresh" )

   IF hPayload == NIL
      RETURN USendJson( { "error" => "refresh_non_valido" }, 401 )
   ENDIF

   USendJson( { ;
      "token" => HIX_JwtEncode( { "user_id" => hPayload["user_id"] } ) ;
   } )
RETURN
```

---

## JWT vs Sessione - tabella rapida

| | JWT | Sessione |
|---|---|---|
| Storage server | ❌ No | ✅ Sì (memory/file) |
| Invalidazione immediata | ❌ Aspetta `exp` o blacklist | ✅ `Destroy()` |
| Scalabilità orizzontale | ✅ Niente stato condiviso | ⚠️ Richiede storage o session affinity |
| Cross-domain / mobile | ✅ Header Bearer | ❌ Cookie legato al dominio |
| CSRF | ❌ Non applicabile (non è un cookie) | ⚠️ Obbligatorio |
| Dimensione per richiesta | ~500-1000 byte | ~50 byte (solo il SID) |
| Revoca token emessi | ❌ Difficile senza blacklist | ✅ Facile |

---

## Best practice

1. **Chiave segreta lunga e ruotabile.** Minimo 32 byte random.
   Cambiala tra gli ambienti (`dev` / `prod`).
2. **Scadenza breve.** 15-60 min per l'access, refresh token separato.
   I JWT eterni sono un buco di sicurezza.
3. **Non mettere dati sensibili nel payload.** Il payload è base64,
   **non cifrato** - chiunque può leggerlo. È solo tamper-proof.
4. **HTTPS sempre.** Il Bearer viaggia in ogni richiesta - senza [SSL](ssl.md) chiunque può intercettarlo.
5. **Non mischiare JWT con i cookie.** Se vai JWT, usa solo l'header `Authorization` - mettere il token in un cookie riporta i problemi di CSRF che il JWT evita.
6. **Blacklist per il logout.** Se devi invalidare prima di `exp`, salva i `jti` (JWT ID) revocati in Redis e controllali nel middleware.

---

## Architettura interna

Dalla versione 2026-07-14, il codice JWT è diviso in due file con responsabilità ben definite:

| File | Strato | Contenuto |
|---|---|---|
| `src/hix_jwt.prg` | **Engine** (puro) | `HIX_JwtEncode`, `HIX_JwtValidate`, `HIX_MwJwtSetup`, `HIX_JwtDefaultKey`, `HIX_JwtDefaultExp` e helper privati per HMAC-SHA256 e firma Base64Url. Nessuna dipendenza dal router. |
| `src/mw/hix_mw_jwt.prg` | **Middleware** | `HIX_MwJwt`, `HIX_MwJwtFactory`, `HIX_MwJwtScope`. Solo pipeline: estrae il Bearer, invoca l'engine e scrive `oCtx:hData["jwt"]`. |

Vantaggi della divisione:
- L'engine può essere riutilizzato fuori dalla pipeline (CLI, worker, validazione
  di token ricevuti via WebSocket) senza caricare il middleware.
- Le STATIC di configurazione (`s_cJwtKey`, `s_nJwtExpSec`) vivono nell'engine.
  Il middleware le consulta tramite `HIX_JwtDefaultKey()` / `HIX_JwtDefaultExp()`
  (le STATIC in Harbour sono file-scoped).
- Modifiche alla pipeline (gestione 403/401, telemetria) non costringono
  a ricompilare l'engine, e viceversa.

> L'API pubblica non cambia: `HIX_MwJwtSetup`, `HIX_JwtEncode`,
> `HIX_JwtValidate`, `HIX_MwJwt`, `HIX_MwJwtFactory` e `HIX_MwJwtScope`
> mantengono lo stesso nome e la stessa firma di prima della divisione.
