# Middleware - Catalogo

Catalogo completo dei middleware inclusi in HIX. Tutti seguono lo schema standard:
una funzione `HIX_MwXxx( oCtx )` pronta da aggiungere alla pipeline, e nella maggior
parte dei casi una variante `HIX_MwXxxFactory( params )` che ritorna un codeblock con
la propria configurazione per una route specifica.

| Legenda | |
|---|---|
| **Web** | Uso consigliato in applicazioni web (HTML, form, sessione) |
| **API** | Uso consigliato in API (JSON, JWT, M2M) |
| **Setup** | Funzione da chiamare prima di `oSrv:Start()` per configurare gli statici |
| **Factory** | Variante che ritorna un codeblock con configurazione indipendente per route |

Tutti i middleware predefiniti di HIX sono nella cartella `/src/mw`

---

## Infrastruttura

### 🚧 `HIX_MwMaintenance`

| | |
|---|---|
| **Descrizione** | Modalità manutenzione gestita: blocca tutto il traffico con `503` e JSON `{ "error": "maintenance" }` durante deploy o interruzioni pianificate. |
| **Funzione** | Attivabile tramite flag programmatico o per esistenza di un lock file su disco (toggle senza riavvio). |
| **Setup** | `HIX_MwMaintenanceSetup( lActive, cFile )` |
| **Factory** | `HIX_MwMaintenanceFactory( lActive )` — solo flag, nessun lock file |
| **Web** | Sì — mostra una pagina 503 amichevole |
| **API** | Sì — i client devono fare retry con backoff |
| **Esempio** | `HIX_MwMaintenanceSetup( .F., "maintenance.lock" )` → creare il file attiva il blocco. |

---

### 📋 `HIX_MwReqLog`

| | |
|---|---|
| **Descrizione** | Logga ogni request in ingresso con `METHOD /path IP` nel logger di HIX. Non blocca mai, ritorna sempre `.T.`. |
| **Funzione** | Scrive una riga per request prima di eseguire l'handler. Livello configurabile (DEBUG/INFO/WARN). |
| **Setup** | `HIX_MwReqLogSetup( nLevel )` |
| **Factory** | `HIX_MwReqLogFactory( nLevel )` |
| **Web** | Sì — utile in dev/staging |
| **API** | Sì — essenziale per audit in produzione |
| **Esempio** | `HIX_MwReqLogSetup( HIX_LOG_INFO )` → scrive `"GET /api/users 192.168.1.10"`. |

---

## Sicurezza HTTP

### 🔐 `HIX_MwSecHeaders`

| | |
|---|---|
| **Descrizione** | Header HTTP di hardening su ogni risposta. Non blocca mai, arricchisce solamente. |
| **Funzione** | Inietta `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Strict-Transport-Security: max-age=31536000` e `Content-Security-Policy`. |
| **Setup** | `HIX_MwSecHeadersSetup( cCSP )` |
| **Factory** | `HIX_MwSecHeadersFactory( cCSP )` |
| **Web** | Critico — includere in qualsiasi sito in produzione |
| **API** | Consigliato — previene l'uso improprio delle risposte come contenuto web |
| **Esempio** | `HIX_MwSecHeadersSetup( "default-src 'self'; script-src 'self' 'nonce-abc'" )` |

---

### 🌐 `HIX_MwCors`

| | |
|---|---|
| **Descrizione** | Gestione CORS completa per API consumate dal browser. |
| **Funzione** | Inietta header `Access-Control-*` su ogni risposta e risponde automaticamente con `204` al preflight `OPTIONS`. |
| **Setup** | `HIX_MwCorsSetup( cOrigin, cMethods, cHeaders )` |
| **Factory** | Non applicabile |
| **Web** | Opzionale — raramente necessario in same-origin |
| **API** | Essenziale — qualsiasi API cross-domain o pubblica |
| **Esempio** | `HIX_MwCorsSetup( "https://app.com", "GET,POST,PUT", "Content-Type,Authorization" )` |

---

### 📦 `HIX_MwBodyLimit`

