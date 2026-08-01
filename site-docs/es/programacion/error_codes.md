# 🐛 Pantallas de error del sistema

Cuando HIX devuelve un error HTTP (404, 403, 405, 422, 429, 500, 503...)
**a un cliente que pide HTML**, sirve una **pantalla de error**. Si el
cliente pide JSON (API, AJAX, `Accept: application/json`), devuelve
`{ "error": "...", "detail": "..." }` automáticamente.

HIX permite **sustituir las pantallas HTML por tus propios HTML estáticos**
por cada código de estado: `error_404.html`, `error_500.html`,
`error_403.html`, etc.

> 🆚 Esta página cubre las pantallas **del sistema** (errores HTTP de
> rutas no encontradas, no permitidas, saturación, etc). Si lo que
> quieres es customizar la pantalla **5xx que se renderiza al fallar tu
> propio código** (excepciones, traces de Harbour), eso vive en
> [programacion/errorsys](../programacion/errorsys.md).

---

## ¿Cuándo lo necesitas?

- Para **branding**: que un 404 muestre tu logo, no la página gris
  genérica.
- Para **redirigir** a una landing personalizada (`/no-encontrado`,
  página de mantenimiento, etc).
- Para **multiidioma** del mensaje (404 traducido por locale).
- Para **ocultar información técnica** en producción (que no salga
  "HIX Web Server" al pie).

---

## Setup en `hix.ini`

### Sección `[paths]`

```ini
[paths]
root = www      ; directorio raíz de la app
```

### Ubicación fija: `<root>/errors/`

HIX busca páginas de error personalizadas en la carpeta fija `errors/`
relativa a `paths.root` (por defecto `www/errors/`):

```text
www/
 ├── errors/
 │   ├── error_404.html
 │   ├── error_403.html
 │   ├── error_500.html
 │   └── error_503.html
 └── ...
```

Si el fichero para un código concreto no existe, HIX usa la pantalla
inline minimalista built-in.

---

## Cómo funciona el lookup

Cuando HIX llama internamente a `HIX_HttpError(oReq, nStatus, cDetail)`:

```
                 HIX_HttpError(oReq, 404, "Route: /no-existe")
                              │
                              ▼
              ¿HIX_WantsJson(oReq)?
                     ├── Sí → JSON {"error":"Not Found","detail":"..."}
                     │
                     └── No → HIX_HttpErrorHtml(404, "Not Found", "...")
                                       │
                                       ▼
                  ¿Existe <root>/errors/error_404.html?
                         ├── Sí → hb_MemoRead() → sirve ese HTML
                         │
                         └── No → HTML inline minimalista de HIX
```

La negociación JSON vs HTML mira:

- `Accept: application/json` o `application/json` en cualquier parte.
- `X-Requested-With: XMLHttpRequest` (AJAX clásico).
- `Content-Type: application/json` del request.

---

## Códigos HTTP devueltos por HIX

HIX puede emitir cualquier código estándar. Los más comunes que ves en
el día a día:

| Código | Cuándo                                                  | Detalle típico              |
|--------|---------------------------------------------------------|-----------------------------|
| 400    | Body o parámetro inválido                               | Bad Request                 |
| 401    | Falta auth (JWT/API key/sesión)                         | Unauthorized                |
| 403    | Sin permisos para esa ruta o IP filtrada                | Forbidden                   |
| 404    | Ruta no registrada o fichero no encontrado              | Not Found, Route: /...      |
| 405    | Ruta existe pero método no permitido                    | Method Not Allowed          |
| 413    | Body más grande que `[bodylimit]`                       | Payload Too Large           |
| 422    | Validación falló (`UValidateOrFail`)                    | Unprocessable Entity        |
| 429    | Rate-limit superado                                     | Too Many Requests           |
| 500    | Excepción en tu código                                  | Internal Server Error       |
| 502    | Backend / API externa caída                             | Bad Gateway                 |
| 503    | Pool saturado, modo mantenimiento                       | Service Unavailable         |

La lista completa la mantiene `HIX_StatusText(nStatus)` en
`src/hix_error.prg`.

---

## Ejemplo de `error_404.html`

```html
<!DOCTYPE html>
<html lang="es">
<head>
   <meta charset="UTF-8">
   <title>Página no encontrada</title>
   <link rel="stylesheet" href="/static/css/app.css">
</head>
<body>
   <header>
      <img src="/static/img/logo.svg" alt="MiApp">
   </header>

   <main class="error">
      <h1>404</h1>
      <p>Esta página ha desaparecido.</p>
      <a href="/">Volver al inicio</a>
   </main>

   <footer>
      <small>&copy; 2026 MiApp</small>
   </footer>
</body>
</html>
```

