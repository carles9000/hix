# 🧩 Middleware - Progettazione

## Struttura del middleware

Fondamentalmente è composto da 2 funzioni all'interno dello stesso .prg:

- Setup: qualche variabile che definiamo di default e che possiamo riconfigurare se necessario
- Middleware: funzione che eseguirà il processo e può usare la variabile di setup

Questa potrebbe essere la progettazione di un middleware

```clipper
STATIC s_MyVar := 3600

FUNCTION Mw_FenixSetup( nExpSecs )

   IF ValType( nExpSecs ) == "N" .AND. nExpSecs > 0
      s_MyVar := nExpSecs 
   ENDIF
   
RETURN nil 

FUNCTION Mw_Fenix( oCtx ) 
   LOCAL lAccept := .T.
   ... 
   
      // Uso di s_MyVar 
   
   ... 
	  
RETURN lAccept 
```


## Dinamiche di progettazione per tipo di applicazione

Non tutte le applicazioni hanno bisogno degli stessi middleware. La scelta dipende da
chi consuma l'API e come.

Qui mostriamo alcuni esempi di progettazione in base allo scenario.


### Applicazione Web classica (HTML + form)

L'utente interagisce da un browser. Lo stato viene salvato in sessione con cookie.

```
Request del browser
     │
     ├─ MW_BodyLimit      ← limita la dimensione (upload)
     ├─ MW_Session        ← carica la sessione dal cookie
     ├─ MW_Csrf           ← verifica il token CSRF su POST/PUT/DELETE
     ├─ MW_RequireAuth    ← c'è una sessione attiva?
     └─ MW_RequireRole    ← ha il ruolo necessario?
```

L'ordine conta: carica prima la sessione, poi verifica il CSRF (che ha bisogno della
sessione), e solo dopo controlla l'autenticazione.

### API REST (JSON, client esterno)

Il client è un'app mobile, SPA o servizio esterno. Nessun cookie di sessione: l'autenticazione
è stateless con JWT o API Key.

```
Request del client API
     │
     ├─ MW_Cors           ← header CORS per il browser
     ├─ MW_RateLimit      ← protezione contro abusi
     ├─ MW_BodyLimit      ← limita la dimensione del body
     ├─ MW_Jwt            ← valida il token Bearer
     ├─ MW_RequireAuth    ← il token è valido?
     └─ MW_RequireRole    ← ruolo sufficiente?
```

### Servizio interno (machine-to-machine)

Comunicazione tra servizi nello stesso sistema. Nessun utente umano, nessuna sessione.
L'autenticazione è tramite API Key statica.

```
Request del servizio interno
     │
     ├─ MW_BodyLimit      ← protezione di base
     ├─ MW_ApiKey         ← valida X-Api-Key
     └─ MW_RequireAuth    ← chiave conosciuta?
```

---

## Cosa proteggere e cosa no

### Proteggere sempre

| Cosa? | Con cosa? |
|---|---|
| Route private (pannello, dati utente) | Autenticazione + ruoli |
| Endpoint che modificano dati (POST/PUT/DELETE) | CSRF sul web, JWT/ApiKey sull'API |
| Upload di file o payload grandi | Body limit |
| Endpoint pubblici con traffico elevato | Rate limiting |
| Qualsiasi cosa che restituisca dati sensibili | Header di sicurezza HTTP |

### Non proteggere troppo

Un errore comune è applicare tutti i middleware a tutte le route come precauzione. Il
risultato è una latenza aggiunta inutile e codice più difficile da debug.

> La pagina di benvenuto pubblica non ha bisogno di JWT.
> Un endpoint di health-check non ha bisogno di sessione.
> Gli asset statici non hanno bisogno di CSRF.

La regola è semplice: applica il middleware minimo necessario per il livello di fiducia
che quella route richiede.

---

## Esempi concettuali

### Esempio semplice: logging delle request

Il middleware più semplice possibile non blocca nulla. Osserva e logga solamente:

```
Arriva la request
     │
     ▼
[MW_ReqLog]
   Annota: method + path + IP nel log
   Ritorna sempre .T.
     │
     ▼
   Handler - viene eseguito normalmente
```

Utile per la tracciabilità: sapere quali route vengono chiamate, con quale frequenza, da quali IP.

### Esempio composito: route API protetta

Una route API che possono usare solo utenti autenticati con ruolo `editor`:

```
POST /api/articles  (crea articolo)
     │
     ▼
[MW_RateLimit]
   Questo IP ha superato 100 req/min?
   No → .T., continua
     │
     ▼
[MW_Jwt]
   C'è l'header Authorization: Bearer xxx?
   Il token è valido e non scaduto?
   Sì → deposita il payload in oCtx:hData["jwt"] → .T.
   No → risponde 401 → .F. → break
     │
     ▼
[MW_RequireRole("editor")]
   oCtx:hData["jwt"]["role"] == "editor"?
   Sì → .T.
   No → risponde 403 → .F. → break
     │
     ▼
   Handler _CreateArticle()
   Sa già che l'utente è valido e ha il permesso.
   Si preoccupa solo di creare l'articolo.
```

Tre middleware, tre responsabilità chiare, codice di business pulito.

