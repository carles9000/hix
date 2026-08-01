# ✔️ HIX Validator - Tutorial completo

El validador de **HIX** permite validar y limpiar los datos de entrada HTTP en tres fases
ordenadas: **cast** (conversion de tipo), **validacion** (reglas) y **sanitizacion**
(transformaciones de limpieza). Todo se encadena con una sintaxis de reglas en string
separadas por `|`.

---

## 1. Concepto basico

```clipper
LOCAL oVal := UValidateOrFail( {
   "name"  => "required|string|max:100",
   "email" => "required|string|email",
   "age"   => "required|integer|min:18"
} )
IF oVal == NIL ; RETURN NIL ; ENDIF   // ya respondio 422

cName  := oVal:Get( "name" )
cEmail := oVal:Get( "email" )
nAge   := oVal:Get( "age" )           // tipo N, no string
```

`UValidateOrFail` es el camino mas corto: ejecuta `Make()`, y si hay errores envia
automaticamente un JSON 422 y devuelve `NIL`. Si pasa, devuelve el objeto validador
con los valores ya convertidos al tipo correcto.

---

## 2. Fuentes de entrada

Cada helper captura los datos de entrada de una fuente distinta del request actual.

| Funcion | Fuente primaria | Route params `:var` |
|---|---|---|
| `UValidatePost(hRules)` | POST body: form-urlencoded primero, JSON como fallback | incluidos |
| `UValidateGet(hRules)` | Query string (`?key=val`) | incluidos |
| `UValidateJson(hRules)` | JSON body unicamente | incluidos |
| `UValidateOrFail(hRules)` | POST body — ejecuta Make() y responde 422 si falla | incluidos |
| `UValidateParams(hRules)` | Alias de `UValidateGet` (compatibilidad) | incluidos |

Todos aceptan un segundo parametro opcional `hSanitate` (ver seccion 6).

Todos los helpers fusionan siempre las variables de ruta (`:id`, `:slug`...) en
`hInput` despues de leer la fuente primaria. Si una misma clave existe en ambas
fuentes se lanza un error 500 para evidenciar el conflicto de nombres.

### UValidatePost vs UValidateJson

`UValidatePost` auto-detecta el formato: intenta leer form-urlencoded primero
y, si esta vacio, intenta JSON. Es el helper universal para endpoints que aceptan
ambos formatos.

`UValidateJson` lee exclusivamente el body como JSON. Si el body no es JSON
valido, `hInput` queda vacio y los campos `required` fallan con un 422 normal.
Usar cuando el endpoint es una API pura que exige JSON.

```clipper
// Endpoint que acepta form Y json
oVal := UValidatePost( hRules )

// API pura — solo JSON
oVal := UValidateJson( hRules )
IF ! oVal:Make()
   USendJson( { "errors" => oVal:GetErrors() }, 422 )
   RETURN NIL
ENDIF
```

### UValidateGet — query string y route params

`UValidateGet` fusiona la query string con las variables de ruta en un unico
hash. Cubra todos los casos de un endpoint GET:

```clipper
// GET /products?page=2&q=book  (sin :vars)
oVal := UValidateGet( { "page" => "optional|integer|min:1", "q" => "optional|string" } )

// GET /users/:id?expand=roles  (query + :id combinados)
oVal := UValidateGet( { "id" => "required|integer|positive", "expand" => "optional|string" } )

// POST /resource/:id con body JSON  (body + :id combinados)
oVal := UValidatePost( { "id" => "required|integer", "name" => "required|string" } )
```

---

## 3. Flujo completo con Make()

Cuando necesitas controlar la respuesta de error manualmente:

```clipper
FUNCTION _UpdateUser()
   LOCAL oVal, hData

   oVal := UValidatePost( {
      "name"  => "required|string|max:100",
      "email" => "required|string|email"
   } )

   IF ! oVal:Make()
      // opcion A - respuesta JSON estandar
      USendJson( { "errors" => oVal:GetErrors() }, 422 )
      RETURN NIL

      // opcion B - solo el primer error
      USendError( 422, oVal:GetFirstError() )
      RETURN NIL
   ENDIF

   hData := oVal:Validated()   // hash con todos los campos validados
   // ... guardar hData ...
   USendJson( { "ok" => .T. } )
RETURN NIL
```

---

## 4. Reglas de validacion

Las reglas se escriben separadas por `|` en un string. El orden importa: las reglas
se evaluan de izquierda a derecha y se detienen en el primer error del campo.

### Presencia

| Regla | Descripcion |
|---|---|
| `required` | El campo debe existir y no estar vacio |
| `optional` | Si el campo esta vacio, se omite sin error. Debe ir primero |

```clipper
// Campo requerido
"name" => "required|string"

// Campo opcional - solo valida si viene relleno
"nickname" => "optional|string|max:50"
```

### Tipos (tambien hacen cast, ver seccion 5)

| Regla | Descripcion |
|---|---|
| `string` | Convierte a string y hace `AllTrim` |
| `integer` | Convierte a entero; falla si no es numero entero |
| `numeric` / `decimal` | Convierte a numero; acepta decimales |
| `boolean` / `bool` | Convierte a logico `.T.`/`.F.` |
| `date` | Convierte a fecha Harbour desde `YYYY-MM-DD` |
| `positive` | El valor debe ser `N > 0` |

### Longitud y rango

| Regla | Se aplica a | Descripcion |
|---|---|---|
| `min:N` | string: longitud >= N / numero: valor >= N | |
| `max:N` | string: longitud <= N / numero: valor <= N | |
| `minlen:N` | string | longitud >= N (independiente del tipo) |
| `maxlen:N` | string | longitud <= N |
| `between:N,M` | string o numero | entre N y M (longitud o valor) |

```clipper
"title"    => "required|string|min:3|max:200"
"price"    => "required|numeric|min:0|max:9999"
"score"    => "required|integer|between:1,10"
```

### Formato

| Regla | Descripcion |
|---|---|
| `email` | Formato de email valido |
| `url` | Empieza por `http://` o `https://` |
| `ip` | IPv4 valida (cuatro octetos 0-255) |
| `regex:PATRON` | El valor debe coincidir con la expresion regular Harbour |

```clipper
"email"    => "required|string|email"
"web"      => "optional|string|url"
"subnet"   => "required|ip"
"code"     => "required|regex:[A-Z]{3}[0-9]{4}"
```

### Listas

| Regla | Descripcion |
|---|---|
| `in:a,b,c` | El valor debe estar en la lista |
| `notin:a,b,c` | El valor no debe estar en la lista |

```clipper
"role"     => "required|string|in:admin,editor,viewer"
"status"   => "required|string|notin:deleted,banned"
```

### Fechas

| Regla | Descripcion |
|---|---|
| `mindate:YYYY-MM-DD` | La fecha debe ser >= a la indicada |
| `maxdate:YYYY-MM-DD` | La fecha debe ser <= a la indicada |

```clipper
"birthday" => "required|date|maxdate:2010-01-01"
"start"    => "required|date|mindate:2026-01-01"
```

### Confirmacion

| Regla | Descripcion |
|---|---|
| `confirmed` | Busca en el input un campo `<campo>_confirmation` y lo compara |

```clipper
// El formulario debe enviar "password" y "password_confirmation"
"password" => "required|string|min:8|confirmed"
```

### Reglas con codeblock personalizado

Cuando ninguna regla estandar se ajusta, puedes pasar un codeblock directamente:

```clipper
oVal := UValidatePost( {
   "username" => { "required|string",
                   "Username",   // etiqueta para el mensaje de error
                   "",           // valor por defecto
                   {|v| iif( _UserExists(v), "El usuario ya existe", .T. ) }
                 }
} )
```

