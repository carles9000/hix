# ✨ Modalità HixStyle

**HixStyle** è il volto strutturato di HIX. Dove la [Modalità base](modo-basico.md)
ti permette di servire qualsiasi `.html`, `.prg` o `.hrb` con completa libertà, **HixStyle**
impone un modo di lavorare: un'architettura fissa, nomi prevedibili, un flusso
chiaro e convenzioni condivise dall'intera community.

Non è più potente perché ha più funzionalità — HIX le ha in entrambe le modalità.
È più potente perché **tutti gli sviluppatori lavorano allo stesso modo**. Questa è vera
manutenibilità, vera collaborazione e moduli intercambiabili tra progetti.

---

## 🎯 Un unico modo di lavorare

**HixStyle** implementa il pattern **MVC (Model-View-Controller)**, uno standard
ampiamente sperimentato nell'industria del software (Laravel, Rails, Django,
Spring, ASP.NET MVC, Phoenix...). Non abbiamo reinventato nulla: abbiamo adottato ciò che già
funziona e lo abbiamo adattato all'ecosistema Harbour.

La conseguenza pratica:

- Un programmatore che entra in un progetto HixStyle **sa immediatamente dove si trova tutto** senza bisogno di spiegazioni.
- Le route sono dichiarate in un unico posto. I controller vivono in un altro. Le view
  in un altro ancora. I model in un altro. I middleware in un altro.
- Non ci sono "script sparsi in giro". Non c'è "quel .prg che fa tutto".
  Non ci sono file appesi in cartelle casuali.

> 💡 La rigidità non è un costo — è la garanzia che un progetto rimanga
> leggibile nel corso degli anni, anche se diverse mani ci passano attraverso.

---

## 📁 Struttura delle cartelle da `<root>`

Quando attivi HixStyle, HIX si aspetta di trovare (e crea se non esistono) una
struttura fissa dalla cartella root (`<root>`, di solito `www/`):

```
www/
 ├── public/         ← l'unica cartella servita direttamente al browser
 ├── routes/         ← definizioni delle route in JSON
 ├── controllers/    ← logica degli endpoint (.prg)
 ├── views/          ← template .view.html
 ├── models/         ← accesso ai dati (UDbf, SQL, API esterne)
 ├── middlewares/    ← intercettori (auth, csrf, rate-limit, ...)
 ├── errors/         ← pagine di errore
 └── loaders/        ← auto-load all'avvio (routes, MW, helpers)
```

Ogni cartella ha **uno scopo unico** e **semantica chiara**.
Questo non è un suggerimento: HixStyle cerca attivamente in queste
directory e rifiuta qualsiasi tentativo di eseguire codice fuori dal flusso stabilito.

---

## 🔒 Privacy delle cartelle

In HixStyle il browser **può accedere solo a `public/`**. Punto.

- `public/` contiene asset statici: CSS, JS, immagini, font, PDF scaricabili,
  robots.txt, favicon, ecc.
- Tutto il resto (`controllers/`, `views/`, `models/`, `routes/`...) è
  **privato per impostazione predefinita**. Un tentativo di richiedere `/controllers/auth.prg`
  direttamente dal browser riceve un **403/404**, mai il codice.

Questa policy è applicata a livello di dispatcher, non per convenzione. Non c'è
modo di rilasciare accidentalmente un file `.prg`: se non è montato come route
in `routes/*.json`, non viene eseguito.

> 🛡️ In [Modalità base](modo-basico.md) qualsiasi `.prg` o `.hrb` posizionato
> sotto `<root>/` può essere eseguito richiedendone l'URL. In HixStyle questo è
> **completamente bloccato** — è una delle prime differenze visibili
> quando attivi `hixstyle.enabled = true` in `hix.json`.

---

## 🚦 Il flusso: route → controller → view

Ogni richiesta HTTP in HixStyle segue lo stesso percorso:

```
     Request
        │
        ▼
┌─────────────┐
│  routes/    │  Quale controller gestisce questo URL?
│  *.json     │  Quali middleware si applicano prima?
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  middlewares/   │  auth, csrf, rate-limit, cors, ...
│  (chain)        │  possono interrompere la richiesta qui
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  controllers/   │  logica di business
│  *.prg          │  richiede dati dai model/
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  models/        │  accesso ai dati (UDbf, SQL, API)
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  views/         │  render HTML finale
│  *.view.html    │  (oppure JSON per le API)
└──────┬──────────┘
       │
       ▼
   Response
```

Questo flusso è **sempre lo stesso**, sia che la risposta sia una
pagina HTML per un umano o JSON per un'app mobile.

---

## 🎨 Il view engine (Mambo)

**HixStyle** ti spinge a usare il [view engine](../hixstyle/views/mambo.md)
di HIX per renderizzare l'HTML — non a concatenare stringhe dentro il controller.
Il nostro view engine che chiamiamo Mambo (ci dà grande ritmo) ci offre
alcuni vantaggi (dettagliati nel capitolo dedicato):

