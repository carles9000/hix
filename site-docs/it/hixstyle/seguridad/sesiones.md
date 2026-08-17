# 🔑 Sessioni

Una **sessione** è uno spazio di storage sul server dove HIX conserva i dati associati
a uno specifico client (tipicamente l'utente loggato). Ciò che lega il client alla
sua sessione è un **cookie** che viaggia in ogni request e contiene un
identificativo opaco (SID).

```
Client                              Server
   │                                    │
   │  GET /login                        │
   ├───────────────────────────────────>│  no SID -> crea nuova sessione
   │                                    │  SID = "abc...123"
   │  Set-Cookie: HIXSID=abc...123      │
   │<───────────────────────────────────┤
   │                                    │
   │  POST /auth                        │
   │  Cookie: HIXSID=abc...123          │  riconosce il SID -> recupera i dati
   ├───────────────────────────────────>│  USession():Set("user", hUser)
```

Le sessioni HIX sono **idempotenti**: toccare `oCtx:hData["session"]` da un
middleware o chiamare `USession():Set()` da un controller modifica lo stesso
hash di dati per quel client.

---

## Quando usarle

| Caso d'uso | Sessioni |
|---|---|
| App web tradizionale con login | ✅ Sì - pattern canonico |
| SPA con autenticazione basata su cookie | ✅ Sì |
| API REST stateless | ❌ No - usa [JWT](jwt.md) |
| Microservizi / app mobile | ❌ No - usa [JWT](jwt.md) |
| Carrello, wizard multi-schermata | ✅ Sì |
| Messaggi flash tra redirect | ✅ Sì (`UFlash`) |

> Le sessioni sono **stateful**: il server ricorda il client attraverso le richieste.
> Rendono la programmazione più facile ma legano il client a un'istanza (o richiedono
> session affinity / storage condiviso in un cluster).

---

## Setup

### Da `hix.json`

`storage`: `"memory"` | `"file"`.
`lifetime`: durata del cookie di sessione in minuti (`0` = indefinita).
`gc_days`: giorni per la GC dei file orfani (solo `storage="file"`).
`seed`: chiave segreta per la cifratura (richiesta se `crypt=true`).

```json
{
  "session": {
    "storage":  "memory",
    "prefix":   "sess_",
    "crypt":    false,
    "seed":     "",
    "lifetime": 60,
    "gc_days":  3
  }
}
```

### Da codice

```clipper
HIX_MwSessionSetup( ;
   "HIXSID",     ;   // nome del cookie
   3600,         ;   // TTL in secondi (1 ora)
   60,           ;   // GC: pulisci gli scaduti ogni N chiamate
   "memory",     ;   // storage: "memory" | "file"
   "sessions/",  ;   // path (solo se storage="file")
   "sess_",      ;   // prefisso file
   .F.,          ;   // cifra
   "",           ;   // seed di cifratura
   7 )               // durata del cookie in giorni
```

### Dall'app - convenzione Fenix

Fenix espone i parametri in `www/middlewares/config.json` per tenerli vicini
alla logica dell'app:

```json
{
  "setup": {
    "session": {
      "cookie":  "FENIXSID",
      "ttl":     3600,
      "max":     100,
      "storage": "memory"
    }
  }
}
```

Questi valori si leggono con `UMwConfig("session", "cookie")` da qualsiasi
controller o middleware.

---

## Abilitare la sessione su una route

`HIX_MwSession` è il middleware che carica/crea la sessione. Va aggiunto
alla catena di middleware della route - direttamente o dentro un gruppo di middleware dell'app.

### Singola route

```clipper
oSrv:AddRouteGet( "dash", "/dashboard", bAction, "HIX_MwSession" )
```

```json
{ "name": "dashboard", "url": "/dashboard", "action": "controllers/dash.prg",
  "middleware": "HIX_MwSession" }
```

### Pattern Fenix - gruppo di middleware riutilizzabile

In Fenix definisci **una volta** un gruppo che combina sessione + autenticazione e
lo applichi a tutte le route che ne hanno bisogno:

```clipper
// www/middlewares/myappauth.prg
FUNCTION MyAppAuth( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
RETURN o:Run()
```

```json
{ "name": "main", "url": "/main", "action": "controllers/main.prg",
  "middleware": "MyAppAuth" }
```

> 📖 Dettagli del pattern in [Middleware](../middleware/middleware.md).

---

## Leggere e scrivere da un controller

