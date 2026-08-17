# 📦 Contesto - `oCtx`

Quando **HIX** esegue un middleware, passa sempre un singolo parametro: **`oCtx`**.
È il **contesto della request** - un'istanza di `THixContext` che raggruppa tutto
ciò che un middleware ha bisogno per ispezionare la request, comunicare con gli altri anelli della catena di middleware
e decidere cosa deve succedere dopo.

```clipper
FUNCTION MW_ApiKey( oCtx )
   // oCtx è il contesto - vive per tutta la catena di middleware
   // e scompare quando la request termina
RETURN .T.
```

---

## Perché esiste `oCtx` invece di un semplice `oReq`?

Un middleware raramente agisce da solo. In una catena tipica (rate limit → JWT →
ruoli → action), ogni middleware ha bisogno di **condividere informazioni** con i
successivi: il payload JWT, la sessione dell'utente, un flag di audit...

`oCtx` è quello "spazio condiviso". È il vassoio che si passa di mano in mano
per tutta la catena, e quando arriva all'action della route resta disponibile.

---

## Proprietà principali

| Proprietà | Tipo | Descrizione |
|----------|------|-------------|
| `oCtx:oReq` | `THixRequest` | Oggetto request della request corrente. |
| `oCtx:hData` | Hash | Dizionario libero per condividere dati tra middleware. |
| `oCtx:lHandled` | Logico | Impostalo a `.T.` quando il middleware ha già risposto. |
| `oCtx:cScope` | Stringa | Metadati liberi assegnati alla route (accessibile dai MW). |
| `oCtx:cOnFail` | Stringa | URL di redirect se il middleware ritorna `.F.` (opzionale). |

---

## `oCtx:oReq` - la request

È l'oggetto `THixRequest` della request corrente. Possiamo leggere header,
cookie, body, parametri di query, ecc. da lì:

```clipper
LOCAL cKey := oCtx:oReq:Header( "X-Api-Key", "" )
LOCAL cSid := oCtx:oReq:Cookie( "hix_sess", "" )
LOCAL cIp  := oCtx:oReq:IP()
```

### Alternativa consigliata - helper `U*`

HIX collega automaticamente la request al thread corrente prima di eseguire ogni
middleware, quindi **gli helper `U*` funzionano** anche dentro il middleware,
e sono di solito più brevi e coerenti con il codice delle action:

```clipper
FUNCTION MW_ApiKey( oCtx )

   // Entrambe le righe sono equivalenti:
   LOCAL cKey := oCtx:oReq:Header( "X-Api-Key", "" )
   LOCAL cKey := UHeader( "X-Api-Key", "" )    // più breve e leggibile

   IF cKey != "chiave-segreta-123"
      USendError( 401, "API Key non valida" )
      RETURN .F.
   ENDIF

RETURN .T.
```

| Stile con `oCtx:oReq` | Stile con `U*` |
|------------------------|-----------------|
| `oCtx:oReq:Header( c, x )` | `UHeader( c, x )` |
| `oCtx:oReq:Cookie( c, x )` | `UCookie( c, x )` |
| `oCtx:oReq:Body()` | `UBody()` |
| `oCtx:oReq:IP()` | `UIP()` |
| `oCtx:oReq:Method()` | `UMethod()` |

Scegli lo stile che preferisci - HIX non ne impone uno. La convenzione attuale è
usare gli `U*` dentro action e middleware per mantenere il codice conciso.

---

## `oCtx:hData` - condividere dati tra middleware

`hData` è un hash libero che **si propaga attraverso l'intera** catena di middleware e
arriva intatto all'action della route. È il canale ufficiale per passare
informazioni tra anelli.

Chiavi convenzionali già usate dai middleware di sistema:

| Chiave | Impostata da | Contenuto |
|-----|--------|---------|
| `oCtx:hData["jwt"]` | `HixMwJwt` | Hash con il payload del token JWT verificato. |
| `oCtx:hData["session"]` | `HixMwSession` | Hash con i dati della sessione attiva. |
| `oCtx:hData["_sid"]` | `HixMwSession` | ID della sessione attiva. |
| `oCtx:hData["user"]` | Middleware di auth | Oggetto/hash dell'utente autenticato. |

Esempio - un middleware di ruoli che legge ciò che `HixMwJwt` ha già lasciato:

```clipper
FUNCTION MW_RequireAdmin( oCtx )

   LOCAL hJwt := hb_HGetDef( oCtx:hData, "jwt", NIL )

   IF hJwt == NIL .OR. hb_HGetDef( hJwt, "role", "" ) != "admin"
      USendError( 403, "Solo admin" )
      RETURN .F.
   ENDIF

RETURN .T.
```

Puoi aggiungere le tue chiavi senza toccare nulla del sistema:

```clipper
oCtx:hData["mio_flag"]   := .T.
oCtx:hData["tenant_id"] := 42
```

---

## `oCtx:lHandled` - "Ho già risposto, non eseguire l'action"

Quando un middleware decide di **interrompere la catena** (rifiutare la request) deve:

1. Inviare la risposta al client.
2. Impostare `oCtx:lHandled := .T.` così il dispatcher sa che la risposta è già stata
   inviata e non esegue nient'altro.
3. Restituire `.F.`.

Se usi gli helper `USendError` / `USendJson` / `URedirect`, **segnano già
`lHandled` internamente** - non devi farlo manualmente.

```clipper
FUNCTION MW_ApiKey( oCtx )

   IF UHeader( "X-Api-Key", "" ) != "chiave-segreta-123"
      USendError( 401, "API Key non valida" )   // segna lHandled
      RETURN .F.
   ENDIF

RETURN .T.
```

---

## `oCtx:cScope` - metadati della route

Quando registri una route puoi allegare una stringa libera come `scope`. Quel
valore arriva al middleware tramite `oCtx:cScope` e serve per variare il comportamento
in base al "gruppo logico" a cui appartiene la route.

```clipper
oSrv:AddRouteGet( "admin.users", "/admin/users", 'users.prg', "MW_Log", "admin" )
oSrv:AddRouteGet( "api.stats",   "/api/stats",   'stats.prg', "MW_Log", "public" )
```

```clipper
FUNCTION MW_Log( oCtx )

   IF oCtx:cScope == "admin"
      l( "[AUDIT] " + UMethod() + " " + UPath() + " da " + UIP() )
   ENDIF

RETURN .T.
```

---

## `oCtx:cOnFail` - redirect di fallback

Route a cui reindirizzare automaticamente quando il middleware ritorna `.F.`
(opzionale). Utile, ad esempio, per mandare a `/login` qualsiasi route che fallisce
l'autenticazione senza ripetere la logica in ogni middleware.

---

## Riepilogo

- `oCtx` è il **contesto della request**, l'unico parametro ricevuto da ogni middleware.
- `oCtx:oReq` fornisce accesso alla request; in alternativa puoi usare gli helper `U*`.
- `oCtx:hData` è l'hash **condiviso** tra middleware e l'action.
- `oCtx:lHandled := .T.` quando interrompi la catena; gli helper `USend*` lo fanno già.
- `oCtx:cScope` sono metadati liberi della route.
- `oCtx:cOnFail` definisce l'URL di redirect se il middleware rifiuta.
