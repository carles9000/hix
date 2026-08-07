# Views

Simple template engine. Files under `www/views/` with extension `.view.html`.

## Anatomy

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

## Rules

- **First line** is `@args` listing every variable the template expects.
- `{{ expr }}` is evaluated as Harbour and inserted (any expression allowed).
- **No control blocks** (no `{{ if }}`, `{{ for }}`) — do loops/branches in the controller and pass the finished pieces in.
- HTML comments `<!-- -->` are supported. **Never** use `{{-- --}}` — the engine tries to eval it.
- Extension `.view.html` for templates (rendered via action). Plain `.html` = static file (served from `public/` only).

## Rendering

From a controller / route action:

    USendView( "users.edit.view.html", { ;
       "cName"  => "Charly", ;
       "nAge"   => 42,        ;
       "aRoles" => { "admin", "user" } ;
    } )

Just render (no send):

    LOCAL cHtml := UView( "partials/header.view.html", { "cTitle" => "My app" } )

## Partials

No native `@include`. Compose via multiple `UView` calls:

    LOCAL cHead := UView( "partials/head.view.html",  {} )
    LOCAL cNav  := UView( "partials/nav.view.html",   { "aItems" => aMenu } )
    LOCAL cBody := UView( "users.list.view.html",     { "aRows"  => aRows } )
    USendHtml( cHead + cNav + cBody )

## Escaping

`{{ expr }}` does NOT escape HTML by default. For untrusted input:

    {{ HIX_EscapeHtml( cUserInput ) }}

## Common expressions

    {{ hb_NToS( nValue ) }}                  Number to string
    {{ DToC( dDate ) }}                      Date to string
    {{ iif( lActive, "Yes", "No" ) }}        Conditional
    {{ Upper( cName ) }}                     Uppercase
    {{ hb_JsonEncode( hData ) }}             Inline JSON (for JS)

## Iterating

Loops happen in the controller. Assemble HTML lines and pass a string in:

    LOCAL cRows := ""
    FOR EACH hRow IN aRows
       cRows += UView( "partials/user_row.view.html", { "hRow" => hRow } )
    NEXT
    USendView( "users.list.view.html", { "cRows" => cRows } )

Then in `users.list.view.html`:

    @args cRows
    <table>
      <thead><tr><th>Name</th><th>Email</th></tr></thead>
      <tbody>{{ cRows }}</tbody>
    </table>

## Layout / master template

Same trick — controller renders inner view first, then master:

    LOCAL cContent := UView( "users.list.view.html", { "aRows" => aRows } )
    USendView( "layouts/main.view.html", { "cTitle" => "Users", "cContent" => cContent } )

## Debugging templates

If the page renders blank or crashes:
- Confirm `@args` lists exactly the variables you're passing (extra/missing name → runtime error).
- Any `{{ ... }}` that returns `NIL` or an object → error.
- Check log — the dispatcher logs template compile errors with the file name and line.
