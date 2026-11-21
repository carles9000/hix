# 🔑 Archiviazione password — `HIX_Password*`

## Cos'è?

Primitiva del core HIX per **archiviare le password** in modo sicuro.
Trasforma una chiave umana (`"admin1234"`) in un record portabile
memorizzabile in DBF, SQL o JSON e verificabile in seguito.

Algoritmo: **PBKDF2-HMAC-SHA256** tramite OpenSSL `libcrypto` (la
stessa libreria che HIX già carica per HMAC, JWT e CSRF — nessuna
nuova dipendenza di link). Minimo di default: **600 000 iterazioni**,
conforme alla raccomandazione OWASP 2026.

!!! tip "Dove si trova"
    Modulo core: `src/hix_password.prg`. Le tre funzioni pubbliche
    (`HIX_PasswordHash`, `HIX_PasswordVerify`, `HIX_PasswordNeedsRehash`)
    sono disponibili in qualsiasi app HIX senza registrare middleware
    o loader.

---

## Perché non un semplice `SHA256(password)`?

Un hash veloce (SHA256, MD5) è **banale da forzare**: una GPU moderna
calcola miliardi di SHA256 al secondo. Un dizionario da 10 M parole
cade in secondi.

PBKDF2 aggiunge **costo artificiale**:

| Iterazioni | Tempo login legittimo | Tentativi/sec dell'attaccante |
|---|---|---|
| 1               | ~1 µs   | ~1 000 000 000 |
| 100 000         | ~100 ms | ~10             |
| **600 000**     | ~600 ms | ~1.6            |
| 1 000 000       | ~1 s    | ~1              |

600 ms sono impercettibili per l'utente; per un attaccante con un
dump del DB ogni password candidata costa gli stessi 600 ms. Un
dizionario da 10 M parole passa da "risolto in 10 s" a "risolto in
1–2 mesi" — tempo sufficiente per rilevare la breach e ruotare.

Il **salt** casuale per utente annulla inoltre le *rainbow table*:
due utenti con la stessa password producono hash diversi.

---

## API pubblica

```clipper
HIX_PasswordHash( cPassword [, nRounds ] )  -> record hash | NIL
HIX_PasswordVerify( cPassword, hRecord )    -> .T. | .F.
HIX_PasswordNeedsRehash( hRecord )          -> .T. | .F.
```

| Parametro | Intervallo valido | Comportamento fuori intervallo |
|---|---|---|
| `cPassword` | stringa, 1..1024 byte | `NIL` / `.F.` |
| `nRounds`   | 600 000..2 000 000 (default 600 000) | `NIL` |
| `hRecord`   | hash con `PASSALG`, `PASSITER`, `SALT`, `PASSHASH` | `.F.` |

- Il salt (16 byte OS-seeded) è generato con `RAND_bytes` di libcrypto.
- `Verify` confronta con `HIX_ConstantEq` → **timing-safe**:
  l'attaccante non può inferire l'hash per differenze di latenza.

---

## Formato del record hash

```clipper
{ ;
   "PASSALG"  => "PBKDF2-SHA256",      ;   // tag dell'algoritmo
   "PASSITER" => 600000,               ;   // n. iterazioni effettivo
   "SALT"     => "…32 hex chars…",     ;   // 16 byte in hex (lowercase)
   "PASSHASH" => "…64 hex chars…"      ;   // 32 byte in hex (lowercase)
}
```

Portabile verso qualsiasi backend:

| Campo | DBF | SQL | JSON |
|---|---|---|---|
| `PASSALG`  | `C(16)` | `VARCHAR(16)` | stringa |
| `PASSITER` | `N(9)`  | `INTEGER`     | numero  |
| `SALT`     | `C(32)` | `CHAR(32)`    | stringa |
| `PASSHASH` | `C(64)` | `CHAR(64)`    | stringa |

