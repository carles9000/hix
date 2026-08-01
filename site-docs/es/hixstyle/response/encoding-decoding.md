# 🔤 Encoding / Decoding

Cuando los datos cruzan la barrera entre el servidor y el cliente
(HTML, URL, JSON, header, body multipart), hay que **encodear** o
**decodear** caracteres especiales. Si lo haces mal:

- `<script>` del usuario acaba ejecutándose en otro navegador → **XSS**.
- Una `&` en una URL rompe la query string.
- Un `ñ` mal codificado sale como `Ã±` en el cliente.
- Un binario sin base64 corrompe el JSON.

HIX expone helpers para cada caso típico y reutiliza los de Harbour
estándar donde tiene sentido.

---

## HTML

### `UHtmlEncode( cText )`

Escapa los 5 caracteres peligrosos: `& < > " '`.

```clipper
UHtmlEncode( '<script>alert("x")</script>' )
// → "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"

UHtmlEncode( "Pérez & Sons" )
// → "Pérez &amp; Sons"      (& → &amp;)
```

#### Cuándo usarlo

Siempre que insertes **input del usuario** dentro de HTML:

```clipper
LOCAL cName := UPost( "name", "" )

// MAL - el usuario puede inyectar <script>
USendHtml( "<h1>Hola " + cName + "</h1>" )

// BIEN - escapado
USendHtml( "<h1>Hola " + UHtmlEncode( cName ) + "</h1>" )
```

> En templates `.view.html`, el motor **no escapa automáticamente** - la
> regla `{{ expr }}` evalúa la expresión y la imprime tal cual. Si lo
> que metes viene del usuario, llama `UHtmlEncode` dentro de la expresión:
> `{{ UHtmlEncode( cName ) }}`.

### Caracteres permitidos sin escapar

- Letras y dígitos.
- Espacios, puntuación normal (`. , ; : ! ?`).
- Acentuados (`ñ á é í ó ú`) - siempre que la página vaya en UTF-8.

### Lo inverso - decodear HTML entities

No hay helper específico en HIX. Harbour estándar puede hacerlo con
`hb_StrReplace` invirtiendo el hash, pero **no debería hacer falta** -
si tu BD guarda texto plano, no aparecerán entities ya escapados.

---

## URL

Para encodear valores en query strings o paths, usar las funciones de
Harbour:

```clipper
hb_URLEncode( "Pérez & Sons" )
// → "P%C3%A9rez%20%26%20Sons"

hb_URLDecode( "P%C3%A9rez%20%26%20Sons" )
// → "Pérez & Sons"
```

### Cuándo usarlo

Cuando construyas URLs con datos dinámicos:

```clipper
LOCAL cName := "Pérez & Sons"
LOCAL cUrl  := "/search?q=" + hb_URLEncode( cName )
URedirect( cUrl )
```

> HIX **decodea automáticamente** los `UGet()` / `UPost()` / `UParam()` -
> no hay que hacer nada extra al leer.

---

## JSON

### Encodear → string

```clipper
hb_jsonEncode( hData )
```

Convierte hash/array/escalar a un string JSON válido. Es lo que usa
`USendJson` por dentro:

```clipper
USendJson( { "ok" => .T., "user" => "Carles" } )
// equivale a:
USetMime( "json" )
UWrite( hb_jsonEncode( { "ok" => .T., "user" => "Carles" } ) )
```

#### Tipos soportados

| Harbour | JSON |
|---|---|
| Hash `{=>}` | objeto `{...}` |
| Array `{}` | array `[...]` |
| String | `"..."` |
| Número | número |
| `.T.` / `.F.` | `true` / `false` |
| `NIL` | `null` |
| Date | `"YYYY-MM-DDTHH:MM:SSZ"` ISO 8601 |

### Decodear → hash/array

```clipper
hb_jsonDecode( cJson, @xData )
```

Devuelve cuántos caracteres consumió (0 si falló). Más práctico desde
una acción:

```clipper
hData := UJson()    // NIL si el body no es JSON válido
```

```clipper
FUNCTION _ApiCreate()
   LOCAL hBody := UJson()

   IF hBody == NIL
      RETURN USendError( 400, "Body no es JSON" )
   ENDIF

   USendJson( { "received" => hBody } )
RETURN NIL
```

---

## UTF-8

### Conversión explícita

| Función Harbour | Qué hace |
|---|---|
| `hb_StrToUtf8( c )` | Convierte de codepage local → UTF-8 |
| `hb_Utf8ToStr( c )` | Convierte UTF-8 → codepage local |
| `hb_cdpSelect( "UTF8" )` | Cambia codepage del proceso |

