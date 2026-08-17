# 🍪 Cookie

Un **cookie** è una piccola coppia `nome=valore` che il server invia al
browser tramite `Set-Cookie`, e che il browser restituisce in ogni request successiva
tramite `Cookie`. È il meccanismo di base per mantenere lo stato (sessioni, preferenze, autenticazione) tra request HTTP, che di per sé non hanno memoria.

```
Browser  ─── GET /login ───────────────▶ HIX
                                           │  valida user/pass
                                           │  USetCookie( "HIXSID", cSid, 3600 )
          <── 200 + Set-Cookie  ───────────┤
             HIXSID=abc...; Max-Age=3600;
             Path=/; HttpOnly; SameSite=Lax

Browser  ─── GET /dashboard ───────────▶ HIX
             Cookie: HIXSID=abc...         │  UCookie( "HIXSID" )  → "abc..."
                                           │  identifica l'utente
          <── 200 + data  ─────────────────┤
```

---

## Leggere un cookie

```clipper
UCookie( cName, xDef )
```

```clipper
cSid   := UCookie( "HIXSID",     "" )
cTheme := UCookie( "ui_theme",   "light" )
cLang  := UCookie( "lang",       "es" )
```

Internamente analizza l'header `Cookie` solo una volta per request (lazy).

---

## Scrivere un cookie

```clipper
USetCookie( cName, cValue, nMaxAge )
```

```clipper
USetCookie( "ui_theme", "dark", 86400 * 30 )    // 30 giorni
USetCookie( "HIXSID",   cSid,   3600 )          // 1 ora
USetCookie( "pref",     "x",    0 )             // cookie di sessione
USetCookie( "old",      "",     -1 )            // scadenza
```

### Significato di `nMaxAge`

| Valore | Comportamento |
|---|---|
| `> 0` | Durata in secondi - il browser lo conserva fino alla scadenza |
| `0` | **Cookie di sessione** - il browser lo cancella alla chiusura |
| `-1` | **Scade immediatamente** - invia `Max-Age=0` per eliminarlo |

```clipper
// Logout
USetCookie( "HIXSID", "", -1 )    // il browser dimentica il cookie
URedirect( "/login" )
```

---

## Flag automatici

HIX **aggiunge sempre** tre flag di default:

```
Set-Cookie: nome=valore; Path=/; HttpOnly; SameSite=Lax
```

| Flag | Cosa fa |
|---|---|
| `Path=/` | Il cookie viene inviato per l'intera app, non solo per `/login` |
| `HttpOnly` | JavaScript **non può** leggerlo (`document.cookie` lo ignora) - anti-XSS |
| `SameSite=Lax` | Il browser non lo invia nelle request POST/PUT cross-site - difesa CSRF di base |