El codeblock recibe el valor y debe retornar:
- `.T.` si pasa la validacion
- `.F.` si falla (mensaje generico)
- `C` con el mensaje de error si falla (mensaje personalizado)

---

## 5. Cast de tipos (fase 1)

El cast convierte el valor del string HTTP al tipo Harbour correcto **antes** de validar.
Esto significa que despues de `Make()`, `oVal:Get("age")` devuelve un `N`, no un `C`.

| Regla de cast | Conversion |
|---|---|
| `string` | `AllTrim( UStr(v) )` |
| `integer` | `Val(v)` truncado a entero |
| `numeric` / `decimal` | `Val(v)` con punto decimal |
| `boolean` / `bool` | `"1","true","yes","on",".t."` → `.T.`; resto → `.F.` |
| `date` | `"YYYY-MM-DD"` o `"YYYY/MM/DD"` → fecha Harbour |

**El cast y la validacion se pueden combinar**:

```clipper
// "integer" convierte Y valida que sea entero
"qty"  => "required|integer|min:1|max:999"

// "boolean" convierte; sin required, un checkbox no enviado sera .F.
"active" => "boolean"
```

---

## 6. Sanitizacion (fase 3)

La sanitizacion se ejecuta **despues** de que todas las validaciones han pasado.
Se define en el segundo parametro del helper (`hSanitate`):

```clipper
oVal := UValidatePost(
   { "name" => "required|string", "bio" => "optional|string" },
   { "name" => "trim|upper",      "bio" => "trim|strip_tags" }
)
```

> **Nota:** Los tokens de sanitizacion escritos inline en la cadena de reglas
> (`"required|string|trim|upper"`) son ignorados por el motor. La unica forma
> de aplicar sanitizacion es mediante el segundo parametro `hSanitate`.
> El cast `string` aplica `AllTrim()` internamente, pero `upper`/`lower`/etc.
> requieren `hSanitate`.

### Transformaciones disponibles

| Regla | Descripcion |
|---|---|
| `trim` | `AllTrim()` - elimina espacios al inicio y al final |
| `ltrim` | `LTrim()` - solo espacios a la izquierda |
| `rtrim` | `RTrim()` - solo espacios a la derecha |
| `upper` | `Upper()` |
| `lower` | `Lower()` |
| `strip_tags` | Elimina etiquetas HTML (`<tag>` → `""`) |
| `slug` | Convierte a slug URL-safe: `"Mi Titulo"` → `"mi-titulo"` |
| `nl2br` | Convierte saltos de linea en `<br>` |
| `escape` | Codifica caracteres HTML (`<`, `>`, `&`, `"`) |
| `abs` | Valor absoluto de un numero |
| `round:N` | Redondea un numero a N decimales |

```clipper
"title"   => "required|string|trim|slug"      // "Mi Articulo!" -> "mi-articulo"
"content" => "required|string|trim|strip_tags"
"price"   => "required|numeric|abs|round:2"
"email"   => "required|string|trim|lower|email"
```

---

## 7. Marcadores especiales

### `field` y `escapedfield`

Marcan los campos que deben incluirse en `oVal:DataFields()`. Util para rellenar
formularios HTML tras un error de validacion.

```clipper
oVal := UValidatePost( {
   "name"  => "required|string|max:100|field",
   "email" => "required|string|email|escapedfield"   // HTML-encoded
} )

// Si la validacion falla, los datos originales estan disponibles
hData := oVal:DataFields()  // { "name" => "Carles", "email" => "c&lt;a&gt;@..." }
```

### `resume`

Marca campos que se deben incluir en `oVal:Resume()`. Se usa para re-rellenar formularios
devolviendo los datos (ya casteados) al template incluso cuando hay error.

```clipper
"name"  => "required|string|max:100|resume"
"email" => "required|string|email|resume"

// Resume incluye los campos marcados con el valor ya convertido al tipo correcto.
// Sin marcadores resume, Resume() devuelve el hash de input original sin convertir.
hResume := oVal:Resume()
```

---