!!! warning "Tutti i 4 campi sono obbligatori"
    Se collassi il record in un singolo campo `password_crittografata`
    perdi la possibilità di **alzare il costo** (`PASSITER`) o
    **migrare algoritmo** (`PASSALG`) senza forzare reset di tutte
    le password. I 4 campi insieme sono il contratto PBKDF2.

---

## Flusso tipico

### Creazione utente

```clipper
FUNCTION UserCreate()

   LOCAL hRec, oVal

   oVal := UValidateOrFail( { ;
      "user" => "required|string|max:40", ;
      "pass" => "required|string|min:8"   ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   hRec := HIX_PasswordHash( oVal:Get( "pass" ) )
   IF hRec == NIL
      RETURN USendError( 400, "password fuori intervallo" )
   ENDIF

   oRow := UserRepoNew( oVal:Get( "user" ) )
   oRow:PASSALG  := hRec[ "PASSALG" ]
   oRow:PASSITER := hRec[ "PASSITER" ]
   oRow:SALT     := hRec[ "SALT" ]
   oRow:PASSHASH := hRec[ "PASSHASH" ]
   oRow:Save()

   USendJson( { "ok" => .T., "user" => oRow:USUARIO }, 201 )
RETURN NIL
```

### Login — verify + rehash trasparente

```clipper
FUNCTION UserLogin()

   LOCAL oRow, hStored, hRec

   oRow := UserRepoFind( UParam( "user" ) )
   IF oRow == NIL
      // Hash fittizio: il tempo di risposta sarà indistinguibile fra
      // "utente non esiste" e "password errata" (anti-enumeration).
      HIX_PasswordVerify( UParam( "pass" ), _DummyRecord() )
      RETURN USendError( 401, "credenziali non valide" )
   ENDIF

   hStored := { "PASSALG"  => oRow:PASSALG,  ;
                "PASSITER" => oRow:PASSITER, ;
                "SALT"     => oRow:SALT,     ;
                "PASSHASH" => oRow:PASSHASH }

   IF ! HIX_PasswordVerify( UParam( "pass" ), hStored )
      RETURN USendError( 401, "credenziali non valide" )
   ENDIF

   // Rehash trasparente: se i parametri salvati sono obsoleti
   // (iterazioni sotto il minimo o algoritmo vecchio) ri-derivo la
   // chiave con i parametri correnti e aggiorno la riga.
   IF HIX_PasswordNeedsRehash( hStored )
      hRec := HIX_PasswordHash( UParam( "pass" ) )
      IF hRec != NIL
         oRow:PASSALG  := hRec[ "PASSALG" ]
         oRow:PASSITER := hRec[ "PASSITER" ]
         oRow:SALT     := hRec[ "SALT" ]
         oRow:PASSHASH := hRec[ "PASSHASH" ]
         oRow:Save()
      ENDIF
   ENDIF

   USession():Set( "user", { "id" => oRow:ID, "name" => oRow:NOMBRE } )
   USession():Save()
   URedirect( "/main" )
RETURN NIL
```

---

## `HIX_PasswordNeedsRehash` — alzare il costo a caldo

Il costo consigliato da OWASP **cresce ogni ~2 anni** per mantenere
costante il costo d'attacco. Con `PASSITER` per utente puoi:

1. Cambiare il minimo interno (`HIX_PASSWORD_MIN_ROUNDS`).
2. Al prossimo login di ciascun utente `NeedsRehash` restituisce
   `.T.` se il suo record è sotto il nuovo minimo.
3. Ri-derivi con `HIX_PasswordHash` (nuovo costo) e salvi.

Alzi la sicurezza **in modo trasparente per l'utente**, senza reset.

L'helper ritorna `.T.` in questi casi:

| Caso | Motivo |
|---|---|
| `hRecord` non è un hash | `.T.` — record invalido |
| `PASSALG != "PBKDF2-SHA256"` | algoritmo legacy, migrare |
| `PASSITER < 600 000` | costo sotto il minimo |
| `SALT` o `PASSHASH` con lunghezza/formato errato | record corrotto |

