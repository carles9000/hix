# Test suite HTML - `www/test/index.html`

Página HTML interactiva que ejecuta **25 peticiones secuenciales** contra la aplicación CRUD y valida el código HTTP devuelto por cada una. Sirve como smoke test manual del ciclo completo: público → login con CSRF → operaciones autenticadas → logout → login como usuario restringido → verificación de que `HasRole` bloquea.

Ubicación:

```
examples/web/crud/www/test/index.html
```

URL de acceso mientras el servidor está arriba:

```
http://localhost/test/index.html
```

---

## `oServer:AllowDir( "test", .F. )` - por qué existe esta línea

`src/app.prg` contiene una única llamada explícita:

```harbour
oServer := THixServer():New()
   oServer:AllowDir( "test", .F. )   // ← ¡Sin esto el test da 404!
oServer:Start()
```

En modo hixstyle, HIX aplica una **whitelist ACL estricta** sobre 
el <root> definido, por defecto `www/`. Solo se sirven:

- `www/public/*` - automáticamente incluido (CSS/JS/imágenes).
- Directorios que el proyecto añada explícitamente con `AllowDir()`.

Todo lo demás (`www/controllers/`, `www/middlewares/`, `www/views/`, `www/models/`, `www/loaders/`, …) queda bloqueado con **HTTP 403**. Esta es una defensa del framework: sirve para que no puedas exponer accidentalmente un `.prg`, un `.json` de configuración o una vista sin pasar por una ruta.

`AllowDir( "test", .F. )` amplía la whitelist:

- Primer parámetro: nombre del subdirectorio bajo `www/` (aquí `www/test/`).
- Segundo parámetro:
  - `.F.` → **solo lectura de estáticos**; los `.prg` dentro del directorio no se ejecutan aunque existan. Es lo correcto para servir un HTML de test.
  - `.T.` → permite ejecutar `.prg` (peligroso; solo si sabes lo que haces).

Sin esta línea, `GET /test/index.html` devolvería 404. Con ella, el dispatcher sirve el HTML como fichero estático.

---

## Por qué el test debe servirse desde el mismo origen

Un intento inicial fue abrir `test/index.html` directamente vía `file://`. **No funciona.** Razones:

1. **Cookies**: la sesión (`FENIXSID`) y el token CSRF se guardan como cookies del origen `http://localhost`. Un HTML servido desde `file://` es otro origen, y el navegador no propaga cookies entre orígenes.
2. **CORS**: la app no habilita CORS (no hay `HIX_MwCorsSetup`). Cualquier fetch cross-origin sin CORS es bloqueado por el navegador.
3. **Opaque redirects**: sin mismo origen, la respuesta a un 302 se recibe como `type: opaqueredirect` sin cabeceras - los cookies del 302 (por ejemplo el `Set-Cookie: FENIXSID=...` que emite `POST /auth`) se pierden.

Por eso el fichero está en `www/test/` (misma raíz de la app, mismo puerto, mismo origen) y no en, por ejemplo, `examples/web/crud/test/` (fuera de `www/`, imposible de servir).

---

## Los tests, por bloques

| # | Método | URL | Espera | Qué prueba |
|---|--------|-----|:------:|------------|
|   | | **Público (sin sesión)** | | |
| 01 | GET  | `/`                          | 200 | Portada estática se sirve |
| 02 | GET  | `/login`                     | 200 | El formulario incluye un token CSRF fresco |
|   | | **Protegido sin sesión → 302 → /login** | | |
| 03 | GET  | `/main`                      | 302 | `MyAppAuth` rechaza |
| 04 | GET  | `/module_a`                  | 302 | idem |
| 05 | GET  | `/customer/search`           | 302 | `MyAppAuthRole` rechaza (no hay sesión → IsAuth corta antes que HasRole) |
| 06 | GET  | `/customer/1`                | 302 | idem |
|   | | **Auth como `demo` (admin completo)** | | |
| 07 | POST | `/auth` sin CSRF              | 302 | `MyAppLogin` → `CsrfCheck` rechaza |
| 08 | POST | `/auth` demo/1234 + CSRF      | 302 | OK → redirige a `/main` |
| 09 | GET  | `/main` con sesión           | 200 | Dashboard renderizado |
| 10 | GET  | `/module_a`                  | 200 | Autenticado OK |
| 11 | GET  | `/module_b`                  | 200 | idem |
| 12 | GET  | `/customer/search`           | 200 | demo tiene `customers:search` |
| 13 | GET  | `/customer/create`           | 200 | demo tiene `customers:create` |
| 14 | GET  | `/customer/1`                | 200 | demo tiene `customers:show` |
| 15 | GET  | `/customer/1/edit`           | 200 | demo tiene `customers:edit` |
|   | | **Escritura protegida por CSRF (como demo)** | | |
| 15b | POST | `/customer/store` sin CSRF   | 302 | `MyAppAuthRoleEdit` → `CsrfCheck` rechaza (HasRole habría pasado - demo tiene el scope) |
|   | | **Logout** | | |
| 16 | GET  | `/logout`                    | 302 | Sesión destruida, redirige a `/login` |
| 17 | GET  | `/main` tras logout          | 302 | Vuelve a rechazar sin sesión |
|   | | **Auth como `carles` (restringido - solo search+show)** | | |
| 18 | POST | `/auth` carles/1234 + CSRF   | 302 | OK |
| 19 | GET  | `/customer/search`           | 200 | carles tiene `customers:search` |
| 20 | GET  | `/customer/1`                | 200 | carles tiene `customers:show` |
| 21 | GET  | `/customer/create`           | 403 | carles NO tiene `customers:create` → HasRole rechaza |
| 22 | GET  | `/customer/1/edit`           | 403 | carles NO tiene `customers:edit` → HasRole rechaza |
| 23 | POST | `/customer/store` como carles | 403 | HasRole rechaza (sin `customers:create`) **antes** que CsrfCheck |
|   | | **Cleanup** | | |
| 24 | GET  | `/logout`                    | 302 | Sesión final destruida |

