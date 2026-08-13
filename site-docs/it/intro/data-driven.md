# 🧭 HixStyle - Roadmap

Una delle caratteristiche di **HIX** è la capacità di permettere a chiunque di creare
un server personalizzato, definendone le route, le configurazioni, le funzioni,
i middleware, i processi,... in sostanza tutto ciò che un'applicazione
web ha, tutto integrato.

Un altro modo è configurarlo in modalità HixStyle, seguendone il pattern, e
uno dei vantaggi che offre è poter configurare un server HIX standard in modo che si adatti a un'intera applicazione tramite
la configurazione **data-driven**.

**HixStyle** permette diversi modi di plasmare l'intera applicazione.
Come abbiamo visto nei capitoli precedenti, ha una propria architettura
e struttura per offrire un sistema comune a tutti. Una di queste
funzionalità è la capacità di definire diverse funzionalità tramite file di
configurazione.

## Config
Alla root del tuo progetto avrai un file `config.json` in cui imposterai
i parametri principali che configureranno la tua applicazione: set Harbour,
ddriver, configurazioni del database, diverse chiavi (session, jwt, csrf,...).

## loaders

I `loaders` sono le funzioni che vuoi precaricare in HIX per usarle
dalla tua applicazione. All'interno della struttura di cartelle che definisci
quando usi HixStyle, se hai una cartella `/loaders`, HIX caricherà
tutti i file `*.prg` che hai al suo interno all'avvio del server. Il server compilerà e
aggungerà alla mappa interna dei simboli le funzioni che hai definito.

Se un modulo incontra un errore durante la compilazione e/o il caricamento, HIX
non si avvierà.

## middlewares

I middleware, come i loaders, saranno situati nella loro
cartella `/middlewares`, e a differenza della cartella loaders, ci sarà un
file `config.json` che indica quali file nella cartella saranno caricati
e come ogni middleware sarà configurato. Nella sezione di aiuto questo è
ben definito.

## routes

Le route possono essere definite in file JSON che saranno situati nella
cartella `/routes`. Puoi avere le route in un unico file o
suddividere in più file. Quando HIX si avvia, leggerà tutti i file JSON
dalla cartella /routes e inizializzerà il server.


## Prepararsi per l'AI

### Quale vantaggio offre questo sistema di configurazione?

Uno dei vantaggi che offre è che, a partire da un server che hai,
sia tuo che di terze parti, il server sarà già pronto, testato, e
dovrai solo mappare come vuoi che funzioni senza bisogno di
ricompilare il server.

D'altra parte, e forse uno dei più importanti, stiamo cercando di progettare
uno strumento attraverso cui qualsiasi AI possa aiutarci nello scopo
di progettare la nostra app usando **HIX**.

L'AI sarà in grado di avviare il server, fermarlo, modificare i diversi
file di configurazione, rileggere e ricaricare le route via API verso il server,
rimuovere qualche route, aggiungere qualche funzionalità, senza la necessità di ricompilare
il nostro server. Questo è l'obiettivo nella prossima revisione di **HIX**.

La creazione di diverse `/skills` e `/commands` che ci permettano di avanzare
in questa direzione è l'obiettivo principale.
