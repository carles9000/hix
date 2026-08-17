# 🧱 Firewall - Filtraggio IP

## Cos'è?

Il **firewall** in HIX decide, **prima** di accettare una connessione TCP,
se l'IP del client è ammesso. È la **prima linea di difesa**:
se l'IP è bloccato, l'HTTP non viene nemmeno parlato - il socket si chiude immediatamente.

```
TCP accept()    ┌───────────────────┐
   ↓            │   Controllo FW    │
  cIP ------->  │  IP ammesso?      │
                └─────────┬─────────┘
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
        ✅ continua pipeline    ❌ chiusura socket
        (HTTP/WS/SSE)
```

---

## Quando usarlo

| Caso | Firewall |
|---|---|
| Bloccare IP specifici che abusano | ✅ Sì - blacklist |
| Limitare il pannello admin alla rete interna | ✅ Sì - whitelist con CIDR |
| API accessibile solo da certi partner | ✅ Sì - whitelist |
| Bloccare interi paesi | ⚠️ Sì, ma con attenzione - usa DB GeoIP esterni |
| Sostituire l'auth | ❌ No - l'IP cambia, non autentica |
| Sostituire il rate limit | ❌ No - nuovi IP passano |

---

## Setup

### Da `hix.json`

```json
{
  "firewall": {
    "mode":   "blacklist",
    "filter": "1.2.3.4 10.0.0.0/8 192.168.1.10-192.168.1.50"
  }
}
```

### Da codice

```clipper
HIX_FirewallSetup( ;
   "1.2.3.4 10.0.0.0/8 !10.0.1.0/24",   ;   // cFilter
   "blacklist" )                            // cMode: blacklist | whitelist
```

Chiamalo **prima** di `oSrv:Start()`. Se `cFilter` è vuoto, il firewall
è disabilitato e lascia passare tutto.

### Disabilitare a runtime

```clipper
HIX_FirewallClear()        // permette qualsiasi IP
```

---

## Modalità

| Modalità | Significato |
|---|---|
| **`blacklist`** | Gli IP nel filtro sono **bloccati**. Tutti gli altri passano. |
| **`whitelist`** | Solo gli IP nel filtro **passano**. Il resto è bloccato. |

```clipper
// Blacklist - blocca attaccanti conosciuti
HIX_FirewallSetup( "1.2.3.4 5.6.7.8 198.51.100.0/24", "blacklist" )

// Whitelist - solo ufficio + VPN
HIX_FirewallSetup( "10.0.0.0/8 203.0.113.42", "whitelist" )
```

---

## Sintassi del filtro

Lista di espressioni separate da **spazi o virgole** (entrambi validi - usa
quello che è più pulito nel tuo `hix.json`). Ogni espressione è una di queste forme:

| Forma | Esempio | Rappresenta |
|---|---|---|
| IP singolo | `1.2.3.4` | Solo quell'IP |
| CIDR | `192.168.1.0/24` | Blocco `/24` |
| Netmask dotted | `192.168.1.0/255.255.255.0` | Equivalente a `/24` |
| Range | `192.168.1.10-192.168.1.50` | Tutti gli IP nel range |
| Esclusione | `!10.0.1.0/24` | Esclude un sottoblocco |
| IPv6 | `::1` `2001:db8::/32` | Anche supportato |

### Combinare inclusione + esclusione

```json
{
  "firewall": {
    "filter": "10.0.0.0/8 !10.0.1.0/24 !10.0.2.5"
  }
}
```

Equivalente a: "tutto `10.0.0.0/8` **tranne** `10.0.1.0/24` e l'IP
`10.0.2.5`".

```clipper
HIX_FirewallSetup( "10.0.0.0/8 !10.0.1.0/24 !10.0.2.5", "whitelist" )
```

Le esclusioni (`!`) sono applicate dopo aver fuso le inclusioni - il
parser lascia un set finale ordinato e compatto.

---

## Esempi completi

### Pannello admin solo per LAN

```json
{
  "firewall": {
    "mode":   "whitelist",
    "filter": "127.0.0.1 ::1 192.168.0.0/16 10.0.0.0/8"
  }
}
```

Solo localhost e reti private raggiungono il server. Internet → drop.

### Bloccare attaccanti rilevati

```json
{
  "firewall": {
    "mode":   "blacklist",
    "filter": "1.2.3.4 5.6.7.8 91.0.0.0/8"
  }
}
```

Ogni IP/blocco cade nel silenzio (nessuna response HTTP). Utile per eliminare
scraper che hai già identificato.

### Whitelist con eccezioni interne

```json
{
  "firewall": {
    "mode":   "whitelist",
    "filter": "203.0.113.0/24 !203.0.113.99"
  }
}
```

Gli IP nel blocco `/24` passano **tranne** `203.0.113.99` (server in
manutenzione, per esempio).

---

## Dietro proxy

Se HIX è dietro un load balancer (Apache, Nginx, AWS ALB), l'IP che vede
il firewall è quello del **proxy**, non del client reale. Il filtraggio IP
**non funziona** a meno che non lo configuri.

```json
{
  "server": {
    "mode": "proxied"
  }
}
```

Con `server.mode = "proxied"`, HIX legge `X-Forwarded-For` / `X-Real-IP` per identificare
il client reale. Ma **il firewall agisce a `accept()`**, prima di analizzare
gli header - l'IP che filtra è quello del socket TCP.

> Ecco perché il firewall è utile solo quando HIX è **direttamente esposto**.
> Dietro un proxy, configura il firewall **nel proxy**
> (mod_authz_host in Apache, deny in Nginx).

---

## Verifica manuale

Utile per test o per controllare se un IP è ammesso:

```clipper
IF HIX_FirewallCheck( "1.2.3.4" )
   ? "IP ammesso"
ELSE
   ? "IP bloccato"
ENDIF
```

---

## Confronto con altri strati

| Strato | Blocca | Quando |
|---|---|---|
| **Firewall** | IP specifici / range | A `accept()` - prima dell'HTTP |
| **[Rate Limit](ratelimit.md)** | Troppe richieste dallo stesso IP | Per richiesta HTTP |
| **[CORS](cors.md)** | Cross-origin dal browser | Per richiesta HTTP |
| **[Auth](autenticacion.md)** | Utente non autenticato | Per richiesta HTTP |

Di solito si combinano: il firewall taglia gli IP cattivi, il rate limit rallenta gli abusi, CORS valida l'origine, e l'auth identifica l'utente.

---

## Best practice

1. **Whitelist per servizi interni.** Pannello admin, metriche o un
   endpoint webhook dovrebbero essere in whitelist per IP.
2. **Blacklist per focolai specifici.** Blocca IP specifici dopo aver rilevato abusi. Non fare affidamento solo sulla blacklist - gli IP cambiano.
3. **Non bloccare interi paesi con liste manuali.** Impossibile da mantenere.
   Se hai bisogno di un geo-blocking serio, usa servizi GeoIP esterni al firewall.
4. **Combina con il rate limit.** Il firewall taglia gli IP **conosciuti**;
   il rate limit taglia gli IP **sconosciuti** che abusano.
5. **Fai attenzione con whitelist + IPv6.** Se pubblichi IPv6, ricordati di aggiungere
   sia v4 che v6 delle tue location ammesse.
6. **Testa prima di applicare la whitelist in prod.** Una whitelist sbagliata ti blocca l'accesso al
   tuo stesso server - compreso il tuo IP.
