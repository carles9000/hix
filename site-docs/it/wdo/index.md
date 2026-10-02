# WDO - Web Database Objects

WDO è il livello di accesso ai dati di HIX. Il nome completo è **W**eb **D**ata **O**bjects: avvolge i driver di database nativi (librerie C) ed espone un'API Harbour coerente, thread-safe e pronta per la produzione.

## Perché esiste WDO

In un server web multi-thread come HIX, ogni richiesta HTTP viene eseguita nel proprio thread. Senza WDO, il modo "naturale" di connettersi al database sarebbe aprire e chiudere una connessione TCP per ogni richiesta. Questo funziona in sviluppo, ma sotto carico reale collassa in pochi minuti:

- Ogni `connect()` lascia il socket in stato **TIME_WAIT** per 60–240 secondi.
- Il sistema operativo ha un intervallo limitato di porte efimere (~16.000 su Windows).
- Dopo qualche migliaio di richieste rapide, il SO non riesce più ad assegnare porte → errore 10048 / `WSAEADDRINUSE`.

WDO risolve questo problema con un **pool di connessioni**: apre N socket all'avvio dell'app, li mantiene attivi e li presta ai thread che ne hanno bisogno. Ogni "chiusura" restituisce la connessione al pool, mai al sistema operativo.

Questo problema non è esclusivo di Harbour. PHP, Node.js, Python e Java usano tutti il pooling esattamente per la stessa ragione.

## Driver disponibili

| Driver | Stato | Chiave JSON |
|--------|-------|-------------|
| **MySQL / MariaDB** | Production-ready | `"driver": "mysql"` o `"driver": "mariadb"` |
