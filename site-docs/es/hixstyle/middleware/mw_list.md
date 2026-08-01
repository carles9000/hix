# Middleware - Catálogo

Catálogo completo de middlewares incluidos en HIX. Todos siguen el patrón estándar:
una función `HIX_MwXxx( oCtx )` lista para añadir al pipeline, y en la mayoría de
casos una variante `HIX_MwXxxFactory( params )` que devuelve un codeblock con
configuración propia para una ruta concreta.

| Leyenda | |
|---|---|
| **Web** | Uso recomendado en aplicaciones web (HTML, formularios, sesión) |
| **API** | Uso recomendado en APIs (JSON, JWT, M2M) |
| **Setup** | Función a llamar antes de `oSrv:Start()` para configurar las statics |
| **Factory** | Variante que devuelve codeblock con config independiente por ruta |

Todos los middleware pre-fabricados por HIX estan en la carpeta `/src/mw` 

---

## Infraestructura

### 🚧 `HIX_MwMaintenance`

| | |
|---|---|
| **Descripción** | Modo mantenimiento gestionado: corta todo el tráfico con `503` y JSON `{ "error": "maintenance" }` durante despliegues o paradas planificadas. |
| **Función** | Activable por flag programático o por la existencia de un fichero lock en disco (toggle sin reiniciar). |
| **Setup** | `HIX_MwMaintenanceSetup( lActive, cFile )` |
| **Factory** | `HIX_MwMaintenanceFactory( lActive )` — solo flag, no lock file |
| **Web** | Sí — mostrar página amigable de 503 |
| **API** | Sí — clientes deben reintentar con backoff |
| **Ejemplo** | `HIX_MwMaintenanceSetup( .F., "maintenance.lock" )` → crear el fichero activa el bloqueo. |

---

### 📋 `HIX_MwReqLog`

| | |
|---|---|
| **Descripción** | Registra cada petición entrante con `MÉTODO /path IP` en el logger HIX. No bloquea nunca, siempre `.T.`. |
| **Función** | Escribe una línea por petición antes de ejecutar el handler. Nivel configurable (DEBUG/INFO/WARN). |
| **Setup** | `HIX_MwReqLogSetup( nLevel )` |
| **Factory** | `HIX_MwReqLogFactory( nLevel )` |
| **Web** | Sí — útil en dev/staging |
| **API** | Sí — esencial para auditoría en producción |
| **Ejemplo** | `HIX_MwReqLogSetup( HIX_LOG_INFO )` → escribe `"GET /api/users 192.168.1.10"`. |

---

## Seguridad HTTP

### 🔐 `HIX_MwSecHeaders`

| | |
|---|---|
| **Descripción** | Cabeceras de hardening HTTP en cada respuesta. Nunca bloquea, solo enriquece. |
| **Función** | Inyecta `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Strict-Transport-Security: max-age=31536000` y `Content-Security-Policy`. |
| **Setup** | `HIX_MwSecHeadersSetup( cCSP )` |
| **Factory** | `HIX_MwSecHeadersFactory( cCSP )` |
| **Web** | Crítico — incluir en cualquier sitio en producción |
| **API** | Recomendado — evita usos indebidos de respuestas como contenido web |
| **Ejemplo** | `HIX_MwSecHeadersSetup( "default-src 'self'; script-src 'self' 'nonce-abc'" )` |

---

### 🌐 `HIX_MwCors`

| | |
|---|---|
| **Descripción** | Gestión completa de CORS para APIs consumidas desde el navegador. |
| **Función** | Inyecta cabeceras `Access-Control-*` en cada respuesta y responde `204` automáticamente al preflight `OPTIONS`. |
| **Setup** | `HIX_MwCorsSetup( cOrigin, cMethods, cHeaders )` |
| **Factory** | No |
| **Web** | Opcional — raramente necesario en same-origin |
| **API** | Esencial — cualquier API cross-domain o pública |
| **Ejemplo** | `HIX_MwCorsSetup( "https://app.com", "GET,POST,PUT", "Content-Type,Authorization" )` |

---

### 📦 `HIX_MwBodyLimit`