| | |
|---|---|
| **Descrizione** | Protegge dagli upload abusivi leggendo `Content-Length` prima di processare il body. |
| **Funzione** | Rifiuta con `413 payload_too_large` se la dimensione dichiarata supera il massimo. Default: 1 MB. |
| **Setup** | `HIX_MwBodyLimitSetup( nMax )` (in byte) |
| **Factory** | `HIX_MwBodyLimitFactory( nMax )` — limite specifico per route |
| **Web** | Sì — protegge form e upload di file |
| **API** | Sì — previene abusi con payload grandi |
| **Esempio** | `HIX_MwBodyLimitSetup( 2 * 1024 * 1024 )` → massimo 2 MB globale. |

---

### 🚦 `HIX_MwRateLimit`

| | |
|---|---|
| **Descrizione** | Limitatore di frequenza delle request per IP in finestra fissa. Thread-safe con mutex. |
| **Funzione** | Conta le request per IP in una finestra di N secondi. Ritorna `429` quando si supera il massimo. Espone il contatore in `oCtx:hData["rate_count"]`. |
| **Setup** | `HIX_MwRateLimitSetup( nMax, nWindowSecs )` |
| **Factory** | `HIX_MwRateLimitFactory( nMax, nWindowSecs )` — limite specifico per route |
| **Web** | Utile su form di login/register |
| **API** | Essenziale per endpoint pubblici o non autenticati |
| **Esempio** | `HIX_MwRateLimitSetup( 100, 60 )` → 100 req/min per IP. Per login rigido: `HIX_MwRateLimitFactory( 5, 60 )`. |

---

## Sessioni

### 🍪 `HIX_MwSession`

| | |
|---|---|
| **Descrizione** | Fondamento di qualsiasi flusso web stateful. Richiesto prima di `MwAuth`, `MwIsAuth`, `MwRequireAuth` e `MwCsrf`. |
| **Funzione** | Carica la sessione dal cookie `HIXSID` (configurabile), la persiste secondo il backend, espone i dati in `oCtx:hData["session"]` e il SID in `oCtx:hData["_sid"]`. |
| **Setup** | `HIX_MwSessionSetup( cName, nTtl, nGcEvery, cStorage, cPath, cPrefix, lCrypt, cSeed, nLifeDays )` |
| **Backend** | `"memory"` (volatile, default) o `"file"` (persistente su disco) |
| **Apache LB** | `HIX_MwSessionSetRoute( "i1" )` aggiunge suffisso al SID per `stickysession=HIXSID`. |
| **Web** | Essenziale per qualsiasi flusso con login + cookie |
| **API** | No — usa JWT invece |
| **Esempio** | `HIX_MwSessionSetup( "MIOSID", 3600, 60, "file", "sessions/" )` |

---

## Autenticazione

### 🔓 `HIX_MwAuth`

| | |
|---|---|
| **Descrizione** | Gestisce il flusso completo di login e logout con sessione. Richiede `HIX_MwSession` prima. |
| **Funzione** | Se la request è `POST` alla route di login, legge le credenziali dal body (form o JSON), chiama il codeblock `bValidate` e, se valida, salva l'utente in sessione. Se è la route di logout, distrugge la sessione. |
| **Setup** | `HIX_MwAuthSetup( hConfig )` con `bValidate`, `cLoginRoute`, `cLogoutRoute`, `cUserField`, `cPassField`, `cRedirectOk`, `cRedirectFail`, `cSessionKey` |
| **Factory** | Non applicabile |
| **Web** | Sì — pattern primario |
| **API** | No — per il login in API usa JWT direttamente |
| **Esempio** | `HIX_MwAuthSetup( { "bValidate" => {\|u,p\| MyValidate(u,p)}, "cLoginRoute" => "/login" } )` |

---

### 🪙 `HIX_MwJwt`

| | |
|---|---|
| **Descrizione** | Autenticazione stateless tramite Bearer token HS256. Ideale per API, mobile e SPA. |
| **Funzione** | Estrae il token da `Authorization: Bearer xxx`, valida la firma HMAC-SHA256 e la scadenza (`exp`) e deposita il payload completo in `oCtx:hData["jwt"]`. Ritorna `401` se fallisce. |
| **Setup** | `HIX_MwJwtSetup( cKey, nExpSecs )` |
| **Factory** | `HIX_MwJwtFactory( cKey )` — chiave diversa per route (multi-tenant, partner) |
| **Helper** | `HIX_JwtEncode( hData )` genera il token al login. `HIX_JwtValidate( cToken )` valida fuori dalla pipeline. |
| **Web** | Opzionale — preferire `MwSession` con CSRF |
| **API** | Sì — meccanismo stateless preferito |
| **Esempio** | `HIX_MwJwtSetup( "mia-chiave-segreta", 3600 )` → `Authorization: Bearer eyJ...` |

