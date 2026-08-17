# 🛡️ Middleware - Introduzione

La sezione middleware è forse uno degli aspetti più importanti nella progettazione di un'applicazione web, perché è responsabile della sicurezza. Molti di voi potrebbero già conoscere questo argomento, ma è fondamentale studiarlo attentamente per capire come dovremmo progettarli. È un po' esteso ma necessario per incastrare tutti i pezzi.

Immagina di avere un negozio con un'unica entrata. Prima che un cliente raggiunga il bancone, passa attraverso una guardia giurata, poi un metal detector, e se ha una tessera VIP, attraverso l'accesso prioritario. Solo allora raggiunge il commesso.

**Middleware** è semplicemente una funzione che restituisce un valore logico .T./.F.
Questa funzione riceve un parametro `oCtx` che è il contesto della chiamata, ma possiamo usare gli UHelpers
per accedervi più facilmente.

In questo esempio, controlliamo che la request porti una API Key valida nell'header
`X-Api-Key`:

```clipper
FUNCTION MW_ApiKey()

   LOCAL cKey := UHeader( "X-Api-Key", "" )

   IF cKey != "chiave-segreta-123"
      USendError( 401, "API Key non valida" )
      RETURN .F.
   ENDIF

RETURN .T.
```

In questo caso, il middleware recupera l'header per verificare che la request abbia un header `X-Api-Key` e ne validiamo la chiave.




### Container - UMiddleware()

`UMiddleware` è il container che HIX utilizza internamente per eseguire qualsiasi middleware, sia esso una funzione per nome o un codeblock. Questa classe ci restituirà un oggetto che si occuperà di eseguire la nostra funzione e gestirla. Seguendo il nostro esempio, definiremmo il nostro MW così.

```clipper
UMiddleware():New( "MW_ApiKey", "apikey" )
```

Il secondo parametro è un nome descrittivo che appare nei log quando il middleware interrompe la catena e ci aiuta a tracciare.

### Relazione Route <-> Middleware

Quando definiamo la nostra route, la associamo al nostro middleware (MW). Solo se passiamo lo strato di sicurezza del MW, il server esegue la route. Altrimenti, sarà il middleware stesso, a seconda di come lo definiamo, a stabilire cosa fare.

Es: Definiamo una route che utilizzerà il middleware che abbiamo progettato `MW_ApiKey`

```clipper
oSrv:AddRouteGet( "data", "/data", 'mydata.prg', "MW_ApiKey" )
```

Definiamo `mydata.prg`, una semplice funzione che restituisce una risposta, ma verrà eseguita solo se ha superato con successo il controllo del middleware.

```clipper
FUNCTION MyData()
   USendJson( { "info" => "solo per clienti con API Key", "ok" => .T. } )
RETURN NIL
```

### Flusso di esecuzione

```
GET /data  (senza header X-Api-Key)
     │
     ▼
[MW_ApiKey]
   Header X-Api-Key presente e corretto?
   No → USendError(401) → RETURN .F. → break
     │ Sì
     ▼
   MyData()  ← raggiunge qui solo se la chiave è valida
```

**NOTA** Con i middleware definisci le regole **una volta** e le applichi alle route che ne hanno bisogno, in modo dichiarativo e coerente.

### Setup (parametri)

L'ultimo dettaglio da sapere è che possiamo creare un middleware statico o dinamico. Nel caso vogliamo riutilizzare un middleware, dovremo definire in qualche modo il suo `setup`. Ciò significa che quando definiamo nel nostro sistema che useremo il middleware MW_A(), possiamo anche dirgli con quali parametri lavorerà.

Immagina di avere un MW che controlla quante volte un IP fa una richiesta e vogliamo che sul nostro endpoint non possa essere eseguito più di 10 volte al minuto. In questo caso, definiamo il nostro MW di uso generale e lo configuriamo con un setup di 10.

Ogni MW porta con sé il proprio setup se definito in quel modo.

## Middleware multipli - UBaseMiddleware

Ma la questione dei middleware non è così semplice, e ora faremo un piccolo salto. Possiamo facilmente avere molti middleware necessari per gestire la nostra sicurezza. Il sistema deve gestire l'arrivo della request HTTP e il momento in cui la tua logica di business la elabora.

Come funzionerebbe il nostro sistema?

```
 Request HTTP
       │
       ▼
┌──────────────┐
│ Middleware 1 │  ← Passa? ──No──▶  Risponde 401/403/429...
└──────┬───────┘
       │ Sì
       ▼
┌──────────────┐
│ Middleware 2 │  ← Passa? ──No──▶  Risponde 503/413...
└──────┬───────┘
       │ Sì
       ▼
┌──────────────────────────────┐
│   La tua logica di business  │  ← Solo ciò che deve arrivare arriva qui
└──────────────────────────────┘
```