| | |
|---|---|
| **Descripción** | Protege contra uploads abusivos leyendo `Content-Length` antes de procesar el body. |
| **Función** | Rechaza con `413 payload_too_large` si el tamaño declarado supera el máximo. Por defecto: 1 MB. |
| **Setup** | `HIX_MwBodyLimitSetup( nMax )` (en bytes) |
| **Factory** | `HIX_MwBodyLimitFactory( nMax )` — límite específico por ruta |
| **Web** | Sí — protege formularios y subidas de fichero |
| **API** | Sí — evita abuso con payloads grandes |
| **Ejemplo** | `HIX_MwBodyLimitSetup( 2 * 1024 * 1024 )` → máximo 2 MB global. |

---

### 🚦 `HIX_MwRateLimit`

| | |
|---|---|
| **Descripción** | Limitador de peticiones por IP en ventana fija. Thread-safe con mutex. |
| **Función** | Cuenta peticiones por IP en una ventana de N segundos. Devuelve `429` al superar el máximo. Expone el contador en `oCtx:hData["rate_count"]`. |
| **Setup** | `HIX_MwRateLimitSetup( nMax, nWindowSecs )` |
| **Factory** | `HIX_MwRateLimitFactory( nMax, nWindowSecs )` — límite específico por ruta |
| **Web** | Útil en formularios de login/register |
| **API** | Esencial para endpoints públicos o no autenticados |
| **Ejemplo** | `HIX_MwRateLimitSetup( 100, 60 )` → 100 req/min por IP. Para login estricto: `HIX_MwRateLimitFactory( 5, 60 )`. |

---

## Sesiones

### 🍪 `HIX_MwSession`

| | |
|---|---|
| **Descripción** | Base de cualquier flujo web con estado. Necesario antes de `MwAuth`, `MwIsAuth`, `MwRequireAuth` y `MwCsrf`. |
| **Función** | Carga la sesión desde la cookie `HIXSID` (configurable), la persiste según backend, expone los datos en `oCtx:hData["session"]` y el SID en `oCtx:hData["_sid"]`. |
| **Setup** | `HIX_MwSessionSetup( cName, nTtl, nGcEvery, cStorage, cPath, cPrefix, lCrypt, cSeed, nLifeDays )` |
| **Backends** | `"memory"` (volátil, default) o `"file"` (persistente en disco) |
| **Apache LB** | `HIX_MwSessionSetRoute( "i1" )` añade sufijo al SID para `stickysession=HIXSID`. |
| **Web** | Esencial para cualquier flujo con login + cookie |
| **API** | No — usar JWT en su lugar |
| **Ejemplo** | `HIX_MwSessionSetup( "MISID", 3600, 60, "file", "sessions/" )` |

---

## Autenticación

### 🔓 `HIX_MwAuth`

| | |
|---|---|
| **Descripción** | Gestiona el flujo completo de login y logout con sesión. Requiere `HIX_MwSession` antes. |
| **Función** | Si la petición es `POST` a la ruta de login, lee credenciales del body (form o JSON), llama al codeblock `bValidate` y, si valida, guarda el usuario en sesión. Si es la ruta de logout, destruye la sesión. |
| **Setup** | `HIX_MwAuthSetup( hConfig )` con `bValidate`, `cLoginRoute`, `cLogoutRoute`, `cUserField`, `cPassField`, `cRedirectOk`, `cRedirectFail`, `cSessionKey` |
| **Factory** | No |
| **Web** | Sí — patrón principal |
| **API** | No — para login en API usar JWT directo |
| **Ejemplo** | `HIX_MwAuthSetup( { "bValidate" => {\|u,p\| MyValidate(u,p)}, "cLoginRoute" => "/login" } )` |

---

### 🪙 `HIX_MwJwt`

