# 🕸️ Directives - Harbour

## Harbour Code
Each directive must begin with **@**. These directives are exclusive to Harbour and are designed to execute specific processes. We will divide them into two types: `Directives` and `Functional`.

### Harbour Directives

#### `@args` <parameters,...>
When executing a view, you can pass the parameters you need. Within the view, you define the names of these parameters in the order they are sent from a controller. If desired, you can initialize the variable in case you use the view from several controllers and one does not send the parameter.

```
@args aData, lActive := .F.
```

#### `@global` <variables,...>
This directive allows you to declare variables that can be used throughout the script, visible from any directive, function, macro, etc. Just like `@args`, you can initialize with a value.

```
@global nTotal, lCanDelete := .F. 
```

#### `@if` <Condition>
IF directive, which can be used with `@elseif`, `@else` and `@endif`. You can chain as many `@elseif` as needed before the final `@else`.

```html
@if lActive

   <div>
     <p>Message: You cannot access the module...</p>
   </div>

@elseif lPending

   <div>
     <p>Your access is pending approval.</p>
   </div>

@else

   <div>
     <p>Access denied!</p>
   </div>
   
@endif
```

#### `@foreach` <oItem in aData>

FOREACH directive, which is used with `@endforeach`. Iterates through an array.

```html
<ul>
   @foreach oItem in aData
      <li> Element {{ oItem:name }} </li>
   @endforeach
</ul>
```

#### `@for`

FOR directive, used with `@next`

```html
<ul>
   @for n := 5 to 10
     <li> Element {{ n }} </li>
   @next
</ul>

```
### Injection Helpers

These directives do not control flow: they insert already-prepared HTML content at the point where they are written.

#### `@view` <expression>

Renders another view inline and outputs its HTML at the current position. The expression is exactly the same as a call to `UView()` — the first parameter is the view path (relative to `<cRoot>/views/`), the rest are the parameters it receives.

```html
<div class="layout">
   @view 'partials/menu.html', hUser
   <main>
      @view 'dashboard/kpis.html', aMetrics, lAdmin
   </main>
</div>
```

#### `@css` <file>

Emits a `<link rel="stylesheet">` pointing to the CSS file specified within `<cRoot>/public/css/` (in HixStyle mode). Throws a 404 error if the file does not exist.

```html
@css 'app.css'
@css 'theme/dark.css'
```

HTML equivalent:

```html
<link href="/public/css/app.css" rel="stylesheet">
```

#### `@js` <file>

Emits a `<script src="...">` pointing to the JS file specified within `<cRoot>/public/js/` (in HixStyle mode). Throws a 404 error if the file does not exist.

```html
@js 'app.js'
@js 'modules/charts.js'
```

#### `@csrf`

Inserts the `<input type="hidden">` with the current session's CSRF token, ready to place inside a `<form>`. Equivalent to manually calling `UCsrfToHtml()`.

```html
<form method="POST" action="/users/save">
   @csrf
   <input name="name" type="text" />
   <button type="submit">Save</button>
</form>
```

Requires that the `HIX_MwCsrf` middleware is active in the route. See [Security → CSRF](../seguridad/csrf.md).

#### `@resource` <id>

Inserts the `<input type="hidden">` with an HMAC-signed identifier for a specific resource. You use it in edit/delete forms so the controller can later validate with `UGetResource()` that the id was not tampered with.

```html
<form method="POST" action="/invoices/delete">
   @csrf
   @resource nInvoiceId
   <button type="submit">Delete invoice</button>
</form>
```

See [Security → Resources & IDs](../seguridad/resources-ids.md).

### Functional

#### `@prg`

This is a special directive because it allows you to execute Harbour code inside the block, as a functional routine. It can contain functions and acts as pure Harbour. The block closes with the `@endprg` directive. Any `@prg` block returns a result that is inserted right where it was defined.

Important aspects:

- A block always returns a result that is inserted at the point where it was defined.

- You can use the same variables defined with `@global` in different blocks.

- Within a block, you can define functions that will be visible from other blocks, whether they are defined before or after.

- You cannot define directives inside `@prg`/`@endprg`.

- You cannot use the `{{ }}` or `{!! !!}` macros. Macros are only for inserting container code in the middle of HTML.

- It is the developer's responsibility to escape or not the result.

```clipper
<h1>Ticket</h1>
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
<h3>End of summary</h3>
<hr>
```

## Summary of Directives

| Group | Directives | Explanation |
|-------|------------|-------------|
| **Parameters** | `@args` | Defines the parameters that the view receives from the controller. |
| **Variables** | `@global` | Declares variables accessible globally throughout the view. |
| **Conditionals** | `@if` / `@elseif` / `@else` / `@endif` | Conditional structure with chained branches. |
| **Loops** | `@foreach` / `@endforeach` | Iterates over collections or arrays, traversing each element. |
| **Loops** | `@for` / `@next` | Classic counter loop that executes a defined number of iterations. |
| **Code blocks** | `@prg` / `@endprg` | Block of pure Harbour that allows complex logic and returns a result inserted in the view. |
| **Sub-views** | `@view` | Renders another view inline and inserts its HTML. |
| **Assets** | `@css` / `@js` | Inserts `<link>` or `<script>` pointing to `<cRoot>/public/css/` or `/public/js/`. |
| **Security** | `@csrf` | Inserts the hidden `<input>` with the current CSRF token. |
| **Security** | `@resource` | Inserts the hidden `<input>` with the HMAC-signed id for the specified resource. |
| **Injection macros** | `{{ }}` / `{!! !!}` | Macros for injecting Harbour into HTML; the first is automatically escaped, the second is not. |
