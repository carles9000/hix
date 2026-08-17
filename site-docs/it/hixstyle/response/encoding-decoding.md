# 🔤 Encoding / Decoding

Quando i dati attraversano la barriera tra server e client (HTML, URL, JSON, header, body multipart), devi **codificare** o **decodificare** i caratteri speciali. Se lo fai nel modo sbagliato:

- Un `<script>` di un utente finisce per essere eseguito in un altro browser → **XSS**.
- Una `&` in un URL rompe la query string.
- Una `ñ` codificata male appare come `Ã±` sul client.
- Un binario senza base64 corrompe il JSON.

HIX espone helper per ogni caso tipico e riusa le funzioni standard di Harbour dove ha senso.

---

## HTML

### `UHtmlEncode( cText )`

Effettua l'escape dei 5 caratteri pericolosi: `& < > " '`.

```clipper
UHtmlEncode( '<script>alert("x")</script>' )
// → "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"

UHtmlEncode( "Pérez & Sons" )
// → "Pérez &amp; Sons"      (& → &amp;)
```

#### Quando usarlo

Sempre quando inserisci **input utente** dentro HTML:

```clipper
LOCAL cName := UPost( "name", "" )

// MALE - l'utente può iniettare <script>
USendHtml( "<h1>Ciao " + cName + "</h1>" )

// BENE - escaped
USendHtml( "<h1>Ciao " + UHtmlEncode( cName ) + "</h1>" )
```

> Nei template `.view.html` il motore **non esegue l'escape automaticamente** - la
> regola `{{ expr }}` valuta l'espressione e la stampa così com'è. Se ciò che ci metti
> viene dall'utente, chiama `UHtmlEncode` dentro l'espressione:
> `{{ UHtmlEncode( cName ) }}`.

### Caratteri consentiti senza escape

- Lettere e cifre.
- Spazi, punteggiatura normale (`. , ; : ! ?`).
- Caratteri accentati (`ñ á é í ó ú`) - purché la pagina sia in UTF-8.

### L'inverso - decodifica entità HTML

Non c'è un helper specifico in HIX. Harbour standard può farlo con
`hb_StrReplace` invertendo l'hash, ma **non dovresti averne bisogno** -
se il tuo DB memorizza testo puro, le entità già escaped non appariranno.

---

## URL

Per codificare valori nelle query string o nei path, usa le funzioni Harbour:

```clipper
hb_URLEncode( "Pérez & Sons" )
// → "P%C3%A9rez%20%26%20Sons"

hb_URLDecode( "P%C3%A9rez%20%26%20Sons" )
// → "Pérez & Sons"
```

### Quando usarlo

Quando costruisci URL con dati dinamici:

```clipper
LOCAL cName := "Pérez & Sons"
LOCAL cUrl  := "/search?q=" + hb_URLEncode( cName )
URedirect( cUrl )
```

> HIX **decodifica automaticamente** `UGet()` / `UPost()` / `UParam()` -
> non c'è nient'altro da fare in lettura.

---

## JSON

### Encode → stringa

```clipper
hb_jsonEncode( hData )
```

Converte hash/array/scalare in una stringa JSON valida. È quello che
`USendJson` usa internamente:

```clipper
USendJson( { "ok" => .T., "user" => "Carles" } )
// equivalente a:
USetMime( "json" )
UWrite( hb_jsonEncode( { "ok" => .T., "user" => "Carles" } ) )
```

#### Tipi supportati

| Harbour | JSON |
|---|---|
| Hash `{=>}` | object `{...}` |
| Array `{}` | array `[...]` |
| Stringa | `"..."` |
| Numero | number |
| `.T.` / `.F.` | `true` / `false` |
| `NIL` | `null` |
| Data | `"YYYY-MM-DDTHH:MM:SSZ"` ISO 8601 |

### Decode → hash/array

```clipper
hb_jsonDecode( cJson, @xData )
```

Ritorna quanti caratteri ha consumato (0 se fallito). Più pratico da
un'action:

```clipper
hData := UJson()    // NIL se il body non è JSON valido
```

```clipper
FUNCTION _ApiCreate()
   LOCAL hBody := UJson()

   IF hBody == NIL
      RETURN USendError( 400, "Il body non è JSON" )
   ENDIF

   USendJson( { "received" => hBody } )
