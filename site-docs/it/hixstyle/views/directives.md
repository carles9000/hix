# 🕸️ Direttive - Harbour

## Codice Harbour
Ogni direttiva deve iniziare con **@**. Queste direttive sono esclusive di Harbour e sono progettate per eseguire processi specifici. Le divideremo in due tipi: `Direttive` e `Funzionali`.

### Direttive Harbour

#### `@args` <parametri,...>
Quando esegui una view, puoi passare i parametri di cui hai bisogno. All'interno della view, definisci i nomi di questi parametri nell'ordine in cui vengono inviati da un controller. Se lo desideri, puoi inizializzare la variabile nel caso usi la view da più controller e uno non invia il parametro.

```
@args aData, lActive := .F.
```

#### `@global` <variabili,...>
Questa direttiva permette di dichiarare variabili che possono essere utilizzate in tutto lo script, visibili da qualsiasi direttiva, funzione, macro, ecc. Proprio come `@args`, puoi inizializzare con un valore.

```
@global nTotal, lCanDelete := .F. 
```

#### `@if` <Condizione>
Direttiva IF, che può essere usata con `@elseif`, `@else` e `@endif`. Puoi concatenare quanti `@elseif` ti servono prima dell'`@else` finale.

```html
@if lActive

   <div>
     <p>Messaggio: Non puoi accedere al modulo...</p>
   </div>

@elseif lPending

   <div>
     <p>Il tuo accesso è in attesa di approvazione.</p>
   </div>

@else

   <div>
     <p>Accesso negato!</p>
   </div>
   
@endif
```

#### `@foreach` <oItem in aData>

Direttiva FOREACH, che si usa con `@endforeach`. Itera su un array.

```html
<ul>
   @foreach oItem in aData
      <li> Elemento {{ oItem:name }} </li>
   @endforeach
</ul>
```

#### `@for`

Direttiva FOR, usata con `@next`

```html
<ul>
   @for n := 5 to 10
     <li> Elemento {{ n }} </li>
   @next
</ul>

```
### Helper di iniezione

Queste direttive non controllano il flusso: inseriscono contenuto HTML già preparato nel punto in cui vengono scritte.

#### `@view` <espressione>

Renderizza un'altra view inline e emette il suo HTML nella posizione corrente. L'espressione è esattamente la stessa di una chiamata a `UView()` - il primo parametro è il path della view (relativo a `<cRoot>/views/`), il resto sono i parametri che riceve.

```html
<div class="layout">
   @view 'partials/menu.html', hUser
   <main>
      @view 'dashboard/kpis.html', aMetrics, lAdmin
   </main>
</div>
```

#### `@css` <file>

Emette un `<link rel="stylesheet">` che punta al file CSS specificato dentro `<cRoot>/public/css/` (in modalità HixStyle). Solleva un errore 404 se il file non esiste.

```html
@css 'app.css'
@css 'theme/dark.css'
```

Equivalente HTML:

```html
<link href="/public/css/app.css" rel="stylesheet">
```

#### `@js` <file>

Emette un `<script src="...">` che punta al file JS specificato dentro `<cRoot>/public/js/` (in modalità HixStyle). Solleva un errore 404 se il file non esiste.

```html
@js 'app.js'
@js 'modules/charts.js'
```

#### `@csrf`

Inserisce l'`<input type="hidden">` con il token CSRF della sessione corrente, pronto da mettere dentro un `<form>`. Equivalente a chiamare manualmente `UCsrfToHtml()`.

```html
<form method="POST" action="/users/save">
   @csrf
   <input name="name" type="text" />
   <button type="submit">Salva</button>
</form>
```

Richiede che il middleware `HIX_MwCsrf` sia attivo sulla route. Vedi [Sicurezza → CSRF](../seguridad/csrf.md).

#### `@resource` <id>

Inserisce l'`<input type="hidden">` con un identificatore firmato HMAC per una specifica risorsa. Lo usi nei form di edit/delete così che il controller possa poi validare con `UGetResource()` che l'id non è stato manomesso.

```html
<form method="POST" action="/invoices/delete">
   @csrf
   @resource nInvoiceId
   <button type="submit">Elimina fattura</button>
</form>
```

Vedi [Sicurezza → Resources & IDs](../seguridad/resources-ids.md).

### Funzionali

#### `@prg`

Questa è una direttiva speciale perché permette di eseguire codice Harbour dentro il blocco, come routine funzionale. Può contenere funzioni e agisce come puro Harbour. Il blocco si chiude con la direttiva `@endprg`. Qualsiasi blocco `@prg` ritorna un risultato che viene inserito esattamente dove è stato definito.

Aspetti importanti:

- Un blocco ritorna sempre un risultato che viene inserito nel punto in cui è stato definito.

- Puoi usare le stesse variabili definite con `@global` in diversi blocchi.

- Dentro un blocco, puoi definire funzioni che saranno visibili da altri blocchi, che siano definiti prima o dopo.

- Non puoi definire direttive dentro `@prg`/`@endprg`.

- Non puoi usare le macro `{{ }}` o `{!! !!}`. Le macro sono solo per inserire codice del contenitore in mezzo all'HTML.

- È responsabilità dello sviluppatore fare l'escape o meno del risultato.

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
<h3>Fine del riepilogo</h3>
<hr>
```

## Riepilogo delle direttive

| Gruppo | Direttive | Spiegazione |
|-------|------------|-------------|
| **Parametri** | `@args` | Definisce i parametri che la view riceve dal controller. |
| **Variabili** | `@global` | Dichiara variabili accessibili globalmente in tutta la view. |
| **Condizionali** | `@if` / `@elseif` / `@else` / `@endif` | Struttura condizionale con rami concatenati. |
| **Cicli** | `@foreach` / `@endforeach` | Itera su collezioni o array, attraversando ogni elemento. |
| **Cicli** | `@for` / `@next` | Ciclo contatore classico che esegue un numero definito di iterazioni. |
| **Blocchi di codice** | `@prg` / `@endprg` | Blocco di puro Harbour che permette logica complessa e ritorna un risultato inserito nella view. |
| **Sub-view** | `@view` | Renderizza un'altra view inline e ne inserisce l'HTML. |
| **Asset** | `@css` / `@js` | Inserisce `<link>` o `<script>` che puntano a `<cRoot>/public/css/` o `/public/js/`. |
| **Sicurezza** | `@csrf` | Inserisce l'<input> hidden con il token CSRF corrente. |
| **Sicurezza** | `@resource` | Inserisce l'<input> hidden con l'id HMAC-firmato per la risorsa specificata. |
| **Macro di iniezione** | `{{ }}` / `{!! !!}` | Macro per iniettare Harbour nell'HTML; la prima fa l'escape automatico, la seconda no. |