| | |
|---|---|
| **Descripción** | Autenticación stateless por token Bearer HS256. Ideal para APIs, móviles y SPAs. |
| **Función** | Extrae el token de `Authorization: Bearer xxx`, valida firma HMAC-SHA256 y expiración (`exp`), y deposita el payload completo en `oCtx:hData["jwt"]`. Devuelve `401` si falla. |
| **Setup** | `HIX_MwJwtSetup( cKey, nExpSecs )` |
| **Factory** | `HIX_MwJwtFactory( cKey )` — clave diferente por ruta (multi-tenant, partners) |
| **Helpers** | `HIX_JwtEncode( hData )` genera token al hacer login. `HIX_JwtValidate( cToken )` valida fuera del pipeline. |
| **Web** | Opcional — preferir `MwSession` con CSRF |
| **API** | Sí — mecanismo stateless preferido |
| **Ejemplo** | `HIX_MwJwtSetup( "mi-clave-secreta", 3600 )` → `Authorization: Bearer eyJ...` |

---

### 🗝️ `HIX_MwApiKey`

| | |
|---|---|
| **Descripción** | Autenticación M2M por clave estática. Alternativa simple a JWT para servicios internos o partners. |
| **Función** | Valida el header `X-Api-Key` contra un hash de claves permitidas (lookup O(1)). Expone la clave aceptada en `oCtx:hData["api_key"]` para logging downstream. |
| **Setup** | `HIX_MwApiKeySetup( aKeys )` |
| **Factory** | `HIX_MwApiKeyFactory( aKeys )` — set de claves privado para una ruta concreta |
| **Web** | No aplica — los usuarios no tienen API key |
| **API** | Estándar para M2M y partners; combinar con `MwRateLimit` para anti brute-force |
| **Ejemplo** | `HIX_MwApiKeySetup( { "svc-key-1", "partner-key-2" } )` |

---

## Autorización (guards)

### 🛡️ `HIX_MwRequireAuth`

| | |
|---|---|
| **Descripción** | Guard universal de ruta: bloquea con `401` si no hay usuario autenticado. Acepta tanto sesión como JWT. |
| **Función** | Busca el usuario primero en `oCtx:hData["session"]` (clave `_auth_user` por defecto). Si no, intenta con `oCtx:hData["jwt"]` (fallback). Si no encuentra ninguno, responde `401`. Si pasa, expone el usuario en `oCtx:hData["user"]` y accesible vía `UCurrentUser()`. |
| **Setup** | No requiere (usa la sesión configurada por `MwAuthSetup`) |
| **Factory** | No |
| **Web** | Sí — proteger rutas que requieran login (con sesión) |
| **API** | Sí — proteger endpoints que requieran JWT |
| **Ejemplo** | Pipeline web: `"HIX_MwSession,HIX_MwRequireAuth"`. Pipeline API: `"HIX_MwJwt,HIX_MwRequireAuth"`. |

---

### 👤 `HIX_MwIsAuth`

| | |
|---|---|
| **Descripción** | Guard de sesión simple — alternativa a `RequireAuth` cuando solo trabajas con sesiones (sin JWT). Redirige a `/login` (302) en lugar de responder JSON 401. |
| **Función** | Lee el usuario de `oCtx:hData["session"]` con la clave configurada (default `_auth_user`). Si no existe, hace redirect a la URL de `redirect_login` (configurable en `config.json` sección `auth`). |
| **Setup** | Vía `config.json`: sección `auth` → `session_user_key`, `redirect_login` |
| **Factory** | No |
| **Web** | Sí — preferible cuando quieres redirect en lugar de JSON 401 |
| **API** | No — usa `RequireAuth` |
| **Ejemplo** | `o:Add( UMiddleware():New( "HIX_MwIsAuth" ) )` después de `HIX_MwSession`. |

---

### 🎭 `HIX_MwHasRole`

| | |
|---|---|
| **Descripción** | Guard de roles y operaciones granulares. Lee el rol requerido del `cScope` de la ruta. Debe ir después de un MW que haya cargado el usuario (`MwIsAuth` o `MwRequireAuth`). |
| **Función** | Compara `oCtx:cScope` (formato `"rol"` o `"rol:operacion"`) contra el hash de roles del usuario. Acceso total si el valor del rol está vacío; granular si lista operaciones separadas por `;`. Responde `403` si falla. |
| **Setup** | Vía `config.json`: sección `auth` → `roles_key` (default `"roles"`) |
| **Factory** | No — la diferencia entre rutas se hace con el parámetro `cScope` de la ruta |
| **Web** | Sí |
| **API** | Sí |
| **Ejemplo** | `oSrv:AddRouteGet( "del", "/users/:id", action, "MyAuth", "admin:delete" )` → exige rol `admin` con operación `delete`. |

