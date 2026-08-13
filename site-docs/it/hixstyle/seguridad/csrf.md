# 🛑 CSRF — Cross-Site Request Forgery

Un attaccante può ingannare il browser di un utente loggato facendogli inviare una richiesta "reale" (con il cookie di sessione incluso) al tuo sito. Poiché il cookie viaggia con ogni richiesta automaticamente, il server non può distinguere il form legittimo da quello falso.

I **token CSRF** prevengono questo: ogni form include un token segreto che solo la pagina reale conosce. Se il POST arriva senza un token o con uno non valido → **403 Forbidden**.

```
GET  /edit/42          <input type="hidden" name="_csrf" value="ABCxyz...">
POST /edit/42          _csrf=ABCxyz...  ->  il middleware controlla e permette
POST /edit/42 (forgiato)  no _csrf      ->  il middleware rifiuta con 403
```

---

## Due varianti in HIX

HIX ha **due** middleware CSRF. Coprono scenari diversi:

| Middleware | Stato | Richiede sessione | Caso d'uso |
|---|---|---|---|
| **`HIX_MwCsrf`** | stateful | ✅ Sì | Il token vive nella sessione. Pipeline web tradizionale. |
| **`HIX_MwCsrfCheck`** | stateless (HMAC) | ❌ No | Il token è firmato con `app_key`. Funziona senza sessione attiva. |

> Fenix usa **`HIX_MwCsrfCheck`** perché permette di includere il token CSRF
> anche nei form pubblici (login) dove non c'è ancora una sessione.

---

## Setup

### Da codice

```clipper
HIX_MwCsrfSetup( ;
   "/login",         ;   // cRedirect — URL in caso di fallimento; "" -> JSON 403
   "x-csrf-token",   ;   // header HTTP con il token
   "_csrf",          ;   // campo form con il token
   "my_app_secret",  ;   // segreto HMAC (memorizzato come app_key)
   0 )                   // nLapsus — TTL in secondi; 0 = nessuna scadenza
```

### Convenzione Fenix — `www/middlewares/config.json`

```json
{
  "setup": {
    "csrf": {
      "redirect": "/login"
    }
  }
}
```

---

## `HIX_MwCsrfCheck` — stateless (Fenix)

Questo è il pattern che Fenix usa in ogni form. Il token è firmato con `app_key` e validato senza toccare la sessione:

```clipper
// www/middlewares/myapplogin.prg - per form pubblici
FUNCTION MyAppLogin( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"    ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()

// www/middlewares/myappauthedit.prg - per form autenticati
FUNCTION MyAppAuthEdit( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"    ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"     ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()
```

E le route:

```json
{ "name": "sys.auth",         "url": "/auth",                "method": "POST",
  "action": "controllers/auth.prg",
  "middleware": "MyAppLogin" }

{ "name": "customer.update",  "url": "/customer/:id/edit",   "method": "POST",
  "action": "controllers/masters/update@customer.prg",
  "middleware": "MyAppAuthEdit", "scope": "customers:edit" }
```

### Nel template

```html
<form method="POST" action="/auth">
  {{ UCsrfToHtml() }}
  <input name="username">
  <input name="password" type="password">
  <button>Accedi</button>
</form>
```

`UCsrfToHtml()` genera l'`<input type="hidden" name="_csrf" value="...">`
con un token appena firmato. Il template lo incorpora senza toccare la sessione.

### Tramite header (AJAX)

```js
fetch( "/customer/42/edit", {
   method: "POST",
   headers: {
      "X-CSRF-Token": "{{ HIX_CsrfMakeToken() }}",
      "Content-Type": "application/x-www-form-urlencoded"
   },
   body: "name=Carles&email=c@example.com"
} );
```

---

## `HIX_MwCsrf` — stateful

Genera il token al primo GET, lo salva nella sessione come `_csrf_token` e valida ogni POST/PUT/DELETE/PATCH contro quel valore.

```clipper
// Applica all'intero server
oSrv:Use( { "HIX_MwSession", "HIX_MwCsrf" } )
```

Il token è esposto in `oCtx:hData["csrf_token"]` così i template possono leggerlo:

```html
<form method="POST">
  <input type="hidden" name="_csrf" value="{{ csrf_token }}">
  ...
</form>
```

Se un POST arriva senza token o con uno non valido → **403 JSON**.

---

## Metodi safe vs unsafe

Il middleware **valida solo** i metodi che modificano lo stato:

| Metodo | Azione del middleware |
|---|---|
| `GET`, `HEAD`, `OPTIONS` | Passa sempre (nessuna validazione) |
| `POST`, `PUT`, `DELETE`, `PATCH` | Richiede un token valido |

---

## Gestione degli errori

Quando `HIX_MwCsrfCheck` fallisce e ha `cRedirect` configurato:

1. Salva un flash `csrf` con `error => "..."`.
2. Esegue `URedirect( cRedirect )`.

Il tuo `login.prg` recupera il messaggio:

```clipper
FUNCTION Main()
   LOCAL oFlash := UFlash( "login" )
   LOCAL cError := oFlash:Get( "error" )
   oFlash:Save()

   IF Empty( cError )
      oFlash := UFlash( "csrf" )                  // ⬅ fallback al flash CSRF
      cError := oFlash:Get( "error" )
      oFlash:Save()
   ENDIF

RETURN UView( "sys/login.view.html", cError )
```

Se `cRedirect` è vuoto, ritorna **403 JSON** con `{ "error": "..." }` - utile per AJAX/SPA.

---

## `app_key` — il segreto HMAC

`HIX_MwCsrfCheck` firma ogni token con `HIX_ConfigApp("app_key")`. Se non esiste, usa il valore di default **`H!x@CSRF@2026`** (⚠️ **cambialo sempre in produzione**).

Configura l'app_key:

```clipper
// Tramite setup
HIX_MwCsrfSetup( "/login", "x-csrf-token", "_csrf", ;
                 "my_secret_app_key", 0 )

// Tramite API diretta
HIX_ConfigAppSet( "app_key", "my_secret_app_key" )
```

> ⚠️ **Cambiare l'`app_key` invalida tutti i token CSRF emessi prima**,
> compresi i form aperti in tab attive. Gli utenti vedranno un 403 finché non aggiornano la pagina.

---

## Best practice

1. **CSRF su tutti i form POST.** Non solo il login - anche edit/delete/trasferimenti/qualsiasi azione che muta lo stato.
2. **`HIX_MwCsrfCheck` di default.** Più semplice (nessuna sessione coinvolta) e più riutilizzabile. Funziona con `UCsrfToHtml()` direttamente nei template.
3. **Cambia `app_key` in produzione.** Il valore di default è pubblicato nel codice sorgente.
4. **TTL ragionevole.** `nLapsus = 3600` (1h) limita il riuso del token se qualcuno copia HTML in cache. `0` = nessuna scadenza.
5. **CSRF + sessione vanno insieme.** Il CSRF ha senso solo per auth basata su cookie. Se usi [JWT](jwt.md) in un'API, il CSRF non si applica (i token Bearer non sono inviati automaticamente).
6. **Double cookie / SameSite=Lax.** Il cookie di sessione di HIX porta già `SameSite=Lax`, che filtra alcuni attacchi CSRF. I token CSRF sono la difesa in profondità.