```clipper
LOCAL cTexto := "Niño"    // codepage local (CP1252 / ISO-8859-1)
LOCAL cUtf8  := hb_StrToUtf8( cTexto )    // "Ni\xc3\xb1o"
```

### Cuándo importa

- **HIX por defecto trabaja en UTF-8** - strings que vienen del body
  HTTP, URLs, headers, JSON, ya están en UTF-8.
- Si lees datos de un DBF antiguo con codepage local (CP850, CP1252),
  conviértelo con `hb_StrToUtf8` antes de meterlo en el response.
- `UDbf:Row( lToStringWeb := .T. )` ya hace la conversión a UTF-8 si le
  pasas `lToUtf8` en el constructor. Ver [UDbf](../models/udbf.md).

```clipper
LOCAL oDbf := UDbf():New( "customers", .T., .T. )  // lToUtf8=.T.
oDbf:Open()
USendJson( oDbf:Row( .T. ) )    // ya viene en UTF-8
```

---

## Base64

Para datos binarios dentro de JSON, URL o cookies firmadas:

```clipper
hb_Base64Encode( cBinary )
// → "SGVsbG8gV29ybGQ="

hb_Base64Decode( cEncoded )
// → "Hello World"
```

### Ejemplo - embed de imagen en JSON

```clipper
LOCAL cBytes := hb_MemoRead( "logo.png" )

USendJson( { ;
   "name"      => "logo.png",       ;
   "mime"      => "image/png",      ;
   "data_b64"  => hb_Base64Encode( cBytes ) ;
} )
```

### Ejemplo - cookie firmada

```clipper
LOCAL cPayload := hb_jsonEncode( { "uid" => 42, "exp" => _Now() + 3600 } )
LOCAL cSig     := hb_HMAC( cPayload, "secret-key" )
LOCAL cToken   := hb_Base64Encode( cPayload + "." + cSig )

USetCookie( "auth", cToken, 3600 )
```

---

## URL-safe Base64

Para tokens en URLs, **sin** `+ / =`:

```clipper
LOCAL cToken := hb_Base64Encode( cBin )

// Convertir a URL-safe
cToken := StrTran( cToken, "+", "-" )
cToken := StrTran( cToken, "/", "_" )
cToken := StrTran( cToken, "=", ""  )    // sin padding
```

Es la convención que usa JWT. Para revertirlo, deshacer los `StrTran` y
re-añadir padding hasta múltiplo de 4.

---

## Comparativa rápida

| Caso | Usa |
|---|---|
| Insertar texto en HTML | `UHtmlEncode` |
| Construir URL con datos | `hb_URLEncode` |
| Responder JSON | `USendJson` (llama `hb_jsonEncode`) |
| Leer JSON del body | `UJson()` |
| Texto a UTF-8 | `hb_StrToUtf8` |
| Binario en string ASCII | `hb_Base64Encode` |
| Hash firma | `hb_HMAC` / `hb_MD5` / `hb_SHA256` |

---

## Errores típicos

| Síntoma | Causa |
|---|---|
| `Ã±` en el browser | El servidor mandó CP1252 pero la página dice `charset=utf-8` |
| `<script>` se ejecuta del input del usuario | No llamaste `UHtmlEncode` antes de embutir |
| `%20` aparece literal en una URL | Lo encodearon dos veces (`hb_URLEncode` sobre algo ya encodeado) |
| JSON con `"\u00f1"` en vez de `ñ` | Decodificación incorrecta del cliente - el JSON con `\uXXXX` es válido y equivalente |
| Cookie binaria corrupta | Olvidaste `hb_Base64Encode` - la cookie no acepta `\0` ni `;` directo |

---

## Buenas prácticas

1. **Escapa al output, no al input.** Guarda en BD el texto tal cual.
   Solo escapa cuando construyas el HTML / URL / JSON de salida.
2. **No mezcles encodings.** 
3. **No reinventes los escapes.** `UHtmlEncode` cubre los 5 caracteres
   estándar de OWASP - no añadas más a mano.
4. **JSON ya es seguro.** `hb_jsonEncode` escapa correctamente - no
   necesitas `UHtmlEncode` sobre datos que ya van por JSON.
5. **Base64 ≠ encriptación.** Base64 solo cambia la representación;
   cualquier atacante lo decodea. Para secretos, encripta de verdad.