Questo gruppo di middleware lo chiameremo una **pipeline** o **stack di middleware**.

Quando una route necessita di più controlli concatenati, viene creata una funzione middleware composita. `UBaseMiddleware` esegue la lista in ordine e si interrompe al primo fallimento.

In questo esempio, proteggiamo un endpoint di amministrazione che richiede:

1. **Rate limiting** - massimo 60 richieste al minuto per IP
2. **JWT valido** - token Bearer verificato
3. **Ruolo admin** - il token deve includere quel ruolo

Solo e soltanto se supera questi controlli può eseguire la route!

```clipper
// ============================================================
// Gruppo MW_Admin — rate limit + JWT + ruolo admin
// ============================================================
FUNCTION MW_Admin( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HixMwRateLimit", "rate"  ) )
   o:Add( UMiddleware():New( "HixMwJwt"      , "jwt"   ) )
   o:Add( UMiddleware():New( "MW_ApiKey"     , "roles" ) )

RETURN o:Run()
```

Con questo sistema di sicurezza che abbiamo progettato, possiamo ora applicarlo a diverse route.

Se definiamo il sistema da codice per compilare tutto:

```clipper
...
	LOCAL oSrv := THixServer():New()

	// --- Configurazione (prima di Start) ---
	HIX_MwRateLimitSetup( 60, 60 )          // 60 req/min per IP
	HIX_MwJwtSetup( "mia-chiave-segreta", 3600 )

...

	// --- Route del pannello admin ---
	oSrv:AddRouteGet(    "admin.users",   "/admin/users",     'users.prg'      , "MW_Admin" )
	oSrv:AddRouteDelete( "admin.user",    "/admin/users/:id", 'users_del.prg'  , "MW_Admin" )
	oSrv:AddRouteGet(    "admin.metrics", "/admin/metrics",   'metrics.prg'    , "MW_Admin" )
	
...
	
	oSrv:Start()	
```

Flusso di esecuzione per una qualsiasi di queste route:

```
GET /admin/users
     │
     ▼
[HixMwRateLimit]
   L'IP ha superato 60 req/min?
   No → .T.
   Sì → 429 Too Many Requests → .F. → break
     │
     ▼
[HixMwJwt]
   Il token Bearer è valido?
   Sì → deposita il payload in oCtx:hData["jwt"] → .T.
   No → 401 Unauthorized → .F. → break
     │
     ▼
[MW_ApiKey]
   oCtx:hData["jwt"]["role"] == "admin"?
   Sì → .T.
   No → 403 Forbidden → .F. → break
     │
     ▼
   _AdminUsers()  ← raggiunge qui solo se supera tutti e tre i controlli
```

Il vantaggio di raggruppare in `MW_Admin` è che le tre route condividono esattamente la stessa pipeline. Se domani avessimo bisogno di aggiungere un quarto controllo (ad esempio, audit logging), aggiungiamo una riga in `MW_Admin` e le tre route sono protette automaticamente, e la manutenzione si fa in 1 solo file!!!

```clipper
// Aggiungi audit a tutte le route admin — basta un cambio
FUNCTION MW_Admin( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HixMwRateLimit", "rate"    ) )
   o:Add( UMiddleware():New( "HixMwJwt"      , "jwt"     ) )
   o:Add( UMiddleware():New( "MW_ApiKey"     , "roles"   ) )
   o:Add( UMiddleware():New( "MW_AuditLog"   , "audit"   ) )  // nuovo

RETURN o:Run()
```

Un middleware è un componente strutturale che funge da strato intermedio tra il sistema operativo e le applicazioni, permettendo la comunicazione tra sistemi distribuiti. In un'architettura, il suo ruolo è disaccoppiare i componenti, permettendo loro di scambiare informazioni e funzioni senza bisogno di conoscere i dettagli tecnici interni gli uni degli altri.

**RIEPILOGO**
L'argomento middleware è importante per controllare la sicurezza della nostra applicazione. Possiamo scegliere di non usarli e l'applicazione funzionerà comunque, ma a seconda del tipo di modulo che eseguiamo, potrebbe essere esposta.

Vale la pena investire nel fare un po' di test e nel capire e imparare come usare questo meccanismo, che ci aiuterà a evitare possibili intrusioni o accessi non autorizzati.

!!! info "Prossimo capitolo" Come dovremmo progettare uno strato middleware.