> I tre flag insieme coprono l'80% dei tipici attacchi via cookie.
> Se ti serve un comportamento diverso, vedi
> [HIX_SetCookie diretto](#hix_setcookie-low-level).

### Flag `Secure` - in sospeso

Il flag `Secure` indicherebbe che il cookie viaggia solo su HTTPS.
La versione attuale di HIX **non lo emette automaticamente** - se termini TLS in un
proxy davanti, normalmente è il proxy ad aggiungerlo. Se HIX termina TLS direttamente,
scrivi il `Set-Cookie` manualmente con `USetHeader` per includere `Secure`.

---

## Cookie multipli

Ogni `USetCookie` genera un header `Set-Cookie` indipendente - i browser
accettano più `Set-Cookie` nella stessa response:

```clipper
USetCookie( "HIXSID",   cSid,    3600 )
USetCookie( "ui_theme", "dark",  86400 * 30 )
USetCookie( "lang",     "es",    86400 * 30 )

// Nella response:
// Set-Cookie: HIXSID=...; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600
// Set-Cookie: ui_theme=dark; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000
// Set-Cookie: lang=es; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000
```

`HIX_SetCookie` rileva i cookie con lo stesso nome e li **sostituisce** invece di
duplicarli - non finisci con due valori diversi di `HIXSID`.

---

## `HIX_SetCookie` - low-level

Quando non sei in una action di route (ad esempio, dentro un middleware con
`oCtx`), usa la funzione con `oReq` esplicito:

```clipper
FUNCTION MyAppRememberMeMw( oCtx )
   LOCAL cToken := _GenerateRememberToken( oCtx )

   HIX_SetCookie( oCtx:oReq, "remember", cToken, 86400 * 30 )
RETURN .T.
```

È esattamente la stessa di `USetCookie`, ma riceve `oReq` come primo
parametro. `USetCookie` la chiama sotto il cofano con la request del
thread corrente.

---

## Pattern utili

### Login con sessione + remember-me

```clipper
FUNCTION _LoginAction()
   LOCAL hUser := _CheckCredentials( UPost("user"), UPost("pass") )

   IF hUser == NIL
      RETURN USendError( 401, "Credenziali non valide" )
   ENDIF

   USession():Set( "user_id", hUser["id"] )
   USession():Save()

   IF UPost( "remember", "" ) == "1"
      USetCookie( "remember", _MakeRememberToken( hUser ), 86400 * 30 )
   ENDIF

   URedirect( "/dashboard" )
RETURN NIL
```

### Logout - pulizia cookie

```clipper
FUNCTION _LogoutAction()
   USession():Destroy()              // fa scadere HIXSID
   USetCookie( "remember", "", -1 )  // cancella il remember-me

   URedirect( "/" )
RETURN NIL
```

### Preferenze UI (light/dark)

```clipper
oSrv:AddRoutePost( "ui.theme.set", "/ui/theme", {||
   LOCAL cTheme := UPost( "theme", "light" )

   IF AScan( { "light", "dark", "auto" }, cTheme ) == 0
      RETURN USendError( 400, "Tema non valido" )
   ENDIF

   USetCookie( "ui_theme", cTheme, 86400 * 365 )
   USendJson( { "ok" => .T., "theme" => cTheme } )
} )
```

### Lingua persistente

```clipper
FUNCTION MyAppLangMw( oCtx )
   LOCAL cLang := UCookie( "lang", "" )

   IF Empty( cLang )
      cLang := Left( UHeader( "accept-language", "es" ), 2 )
      USetCookie( "lang", cLang, 86400 * 365 )
   ENDIF

   oCtx:hData[ "lang" ] := cLang
RETURN .T.
```

---

## Errori comuni

| Sintomo | Causa |
|---|---|
| Il cookie non arriva al client | `USetCookie` dopo l'invio della response (`USendJson`/`URedirect`) |
| Il cookie arriva ma `UCookie` lo legge vuoto | Nome con case diverso - il confronto è case-sensitive |
| Il cookie arriva solo a volte | `Path` diverso o il client sta bloccando i cookie cross-site |
| `document.cookie` non lo vede in JS | `HttpOnly` lo impedisce - design corretto |
| POST da form esterno non invia il cookie | `SameSite=Lax` lo impedisce - design corretto |
| Il cookie scade al refresh | Hai passato `nMaxAge=0` (cookie di sessione) invece di un valore in secondi |

---

## Best practice

1. **Non memorizzare mai dati sensibili nei cookie.** Solo identificatori opachi
   (`HIXSID=abc...`). I dati veri vanno nella sessione server-side.
2. **`HttpOnly` e `SameSite` sempre.** HIX li imposta già - non disabilitarli
   senza un motivo chiaro.
3. **Tieni la dimensione sotto controllo.** I cookie vengono inviati in **ogni** request.
   Un cookie da 4KB × 30 request/secondo = banda sprecata.
4. **Firma i cookie se sensibili.** Se devi memorizzare qualcosa di "reale"
   (un ID utente, un ruolo), firma il valore con HMAC + `app_key`. Se il
   client lo manipola, la firma non corrisponderà.
5. **Fai scadere al logout.** Non basta distruggere la sessione
   server-side - devi anche inviare il cookie con `Max-Age=0` così il
   browser lo dimentica.
6. **Attento con `SameSite=Strict`.** Lax è di solito il punto dolce. Strict
   blocca i cookie sulla navigazione da siti esterni (inclusi i link) e
   rompe molti flussi.