## 8. Leer los datos validados

Despues de un `Make()` exitoso:

| Metodo | Descripcion |
|---|---|
| `oVal:Get(cKey)` | Valor de un campo; `NIL` si no existe |
| `oVal:Get(cKey, xDef)` | Valor de un campo con default |
| `oVal:Validated()` | Hash completo con todos los campos validados |
| `oVal:Validated(aFields)` | Hash filtrado a los campos indicados |
| `oVal:DataFields()` | Hash de los campos marcados con `field`/`escapedfield` |
| `oVal:Resume()` | Hash para re-rellenar formularios (ver marcador `resume`) |

```clipper
// Obtener campos individuales
cName  := oVal:Get( "name" )
nAge   := oVal:Get( "age", 0 )

// Obtener todos los campos validados
hAll   := oVal:Validated()

// Obtener solo los campos que interesan
hSaved := oVal:Validated( { "name", "email", "age" } )
```

---

## 9. Gestionar errores

| Metodo | Retorna | Descripcion |
|---|---|---|
| `oVal:Passes()` | `L` | `.T.` si no hay errores |
| `oVal:Fails()` | `L` | `.T.` si hay algún error |
| `oVal:IsValid()` | `L` | Alias de `Passes()` |
| `oVal:GetErrors()` | `H` | Hash `{ "campo" => "mensaje" }` |
| `oVal:GetFirstError()` | `C` | Mensaje del primer error |
| `oVal:GetErrorsJson()` | `C` | `GetErrors()` serializado como JSON |
| `oVal:GetErrorsTxt()` | `C` | Tabla HTML con los errores |
| `oVal:SendErrors(nStatus)` | - | Responde JSON `{ errors }` con el status indicado |
| `oVal:Formatter()` | `H` | Hash `{ "success", "errors" }` listo para JSON |

```clipper
// Respuesta JSON estandar de errores
IF oVal:Fails()
   USendJson( oVal:Formatter(), 422 )
   RETURN NIL
ENDIF

// Solo el primer error (para respuestas simples)
IF oVal:Fails()
   USendError( 422, oVal:GetFirstError() )
   RETURN NIL
ENDIF

// Errores por campo (para AJAX con feedback por campo)
IF oVal:Fails()
   USendJson( { "errors" => oVal:GetErrors() }, 422 )
   RETURN NIL
ENDIF
```

---

## 10. Etiquetas y defaults en los campos

La regla de un campo puede ser un array de hasta 4 elementos:

```
{ "reglas", "Etiqueta", valorDefault, codeblock }
```

```clipper
oVal := UValidatePost( {
   "name"  => { "required|string|max:100", "Nombre completo" },
   "age"   => { "required|integer|min:18", "Edad", 0 },
   "token" => { "required|string", "Token", NIL,
                {|v| iif( HIX_TokenValid(v, 3600), .T., "Token expirado" ) }
              }
} )
```

- El segundo elemento es la etiqueta que aparece en los mensajes de error.
- El tercero es el valor por defecto cuando el campo no existe en el input.
- El cuarto es un codeblock de validacion personalizado.

---

## 11. Validar un solo valor

`UValidatorOne` valida un unico valor sin necesidad de construir un hash:

```clipper
oVal := UValidatorOne( "Email", cEmail, "required|string|email" )
IF oVal:Fails()
   USendError( 422, oVal:GetFirstError() )
   RETURN NIL
ENDIF
```

---

## 12. Anadir campos sobre la marcha

Puedes enriquecer un validador despues de crearlo con `Add()`:

```clipper
oVal := UValidatePost( { "name" => "required|string" } )
oVal:Add( { "extra" => "optional|integer" }, UGet("extra") )
oVal:Make()
```

---

## 13. Patrones completos

### API REST - crear recurso