---

### 🎯 `HIX_MwJwtScope`

| | |
|---|---|
| **Descripción** | Guard de scopes para JWT (estilo OAuth 2.0). Lee el scope requerido del `cScope` de la ruta y lo compara con el claim `scope` del token. |
| **Función** | Si `cScope` está vacío, pasa. Si no, verifica que cada token (separados por espacio) en `cScope` esté presente en el claim `scope` del JWT. Responde `403` si falta alguno. |
| **Setup** | No requiere |
| **Factory** | No |
| **Web** | No habitual |
| **API** | Sí — control de scopes en APIs JWT |
| **Ejemplo** | Token con `"scope" => "read:products write:orders"`. Ruta `"read:products"` → pasa. Ruta `"delete:products"` → 403. |

---

## CSRF

### 🔏 `HIX_MwCsrf`

| | |
|---|---|
| **Descripción** | Protección CSRF basada en sesión. Genera un token aleatorio por sesión y lo valida en métodos no seguros (POST/PUT/DELETE/PATCH). Requiere `HIX_MwSession` antes. |
| **Función** | En métodos GET/HEAD/OPTIONS, genera el token si no existe y lo expone como `oCtx:hData["csrf_token"]` (para embeber en formularios). En métodos no seguros, lo lee del header `X-CSRF-Token` o del campo de formulario `_csrf` y lo compara con el de sesión. Devuelve `403` si no coincide. |
| **Setup** | `HIX_MwCsrfSetup( cRedirect, cHeader, cField, cSecret, nLapsus )` |
| **Factory** | No |
| **Web** | Esencial — siempre incluir en webs con sesión y formularios |
| **API** | No aplica — usar JWT (no se envía automáticamente por el navegador) |
| **Ejemplo** | Template embebe `{{ oCtx:hData["csrf_token"] }}` en `<input name="_csrf">`. POST sin token → `403`. |

---

### 🔐 `HIX_MwCsrfCheck`

| | |
|---|---|
| **Descripción** | Variante stateless de CSRF basada en HMAC. Valida tokens firmados sin necesidad de sesión. |
| **Función** | Métodos seguros (GET/HEAD/OPTIONS) pasan. En métodos no seguros, lee el token del header o del campo y verifica la firma HMAC con la clave de aplicación. No requiere sesión. |
| **Setup** | Comparte la clave HMAC y configuración con `MwCsrf` |
| **Factory** | No |
| **Web** | Sí — alternativa a `MwCsrf` cuando no quieres mantener estado en sesión |
| **API** | No habitual |
| **Ejemplo** | `oSrv:AddRoutePost( "auth", "/auth", "controllers/auth.prg", "HIX_MwCsrfCheck" )` con token generado por `@csrf` / `UCsrfToHtml()` en el formulario. |

---

## Resumen rápido por escenario

| Escenario | Stack típico |
|---|---|
| **Web pública estática** | `HIX_MwReqLog`, `HIX_MwSecHeaders`, `HIX_MwBodyLimit` |
| **Web con login + sesión** | + `HIX_MwSession`, `HIX_MwCsrf`, `HIX_MwAuth`, `HIX_MwRequireAuth` (o `HIX_MwIsAuth`) |
| **Web con roles** | + `HIX_MwHasRole` (declarar `cScope` en la ruta) |
| **API pública** | `HIX_MwReqLog`, `HIX_MwSecHeaders`, `HIX_MwCors`, `HIX_MwRateLimit`, `HIX_MwBodyLimit` |
| **API autenticada (JWT)** | + `HIX_MwJwt`, `HIX_MwRequireAuth`, `HIX_MwJwtScope` |
| **API M2M / partners** | + `HIX_MwApiKey`, `HIX_MwRequireAuth` |
| **Modo despliegue/parada** | `HIX_MwMaintenance` global (al inicio del pipeline) |
