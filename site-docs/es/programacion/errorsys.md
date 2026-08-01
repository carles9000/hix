# 🛑 Errorsys - Pantalla de error personalizada

Cuando una acción falla, HIX renderiza una página HTML 500. Por defecto
muestra la pantalla interna de `HIX_ErrorSys`.

**Errorsys** permite sustituir esa pantalla por **tu propio template**
`.html`, usando todo el motor de vistas HIX. 

---

## Configuración

### Desde `hix.json`

```json
"app" : { 
   "errorsys" : "errorsys.html"
}
```
### Resolución del path

`app.errorsys` **no lleva la carpeta `errors/`** en el JSON. HIX la añade en
función de `hixstyle.enabled`:

| `hixstyle.enabled` | Valor JSON              | Path resuelto                          |
|--------------------|-------------------------|----------------------------------------|
| `true`             | `errorsys.html`         | `<cRoot>/errors/errorsys.html`         |
| `true`             | `sub/errorsys.html`     | `<cRoot>/errors/sub/errorsys.html`     |
| `false`            | `errorsys.html`         | `<cRoot>/errorsys.html`                |
| `false`            | `sub/errorsys.html`     | `<cRoot>/sub/errorsys.html`            |

Con `hixstyle.enabled=true`, `errors/` es una carpeta fija del layout
(como `controllers/`, `views/`, `models/`) y **siempre** se prefija.
`<cRoot>` viene de `paths.root` en `hix.json` (por defecto `www`).

Flujo:
1. Si el template existe **y** renderiza sin error → se envía al cliente.
2. Si el template **falla al renderizar** → se muestra la página *Errorsys
   Design Error* (fondo rojo oscuro) con el error original + el error del
   propio template.
3. Si el template **no existe** o queda vacío → cae al renderer interno
   (`HIX_ErrorSys`, que a su vez respeta `app.env`).

---

## El template `errorsys.html`

Es un template HIX estándar - mismos `@args`, `{{ }}` y reglas que
cualquier `.html`.

Recibe un único parámetro `hErr` (hash) con los campos del error:

```html
@args hError

<!DOCTYPE html>
<html lang="es">
<head>
   <meta charset="UTF-8">
   <title>Error {{ hb_NToS(hError['subCode']) }}</title>
   <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
   <style>
      body { padding: 2em; font-family: system-ui, sans-serif; }
      pre  { background: #f4f4f4; padding: 1em; }
   </style>
</head>
<body>
   <h1 class="text-danger">Application Error (DEV)</h1>
   <hr>
   <table class="table table-bordered">
      <tr><th>Time</th><td>{{ dtoc(date()) + ' ' + time() }}</td></tr>
      <tr><th>Description</th><td>{{ hError['description'] }}</td></tr>
      <tr><th>Operation</th><td>{{ hError['operation'] }}</td></tr>
      <tr><th>Subsystem</th><td>{{ hError['subsystem'] }}</td></tr>
      <tr><th>File</th><td>{{ hError['file'] }}</td></tr>
      <tr><th>Line</th><td>{{ hb_NToS(hError['line']) }}</td></tr>
      <tr><th>HTTP</th><td>{{ hb_NToS(hError['subCode']) }}</td></tr>
   </table>

   <!-- Volcado bruto util en dev: -->
   <h3>Dump completo</h3>
   {!! _w( hError ) !!}
</body>
</html>
```

Si observas la linea `{!! _w( hError ) !!}` mostrara todo el contenido del hash 

---


## `www/errors/error_XXX.html` - páginas HTTP estáticas

Cuando el router o el dispatcher generan un error HTTP con código (404, 405,
403, 500…) llaman a `HIX_HttpError()`, que a su vez usa `HIX_HttpErrorHtml`.
Esta función busca:

```
www/errors/error_<CODE>.html
```

- Si existe → se envía tal cual como respuesta HTML.
- Si no existe → se envía una página mínima autogenerada con el título del
  código y (opcionalmente) el detalle.

Ejemplo: para un 404, el fichero es `www/errors/error_404.html`.

---

## 5. Diferencia entre `errorsys` y `error_XXX.html`

|                          | `errorsys`                                          | `error_XXX.html`                    |
|--------------------------|-----------------------------------------------------|-------------------------------------|
| Se dispara cuando…        | El handler PRG lanza una **excepción no capturada** | El router/dispatcher devuelve un código HTTP concreto (404, 405, 403…) |
| Se procesa por…           | `HIX_ShowError()`                                   | `HIX_HttpErrorHtml()`               |
| Tipo de fichero           | Template dinámico `.html` (motor de vistas)         | HTML plano                          |
| Recibe datos del error    | Sí (`@args hError`)                                  | No                                   |
| Aplica `app.env`          | Sí (afecta al fallback interno)                     | No                                   |
| Uno solo o varios         | Un único template                                   | Uno por código HTTP                 |

En resumen:
- **`errorsys`** = **crashes** de la lógica de la app.
- **`error_XXX.html`** = respuestas HTTP con código de error semántico.

