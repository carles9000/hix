# ✨ Modo HixStyle

**HixStyle** es la cara estructurada de HIX. Donde el [modo básico](modo-basico.md)
te deja servir cualquier `.html`, `.prg` o `.hrb` con total libertad, **HixStyle**
te impone una manera de trabajar: una arquitectura fija, unos nombres
predecibles, un flujo claro y unas convenciones compartidas por toda la
comunidad.

No es más potente porque tenga más funciones - HIX las tiene en ambos modos.
Es más potente porque **todos los desarrolladores trabajan igual**. Eso es
mantenibilidad real, colaboración real y módulos intercambiables entre proyectos.

---

## 🎯 Una sola manera de trabajar

**HixStyle** implementa el patrón **MVC (Modelo-Vista-Controlador)**, un estándar
ampliamente probado en la industria del software (Laravel, Rails, Django,
Spring, ASP.NET MVC, Phoenix...). No reinventamos nada: adoptamos lo que ya
funciona y lo adaptamos al ecosistema Harbour.

La consecuencia práctica:

- Un programador que entra a un proyecto HixStyle **sabe inmediatamente dónde
  está cada cosa** sin necesidad de explicaciones.
- Las rutas se declaran en un sitio. Los controladores viven en otro. Las
  vistas en otro. Los modelos en otro. Los middlewares en otro.
- No hay "scripts sueltos por ahí". No hay "ese .prg que hace de todo".
  No hay archivos colgando en cualquier carpeta.

> 💡 La rigidez no es un coste - es la garantía de que un proyecto sigue
> siendo legible al cabo de los años, aunque pasen varias manos por él.

---

## 📁 Estructura de carpetas desde el `<root>`

Cuando activas HixStyle, HIX espera encontrar (y crea si no existen) una
estructura fija a partir del directorio raíz (`<root>`, normalmente `www/`):

```
www/
 ├── public/         ← único directorio servido directamente al navegador
 ├── routes/         ← definición de rutas en JSON
 ├── controllers/    ← lógica de los endpoints (.prg)
 ├── views/          ← plantillas .view.html
 ├── models/         ← acceso a datos (UDbf, SQL, APIs externas)
 ├── middlewares/    ← interceptores (auth, csrf, rate-limit, ...)
 ├── errors/         ← paginas de error
 └── loaders/        ← auto-carga al arrancar (rutas, MW, helpers)
```

Cada carpeta tiene **un propósito único** y **una semántica clara**.
Esto no es una sugerencia: HIX en modo HixStyle busca activamente en estos
directorios y rechaza cualquier intento de ejecutar código fuera del flujo
establecido.

---

## 🔒 Privacidad de carpetas

En HixStyle el navegador **solo puede acceder a `public/`**. Punto.

- `public/` contiene los assets estáticos: CSS, JS, imágenes, fuentes, PDFs
  descargables, robots.txt, favicon, etc.
- Todo lo demás (`controllers/`, `views/`, `models/`, `routes/`...) es
  **privado por defecto**. Un intento de pedir `/controllers/auth.prg`
  directamente desde el navegador recibe un **403/404**, nunca el código.

Esta política se aplica a nivel de dispatcher, no por convención. No hay
forma de filtrar un `.prg` accidentalmente: si no está montado como ruta
en `routes/*.json`, no se ejecuta.

> 🛡️ En el [modo básico](modo-basico.md) cualquier `.prg` o `.hrb` colocado
> bajo `<root>/` se puede ejecutar pidiendo su URL. En HixStyle eso se
> **bloquea completamente** - es una de las primeras diferencias visibles
> cuando activas `hixstyle.enabled = true` en `hix.json`.

---

## 🚦 El flujo: ruta → controlador → vista

Toda petición HTTP en HixStyle sigue el mismo viaje:

```
    Petición
       │
       ▼
┌─────────────┐
│  routes/    │  ¿qué controller atiende esta URL?
│  *.json     │  ¿qué middlewares se aplican antes?
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  middlewares/   │  auth, csrf, rate-limit, cors, ...
│  (cadena)       │  pueden cortar la petición aquí
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  controllers/   │  lógica de negocio
│  *.prg          │  pide datos a models/
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  models/        │  acceso a datos (UDbf, SQL, API)
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  views/         │  render del HTML final
│  *.view.html    │  (o JSON para APIs)
└──────┬──────────┘
       │
       ▼
   Respuesta
```

Este flujo es **siempre el mismo**, tanto si la respuesta es una pantalla
HTML para un humano como si es un JSON para una app móvil.

---

## 🎨 El motor de vistas (Mambo)

**HixStyle** te empuja a usar el [motor de vistas](../hixstyle/response/motor-vistas.md)
de HIX para renderizar HTML - no a concatenar strings dentro del controlador. 
Nuestro motor de vistas al que llamaremos Mambo (nos dara mucho ritmo) nos ofrecerá 
unas ventajas (que se detallan en su capítulo dedicado):