> 📌 Los `error_XXX.html` son **HTML estático puro** servido vía
> `hb_MemoRead()`. **No** pasan por el motor de vistas. Si necesitas
> contenido dinámico (variables interpoladas), usa
> [programacion/errorsys](../programacion/errorsys.md) con un `.view.html`.

---

## Pantalla inline por defecto

Cuando no hay `error_XXX.html`, HIX sirve algo como:

```html
<!DOCTYPE html>
<html>
<head>
   <title>404 Not Found</title>
   <style>body{font-family:sans-serif;padding:2em;color:#333}h1{color:#c00}</style>
</head>
<body>
   <h1>404 Not Found</h1>
   <h2 style='color:#c00'><small>Route: /no-existe</small></h2>
   <hr>
   <small>HIX Web Server</small>
</body>
</html>
```

Compacto, autosuficiente y sin recursos externos. Para producción
público se recomienda **siempre** sustituirlo.

---

## Respuesta JSON automática

Si el cliente pide JSON, HIX emite directamente:

```json
{ "error": "Not Found", "detail": "Route: /no-existe" }
```

Para errores 422 desde `UValidateOrFail`, además incluye el detalle de
campos inválidos:

```json
{
   "error": "Unprocessable Entity",
   "errors": {
      "email": [ "El campo email es obligatorio" ],
      "age":   [ "El campo age debe ser numérico" ]
   }
}
```

> 🤖 Para una API REST nunca necesitas tocar nada: el comportamiento por
> defecto ya es el correcto.

---

## Generar errores desde tu código

### Desde un controlador

```clipper
USendError( 404, "Usuario no existe" )
USendError( 403, "Sin permisos para esta operación" )
USendError( 422, "Email obligatorio" )
USendError( 503, "Base de datos en mantenimiento" )
```

`USendError` se respeta la negociación: si el cliente pide JSON, devuelve
JSON; si pide HTML, devuelve la pantalla custom (o la inline si no la
hay).

### Desde un middleware

```clipper
FUNCTION HixMwApiKey( oCtx )
   IF Empty( oCtx:oReq:Header( "X-Api-Key", "" ) )
      oCtx:lHandled := .T.
      HIX_HttpError( oCtx:oReq, 401, "API key requerida" )
      RETURN .F.
   ENDIF
RETURN .T.
```

`HIX_HttpError` es el helper de bajo nivel que también respeta JSON/HTML.

---

## Diferencia con `programacion/errorsys`

| Caso                                            | Qué se usa                                |
|-------------------------------------------------|-------------------------------------------|
| Ruta no encontrada (404)                        | `errors/error_404.html`                   |
| Sin permisos (403)                              | `errors/error_403.html`                   |
| Validación falló (422)                          | `errors/error_422.html` + JSON detalle    |
| **Excepción en tu código** (Harbour error)      | `errors/errorsys.view.html` (errorsys)    |
| Saturación de pool (503)                        | `errors/error_503.html`                   |

Es decir:

- **Errores HTTP del flujo normal** → `error_XXX.html` estáticos.
- **Crash de tu código** → template `.view.html` con datos del error
  (línea, fichero, traza). Eso es [errorsys](../programacion/errorsys.md).

Puedes (y debes) usar **ambos** sistemas a la vez en una app de producción.

---

## Errores típicos

| Síntoma                                       | Causa                                            | Fix                                      |
|-----------------------------------------------|--------------------------------------------------|------------------------------------------|
| Mi `error_404.html` no aparece                | Fichero fuera de `www/errors/`                   | Colocarlo en `<paths.root>/errors/`      |
| Aparece JSON en lugar del HTML                | El cliente envía `Accept: application/json`      | Es correcto - no tocar                   |
| HTML sale sin CSS                             | Rutas relativas en el HTML                       | Usar `/static/...` absoluto              |
| 500 sale con datos técnicos en producción     | `[behavior] env = dev`                           | Cambiar a `env = prod`                   |
| Mi template no interpola variables            | Es HTML estático, no `.view.html`                | Usar [errorsys](../programacion/errorsys.md) |

---

## Buenas prácticas

- **Siempre** define al menos `error_404.html` y `error_500.html` para
  producción. Es la primera impresión de tu marca cuando algo va mal.
- Mantén las páginas **ligeras** y **autocontenidas**: sin JS pesado, sin
  llamadas externas. Una página de error que tarda no debe encadenar
  más errores.
- **No filtres detalles técnicos** en producción: nada de stacktraces,
  paths del servidor, ni nombres de tablas. Eso es para `dev` o el log.
- Para multiidioma: usa **negociación de `Accept-Language`** en tu
  middleware de i18n y devuelve `errors/es/error_404.html` o
  `errors/en/error_404.html` con un router custom.
- Si tu app es **sólo API** (sin HTML), no hace falta crear pantallas -
  la respuesta JSON automática es suficiente.

