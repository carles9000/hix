# 📤 Middleware - Loader

## 📂 `<root>/middlewares`

**HIX** permette sia la definizione statica (basata sul codice sorgente principale) sia
il caricamento dinamico o hot (basato sul caricamento di file nel momento in cui
il server si avvia).

Se usiamo **HixStyle** abbiamo l'opzione di posizionare i middleware nella
cartella `/middlewares`. Questo significa che il programmatore deve solo copiare i
file necessari, e quando HIX si avvierà verificherà i file PRG, li compilerà,
e faranno già parte dell'applicazione.

Ciò significa che non è necessario ricompilare ogni volta che sviluppiamo un'applicazione
web per includere i nostri middleware.

Per configurare i middleware creeremo un file `config.json`
nella directory `/middlewares`.

La configurazione è molto semplice:

chiave `load` che avrà un array di tutti i moduli PRG che abbiamo nella cartella
chiave `setup` che avrà un hash di configurazione per i middleware che ne hanno bisogno

Esempio:
```json
{
  "load": [
    "myappauth.prg",
    "myapplogin.prg",
    "myappauthedit.prg"
  ],
  "setup": {
    "auth": {
      "session_user_key": "_auth_user",
      "roles_key":        "roles",
      "redirect_login":   "/login",
      "redirect_accept":  "/main"
    },
    "session": {
      "cookie":   "FENIXSID",
      "ttl":      3600,
      "max":      100,
      "storage":  "memory"
    },
    "csrf": {
      "redirect": "/login"
    }
  }
}
```
	
La chiave `load` mostra quali file HIX processerà all'avvio

La chiave `setup` mostra la configurazione di ogni middleware.

Qui possiamo vedere la natura di ogni middleware e come viene configurato
secondo le sue esigenze.