Total: **25 tests** (el 15b se numera aparte para ubicarlo en el bloque de escritura con demo). La regla de éxito es: código devuelto == código esperado. Cualquier discrepancia se marca en rojo.

---

## Diseño técnico del runner

El HTML es autocontenido - no depende de librerías externas. Puntos clave:

### 1. Comprobación de conectividad al cargar

Antes de mostrar la UI, hace un `fetch("/")` con timeout de 3 s. Si falla, muestra el banner "server not reachable" y no deja ejecutar tests.

### 2. Origen dinámico

```javascript
const API = location.protocol.startsWith('http')
            ? location.origin
            : 'http://localhost';
```

Si abres el HTML por http (correcto) → usa el mismo origen. Si abres por `file://` (incorrecto, pero como fallback) → intenta `http://localhost`. Esto último probablemente falle por CORS/cookies pero deja un mensaje comprensible en lugar de un error crudo.

### 3. `redirect: 'manual'` por defecto

```javascript
const r = await fetch(API + url, {
  method,
  headers: h,
  body,
  credentials: 'include',
  cache: 'no-store',
  redirect: follow ? 'follow' : 'manual'
});
```

`redirect: 'manual'` permite **detectar el 302 explícitamente** en lugar de que el navegador lo siga automáticamente. Cuando el navegador no puede exponer el status real del redirect opaco, sintetiza `status: 302`. Los tests 03-07, 15b, 16, 17, 23, 24 dependen de esto.

Excepción: las llamadas de setup que necesitan que el `Set-Cookie` del 302 sea aplicado (por ejemplo el `POST /auth` del test 08) pasan `follow: true`, forzando el navegador a seguir el 302 y propagar la cookie.

### 4. `credentials: 'include'`

Fundamental: sin esto el navegador no envía ni recibe cookies. La cookie `FENIXSID` no viajaría y todo el flujo de sesión fallaría.

### 5. `cache: 'no-store'`

Evita que el navegador sirva respuestas cacheadas - imprescindible para volver a ejecutar la suite y ver resultados frescos.

### 6. Extracción del CSRF token

```javascript
async function fetchCsrf() {
  const d = await req('/login', 'GET');
  const m = d.body.match(/name=["']_csrf["']\s+value=["']([^"']+)["']/i)
         || d.body.match(/value=["']([^"']+)["']\s+name=["']_csrf["']/i);
  csrfToken = m ? m[1] : '';
  return csrfToken;
}
```

Antes de un `POST /auth` con CSRF (test 08, 18), el runner hace `GET /login`, escanea el HTML devuelto y extrae el `_csrf` del `<input hidden>`. Luego lo incluye en el body form-urlencoded del POST.

### 7. Popup de respuesta

Cada botón `▶` en la columna Run ejecuta el test individualmente y **muestra la respuesta completa** en un popup - útil cuando algo falla y necesitas ver el HTML/mensaje que devolvió el servidor. "Run All" no abre popup, solo colorea el botón (verde/rojo) y actualiza el contador `N ok / N ko`.

---

## Reset

El botón **Reset** limpia el estado local (`csrfToken = ''`, botones neutros) y hace `GET /logout` para destruir la sesión en el servidor. Es prudente pulsarlo entre reruns.

Aún así, si un test falla intermitentemente por caché del navegador, la receta segura es **Ctrl+F5 con DevTools abierto y "Disable cache" marcado**.

---

## Extender el test suite

Para añadir un test 25 nuevo:

1. Añadir la fila `<tr>` en la tabla con id nuevo, botón `runTest('25', this)` y span `.e2xx/.e3xx/.e4xx` con el código esperado.
2. Añadir la entrada en el objeto `EXPECT` del JS: `'25': 200`.
3. Añadir la entrada en el objeto de handlers: `'25': async () => req('/mi/ruta', 'GET')`.
4. Si el nuevo test cambia el estado de la sesión (login/logout), sitúalo en el bloque correcto para no romper los siguientes.

El orden de los tests importa: son secuenciales y comparten cookie de sesión. Test 09 asume que test 08 (login) pasó; test 20 asume que test 18 pasó.

---

## Relación con las otras piezas del proyecto

- Cómo se validan los códigos esperados → ver [rutas.es.md](rutas.es.md) para saber qué middleware cubre cada URL.
- Por qué el test 23 da 403 y no 302 → orden de MW en [middlewares.es.md](middlewares.es.md), sección `MyAppAuthRoleEdit`.
- Qué permisos tiene cada usuario en cada scope → [users.es.md](users.es.md).