- **Separación clara** entre lógica y presentación: los diseñadores tocan
  las vistas sin necesidad de entender Harbour.
- **Sintaxis declarativa** con interpolación `{{ }}`, condicionales `@if`,
  bucles `@for`, herencia entre plantillas...
- **Caché automático**: las vistas se compilan a HRB la primera
  vez y se reutilizan. Render veloz incluso con páginas complejas.
- **`@args` explícito**: cada vista declara qué variables espera recibir.
  No hay variables "mágicas" inyectadas a ciegas, serán los clásicos parámetros
  que se usan cuando se llama a una función. el controlador procesa los datos 
  y los enviará ne forma de argumentos a la view.
- **Escape automático**: protección contra XSS sin pensar en ello.

> 📚 El [motor de vistas](../hixstyle/response/motor-vistas.md) tiene su
> propio capítulo. Aquí solo te interesa saber que **existe** y que en
> HixStyle es la vía recomendada para devolver HTML.

---

## 💾 Modelos

Los modelos viven en `models/` y encapsulan el acceso a datos:

- **DBF** mediante [UDbf](../hixstyle/models/udbf.md), wrapper que añade
  validación, casting y operaciones tipo ActiveRecord.
- **SQL** (MariaDB, PostgreSQL, SQLite) mediante los drivers del proyecto, librerias 
  de Harbour,...
- **APIs externas** mediante `hb_curl`.
- **Ficheros, caches, queues...** cualquier fuente de datos puede vivir aquí.

La regla es simple: **los controladores no acceden directamente a las
tablas**. Pasan por un **modelo**. Esto te da:

- Un único lugar donde tocar si cambia el esquema de la BD.
- Tests unitarios posibles: el modelo se puede mockear.
- Reusabilidad: el mismo modelo sirve a múltiples controladores.

---

## 🌐 Web + API en el mismo ecosistema

Con HixStyle **una misma aplicación sirve simultáneamente** una web
tradicional (HTML) y una API REST (JSON), compartiendo:

- Los mismos modelos.
- Los mismos middlewares de auth, validación y rate-limit.
- La misma estructura de rutas (`routes/web.json` y `routes/api.json`,
  o un único fichero con prefijos `/api/v1/...`).
- La misma sesión de usuario, o tokens JWT si la API es stateless.

No necesitas mantener dos proyectos paralelos. La web del back-office y
la API que consume la app móvil **viven en el mismo HIX**, con el mismo
código de negocio detrás. Cambias el formato de salida (vista vs JSON)
en una línea del controlador.

---

## 🛡️ Middlewares: el verdadero superpoder

Los middlewares son interceptores que se ejecutan **antes** del controlador
en la cadena de cada petición. En HixStyle son **ciudadanos de primera
clase** y la mayoría de aspectos transversales se resuelven aquí:

- **Autenticación** (sesión, JWT, API keys).
- **CSRF** (protección contra peticiones falsificadas).
- **CORS** (políticas cross-origin para APIs).
- **Rate-limit** (anti-fuerza-bruta, anti-DoS).
- **Firewall** (whitelist/blacklist por IP/CIDR).
- **Validación** de input.
- **Logging y métricas** de cada petición.
- **Traducción** (i18n) y selección de locale.
- **Compresión** GZIP de respuestas.

Se declaran en `routes/*.json` por ruta o por grupo de rutas, y se
combinan con coma. El controlador **solo se ejecuta si toda la cadena
pasa**. Si un middleware corta la petición (401, 403, 429...), tu
controlador ni se entera.

> 🧩 Toda la lógica de seguridad y orquestación vive **fuera** del
> controlador. El controlador solo hace lo suyo: orquestar modelos
> y renderizar la respuesta. Eso es código limpio.

---

## 📌 Resumen de bondades

**HixStyle** te ofrece, de un plumazo:

| Bondad                          | Qué te da                                   |
|---------------------------------|---------------------------------------------|
| Estructura fija                 | Cualquiera entiende cualquier proyecto      |
| Carpetas privadas               | Imposible filtrar código por accidente      |
| Flujo MVC                       | Lógica, datos y presentación separados      |
| Motor de vistas (Mambo)         | HTML mantenible, rápido y seguro            |
| Middlewares declarativos        | Seguridad y orquestación fuera del código   |
| Web + API en un solo proyecto   | Un código, dos canales de salida            |
| Convenciones compartidas        | Onboarding de horas, no de semanas          |
| Módulos intercambiables         | Importa un módulo de otro proyecto y corre  |

Cada uno de estos puntos tiene su **propio capítulo** en la documentación.
Esta página es solo la fotografía de conjunto; a partir de aquí, cada
sección del manual desarrolla un aspecto concreto.
