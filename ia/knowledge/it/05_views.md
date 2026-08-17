# View

Motore di template semplice. File sotto `www/views/` con estensione `.view.html`.

## Anatomia

    <!-- users.edit.view.html -->
    @args cName, nAge, aRoles

    <!DOCTYPE html>
    <html>
    <head><title>Edit {{ cName }}</title></head>
    <body>
      <h1>Editing {{ cName }}</h1>
      <p>Age: {{ hb_NToS(nAge) }}</p>
      <p>Roles: {{ hb_JsonEncode(aRoles) }}</p>
    </body>
    </html>

## Regole

- La **prima riga** è `@args` con l'elenco di ogni variabile che il template si aspetta.
- `{{ expr }}` viene valutato come Harbour e inserito (qualsiasi espressione consentita).
- **Nessun blocco di controllo** (no `{{ if }}`, `{{ for }}`) — fai loop/branch nel controller e passa i pezzi finiti.
- I commenti HTML `<!-- -->` sono supportati. **Mai** usare `{{-- --}}` — il motore prova a valutarlo.
- Estensione `.view.html` per i template (renderizzati via action). Plain `.html` = file statico (servito solo da `public/`).

## Rendering

Da un controller / action di route:

    USendView( "users.edit.view.html", { ;
       "cName"  => "Charly", ;
       "nAge"   => 42,        ;
       "aRoles" => { "admin", "user" } ;
    } )

Solo render (no send):

    LOCAL cHtml := UView( "partials/header.view.html", { "cTitle" => "My app" } )

## Partial

Nessun `@include` nativo. Componi tramite più chiamate `UView`:

    LOCAL cHead := UView( "partials/head.view.html",  {} )
    LOCAL cNav  := UView( "partials/nav.view.html",   { "aItems" => aMenu } )
    LOCAL cBody := UView( "users.list.view.html",     { "aRows"  => aRows } )
    USendHtml( cHead + cNav + cBody )

## Escape

`{{ expr }}` NON fa l'escape HTML di default. Per input non fidato:

    {{ HIX_EscapeHtml( cUserInput ) }}

## Espressioni comuni

    {{ hb_NToS( nValue ) }}                  Numero in stringa
    {{ DToC( dDate ) }}                      Data in stringa
    {{ iif( lActive, "Yes", "No" ) }}        Condizionale
    {{ Upper( cName ) }}                     Maiuscolo
    {{ hb_JsonEncode( hData ) }}             JSON inline (per JS)

## Iterazione

I loop avvengono nel controller. Assembla le righe HTML e passa una stringa:

    LOCAL cRows := ""
    FOR EACH hRow IN aRows
       cRows += UView( "partials/user_row.view.html", { "hRow" => hRow } )
    NEXT
    USendView( "users.list.view.html", { "cRows" => cRows } )

Poi in `users.list.view.html`:

    @args cRows
    <table>
      <thead><tr><th>Name</th><th>Email</th></tr></thead>
      <tbody>{{ cRows }}</tbody>
    </table>

## Layout / template master

Stesso trucco — il controller renderizza prima la view interna, poi il master:

    LOCAL cContent := UView( "users.list.view.html", { "aRows" => aRows } )
    USendView( "layouts/main.view.html", { "cTitle" => "Users", "cContent" => cContent } )

## Debug dei template

Se la pagina renderizza vuota o va in crash:
- Conferma che `@args` elenchi esattamente le variabili che stai passando (nome extra/mancante → errore a runtime).
- Qualsiasi `{{ ... }}` che ritorna `NIL` o un oggetto → errore.
- Controlla il log — il dispatcher logga gli errori di compilazione del template con il nome del file e la riga.