Con la sessione attiva, gli helper `USession()` e `UFlash()` permettono di
accedere ai dati senza toccare `oCtx`.

### Leggere

```clipper
cUser := USession( "user" )              // valore o NIL
cRole := USession( "role", "viewer" )    // valore con default
```

### Scrivere

```clipper
LOCAL oSess := USession()                // proxy con Set/Save/Destroy
oSess:Set( "user", hUser )
oSess:Set( "role", "admin" )
oSess:Save()                             // persiste + rinnova TTL + emette cookie
```

### Distruggere

```clipper
USession():Destroy()                     // cancella i dati + fa scadere il cookie
```

### Esempio reale - `auth.prg` da Fenix

```clipper
// POST /auth - validazione credenziali e avvio sessione
FUNCTION Main()
   LOCAL oVal, oSess, hUser

   oVal := UValidatePost( { ;
      "username" => { "required|min:3|max:30", "Username", "" }, ;
      "password" => { "required|min:4",        "Password", "" }  ;
   } )

   IF ! oVal:Make()
      UFlash( "login" ):Set( { "error" => oVal:GetFirstError() } )
      URedirect( "/login" )
      RETURN
   ENDIF

   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   IF ValType( hUser ) == "H"
      // Salva l'utente con la chiave configurata
      oSess := USession()
      oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
      oSess:Save()
      URedirect( UMwConfig( "auth", "redirect_accept" ) )
   ELSE
      UFlash( "login" ):Set( { "error" => "Username o password errati" } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )
   ENDIF
RETURN
```

### Esempio reale - `logout.prg` da Fenix

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

---

## Storage: memory vs file

| Storage | Persistenza | Cluster | Restart | Uso tipico |
|---|---|---|---|---|
| `memory` | RAM del processo | ❌ singola istanza | Persa | Sviluppo, monolitici |
| `file` | Disco | ✅ con session affinity | Sopravvive | Produzione, load balancer |

### Memory

Sessioni veloci, niente scrittura su disco. Tutte le sessioni si perdono al riavvio. In un cluster,
il client perde la sessione se il load balancer lo manda su un'altra istanza.

### File

Ogni sessione è un file in `sessions/<prefix><SID>.dat`. Sopravvivono ai riavvii
e permettono a più istanze di condividere lo stesso storage.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "file", "sessions/", "sess_" )
```

### Cluster con Apache + stickysession

Quando fai il deploy dietro un load balancer Apache, chiama `HIX_MwSessionSetRoute( "i1" )`
con la `route=` del tuo `BalancerMember`. HIX accoda il suffisso al SID così
Apache può mantenere il client sticky alla stessa istanza con
`stickysession=HIXSID`.

---

## Cifratura opzionale

Se `crypt=1` nel config (o `lCrypt=.T.` in `HIX_MwSessionSetup`), i file di sessione
sono cifrati con il `seed`. Senza il seed corretto non possono essere letti.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "file", "sessions/", "sess_", ;
                    .T., "chiave_segreta_di_app", 7 )
```

> ⚠️ Cambiare il seed invalida tutte le sessioni esistenti.

---

## Pattern utili

### Recuperare l'utente in qualsiasi controller

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Sconosciuto" } )

   // hUser è stato messo da HIX_MwIsAuth dopo aver letto la sessione
RETURN UView( "main.view.html", hUser["name"], hUser )
```

> I middleware di auth leggono già `USession( cKey )` per te e mettono l'hash utente
> in `oReq:hData["user"]`.

### Messaggi flash (messaggi one-time)

`UFlash` usa la sessione sotto il cofano. Essenziale per portare messaggi
attraverso un `URedirect`.

```clipper
// POST con errore -> flash + redirect
UFlash( "login" ):Set( { ;
   "error" => "Username o password errati", ;
   "user"  => cUserInserito ;
} )
URedirect( "/login" )

// GET /login -> consuma il flash una sola volta
oFlash := UFlash( "login" )
cError := oFlash:Get( "error" )       // cancellato dopo la lettura
cUser  := oFlash:Get( "user"  )
oFlash:Save()
```

### Sub-hash per organizzare la sessione

```clipper
USession():Set( "cart",  { "items" => aItems, "total" => nTotal } )
USession():Set( "prefs", { "theme" => "dark", "lang"  => "it"   } )
USession():Save()

hCart := USession( "cart" )
nTot  := hCart[ "total" ]
```