---

### 🗝️ `HIX_MwApiKey`

| | |
|---|---|
| **Descrizione** | Autenticazione M2M tramite chiave statica. Alternativa semplice a JWT per servizi interni o partner. |
| **Funzione** | Valida l'header `X-Api-Key` contro un hash delle chiavi consentite (lookup O(1)). Espone la chiave accettata in `oCtx:hData["api_key"]` per il logging a valle. |
| **Setup** | `HIX_MwApiKeySetup( aKeys )` |
| **Factory** | `HIX_MwApiKeyFactory( aKeys )` — insieme privato di chiavi per una route specifica |
| **Web** | Non applicabile — gli utenti non hanno API key |
| **API** | Standard per M2M e partner; combinare con `MwRateLimit` per anti-brute-force |
| **Esempio** | `HIX_MwApiKeySetup( { "svc-key-1", "partner-key-2" } )` |

---

## Autorizzazione (guardie)

### 🛡️ `HIX_MwRequireAuth`

| | |
|---|---|
| **Descrizione** | Guardia universale delle route: blocca con `401` se non c'è un utente autenticato. Accetta sia sessione che JWT. |
| **Funzione** | Cerca prima l'utente in `oCtx:hData["session"]` (chiave `_auth_user` di default). Se non c'è, prova `oCtx:hData["jwt"]` (fallback). Se non trova nessuno dei due, risponde con `401`. Se passa, espone l'utente in `oCtx:hData["user"]` accessibile tramite `UCurrentUser()`. |
| **Setup** | Non richiesto (usa la sessione configurata da `MwAuthSetup`) |
| **Factory** | Non applicabile |
| **Web** | Sì — protegge route che richiedono login (con sessione) |
| **API** | Sì — protegge endpoint che richiedono JWT |
| **Esempio** | Pipeline web: `"HIX_MwSession,HIX_MwRequireAuth"`. Pipeline API: `"HIX_MwJwt,HIX_MwRequireAuth"`. |

---

### 👤 `HIX_MwIsAuth`

| | |
|---|---|
| **Descrizione** | Guardia semplice basata sulla sessione - alternativa a `RequireAuth` quando si lavora solo con sessioni (senza JWT). Reindirizza a `/login` (302) invece di rispondere con JSON 401. |
| **Funzione** | Legge l'utente da `oCtx:hData["session"]` con la chiave configurata (default `_auth_user`). Se non esiste, reindirizza all'URL di `redirect_login` (configurabile in `config.json` sezione `auth`). |
| **Setup** | Tramite `config.json`: sezione `auth` → `session_user_key`, `redirect_login` |
| **Factory** | Non applicabile |
| **Web** | Sì — preferibile quando si vuole il redirect invece di JSON 401 |
| **API** | No — usa `RequireAuth` |
| **Esempio** | `o:Add( UMiddleware():New( "HIX_MwIsAuth" ) )` dopo `HIX_MwSession`. |

---

### 🎭 `HIX_MwHasRole`

| | |
|---|---|
| **Descrizione** | Guardia di ruolo e operazioni granulari. Legge il ruolo richiesto dal `cScope` della route. Deve venire dopo un middleware che ha caricato l'utente (`MwIsAuth` o `MwRequireAuth`). |
| **Funzione** | Compara `oCtx:cScope` (formato `"role"` o `"role:operazione"`) contro l'hash dei ruoli dell'utente. Accesso completo se il valore del ruolo è vuoto; granulare se elenca operazioni separate da `;`. Risponde con `403` se fallisce. |
| **Setup** | Tramite `config.json`: sezione `auth` → `roles_key` (default `"roles"`) |
| **Factory** | Non applicabile — la differenza tra route si fa con il parametro `cScope` della route |
| **Web** | Sì |
| **API** | Sì |
| **Esempio** | `oSrv:AddRouteGet( "del", "/users/:id", action, "MyAuth", "admin:delete" )` → richiede il ruolo `admin` con operazione `delete`. |

