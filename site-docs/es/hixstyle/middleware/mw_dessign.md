# 🧩 Middleware - Diseño

## Estructura del middleware. 

Básicamente está formado por 2 funciones dentro del mismo prg: 

- Setup : Alguna variable que definimos por defecto y podamos reconfigurar si es necesario
- Middleware: funcion que ejecutará el proceso y podrá usar la variable del setup

Este podria ser el diseño de un middleware

```clipper
STATIC s_MyVar := 3600

FUNCTION Mw_FenixSetup( nExpSecs )

   IF ValType( nExpSecs ) == "N" .AND. nExpSecs > 0
      s_MyVar := nExpSecs 
   ENDIF
   
RETURN nil 

FUNCTION Mw_Fenix( oCtx ) 
   LOCAL lAccept := .T.
   ... 
  
      // Uso de s_MyVar 
  
   ... 
	  
RETURN lAccept 
```


## Dinámica de diseño según el tipo de aplicación

No todas las aplicaciones necesitan los mismos middlewares. La elección depende de
quién consume la API y cómo. 

Aqui ponemos algun ejemplo de diseño sgún el escenario.


### Aplicación Web clásica (HTML + formularios)

El usuario interactúa desde un navegador. El estado se guarda en sesión con cookie.

```
Petición navegador
     │
     ├─ MW_BodyLimit      ← limitar tamaño (uploads)
     ├─ MW_Session        ← cargar sesión desde cookie
     ├─ MW_Csrf           ← verificar token CSRF en POST/PUT/DELETE
     ├─ MW_RequireAuth    ← ¿hay sesión activa?
     └─ MW_RequireRole    ← ¿tiene el rol necesario?
```

El orden importa: primero cargar la sesión, luego verificar CSRF (que necesita la
sesión), y solo después comprobar autenticación.

### API REST (JSON, cliente externo)

El cliente es una app móvil, SPA o servicio externo. No hay cookies de sesión: la
autenticación es stateless con JWT o API Key.

```
Petición cliente API
     │
     ├─ MW_Cors           ← cabeceras CORS para el navegador
     ├─ MW_RateLimit      ← protección contra abuso
     ├─ MW_BodyLimit      ← limitar tamaño del body
     ├─ MW_Jwt            ← validar Bearer token
     ├─ MW_RequireAuth    ← ¿token válido?
     └─ MW_RequireRole    ← ¿rol suficiente?
```

### Servicio interno (machine-to-machine)

Comunicación entre servicios del mismo sistema. Sin usuarios humanos, sin sesiones.
La autenticación es por API Key estática.

```
Petición servicio interno
     │
     ├─ MW_BodyLimit      ← protección básica
     ├─ MW_ApiKey         ← validar X-Api-Key
     └─ MW_RequireAuth    ← ¿clave conocida?
```

---

## Qué proteger y qué no

### Proteger siempre

| ¿Qué? | ¿Con qué? |
|---|---|
| Rutas privadas (panel, datos de usuario) | Autenticación + roles |
| Endpoints que modifican datos (POST/PUT/DELETE) | CSRF en web, JWT/ApiKey en API |
| Subida de ficheros o payloads grandes | Límite de body |
| Endpoints públicos con alto tráfico | Rate limiting |
| Cualquier cosa que devuelva datos sensibles | Cabeceras de seguridad HTTP |

### No sobreproteger

Un error común es aplicar todos los middlewares a todas las rutas por precaución. El
resultado es latencia añadida innecesaria y código más difícil de depurar.

> La página de bienvenida pública no necesita JWT.
> Un endpoint de health-check no necesita sesión.
> Los assets estáticos no necesitan CSRF.

La regla es sencilla: aplica el middleware mínimo necesario para el nivel de confianza
que requiere esa ruta.

---

## Ejemplos conceptuales

### Ejemplo simple: registro de peticiones

El middleware más sencillo posible no bloquea nada. Solo observa y registra:

```
Petición llega
     │
     ▼
[MW_ReqLog]
  Anota: método + path + IP en el log
  Devuelve .T. siempre
     │
     ▼
  Handler - ejecuta normalmente
```

Útil para trazabilidad: saber qué rutas se llaman, con qué frecuencia, desde qué IPs.

### Ejemplo compuesto: ruta de API protegida

Una ruta de API que solo pueden usar usuarios autenticados con rol `editor`:

```
POST /api/articles  (crear artículo)
     │
     ▼
[MW_RateLimit]
  ¿Esta IP ha superado 100 req/min?
  No → .T., continúa
     │
     ▼
[MW_Jwt]
  ¿Hay cabecera Authorization: Bearer xxx?
  ¿El token es válido y no ha expirado?
  Sí → deposita payload en oCtx:hData["jwt"] → .T.
  No → responde 401 → .F. → corta
     │
     ▼
[MW_RequireRole("editor")]
  ¿oCtx:hData["jwt"]["role"] == "editor"?
  Sí → .T.
  No → responde 403 → .F. → corta
     │
     ▼
  Handler _CreateArticle()
  Ya sabe que el usuario es válido y tiene permiso.
  Solo se ocupa de crear el artículo.
```

Tres middlewares, tres responsabilidades claras, código de negocio limpio.


