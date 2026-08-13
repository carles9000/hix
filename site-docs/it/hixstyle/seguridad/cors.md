# 🌐 CORS — Cross-Origin Resource Sharing

Di default, il browser **blocca** il JavaScript su `https://app.com` dal
`fetch()` verso `https://api.altrodominio.com`. Questa è la **Same-Origin Policy**, una difesa di base contro attacchi cross-site.

**CORS** è il meccanismo con cui il server dice al browser
"sì, accetto richieste da questo origin, con questi metodi e questi header". Lo fa tramite alcuni header `Access-Control-*`.

```
Browser (app.com)                     Server (api.com)
   │                                       │
   │ OPTIONS /v1/users  (preflight)        │
   │ Origin: https://app.com               │
   │ Access-Control-Request-Method: PUT    │
   ├──────────────────────────────────────>│  HIX_MwCors rileva OPTIONS
   │                                       │  Risponde 204 con header CORS
   │ 204 No Content                        │
   │ Access-Control-Allow-Origin: app.com  │
   │ Access-Control-Allow-Methods: PUT,... │
   │<──────────────────────────────────────┤
   │                                       │
   │ PUT /v1/users/42  (reale)             │
   │ Origin: https://app.com               │
   ├──────────────────────────────────────>│  HIX_MwCors inietta header
   │ 200 OK + data                         │  Il resto della pipeline elabora
   │<──────────────────────────────────────┤
```

> Il **preflight OPTIONS** viene lanciato dal browser automaticamente ogni
> volta che una richiesta cross-origin usa un metodo "non semplice" (PUT, DELETE, PATCH) o header custom (`Authorization`, `Content-Type: application/json`).

---

## Quando usarlo

| Caso | CORS |
|---|---|
| API consumata da SPA su un altro dominio | ✅ Sì - essenziale |
| API pubblica per integrazioni | ✅ Sì |
| Mobile che consuma l'API | ❌ No - niente browser, non si applica |
| Backend stesso dominio del frontend | ❌ No - same-origin |
| Webhook che riceve POST da servizi esterni | ❌ No - i server non rispettano CORS |

> CORS protegge l'**utente**, non il server. Un attaccante con `curl` o
> un suo server non subisce CORS - la regola è applicata solo dal browser.

---

## Setup

```clipper
HIX_MwCorsSetup( ;
   "https://app.com",                                 ;   // cOrigin
   "GET,POST,PUT,DELETE,OPTIONS,PATCH",               ;   // cMethods
   "Content-Type,Authorization,X-Requested-With" )        // cHeaders
```

Valori di default se non chiami `HIX_MwCorsSetup`:

| Parametro | Default |
|---|---|
| `cOrigin` | `"*"` (qualsiasi origin - permissivo, solo sviluppo) |
| `cMethods` | `"GET,POST,PUT,DELETE,OPTIONS,PATCH"` |
| `cHeaders` | `"Content-Type,Authorization,X-Requested-With"` |

Chiamalo **prima** di `oSrv:Start()`.

---

## Attivazione

`HIX_MwCors` è un middleware **globale** - di solito lo applichi all'intero
server con `oSrv:Use()` così ogni response include gli header:

```clipper
oSrv:Use( "HIX_MwCors" )
```

O su una route specifica:

```clipper
oSrv:AddRouteGet( "api", "/api/users", bAction, "HIX_MwCors" )
```

```json
{ "name": "api.users", "url": "/api/users", "method": "GET",
  "action": "controllers/api/users.prg",
  "middleware": "HIX_MwCors" }
```

---

## Come funziona

```clipper
FUNCTION HIX_MwCors( oCtx )
   LOCAL hCors := { ;
      "Access-Control-Allow-Origin"  => s_cCorsOrigin,  ;
      "Access-Control-Allow-Methods" => s_cCorsMethods, ;
      "Access-Control-Allow-Headers" => s_cCorsHeaders, ;
      "Access-Control-Max-Age"       => "86400"          ;
   }

   IF oCtx:oReq:cMethod == "OPTIONS"
      oCtx:oReq:Respond( "", 204, "text", hCors )   // preflight
      oCtx:lHandled := .T.
      RETURN .F.                                     // interrompe la catena
   ENDIF

   hb_HMerge( oCtx:oReq:hExtraHeaders, hCors )      // inietta nella response
RETURN .T.
```