- **Separazione chiara** tra logica e presentazione: i designer toccano
  le view senza dover capire Harbour.
- **Sintassi dichiarativa** con interpolazione `{{ }}`, condizionali `@if`,
  loop `@for`, ereditarietà dei template...
- **Cache automatica**: le view vengono compilate in HRB la prima
  volta e riutilizzate. Rendering veloce anche con pagine complesse.
- **`@args` espliciti**: ogni view dichiara quali variabili si aspetta di ricevere.
  Non ci sono variabili "magiche" iniettate alla cieca, sono i classici parametri
  usati quando si chiama una funzione. Il controller elabora i dati
  e li invia sotto forma di argomenti alla view.
- **Escape automatico**: protezione contro XSS senza pensarci.

> 📚 Il [view engine](../hixstyle/views/mambo.md) ha un suo
> capitolo dedicato. Qui basta sapere che **esiste** e che in
> HixStyle è il modo consigliato per restituire HTML.

---

## 💾 Models

I model vivono in `models/` e incapsulano l'accesso ai dati:

- **DBF** tramite [UDbf](../hixstyle/models/udbf.md), un wrapper che aggiunge
  validazione, casting e operazioni in stile ActiveRecord.
- **SQL** (MariaDB, PostgreSQL, SQLite) tramite i driver del progetto, librerie Harbour,...
- **API esterne** tramite `hb_curl`.
- **File, cache, code...** qualsiasi fonte di dati può vivere qui.

La regola è semplice: **i controller non accedono direttamente alle tabelle**.
Passano attraverso un **model**. Questo ti dà:

- Un unico posto da toccare se lo schema del database cambia.
- Possibili unit test: il model può essere mockato.
- Riusabilità: lo stesso model serve più controller.

---

## 🌐 Web + API nello stesso ecosistema

Con HixStyle **la stessa applicazione serve contemporaneamente** un
web tradizionale (HTML) e un'API REST (JSON), condividendo:

- Gli stessi model.
- Gli stessi middleware per auth, validazione e rate-limit.
- La stessa struttura di route (`routes/web.json` e `routes/api.json`,
  o un unico file con prefissi `/api/v1/...`).
- La stessa sessione utente, oppure token JWT se l'API è stateless.

Non hai bisogno di mantenere due progetti paralleli. Il web back-office e
l'API consumata dall'app mobile **vivono nello stesso HIX**, con la stessa
logica di business dietro. Cambi il formato di output (view vs JSON)
in una riga del controller.

---

## 🛡️ Middleware: il vero superpotere

I middleware sono intercettori che vengono eseguiti **prima** del controller
nella catena di ogni richiesta. In HixStyle sono **cittadini di prima classe**
e la maggior parte delle preoccupazioni trasversali si risolvono qui:

- **Autenticazione** (sessione, JWT, API key).
- **CSRF** (protezione contro richieste forgiate).
- **CORS** (policy cross-origin per le API).
- **Rate-limit** (anti-brute-force, anti-DoS).
- **Firewall** (whitelist/blacklist per IP/CIDR).
- **Validazione** dell'input.
- **Logging e metriche** di ogni richiesta.
- **Traduzione** (i18n) e selezione del locale.
- **Compressione GZIP** delle risposte.

Sono dichiarati in `routes/*.json` per route o per gruppo di route, e
combinati con la virgola. Il controller **viene eseguito solo se l'intera catena
passa**. Se un middleware interrompe la richiesta (401, 403, 429...), il tuo
controller non ne sa nulla.

> 🧩 Tutta la logica di sicurezza e orchestrazione vive **fuori** dal
> controller. Il controller fa solo il suo lavoro: orchestrare i model
> e renderizzare la risposta. Questo è codice pulito.

---

## 📌 Riepilogo dei vantaggi

**HixStyle** ti offre, in un colpo solo:

| Vantaggio                     | Cosa ti dà                                   |
|-------------------------------|----------------------------------------------|
| Struttura fissa               | Chiunque comprende qualsiasi progetto        |
| Cartelle private              | Impossibile rilasciare accidentalmente codice |
| Flusso MVC                    | Logica, dati e presentazione separati        |
| View engine (Mambo)           | HTML manutenibile, veloce e sicuro           |
| Middleware dichiarativi       | Sicurezza e orchestrazione fuori dal codice  |
| Web + API in un progetto      | Un codice, due canali di output              |
| Convenzioni condivise         | Onboarding in ore, non settimane             |
| Moduli intercambiabili       | Importa un modulo da un altro progetto e vai |

Ognuno di questi punti ha un **suo capitolo** nella documentazione.
Questa pagina è solo il quadro generale; d'ora in poi, ogni
sezione del manuale sviluppa un aspetto specifico.