---

## Sicurezza — dettagli importanti

### `libcrypto` risolta a runtime

HIX non linka staticamente libcrypto; la carica con `LoadLibraryA`
(Windows: `libcrypto-4-x64.dll`) o `dlopen` (Linux:
`libcrypto.so.{4,3,1.1}`) **al primo uso**.

Se la libreria non è disponibile:

- `HIX_PasswordHash` ritorna `NIL` → mai fallback a un hash debole.
- `HIX_PasswordVerify` ritorna `.F.` → il login fallisce, la porta
  resta chiusa.

La politica "fallire invece che indebolire" evita il caso classico
di un'app che improvvisamente accetta hash MD5 perché qualcuno ha
deployato senza le DLL.

### Timing attack

`HIX_PasswordVerify` confronta con `HIX_ConstantEq` — scorre sempre
tutti i 32 byte e accumula le differenze in XOR. Due hash che
differiscono al byte 1 impiegano lo stesso tempo di due hash
identici. L'attaccante non può usare la latenza per indovinare
l'hash byte per byte.

### Mai inviare il record al client

I 4 campi insieme sono **materiale sensibile**. Non emetterli mai
in una risposta JSON, in una vista o in un log. Se
`GET /users/:id` restituisce i dati utente, filtra esplicitamente
questi campi prima di serializzare.

### Lunghezza massima della password

Il tetto di 1024 byte protegge da **denial-of-service** con
password ultra-lunghe: senza questo cap un client potrebbe inviare
100 MB forzando il server a derivare 600 k volte quella stringa.

---

## Confronto con altri algoritmi

| Algoritmo | CPU-hard | Memory-hard | Stato |
|---|---|---|---|
| MD5 / SHA1 / SHA256 diretto | ❌ | ❌ | **Insicuro** — non usare mai |
| bcrypt      | ✅ | Debole (4 KB) | Accettabile |
| **PBKDF2**  | ✅ | ❌             | **Standard HIX** (NIST/FIPS) |
| scrypt      | ✅ | ✅             | Buono |
| Argon2id    | ✅ | ✅ (tunable)  | Raccomandazione OWASP 2026 |

PBKDF2 resta valido perché:

- È in tutte le librerie standard.
- Richiesto da **FIPS 140** (ambienti governativi/bancari).
- Con 600 k+ iterazioni il costo d'attacco è ancora proibitivo per
  la maggior parte degli attaccanti.

Se HIX in futuro aggiungerà Argon2id, il campo `PASSALG` consente
una **migrazione graduale**: nuove password taggate `"argon2id"`,
quelle esistenti con `"PBKDF2-SHA256"` continuano a essere
verificate con i parametri salvati.

---

## Cosa **non** fa questa primitiva

`HIX_Password*` è **crypto input/output puro**. Non copre:

| Fuori scope | Livello che lo copre |
|---|---|
| Rate-limit tentativi di login | Middleware (`HIX_MwRateLimit` o repo utenti) |
| Persistenza del record | Il tuo `model/userrepo.prg` (DBF, WDO, ecc.) |
| Sessione post-login | `HIX_MwSession` + `USession()` |
| Revoca sessioni al cambio password | Campo `AUTHVER` + `MyAppReloadUser` |
| Flusso di reset password via email | La tua app (HIX fornisce token con `HIX_TokenMake`) |
| Policy password (maiuscole, cifre...) | `UValidator` con regola `regex:` |

Il design è deliberato: una primitiva piccola e verificabile, non
un "auth framework" monolitico.

---

## Riferimenti

- **RFC 2898** / **RFC 8018** — specifica formale PBKDF2
- **NIST SP 800-63B** — Digital Identity Guidelines
- **OWASP Password Storage Cheat Sheet** — iterazioni raccomandate per anno
- **Password Hashing Competition 2015** — contesto Argon2
