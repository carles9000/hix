# Vistas

Motor de plantillas sencillo. Ficheros bajo `www/views/` con extensión `.view.html`.

## Anatomía

    <!-- users.edit.view.html -->
    @args cName, nAge, aRoles

    <!DOCTYPE html>
    <html>
    <head><title>Editar {{ cName }}</title></head>
    <body>
      <h1>Editando {{ cName }}</h1>
      <p>Edad: {{ hb_NToS(nAge) }}</p>
      <p>Roles: {{ hb_JsonEncode(aRoles) }}</p>
    </body>
    </html>

## Reglas

- La **primera línea** es `@args` listando cada variable que espera la plantilla.
- `{{ expr }}` se evalúa como Harbour y se inserta (se permite cualquier expresión).
- **Sin bloques de control** (nada de `{{ if }}`, `{{ for }}`) — haz bucles/ramas en el controller y pasa las piezas ya listas.
- Se admiten los comentarios HTML `<!-- -->`. **Nunca** uses `{{-- --}}` — el motor intenta evaluarlo.
- Extensión `.view.html` para plantillas (renderizadas vía acción). `.html` plano = fichero estático (solo servido desde `public/`).

## Renderizado

Desde un controller / acción de ruta:

    USendView( "users.edit.view.html", { ;
       "cName"  => "Charly", ;
       "nAge"   => 42,        ;
       "aRoles" => { "admin", "user" } ;
    } )

Solo renderizar (sin enviar):

    LOCAL cHtml := UView( "partials/header.view.html", { "cTitle" => "Mi app" } )

## Parciales

No hay `@include` nativo. Compón con múltiples `UView`:

    LOCAL cHead := UView( "partials/head.view.html",  {} )
    LOCAL cNav  := UView( "partials/nav.view.html",   { "aItems" => aMenu } )
    LOCAL cBody := UView( "users.list.view.html",     { "aRows"  => aRows } )
    USendHtml( cHead + cNav + cBody )

## Escapado

`{{ expr }}` NO escapa HTML por defecto. Para input no confiable:

    {{ HIX_EscapeHtml( cUserInput ) }}

## Expresiones comunes

    {{ hb_NToS( nValor ) }}                  Número a string
    {{ DToC( dFecha ) }}                     Fecha a string
    {{ iif( lActivo, "Sí", "No" ) }}         Condicional
    {{ Upper( cNombre ) }}                   Mayúsculas
    {{ hb_JsonEncode( hDatos ) }}            JSON inline (para JS)

## Iterar

Los bucles ocurren en el controller. Ensambla líneas HTML y pasa un string:

    LOCAL cRows := ""
    FOR EACH hRow IN aRows
       cRows += UView( "partials/user_row.view.html", { "hRow" => hRow } )
    NEXT
    USendView( "users.list.view.html", { "cRows" => cRows } )

Y en `users.list.view.html`:

    @args cRows
    <table>
      <thead><tr><th>Nombre</th><th>Email</th></tr></thead>
      <tbody>{{ cRows }}</tbody>
    </table>

## Layout / plantilla maestra

Mismo truco — el controller renderiza la vista interna primero, luego la maestra:

    LOCAL cContent := UView( "users.list.view.html", { "aRows" => aRows } )
    USendView( "layouts/main.view.html", { "cTitle" => "Usuarios", "cContent" => cContent } )

## Depurar plantillas

Si la página sale en blanco o casca:
- Confirma que `@args` lista exactamente las variables que pasas (nombre extra/faltante → error en runtime).
- Cualquier `{{ ... }}` que devuelva `NIL` u objeto → error.
- Consulta el log — el dispatcher registra errores de compilación de plantilla con nombre de fichero y línea.
