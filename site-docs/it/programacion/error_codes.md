# 🐛 Pagine di errore di sistema

Quando HIX restituisce un errore HTTP (404, 403, 405, 422, 429, 500, 503...)
**a un client che richiede HTML**, serve una **pagina di errore**. Se il
client richiede JSON (API, AJAX, `Accept: application/json`), restituisce
automaticamente `{ "error": "...", "detail": "..." }`.

HIX ti permette di **sostituire le pagine HTML con le tue pagine statiche HTML** per
ciascun codice di stato: `error_404.html`, `error_500.html`,
`error_403.html`, ecc.

> 🆚 Questa pagina riguarda le pagine di **sistema** (errori HTTP da route non trovate,
> non consentite, saturazione dei pool, ecc). Se quello che vuoi è personalizzare la
> **pagina 5xx che viene renderizzata quando il tuo codice fallisce** (eccezioni,
> trace Harbour), quella vive in
> [programacion/errorsys](../programacion/errorsys.md).

---

## Quando ti serve

- Per il **branding**: un 404 mostra il tuo logo, non la pagina grigia generica.
- Per **reindirizzare** a una landing personalizzata (`/not-found`, pagina di manutenzione,
  ecc).
- Per messaggi **multilingua** (404 tradotto per locale).
- Per **nascondere informazioni tecniche** in produzione (niente "HIX Web Server" in
  fondo).

---

## Setup in `hix.ini`

### Sezione `[paths]`

```ini
[paths]
root = www      ; directory root dell'app
```

### Posizione fissa: `<root>/errors/`

HIX cerca le pagine di errore personalizzate nella cartella fissa `errors/`
relativa a `paths.root` (default `www/errors/`):

```text
www/
 ├── errors/
 │   ├── error_404.html
 │   ├── error_403.html
 │   ├── error_500.html
 │   └── error_503.html
 └── ...
```

Se il file per un codice specifico non esiste, HIX usa la pagina inline
minimalista integrata.

---

## Come funziona la ricerca

Quando HIX chiama internamente `HIX_HttpError(oReq, nStatus, cDetail)`:

```
                 HIX_HttpError(oReq, 404, "Route: /non-esiste")
                              │
                              ▼
              HIX_WantsJson(oReq)?
                     ├── Sì → JSON {"error":"Not Found","detail":"..."}
                     │
                     └── No → HIX_HttpErrorHtml(404, "Not Found", "...")
                                       │
                                       ▼
                  Esiste <root>/errors/error_404.html?
                         ├── Sì → hb_MemoRead() → serve quell'HTML
                         │
                         └── No → HTML inline minimalista di HIX
```

La negoziazione JSON vs HTML controlla:

- `Accept: application/json` o `application/json` ovunque.
- `X-Requested-With: XMLHttpRequest` (AJAX classico).
- `Content-Type: application/json` dalla request.

---

## Codici HTTP restituiti da HIX

HIX può emettere qualsiasi codice standard. I più comuni che vedi ogni giorno:

| Codice | Quando                                              | Dettaglio tipico          |
|--------|-----------------------------------------------------|---------------------------|
| 400    | Body o parametro non valido                         | Bad Request               |
| 401    | Autenticazione mancante (JWT/API key/sessione)      | Unauthorized              |
| 403    | Nessun permesso per quella route o IP filtrato      | Forbidden                 |
| 404    | Route non registrata o file non trovato             | Not Found, Route: /...    |
| 405    | La route esiste ma il metodo non è consentito       | Method Not Allowed        |
| 413    | Body più grande di `[bodylimit]`                    | Payload Too Large         |
| 422    | Validazione fallita (`UValidateOrFail`)             | Unprocessable Entity      |
| 429    | Rate-limit superato                                 | Too Many Requests         |
| 500    | Eccezione nel tuo codice                            | Internal Server Error     |
| 502    | Backend / API esterna giù                           | Bad Gateway               |
| 503    | Pool saturo, modalità manutenzione                  | Service Unavailable       |

La lista completa è mantenuta da `HIX_StatusText(nStatus)` in
`src/hix_error.prg`.

---

## Esempio di `error_404.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
   <meta charset="UTF-8">
   <title>Page not found</title>
   <link rel="stylesheet" href="/static/css/app.css">
</head>
<body>
   <header>
      <img src="/static/img/logo.svg" alt="MiApp">
   </header>

   <main class="error">
      <h1>404</h1>
      <p>This page has disappeared.</p>
      <a href="/">Back to home</a>
   </main>

   <footer>
      <small>&copy; 2026 MiApp</small>
   </footer>
