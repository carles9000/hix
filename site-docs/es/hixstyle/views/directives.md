# 🕸️ Directivas - Harbour

## Código de Harbour
Cada directiva debe comenzar con **@**. Estas directivas son
exclusivas de Harbour y están diseñadas para ejecutar procesos específicos. 
Las dividiremos en dos tipos: `Directivas` y `Funcionales`.

### Directivas de Harbour

#### `@args` <parámetros,...>
Al ejecutar una vista, puedes pasar los parámetros que necesites. Dentro de 
la vista, defines los nombres de estos parámetros en el orden en que se envían 
desde un controlador. Si deseamos podemos inicializar la variable por si utilizamos 
la vista desde varios controladores y alguno no envia el parámetro 

```
@args aData, lActive := .F.
```

#### `@global` <variables,...>
Esta directiva permite declarar variables que se pueden usar en todo el script, 
visibles desde cualquier directiva, función, macro, etc. Al igual que los `@args` 
podemos inicializar con valor.

```
@global nTotal, lCanDelete := .F. 
```

#### `@if` <Condición>
Directiva IF, que se puede usar con `@elseif`, `@else` y `@endif`. Se pueden 
encadenar tantos `@elseif` como se necesiten antes del `@else` final.

```html
@if lActive

   <div>
     <p>Mensaje: No puedes acceder al módulo...</p>
   </div>

@elseif lPending

   <div>
     <p>Tu acceso está pendiente de aprobación.</p>
   </div>

@else

   <div>
     <p>¡Acceso denegado!</p>
   </div>
   
@endif
```

#### `@foreach` <oItem in aData>

Directiva FOREACH, que se usa con `@endforeach`. Recorre un array.

```html
<ul>
   @foreach oItem in aData
      <li> Elemento {{ oItem:name }} </li>
   @endforeach
</ul>
```

#### `@for`

Directiva FOR, utilizada con `@next`

```html
<ul>
   @for n := 5 to 10
     <li> Elemento {{ n }} </li>
   @next
</ul>

```
### Helpers de inyección

Estas directivas no controlan flujo: insertan contenido HTML ya preparado en 
el punto donde se escriben.

#### `@view` <expresión>

Renderiza otra vista en línea y vuelca su HTML en la posición actual. La 
expresión es exactamente igual a una llamada a `UView()` — primer parámetro 
es la ruta de la vista (relativa a `<cRoot>/views/`), el resto son los 
parámetros que recibe.

```html
<div class="layout">
   @view 'partials/menu.html', hUser
   <main>
      @view 'dashboard/kpis.html', aMetrics, lAdmin
   </main>
</div>
```

#### `@css` <fichero>

Emite un `<link rel="stylesheet">` apuntando al CSS indicado dentro de 
`<cRoot>/public/css/` (en modo HixStyle). Lanza error 404 si el fichero no 
existe.

```html
@css 'app.css'
@css 'theme/dark.css'
```

Equivalente HTML:

```html
<link href="/public/css/app.css" rel="stylesheet">
```

#### `@js` <fichero>

Emite un `<script src="...">` apuntando al JS indicado dentro de 
`<cRoot>/public/js/` (en modo HixStyle). Lanza error 404 si el fichero no 
existe.

```html
@js 'app.js'
@js 'modules/charts.js'
```

#### `@csrf`

Inserta el `<input type="hidden">` con el token CSRF actual de la sesión, 
listo para meter dentro de un `<form>`. Equivalente a invocar 
`UCsrfToHtml()` manualmente.

```html
<form method="POST" action="/users/save">
   @csrf
   <input name="name" type="text" />
   <button type="submit">Guardar</button>
</form>
```

Requiere que el middleware `HIX_MwCsrf` esté activo en la ruta. Ver 
[Seguridad → CSRF](../seguridad/csrf.md).

#### `@resource` <id>

Inserta el `<input type="hidden">` con un identificador firmado HMAC para 
un recurso concreto. Lo usas en formularios de edición/borrado para que el 
controlador valide después con `UGetResource()` que el id no fue manipulado.

```html
<form method="POST" action="/invoices/delete">
   @csrf
   @resource nInvoiceId
   <button type="submit">Borrar factura</button>
</form>
```

Ver [Seguridad → Resources & IDs](../seguridad/resources-ids.md).

### Funcional

#### `@prg`

Esta es una directiva especial porque permite ejecutar código Harbour dentro 
del bloque, como una rutina funcional. Puede contener funciones y actúa como 
Harbour puro. El bloque se cierra con la directiva `@endprg`. Cualquier bloque 
`@prg` devuelve un resultado que se inserta justo donde se definió. 

Aspectos importantes:

- Un bloque siempre devuelve un resultado que se inserta en el punto donde se 
definió. 

- Puedes usar las mismas variables definidas con `@global` en diferentes bloques.

- Dentro de un bloque, puedes definir funciones que serán visibles desde otros 
bloques, ya sea que se definan antes o después.

- No puedes definir directivas dentro de `@prg`/`@endprg`.

- No puedes usar las macros `{{ }}` ni `{!! !!}`. Las macros solo sirven para 
insertar código contenedor en medio del HTML.

- Es responsabilidad del desarrollador escapar o no el resultado.

```clipper
<h1>Boleto</h1>
<hr>

@prg

  local cHtml := ''
  local n

  for n := 1 to len( aData )
    cHtml += '<br>' + aData[n][ 'name' ] + ' ' + CalcPrice( aData[n][ 'qty'] )
  next

return cHtml

//------------------------------------------------- //

function CalcPrice( nQty )

   do case
     case nQty > 10 ; nPrice := 8
     case nQty > 5 ; nPrecio := 9
   otherwise
     nPrecio := 10
   endcase 

return ltrim(str( nPrecio * nCantidad ))

@endprg

<hr>
<h3>Fin del resumen</h3>
<hr>
```

## Resumen de directivas

| Grupo | Directivas | Explicación |
|-------|------------|-------------|
| **Parámetros** | `@args` | Define los parámetros que la vista recibe del controlador. |
| **Variables** | `@global` | Declara variables accesibles globalmente en toda la vista. |
| **Condicionales** | `@if` / `@elseif` / `@else` / `@endif` | Estructura condicional con ramas encadenadas. |
| **Bucles** | `@foreach` / `@endforeach` | Itera sobre colecciones o matrices, recorriendo cada elemento. |
| **Bucles** | `@for` / `@next` | Bucle contador clásico que ejecuta un número definido de iteraciones. |
| **Bloques de código** | `@prg` / `@endprg` | Bloque de Harbour puro que permite lógica compleja y devuelve un resultado insertado en la vista. |
| **Sub-vistas** | `@view` | Renderiza otra vista en línea e inserta su HTML. |
| **Assets** | `@css` / `@js` | Inserta `<link>` o `<script>` apuntando a `<cRoot>/public/css/` o `/public/js/`. |
| **Seguridad** | `@csrf` | Inserta el `<input>` oculto con el token CSRF actual. |
| **Seguridad** | `@resource` | Inserta el `<input>` oculto con el id firmado HMAC para el recurso indicado. |
| **Macros de inyección** | `{{ }}` / `{!! !!}` | Macros para inyectar Harbour en HTML; la primera se escapa automáticamente, la segunda no. |