---

### 🎯 `HIX_MwJwtScope`

| | |
|---|---|
| **Descrizione** | Guardia di scope per JWT (stile OAuth 2.0). Legge lo scope richiesto dal `cScope` della route e lo confronta con il claim `scope` del token. |
| **Funzione** | Se `cScope` è vuoto, passa. Altrimenti verifica che ogni token (separato da spazio) in `cScope` sia presente nel claim `scope` del JWT. Risponde con `403` se ne manca qualcuno. |
| **Setup** | Non richiesto |
| **Factory** | Non applicabile |
| **Web** | Non comune |
| **API** | Sì — controllo scope in API JWT |
| **Esempio** | Token con `"scope" => "read:products write:orders"`. Route `"read:products"` → passa. Route `"delete:products"` → 403. |

---

## CSRF

### 🔏 `HIX_MwCsrf`

| | |
|---|---|
| **Descrizione** | Protezione CSRF basata sulla sessione. Genera un token casuale per sessione e lo valida sui metodi non sicuri (POST/PUT/DELETE/PATCH). Richiede `HIX_MwSession` prima. |
| **Funzione** | Su metodi GET/HEAD/OPTIONS, genera il token se non esiste e lo espone come `oCtx:hData["csrf_token"]` (da incorporare nei form). Su metodi non sicuri, lo legge dall'header `X-CSRF-Token` o dal campo form `_csrf` e lo confronta con quello in sessione. Ritorna `403` se non corrisponde. |
| **Setup** | `HIX_MwCsrfSetup( cRedirect, cHeader, cField, cSecret, nLapsus )` |
| **Factory** | Non applicabile |
| **Web** | Essenziale — includere sempre in web con sessione e form |
| **API** | Non applicabile — usa JWT (non inviato automaticamente dal browser) |
| **Esempio** | Il template incorpora `{{ oCtx:hData["csrf_token"] }}` in `<input name="_csrf">`. POST senza token → `403`. |

---

### 🔐 `HIX_MwCsrfCheck`

| | |
|---|---|
| **Descrizione** | Variante stateless di CSRF basata su HMAC. Valida token firmati senza bisogno di una sessione. |
| **Funzione** | I metodi sicuri (GET/HEAD/OPTIONS) passano. Su metodi non sicuri, legge il token dall'header o dal campo e verifica la firma HMAC con la chiave dell'applicazione. Non richiede una sessione. |
| **Setup** | Condivide la chiave HMAC e la configurazione con `MwCsrf` |
| **Factory** | Non applicabile |
| **Web** | Sì — alternativa a `MwCsrf` quando non si vuole mantenere lo stato in sessione |
| **API** | Non comune |
| **Esempio** | `oSrv:AddRoutePost( "auth", "/auth", "controllers/auth.prg", "HIX_MwCsrfCheck" )` con token generato da `@csrf` / `UCsrfToHtml()` nel form. |

---

## Riepilogo rapido per scenario

| Scenario | Stack tipico |
|---|---|
| **Web statico pubblico** | `HIX_MwReqLog`, `HIX_MwSecHeaders`, `HIX_MwBodyLimit` |
| **Web con login + sessione** | + `HIX_MwSession`, `HIX_MwCsrf`, `HIX_MwAuth`, `HIX_MwRequireAuth` (o `HIX_MwIsAuth`) |
| **Web con ruoli** | + `HIX_MwHasRole` (dichiara `cScope` sulla route) |
| **API pubblica** | `HIX_MwReqLog`, `HIX_MwSecHeaders`, `HIX_MwCors`, `HIX_MwRateLimit`, `HIX_MwBodyLimit` |
| **API autenticata (JWT)** | + `HIX_MwJwt`, `HIX_MwRequireAuth`, `HIX_MwJwtScope` |
| **API M2M / partner** | + `HIX_MwApiKey`, `HIX_MwRequireAuth` |
| **Modalità deploy/outage** | `HIX_MwMaintenance` globale (all'inizio della pipeline) |