| Metodo | Comportamento |
|---|---|
| `OPTIONS` | Risponde **204 No Content** con header CORS - preflight risolto |
| Qualsiasi altro | Inietta gli header `Access-Control-*` nella response finale |

`Access-Control-Max-Age: 86400` dice al browser di mettere in cache la
risposta al preflight per 24 ore, evitando un OPTIONS extra per richiesta.

---

## Combinare con altri middleware

CORS di solito va **prima** nella pila, prima dell'auth, così il
preflight si risolve senza incorrere in un 401:

```clipper
oSrv:Use( { "HIX_MwCors", "HIX_MwSession" } )

oSrv:AddRouteGet( "api.me", "/api/me", bAction, ;
   "HIX_MwCors,HIX_MwJwt" )
```

> Se `HIX_MwJwt` girasse prima di CORS, l'OPTIONS senza Bearer riceverebbe
> un 401 e il browser non farebbe mai la vera richiesta.

---

## Pattern utili

### CORS aperto solo in sviluppo

```clipper
IF HIX_Config( "env" ) == "dev"
   HIX_MwCorsSetup( "*" )
ELSE
   HIX_MwCorsSetup( "https://app.com" )
ENDIF
```

### Più origini (non supportate nativamente)

`HIX_MwCorsSetup` accetta **solo un** `cOrigin`. Per più origini, scrivi il tuo
middleware che guarda l'header `Origin` e ritorna l'header appropriato:

```clipper
FUNCTION MyAppCors( oCtx )
   LOCAL aAllowed := { "https://app.com", "https://admin.app.com" }
   LOCAL cOrigin  := oCtx:oReq:Header( "origin", "" )

   IF AScan( aAllowed, cOrigin ) > 0
      oCtx:oReq:hExtraHeaders[ "Access-Control-Allow-Origin" ] := cOrigin
   ENDIF

RETURN HIX_MwCors( oCtx )   // delega il resto al middleware standard
```

### Cookie cross-origin

Se l'API invia cookie (sessione) e il frontend è su un altro dominio,
aggiungi `Access-Control-Allow-Credentials: true` e specifica un'origine concreta
(`*` non è compatibile con le credenziali):

```clipper
oReq:hExtraHeaders[ "Access-Control-Allow-Credentials" ] := "true"
```

---

## Errori comuni

| Sintomo | Causa |
|---|---|
| `CORS policy: No 'Access-Control-Allow-Origin'` | Manca `HIX_MwCors` sulla route - o non applicato a OPTIONS |
| `Origin not allowed` | `s_cCorsOrigin` non corrisponde all'`Origin` del client |
| `Method PUT is not allowed` | `s_cCorsMethods` non include PUT |
| `Header authorization is not allowed` | `s_cCorsHeaders` non include Authorization |
| Il preflight ritorna 401 | CORS configurato **dopo** il middleware di auth |

---

## Best practice

1. **`"*"` solo in sviluppo.** In produzione, elenca le origini concrete
   che possono consumare la tua API.
2. **CORS non è autenticazione.** Dice solo al browser quali richieste
   possono essere completate - non autentica nulla. Combinalo sempre con
   [JWT](jwt.md) o [Sessioni](sesiones.md).
3. **Applica con `oSrv:Use`.** Il preflight OPTIONS raggiunge qualsiasi URL,
   anche quelli inesistenti - registrarlo globalmente evita
   sorprese con 405/404 su OPTIONS.
4. **Metti CORS prima dell'auth nella pipeline.** OPTIONS non porta
   credenziali e un middleware di auth lo rifiuterebbe.
5. **Limita metodi e header.** Non esporre tutto se non lo usi.