Si se origina un 404 standard sin tener definido este error, se muestra una pantalla 
básica interna 


![image](../../../assets/images/manual/errors/404_std.png)

Pero si definimos /errors/error_404.html con algo parecido a esto:

```html
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>HIX Error 404</title>
  <link rel="icon" type="image/x-icon" href="https://raw.githubusercontent.com/carles9000/hix/main/resources/images/hix.ico">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">

  <style>
    :root {
      --hix-red: #F60000;
      --hix-dark: #222222;
      --hix-gray: #717171;
    }  
  
    .mynav {
      padding: 20px 32px;
      border-bottom: 1px solid #ebebeb;
    }  
  
    body {
      font-family: 'Nunito', -apple-system, BlinkMacSystemFont, sans-serif;
      background: #fff;
      color: var(--hix-dark);
      min-height: 100vh;
    }  
	
    .error-title {
      font-size: 2.6rem;
      font-weight: 800;
      color: var(--hix-dark);
      margin-bottom: 10px;
    }
    .error-subtitle {
      color: var(--hix-gray);
      font-size: 1.2rem;
      font-weight: 400;
      margin-bottom: 14px;
    }
	
    .error-code {
      font-weight: 700;
      color: var(--hix-red);
    }	
	
    .error-section {
      min-height: calc(100vh - 74px);
    }
    .error-text {
      padding: 10px 50px 10px 50px;
    }	
  </style>
</head>
<body>

<nav class="mynav ">
  <img src="https://raw.githubusercontent.com/carles9000/hix/main/resources/images/hix.png" height="50" style="margin-right: 10px;">
</nav>


<div class="container error-section d-flex align-items-center fade-container">
  <div class="row w-100 align-items-center">

    <div class="col-md-6 error-text">
      <h1 class="error-title">Shoot!</h1>
      <p class="error-subtitle">Well, this is unexpected…</p>
      <p class="error-code">Error code: 404</p>      
      <p class="error-body">
        An error has occurred and we're working to fix the problem! We'll be up and running shortly.
      </p>
      <p class="error-body">
        If you need immediate help from our customer service team about an ongoing reservation, please
        <a class="lnk" href="#">call us</a>.
        If it isn't an urgent matter, please visit our
        <a class="lnk" href="#">Help Center</a>
        for additional information. Thanks for your patience!
      </p>
      <p class="error-body">
        For urgent situations please <a class="lnk" href="#">call us</a> 📞
      </p>
    </div>

    <div class="col-md-6 illustration-col">
		<img src="/images/boom.jpg" style="margin-right: 10px;">
    </div>

  </div>
</div>

</body>
</html>
```

Al ocurrir el error 404 nos apareceria esto:

![image](../../../assets/images/manual/errors/404_dsg.png)


---

## Web vs AJAX / JSON

En `HIX_ShowError` y `HIX_HttpError` se llama a `HIX_WantsJson(oReq)`. Esa
función mira el header `Accept` (`application/json`) y el `X-Requested-With`
del request, y decide:

- **JSON** → responde `{ "error": "...", "code": NNN }` con el status HTTP
  correspondiente. Ignora `errorsys` y `error_XXX.html`.
- **HTML** → aplica todo el pipeline anterior (errorsys custom → renderer
  interno dev/prod → páginas `error_XXX.html`).

Esto significa que:
- Un mismo endpoint que sirve HTML mostrará la página de errorsys.
- El mismo endpoint llamado desde `fetch()` con `Accept: application/json`
  recibirá JSON con `error` y `code`, sin HTML.

No hay que configurar nada: la detección es automática.

---

## 7. Flujo completo (recap visual)

```
Handler PRG lanza excepción no capturada
        │
        ▼
hix_worker_http.prg _HixHTTPProcessOne
        │  TRY / CATCH oError
        ▼
HIX_GetErrorHandler() != NIL ?
        │            │
       sí            no
        │            │
        ▼            ▼
   handler       HIX_ShowError(oError, oReq)
   custom            │
                     ├── log a errors.log
                     │
                     ├── WantsJson(oReq)? → responde JSON, fin
                     │
                     ├── app.errorsys definido y fichero existe?
                     │       │
                     │      sí ── renderiza template
                     │       │        │       │
                     │       │      ok        falla
                     │       │       │         │
                     │       │       ▼         ▼
                     │       │   respuesta   design error page
                     │       │
                     │      no
                     │       │
                     │       ▼
                     └── HIX_ErrorSys(oError)
                              │
                              ├── env=dev → HIX_ErrorSysDev
                              └── env=prod → HIX_ErrorSysProd
```

Para errores HTTP semánticos (404 en el router, 405 en método no permitido,
etc.):

```
Router / dispatcher genera código HTTP
        │
        ▼
HIX_HttpError(oReq, nStatus, cDetail)
        │
        ├── WantsJson(oReq)? → JSON con {error, [detail]}
        │
        └── HIX_HttpErrorHtml(nStatus, cMsg, cDetail)
                │
                ├── www/errors/error_<nStatus>.html existe? → envía fichero
                │
                └── HTML mínimo autogenerado
```

---

