# 🛠️ Modo dev / modo prod

**HIX** distingue dos entornos de ejecución según `env`:

- **`dev`** - desarrollo local. Todo facilita el debug: errores con
  detalle, sin cache de assets, recarga inmediata de templates.
- **`prod`** - producción. Todo facilita el rendimiento y la seguridad:
  errores genéricos, cache agresiva, templates compilados una sola vez.

Cambiar el modo es **una sola línea** - y altera el comportamiento de
medio framework.

`hix.json`
```json
"app" : {  
  "env" : "dev"          ◀───── Local: F5 recarga, traceback completo, sin cache
  "env" : "prod"         ◀───── Servidor real: 500 genéricos, assets cacheados 1h
}
```

---

## Qué cambia entre modos

| Comportamiento | `dev` | `prod` |
|---|---|---|
| **Páginas de error** | HTML detallado con stack + código fuente | 500 genérico (o template errorsys minimal) |
| **`Cache-Control` de assets** | `no-store` - el browser no cachea | `public, max-age=3600` - 1 hora |
| **Vistas `.html`** | Re-transpilan si cambia el fichero | Cache en memoria, no rechequeo |
| **`errors.log`** | Igual en ambos - siempre se escribe | Igual |
| **Trazas `_d()`** | Visibles si `app.debug = true` | Habitualmente off |
| **Panel admin** | Acceso si `lAdminEnabled=.T.` | Mejor desactivar o restringir por IP |

> Las dos diferencias **observables desde el cliente** son las páginas de
> error y la cache. El resto son optimizaciones server-side.

---

## Páginas de error

### En dev

`HIX_ErrorSys` renderiza un HTML grande con tabla de campos del error:
descripción, subsistema, operación, fichero, línea, código fuente
alrededor de la línea con la línea fallida resaltada en rojo.

```
┌─────────────────────────────────┐
│  View Error                     │  
├─────────────────────────────────┤
│  Description: undefined var X   │
│  Subsystem  : BASE              │
│  File       : views/login.html  │
│  Line       : 23                │
│                                 │
│    0020  <form action="..">     │
│    0021    <input name="user">  │
│    0022    <input name="pass">  │
│ => 0023  {{ X + 1 }}            │
│    0024    <button>OK</button>  │
│    0025  </form>                │
└─────────────────────────────────┘
```

### En prod

```
┌─────────────────────────────────┐
│  500 - Internal Server Error    │
└─────────────────────────────────┘
```

Si configuras [errorsys](errorsys.md) con tu propio template, el modo
prod usa **tu** página, pero con la información que **tú** decidas
exponer:

```html
@args hErr

@if UIsProd()
  <h1>Something went wrong.</h1>
  <p>We're investigating. Please try again in a few minutes.</p>
@else
  <h1>{{ UHtmlEncode(hErr["description"]) }}</h1>
  <pre>{{ UHtmlEncode(hErr["file"]) }}:{{ hb_NToS(hErr["line"]) }}</pre>
@endif
```

### DEV 

![image](../../../assets/images/manual/errors/dev.png)

### PROD

![image](../../../assets/images/manual/errors/prod.png)


---

## Cache de assets

El dispatcher emite `Cache-Control` distinto según `cEnv` para los
ficheros servidos desde `www/`:

| Modo | Cache-Control |
|---|---|
| `dev` | `no-store` - recarga cada vez |
| `prod` | `public, max-age=3600` - 1 hora |

Esto vale para CSS, JS, imágenes, fuentes. En dev, modificas `app.css`
y un `Ctrl+F5` lo trae al instante; en prod, el browser lo reutiliza
durante una hora sin hacer GET.

---

## Templates `.html`

| Modo | Comportamiento |
|---|---|
| `dev` | El motor re-transpila si el fichero cambió (mtime) |
| `prod` | Compila la primera vez, cachea, no rechequea |

En producción, **edita y reinicia** el servidor - no hay hot-reload de
templates.

---


### Logs distintos por entorno

```clipper
IF UIsDev()
   HIX_LoggerInit( "logs/hix.log", HIX_LOG_DEBUG, .T. )    // verbose + console
ELSE
   HIX_LoggerInit( "logs/hix.log", HIX_LOG_INFO,  .F. )    // solo fichero, info+
ENDIF
```

### CSRF / sesión más estricta en prod

```clipper
IF UIsProd()
   HIX_MwSessionSetup( "HIXSID", 1800, 60, "file", ".sessions/" )    // 30 min
ELSE
   HIX_MwSessionSetup( "HIXSID", 86400, 60, "memory" )               // 1 día en RAM
ENDIF
```

---


## Checklist al pasar a `prod`

- **`app.env = "prod"`** en el `hix.json`.
- **`server.ssl = true`** + certificados válidos (Let's Encrypt).
- **`app.debug = false`** y nivel de log a `info` o `warn`.
- **`paths.errors = ".logs"`** (o un directorio fuera del webroot).
- **Panel admin** desactivado o tras whitelist de IP.
- **CORS** con orígenes concretos, **no** `"*"`.
- **Rate limit** activo en endpoints sensibles (`/login`, ...).
- **Cookie de sesión** corta (30-60 min) y `lSessionCrypt=.T.` si va por fichero.

---