</body>
</html>
```

> 📌 I file `error_XXX.html` sono **HTML statico puro** servito tramite
> `hb_MemoRead()`. **Non** passano per il view engine. Se hai bisogno di
> contenuti dinamici (variabili interpolate), usa
> [programacion/errorsys](../programacion/errorsys.md) con un `.view.html`.

---

## Pagina inline di default

Quando non c'è un `error_XXX.html`, HIX serve qualcosa come:

```html
<!DOCTYPE html>
<html>
<head>
   <title>404 Not Found</title>
   <style>body{font-family:sans-serif;padding:2em;color:#333}h1{color:#c00}</style>
</head>
<body>
   <h1>404 Not Found</h1>
   <h2 style='color:#c00'><small>Route: /non-esiste</small></h2>
   <hr>
   <small>HIX Web Server</small>
</body>
</html>
```

Compatta, self-contained e senza risorse esterne. Per la produzione pubblica si
raccomanda di **sostituirla sempre**.

---

## Risposta JSON automatica

Se il client richiede JSON, HIX emette direttamente:

```json
{ "error": "Not Found", "detail": "Route: /non-esiste" }
```

Per gli errori 422 da `UValidateOrFail`, include anche il dettaglio dei
campi non validi:

```json
{
   "error": "Unprocessable Entity",
   "errors": {
      "email": [ "The email field is required" ],
      "age":   [ "The age field must be numeric" ]
   }
}
```

> 🤖 Per una REST API non devi toccare nulla: il comportamento di default
> è già corretto.

---

## Generare errori dal tuo codice

### Da un controller

```clipper
USendError( 404, "L'utente non esiste" )
USendError( 403, "Nessun permesso per questa operazione" )
USendError( 422, "Email obbligatoria" )
USendError( 503, "Database in manutenzione" )
```

`USendError` rispetta la negoziazione: se il client richiede JSON,
restituisce JSON; se richiede HTML, restituisce la pagina personalizzata (o
quella inline se non ne hai una).

### Da un middleware

```clipper
FUNCTION HixMwApiKey( oCtx )
   IF Empty( oCtx:oReq:Header( "X-Api-Key", "" ) )
      oCtx:lHandled := .T.
      HIX_HttpError( oCtx:oReq, 401, "API key obbligatoria" )
      RETURN .F.
   ENDIF
RETURN .T.
```

`HIX_HttpError` è l'helper di basso livello che rispetta anch'esso JSON/HTML.

---

## Differenza da `programacion/errorsys`

| Caso                                            | Cosa usare                                  |
|-------------------------------------------------|---------------------------------------------|
| Route non trovata (404)                         | `errors/error_404.html`                     |
| Nessun permesso (403)                           | `errors/error_403.html`                     |
| Validazione fallita (422)                       | `errors/error_422.html` + dettaglio JSON    |
| **Eccezione nel tuo codice** (errore Harbour)   | `errors/errorsys.view.html` (errorsys)      |
| Saturazione del pool (503)                      | `errors/error_503.html`                     |

In altre parole:

- **Errori HTTP dal flusso normale** → `error_XXX.html` statici.
- **Crash del tuo codice** → template `.view.html` con dati dell'errore
  (riga, file, trace). Questo è [errorsys](../programacion/errorsys.md).

Puoi (e dovresti) usare **entrambi** i sistemi contemporaneamente in un'app in produzione.

---

## Errori comuni

| Sintomo                                    | Causa                                           | Soluzione                                |
|--------------------------------------------|-------------------------------------------------|------------------------------------------|
| Il mio `error_404.html` non appare         | File fuori da `www/errors/`                     | Posizionalo in `<paths.root>/errors/`    |
| Appare JSON invece di HTML                 | Il client invia `Accept: application/json`      | È corretto - non toccare                 |
| L'HTML appare senza CSS                    | Path relativi nell'HTML                         | Usa path assoluti `/static/...`          |
| Il 500 mostra dati tecnici in produzione   | `[behavior] env = dev`                          | Cambia in `env = prod`                   |
| Il mio template non interpola le variabili  | È HTML statico, non `.view.html`                | Usa [errorsys](../programacion/errorsys.md) |

---

## Best practice

- **Definisci sempre** almeno `error_404.html` e `error_500.html` per la
  produzione. È la prima impressione del tuo brand quando qualcosa va storto.
- Mantieni le pagine **leggere** e **self-contained**: niente JS pesante, niente
  chiamate esterne. Una pagina di errore lenta non deve causare altri errori.
- **Non far trapelare dettagli tecnici** in produzione: niente stacktrace, niente
  path del server, niente nomi di tabelle. Quello è per `dev` o per il log.
- Per il multilingua: usa la **negoziazione `Accept-Language`** nel tuo middleware
  i18n e restituisci `errors/it/error_404.html` o `errors/en/error_404.html`
  con un router personalizzato.
- Se la tua app è **solo API** (no HTML), non c'è bisogno di creare pagine —
  la risposta JSON automatica è sufficiente.