```clipper
FUNCTION _ProductCreate()
   LOCAL oVal, hProd

   oVal := UValidateOrFail( {
      "name"        => { "required|string|max:200|trim",     "Nombre" },
      "price"       => { "required|numeric|min:0|round:2",   "Precio" },
      "stock"       => { "required|integer|min:0",           "Stock" },
      "category_id" => { "required|integer|positive",        "Categoria" },
      "active"      => { "boolean",                          "Activo" }
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   hProd := oVal:Validated( { "name", "price", "stock", "category_id", "active" } )
   // ... insertar hProd en BD ...

   USendJson( { "id" => nNewId }, 201 )
RETURN NIL
```

### Formulario HTML con re-llenado

```clipper
FUNCTION _RegisterPost()
   LOCAL oVal

   oVal := UValidatePost( {
      "username" => "required|string|min:3|max:50|trim|lower|resume",
      "email"    => "required|string|email|trim|lower|resume",
      "password" => "required|string|min:8|confirmed"
   } )

   IF ! oVal:Make()
      // guardar flash con errores y datos del formulario
      LOCAL oFlash := UFlash( "register" )
      oFlash:Set( "errors",  oVal:GetErrors() )
      oFlash:Set( "data",    oVal:Resume() )
      oFlash:Save()
      URedirect( "/register" )
      RETURN NIL
   ENDIF

   // ... crear usuario ...
   URedirect( "/dashboard" )
RETURN NIL
```

```clipper
FUNCTION _RegisterGet()
   LOCAL oFlash  := UFlash( "register" )
   LOCAL hErrors := oFlash:Get( "errors", {=>} )
   LOCAL hData   := oFlash:Get( "data",   {=>} )
   USendView( "auth/register.view.html", {
      "hErrors"   => hErrors,
      "cUsername" => hb_HGetDef( hData, "username", "" ),
      "cEmail"    => hb_HGetDef( hData, "email",    "" )
   } )
RETURN NIL
```

### Validar query string para busqueda paginada

```clipper
FUNCTION _ProductList()
   LOCAL oVal, nPage, nLimit, cQ

   oVal := UValidateGet( {
      "page"  => { "optional|integer|min:1",    "Pagina",  1 },
      "limit" => { "optional|integer|between:1,100", "Limite", 20 },
      "q"     => { "optional|string|max:200|trim", "Busqueda", "" }
   } )
   oVal:Make()   // nunca falla (todos opcionales con defaults)

   nPage  := oVal:Get( "page" )
   nLimit := oVal:Get( "limit" )
   cQ     := oVal:Get( "q" )

   // ... consultar BD ...
   USendJson( { "page" => nPage, "limit" => nLimit, "results" => aResults } )
RETURN NIL
```

### Validacion con regla personalizada contra BD

```clipper
FUNCTION _ChangeEmail()
   LOCAL oVal

   oVal := UValidateOrFail( {
      "email" => { "required|string|email|trim|lower",
                   "Email",
                   "",
                   {|v| iif( _EmailTaken(v), "El email ya esta registrado", .T. ) }
                 }
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   cEmail := oVal:Get( "email" )
   // ... actualizar email ...
   USendJson( { "ok" => .T. } )
RETURN NIL

STATIC FUNCTION _EmailTaken( cEmail )
   // consultar BD y retornar .T. si el email ya existe
RETURN .F.
```

---

## 14. Referencia rapida de reglas

```
-- Presencia --
required       optional

-- Tipos / cast --
string         integer        numeric/decimal
boolean/bool   date           positive

-- Rango --
min:N          max:N
minlen:N       maxlen:N
between:N,M

-- Formato --
email          url            ip
regex:PATRON

-- Listas --
in:a,b,c       notin:a,b,c

-- Fechas --
mindate:YYYY-MM-DD   maxdate:YYYY-MM-DD

-- Cross-field --
confirmed      (campo_confirmation debe coincidir)

-- Sanitizacion (inline o en hSanitate) --
trim    ltrim   rtrim   upper   lower
strip_tags      slug    nl2br   escape
abs             round:N

-- Marcadores --
field          escapedfield   resume
```
