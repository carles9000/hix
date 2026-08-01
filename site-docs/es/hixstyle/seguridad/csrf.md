# 🛑 CSRF — Cross-Site Request Forgery

Un atacante puede engañar al navegador de un usuario logueado para que
envíe un request "real" (con la cookie de sesión incluida) a tu sitio.
Como la cookie viaja en cada request automáticamente, el servidor no
distingue el formulario legítimo del falso.

Los **tokens CSRF** evitan esto: cada formulario incluye un token secreto
que solo conoce la página real. Si el POST llega sin token o con uno
inválido → **403 Forbidden**.

```
GET  /edit/42          <input type="hidden" name="_csrf" value="ABCxyz...">
POST /edit/42          _csrf=ABCxyz...  ->  middleware compara y deja pasar
POST /edit/42 (forge)  sin _csrf       ->  middleware rechaza con 403
```

---

## Dos sabores en HIX

HIX trae **dos** middlewares CSRF. Cubren escenarios distintos:

| Middleware | Estado | Necesita sesión | Caso de uso |
|---|---|---|---|
| **`HIX_MwCsrf`** | statefull | ✅ Sí | El token vive en la sesión. Pipeline web tradicional. |
| **`HIX_MwCsrfCheck`** | stateless (HMAC) | ❌ No | El token está firmado con `app_key`. Funciona sin sesión activa. |

> Fenix usa **`HIX_MwCsrfCheck`** porque permite incluir el token CSRF
> incluso en formularios públicos (login) donde aún no hay sesión iniciada.

---

## Setup

### Desde código

```clipper
HIX_MwCsrfSetup( ;
   "/login",         ;   // cRedirect — URL al fallar; "" -> JSON 403
   "x-csrf-token",   ;   // header HTTP con el token
   "_csrf",          ;   // campo de form con el token
   "mi_clave_app",   ;   // secret HMAC (guardado como app_key)
   0 )                   // nLapsus — TTL en segundos; 0 = sin expiración
```

### Convención Fenix — `www/middlewares/config.json`

```json
{
  "setup": {
    "csrf": {
      "redirect": "/login"
    }
  }
}
```

---

## `HIX_MwCsrfCheck` — stateless (Fenix)

Es el patrón que Fenix usa en cada formulario. El token va firmado con
`app_key` y se valida sin tocar la sesión:

```clipper
// www/middlewares/myapplogin.prg — para forms públicos
FUNCTION MyAppLogin( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"    ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()

// www/middlewares/myappauthedit.prg — para forms autenticados
FUNCTION MyAppAuthEdit( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"    ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"     ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()
```

Y las rutas:

```json
{ "name": "sys.auth",         "url": "/auth",                "method": "POST",
  "action": "controllers/auth.prg",
  "middleware": "MyAppLogin" }

{ "name": "customer.update",  "url": "/customer/:id/edit",   "method": "POST",
  "action": "controllers/masters/update@customer.prg",
  "middleware": "MyAppAuthEdit", "scope": "customers:edit" }
```

### En el template

```html
<form method="POST" action="/auth">
  {{ UCsrfToHtml() }}
  <input name="username">
  <input name="password" type="password">
  <button>Entrar</button>
</form>
```

`UCsrfToHtml()` genera el `<input type="hidden" name="_csrf" value="...">`
con un token recién firmado. El template lo embebe sin tocar la sesión.

### Vía cabecera (AJAX)

```js
fetch( "/customer/42/edit", {
   method: "POST",
   headers: {
      "X-CSRF-Token": "{{ HIX_CsrfMakeToken() }}",
      "Content-Type": "application/x-www-form-urlencoded"
   },
   body: "name=Carles&email=c@example.com"
} );
```

---

## `HIX_MwCsrf` — statefull

Genera el token al primer GET, lo guarda en la sesión como `_csrf_token` y
valida cada POST/PUT/DELETE/PATCH contra ese valor.

```clipper
// Aplicar a todo el servidor
oSrv:Use( { "HIX_MwSession", "HIX_MwCsrf" } )
```

El token se expone en `oCtx:hData["csrf_token"]` para que los templates lo
puedan leer:

```html
<form method="POST">
  <input type="hidden" name="_csrf" value="{{ csrf_token }}">
  ...
</form>
```

Si llega un POST sin token o con uno inválido → **403 JSON**.

---

## Métodos seguros vs inseguros

El middleware **solo valida** métodos que modifican estado:

| Método | Acción del middleware |
|---|---|
| `GET`, `HEAD`, `OPTIONS` | Pasa siempre (no se valida) |
| `POST`, `PUT`, `DELETE`, `PATCH` | Exige token válido |

---

## Manejo del error

Cuando `HIX_MwCsrfCheck` falla y tiene `cRedirect` configurado:

1. Guarda un flash `csrf` con `error => "..."`.
2. Hace `URedirect( cRedirect )`.

Tu `login.prg` recupera el mensaje:

```clipper
FUNCTION Main()
   LOCAL oFlash := UFlash( "login" )
   LOCAL cError := oFlash:Get( "error" )
   oFlash:Save()

   IF Empty( cError )
      oFlash := UFlash( "csrf" )                  // ⬅ fallback al flash CSRF
      cError := oFlash:Get( "error" )
      oFlash:Save()
   ENDIF

RETURN UView( "sys/login.view.html", cError )
```

Si `cRedirect` está vacío, devuelve **403 JSON** con `{ "error": "..." }` —
útil para AJAX/SPA.

---

## `app_key` — el secret HMAC

`HIX_MwCsrfCheck` firma cada token con `HIX_ConfigApp("app_key")`. Si no
existe, usa el valor por defecto **`H!x@CSRF@2026`** (⚠️ **cambiar siempre
en producción**).

Configurar el app_key:

```clipper
// Vía setup
HIX_MwCsrfSetup( "/login", "x-csrf-token", "_csrf", ;
                 "clave_secreta_de_app", 0 )

// Vía API directa
HIX_ConfigAppSet( "app_key", "clave_secreta_de_app" )
```

> ⚠️ **Cambiar el `app_key` invalida todos los tokens CSRF emitidos antes**,
> incluyendo formularios abiertos en pestañas activas. Los usuarios verán
> un 403 hasta refrescar la página.

---

## Buenas prácticas

1. **CSRF en todos los formularios POST.** No solo en login — también en
   edit/delete/transfer/cualquier acción que mute estado.
2. **`HIX_MwCsrfCheck` por defecto.** Más simple (sin sesión por medio) y
   más reusable. Funciona con `UCsrfToHtml()` directo en plantillas.
3. **Cambia `app_key` en producción.** El valor por defecto está publicado
   en el código fuente.
4. **TTL razonable.** `nLapsus = 3600` (1h) limita el reuse del token si
   alguien copia el HTML cacheado. `0` = sin caducidad.
5. **CSRF + sesión van juntos.** CSRF solo tiene sentido para auth basada
   en cookies. Si usas [JWT](jwt.md) en una API, el CSRF no aplica
   (los Bearer tokens no se envían automáticamente).
6. **Doble cookie / SameSite=Lax.** La cookie de sesión HIX ya lleva
   `SameSite=Lax`, lo que filtra parte de los ataques CSRF. CSRF tokens
   son la defensa de fondo.

