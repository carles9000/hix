# 📦 Contexto - `oCtx`

Cuando **HIX** ejecuta un middleware, le pasa siempre un único parámetro: **`oCtx`**.
Es el **contexto de la petición** - una instancia de `THixContext` que agrupa todo
lo que un middleware necesita para inspeccionar la request, comunicarse con otros
middlewares de la cadena y decidir qué debe pasar a continuación.

```clipper
FUNCTION MW_ApiKey( oCtx )
   // oCtx es el contexto - vive durante toda la cadena de middleware
   // y desaparece cuando termina la petición
RETURN .T.
```

---

## ¿Por qué existe `oCtx` y no solo `oReq`?

Un middleware raramente actúa solo. En una cadena típica (rate limit → JWT →
roles → acción) cada middleware necesita **compartir información** con los
siguientes: el payload del JWT, la sesión del usuario, un flag de auditoría…

`oCtx` es ese "espacio compartido". Es la bandeja que va pasando de mano en mano
por toda la cadena, y al llegar a la acción de la ruta sigue disponible.

---

## Propiedades principales

| Propiedad | Tipo | Descripción |
|-----------|------|-------------|
| `oCtx:oReq` | `THixRequest` | Objeto request de la petición actual. |
| `oCtx:hData` | Hash | Diccionario libre para compartir datos entre middlewares. |
| `oCtx:lHandled` | Lógico | Márcalo `.T.` cuando el middleware ya haya respondido. |
| `oCtx:cScope` | String | Metadato libre asignado a la ruta (accesible desde MW). |
| `oCtx:cOnFail` | String | URL de redirección si el middleware devuelve `.F.` (opcional). |

---

## `oCtx:oReq` - la request

Es el objeto `THixRequest` de la petición en curso. Podemos leer cabeceras,
cookies, body, query params, etc. desde ahí:

```clipper
LOCAL cKey := oCtx:oReq:Header( "X-Api-Key", "" )
LOCAL cSid := oCtx:oReq:Cookie( "hix_sess", "" )
LOCAL cIp  := oCtx:oReq:IP()
```

### Alternativa recomendada - helpers `U*`

HIX enlaza automáticamente el request al hilo actual antes de ejecutar cada
middleware, así que **también funcionan los helpers `U*`** dentro del middleware,
que suelen ser más cortos y consistentes con el código de las acciones:

```clipper
FUNCTION MW_ApiKey( oCtx )

   // Ambas líneas son equivalentes:
   LOCAL cKey := oCtx:oReq:Header( "X-Api-Key", "" )
   LOCAL cKey := UHeader( "X-Api-Key", "" )    // más corto y legible

   IF cKey != "clave-secreta-123"
      USendError( 401, "API Key invalida" )
      RETURN .F.
   ENDIF

RETURN .T.
```

| Estilo con `oCtx:oReq` | Estilo con `U*` |
|-------------------------|-----------------|
| `oCtx:oReq:Header( c, x )` | `UHeader( c, x )` |
| `oCtx:oReq:Cookie( c, x )` | `UCookie( c, x )` |
| `oCtx:oReq:Body()` | `UBody()` |
| `oCtx:oReq:IP()` | `UIP()` |
| `oCtx:oReq:Method()` | `UMethod()` |

Escoge el estilo que prefieras - HIX no impone ninguno. La convención actual es
usar `U*` dentro de acciones y middlewares para mantener el código breve.

---

## `oCtx:hData` - compartir datos entre middlewares

`hData` es un hash libre que **se propaga por toda la cadena** de middleware y
llega intacto hasta la acción de la ruta. Es el canal oficial para pasar
información entre eslabones.

Claves convencionales que ya usan los middlewares del sistema:

| Clave | Puesta por | Contenido |
|-------|------------|-----------|
| `oCtx:hData["jwt"]` | `HixMwJwt` | Hash con el payload del token JWT verificado. |
| `oCtx:hData["session"]` | `HixMwSession` | Hash con los datos de la sesión activa. |
| `oCtx:hData["_sid"]` | `HixMwSession` | ID de la sesión activa. |
| `oCtx:hData["user"]` | Middleware de auth | Objeto/hash del usuario autenticado. |

Ejemplo - un middleware de roles que lee lo que ya dejó `HixMwJwt`:

```clipper
FUNCTION MW_RequireAdmin( oCtx )

   LOCAL hJwt := hb_HGetDef( oCtx:hData, "jwt", NIL )

   IF hJwt == NIL .OR. hb_HGetDef( hJwt, "role", "" ) != "admin"
      USendError( 403, "Solo administradores" )
      RETURN .F.
   ENDIF

RETURN .T.
```

Puedes añadir tus propias claves sin tocar nada del sistema:

```clipper
oCtx:hData["mi_flag"]   := .T.
oCtx:hData["tenant_id"] := 42
```

---

## `oCtx:lHandled` - "ya he respondido, no ejecutes la acción"

Cuando un middleware decide **cortar la cadena** (rechazar la petición) debe:

1. Enviar la respuesta al cliente.
2. Marcar `oCtx:lHandled := .T.` para que el dispatcher sepa que ya se ha
   respondido y no ejecute nada más.
3. Devolver `.F.`.

Si usas los helpers `USendError` / `USendJson` / `URedirect`, **ya marcan
`lHandled` internamente** - no hace falta hacerlo a mano.

```clipper
FUNCTION MW_ApiKey( oCtx )

   IF UHeader( "X-Api-Key", "" ) != "clave-secreta-123"
      USendError( 401, "API Key invalida" )   // marca lHandled
      RETURN .F.
   ENDIF

RETURN .T.
```

---

## `oCtx:cScope` - metadato de la ruta

Cuando registras una ruta puedes adjuntarle un string libre como `scope`. Ese
valor llega al middleware por `oCtx:cScope` y sirve para variar el comportamiento
según el "grupo lógico" al que pertenezca la ruta.

```clipper
oSrv:AddRouteGet( "admin.users", "/admin/users", 'users.prg', "MW_Log", "admin" )
oSrv:AddRouteGet( "api.stats",   "/api/stats",   'stats.prg', "MW_Log", "public" )
```

```clipper
FUNCTION MW_Log( oCtx )

   IF oCtx:cScope == "admin"
      l( "[AUDIT] " + UMethod() + " " + UPath() + " por " + UIP() )
   ENDIF

RETURN .T.
```

---

## `oCtx:cOnFail` - redirección de fallback

Ruta a la que redirigir automáticamente cuando el middleware devuelve `.F.`
(opcional). Útil, por ejemplo, para mandar a `/login` cualquier ruta que falle
la autenticación sin repetir la lógica en cada middleware.

---

## Resumen

- `oCtx` es el **contexto de la petición**, único parámetro que recibe todo middleware.
- `oCtx:oReq` da acceso al request; alternativamente puedes usar los helpers `U*`.
- `oCtx:hData` es el hash **compartido** entre middlewares y la acción.
- `oCtx:lHandled := .T.` cuando cortas la cadena; los helpers `USend*` ya lo hacen.
- `oCtx:cScope` es un metadato libre de la ruta.
- `oCtx:cOnFail` define la URL de redirección si el middleware rechaza.