RETURN NIL
```

---

## UTF-8

### Conversione esplicita

| Funzione Harbour | Cosa fa |
|---|---|
| `hb_StrToUtf8( c )` | Converte dalla codepage locale → UTF-8 |
| `hb_Utf8ToStr( c )` | Converte UTF-8 → codepage locale |
| `hb_cdpSelect( "UTF8" )` | Cambia la codepage del processo |

```clipper
LOCAL cTexto := "Niño"    // codepage locale (CP1252 / ISO-8859-1)
LOCAL cUtf8  := hb_StrToUtf8( cTexto )    // "Ni\xc3\xb1o"
```

### Quando conta

- **HIX lavora in UTF-8 di default** - le stringhe che arrivano dal body HTTP,
  URL, header, JSON, sono già in UTF-8.
- Se leggi dati da un vecchio DBF con codepage locale (CP850, CP1252),
  convertili con `hb_StrToUtf8` prima di metterli nella risposta.
- `UDbf:Row( lToStringWeb := .T. )` esegue già la conversione a UTF-8 se passi
  `lToUtf8` nel costruttore. Vedi [UDbf](../models/udbf.md).

```clipper
LOCAL oDbf := UDbf():New( "customers", .T., .T. )  // lToUtf8=.T.
oDbf:Open()
USendJson( oDbf:Row( .T. ) )    // arriva già in UTF-8
```

---

## Base64

Per dati binari dentro JSON, URL o cookie firmati:

```clipper
hb_Base64Encode( cBinary )
// → "SGVsbG8gV29ybGQ="

hb_Base64Decode( cEncoded )
// → "Hello World"
```

### Esempio - immagine embed in JSON

```clipper
LOCAL cBytes := hb_MemoRead( "logo.png" )

USendJson( { ;
   "name"      => "logo.png",       ;
   "mime"      => "image/png",      ;
   "data_b64"  => hb_Base64Encode( cBytes ) ;
} )
```

### Esempio - cookie firmato

```clipper
LOCAL cPayload := hb_jsonEncode( { "uid" => 42, "exp" => _Now() + 3600 } )
LOCAL cSig     := hb_HMAC( cPayload, "chiave-segreta" )
LOCAL cToken   := hb_Base64Encode( cPayload + "." + cSig )

USetCookie( "auth", cToken, 3600 )
```

---

## Base64 URL-safe

Per token negli URL, **senza** `+ / =`:

```clipper
LOCAL cToken := hb_Base64Encode( cBin )

// Converti a URL-safe
cToken := StrTran( cToken, "+", "-" )
cToken := StrTran( cToken, "/", "_" )
cToken := StrTran( cToken, "=", ""  )    // niente padding
```

Questa è la convenzione usata da JWT. Per invertirla, annulla gli `StrTran` e
ri-aggiungi il padding fino a un multiplo di 4.

---

## Confronto rapido

| Caso | Usa |
|---|---|
| Inserisci testo in HTML | `UHtmlEncode` |
| Costruisci URL con dati | `hb_URLEncode` |
| Rispondi con JSON | `USendJson` (chiama `hb_jsonEncode`) |
| Leggi JSON dal body | `UJson()` |
| Testo a UTF-8 | `hb_StrToUtf8` |
| Binario in stringa ASCII | `hb_Base64Encode` |
| Firma hash | `hb_HMAC` / `hb_MD5` / `hb_SHA256` |

---

## Errori comuni

| Sintomo | Causa |
|---|---|
| `Ã±` nel browser | Il server ha inviato CP1252 ma la pagina dichiara `charset=utf-8` |
| `<script>` eseguito da input utente | Non hai chiamato `UHtmlEncode` prima dell'inlining |
| `%20` appare letterale in un URL | È stato codificato due volte (`hb_URLEncode` su dati già codificati) |
| JSON con `"\u00f1"` invece di `ñ` | Decodifica client sbagliata - JSON con `\uXXXX` è valido ed equivalente |
| Cookie binario corrotto | Hai dimenticato `hb_Base64Encode` - il cookie non accetta `\0` o `;` grezzi |

---

## Best practice

1. **Fai l'escape in output, non in input.** Memorizza il testo grezzo nel DB.
   Fai l'escape solo quando costruisci l'output HTML / URL / JSON.
2. **Non mescolare le codifiche.**
3. **Non reinventare l'escape.** `UHtmlEncode` copre i 5 caratteri standard OWASP
   - non aggiungerne altri a mano.
4. **JSON è già sicuro.** `hb_jsonEncode` esegue l'escape correttamente - non
   ti serve `UHtmlEncode` su dati che passano già per JSON.
5. **Base64 ≠ crittografia.** Base64 cambia solo la rappresentazione; qualsiasi
   attaccante può decodificarlo. Per i segreti, cripta davvero.
