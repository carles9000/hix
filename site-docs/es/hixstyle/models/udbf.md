# 🗄️ UDbf - Acceso a tablas DBF

## ¿Qué es?

`UDbf()` es el wrapper que HixStyle expone sobre la clase `HIX_DBF` para
hablar con **ficheros DBF + CDX** (xBase / Clipper / Harbour) desde tus
controllers como si fueran un modelo de datos moderno.

Encapsula la mecánica xBase (alias, `DbGoTo`, `DbSeek`, `Rlock`, `FieldGet`)
detrás de una API orientada a hashes - los registros entran y salen como
diccionarios `{ "field" => value }`, listos para llevar a JSON, a un
template o a un validator.

```
www/models/tcustomers.prg     ──▶  retorna oDbf configurado y abierto
                                       │
controllers/customer.prg      ──┐      │
   nId := UGetResource()        │      │
   TCustomers():GetRecno(nId, @hRow, NIL, .T.)
                                │
                                ▼
                          hRow = { "first" => "Carles",
                                   "last"  => "Aubia",
                                   "city"  => "Barcelona",
                                   "_recno" => 42,
                                   "_deleted" => .F. }
```

Es el **patrón Model de Fenix**: un `TXxx()` por tabla, los controllers
solo llaman métodos.

---

## Cuándo usarlo

| Caso de uso | UDbf |
|---|---|
| App de gestión sobre DBF/CDX existentes | ✅ Sí - patrón canónico |
| Migración progresiva desde Clipper/Harbour clásico | ✅ Sí |
| Reporting sobre datos históricos en DBF | ✅ Sí |
| Nueva app sobre PostgreSQL / MySQL | ❌ No - usa el adaptador SQL |
| Datos en JSON / NoSQL | ❌ No |
| Cache / configuración en memoria | ❌ No - usa el sistema de cache |

> UDbf no es un ORM. Es un **wrapper directo** sobre la RDD `DBFCDX`.
> No genera SQL, no migra esquemas, no resuelve relaciones; se queda
> en la abstracción xBase clásica.

---

## Crear un modelo

La convención Fenix: un `.prg` por tabla en `www/models/` que devuelve la
instancia configurada y abierta.

```clipper
// www/models/tcustomers.prg
FUNCTION TCustomers()
   LOCAL oCustomers := UDbf()

   oCustomers:cPath := hb_dirbase() + "data"
   oCustomers:cDbf  := "customers.dbf"
   oCustomers:cCdx  := "customers.cdx"
   oCustomers:cTag  := "first"

   oCustomers:Hide( "salary" )    // este campo no debe llegar al hRow
   oCustomers:Open()

RETURN oCustomers
```

```clipper
// www/models/tstates.prg
FUNCTION TStates()
   LOCAL oStates := UDbf()

   oStates:cPath := hb_dirbase() + "data"
   oStates:cDbf  := "states.dbf"
   oStates:cCdx  := "states.cdx"
   oStates:cTag  := "name"

   oStates:Open()
RETURN oStates
```

> El constructor también acepta los argumentos en una sola línea:
> `UDbf( "customers.dbf", "customers.cdx", "first", NIL, .T. )`.
> El patrón Fenix prefiere asignar propiedades para que se lea claro.

---

## Propiedades

| Propiedad | Default | Para qué sirve |
|---|---|---|
| `cPath` | `hb_dirbase()` | Carpeta donde están el .dbf y .cdx |
| `cDbf` | `""` | Nombre del fichero `.dbf` |
| `cCdx` | `""` | Nombre del fichero `.cdx` de índices |
| `cTag` | `""` | Tag activo al abrir |
| `cRdd` | `"DBFCDX"` | RDD (`DBFNTX`, `DBFCDX`, ...) |
| `lExclusive` | `.F.` | Abrir en modo exclusivo (multi-user → `.F.`) |
| `lToUtf8` | `.F.` | Convertir strings a UTF-8 al leer |
| `cAlias` | _(autogen)_ | Alias generado por `NewAlias()` |
| `hFields` | `{=>}` | Estructura: nombre → `{nombre,tipo,len,dec}` |
| `nFields` | _(autocalc)_ | Número de campos visibles |
| `lConnect` | `.F.` | `.T.` si la tabla está abierta |

---

## Apertura y cierre

```clipper
oDbf:Open()              // abre y carga estructura → ::lConnect = .T.
oDbf:Close()             // cierra el área

oDbf:lExclusive := .T.
oDbf:Open()              // exclusivo (Zap, Pack, repair)
```

`Open()` devuelve `.T.` si abre bien. Si falta el fichero o el tag no
existe, llama a `SetError()` y retorna `.F.`.

---

## Navegación

```clipper
oDbf:First()             // DbGoTop
oDbf:Last()              // DbGoBottom
oDbf:Next()              // DbSkip(1)
oDbf:Prev()              // DbSkip(-1)
oDbf:Skip( 5 )           // DbSkip(5)
oDbf:Goto( nRecno )      // DbGoTo(nRecno)

oDbf:Recno()             // recno actual
oDbf:RecCount()          // total registros
oDbf:Bof() / oDbf:Eof()  // límites
```

---

## Búsqueda

```clipper
// Seek por la clave del índice activo
IF oDbf:Seek( "Carles" )
   ? "Encontrado en recno " + Str( oDbf:Recno() )
ENDIF

// Seek en otro índice sin perder el actual
oDbf:Seek( "1234", .F., "id" )

// Cambiar índice activo
oDbf:Focus( "city" )
```

---

## Leer un registro como hash

`Row()` es el corazón del wrapper: convierte el registro actual en un
hash listo para usar.

```clipper
hRow := oDbf:Row()                       // todos los campos visibles
hRow := oDbf:Row( { "first", "last" } )  // solo esos campos
hRow := oDbf:Row( NIL, .T. )             // convertido a string web
```

El hash siempre añade dos campos de control:

| Clave | Valor |
|---|---|
| `_recno` | Número de registro físico |
| `_deleted` | `.T.` / `.F.` (marca de borrado) |

### Modo "string web"

Cuando `lToStringWeb = .T.`, los valores se **serializan a string** listo
para meter en un `<input value="...">`:

| Tipo DBF | Resultado |
|---|---|
| `C`, `M` | `AllTrim(value)` (opcionalmente UTF-8 si `lToUtf8`) |
| `D` | `UDateToHtml( dValue )` → `"2026-06-26"` |
| `N` | `Str( value, len, dec )` |
| `L` | `ULogicToHtmlChecked( value )` → `"checked"` / `""` |

> Es el modo que usan los controllers para llenar formularios HTML.

---

## CRUD básico

### Crear - `Insert`

```clipper
LOCAL hFields := { ;
   "first"  => "Carles",  ;
   "last"   => "Aubia",   ;
   "city"   => "Barcelona" ;
}
LOCAL cError, nNewRecno

IF oDbf:Insert( hFields, @cError, @nNewRecno )
   ? "Creado recno " + Str( nNewRecno )
ELSE
   ? "Error: " + cError
ENDIF
```

`Insert` hace `Append()` + `Update()` en una sola llamada.

### Leer - `GetRecno` / `GetId`

```clipper
LOCAL hRow := {=>}

// Por recno físico
IF oDbf:GetRecno( 42, @hRow, NIL, .T. )
   ? hRow[ "first" ], hRow[ "city" ]
ENDIF

// Por clave del índice activo
IF oDbf:GetId( "Carles", @hRow )
   ? hRow[ "_recno" ]
ENDIF
```

Ambos devuelven `.T.` si el registro existe y rellenan `@hRow` por
referencia. El cuarto parámetro (`lToStringWeb`) es la misma del `Row()`.

### Actualizar - `Update`

```clipper
LOCAL hChanges := { "city" => "Madrid", "salary" => 50000 }
LOCAL cError

IF oDbf:Update( 42, hChanges, @cError )
   ? "Actualizado"
ELSE
   ? "Error: " + cError
ENDIF
```

`Update` hace `Rlock` → `FieldPut` por cada clave del hash → `DbCommit` →
`DbUnlock`.

### Borrar - `Delete`

```clipper
oDbf:Delete( nRecno )                      // marca como borrado
oDbf:Delete( nRecno, .T. )                 // toggle: si está borrado, lo recupera
oDbf:Delete( nRecno, .F., @lIsDeleted )    // @lIsDeleted con el estado final

oDbf:Recall()                              // quitar marca de borrado (recno actual)
oDbf:Pack( @cError )                       // borra físicamente marcados
oDbf:Zap()                                 // vacía la tabla - ⚠️ exclusivo
```

### Registro en blanco para formularios

```clipper
hBlank := oDbf:Blank()              // hash con valores vacíos por tipo
hBlank := oDbf:Blank( .T. )         // en string web (para Form Create)
```

Útil al pintar un form de creación: el template lee del mismo hash que
usará un form de edición.

---

## Listar

### Todos los registros

```clipper
aRows := oDbf:LoadAll()                            // todos los campos visibles
aRows := oDbf:LoadAll( { "first", "city" } )       // solo esos
aRows := oDbf:LoadAll( NIL, "A", "C" )             // scope: from "A" to "C"
aRows := oDbf:LoadAll( NIL, , , {|a| !Deleted() } ) // con condición codeblock
```

Devuelve un array de hashes (uno por registro). Aplica `OrdScope` si se
pasan `cScopeTop`/`cScopeBottom`.

### Paginación

```clipper
LOCAL nTotalPages
LOCAL aRows := oDbf:Page( 1, 20, NIL, @nTotalPages )

// nTotalPages devuelto por referencia
? "Página 1/" + Str( nTotalPages ) + " - " + Str( Len( aRows ) ) + " filas"
```

`Page( nPage, nRows, aFields, @nTotalPages )`:

- Calcula `nTotalPages` redondeando hacia arriba.
- Si `nPage > nTotalPages`, recolocará en la última página.
- Usa `OrdKeyGoto` si hay índice activo, `DbGoto` si no.

---

## Visibilidad de campos

Útil para ocultar campos sensibles (`salary`, `password`) del hash que
viaja a templates / JSON:

```clipper
oDbf:Hide( "salary" )                      // un solo campo
oDbf:Hide( { "salary", "ssn", "passwd" } ) // varios

oDbf:Visible( { "id", "first", "last" } )  // whitelist: solo estos
```

| Método | Comportamiento |
|---|---|
| `Hide( aFields )` | Lista negra - todos menos esos |
| `Visible( aFields )` | Lista blanca - solo esos |

Aplicar **antes** de `Open()`. La estructura `hFields` se recorta al
abrir según la selección.

---

## Bloqueos

```clipper
IF oDbf:Rlock()
   oDbf:FieldPut( "city", "Madrid" )
   oDbf:Unlock()
ENDIF
```

`Rlock()` reintenta hasta `nTime` segundos (default 3s) antes de fallar.
Si falla, llama a `SetError( DBF_ERR_LOCK )` y retorna `.F.`.

> `Update()` e `Insert()` ya gestionan el lock/unlock - solo hace falta
> llamar a `Rlock()` directamente cuando haces `FieldPut` manuales.

---

## Patrón completo Fenix - Customer Edit

### El controller llama al modelo

```clipper
METHOD Edit() CLASS Customer
   LOCAL oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" } } )
   LOCAL oCustomers, oStates, hRow := {=>}
   LOCAL aStates, lFound

   IF ! oVal:Make()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF

   oStates := TStates()                    // ← UDbf de states
   aStates := oStates:LoadAll()

   oCustomers := TCustomers()              // ← UDbf de customers
   lFound := oCustomers:GetRecno( oVal:Get( "id" ), @hRow, NIL, .T. )

   IF ! lFound
      hRow := oCustomers:Blank( .T. )      // en blanco para "create"
   ENDIF

RETURN UView( "masters/customer/edit.html", "edit", lFound, hRow, aStates )
```

### Update

```clipper
METHOD Update() CLASS Customer
   LOCAL cId := UGetResource()
   LOCAL oVal, oCustomers, lSuccess, cError

   oVal := UValidatePost( { ;
      "first" => "required|string|max:20|field", ;
      "city"  => "required|string|max:30|field", ;
      "age"   => "required|numeric|max:99|field" ;
   } )

   IF ! oVal:Make()
      UFlash( "customer" ):Set( { "errors" => oVal:GetErrors(), "input" => oVal:Resume() } )
      RETURN URedirect( URoute( "customer.edit", Val( cId ) ) )
   ENDIF

   oCustomers := TCustomers()
   lSuccess := oCustomers:Update( Val( cId ), oVal:DataFields(), @cError )

   IF lSuccess
      UFlash( "customer" ):Set( { "message" => "Actualizado" } )
      RETURN URedirect( URoute( "customer.show", Val( cId ) ) )
   ELSE
      UFlash( "customer" ):Set( { "message" => cError } )
      RETURN URedirect( URoute( "customer.edit", Val( cId ) ) )
   ENDIF
RETURN
```

Observa la simbiosis con el **validator**:

| Helper | Devuelve |
|---|---|
| `oVal:DataFields()` | Solo claves marcadas con `field` en las reglas |
| `oVal:Resume()` | Todo el input original (para volver a pintar el form) |

`DataFields` está pensado para alimentar directamente `oDbf:Update()`.

---

## UTF-8 y encoding

Los DBF clásicos suelen estar en **CP437** o **CP850**. Para que los
strings lleguen como UTF-8 al navegador:

```clipper
oDbf:lToUtf8 := .T.
oDbf:Open()
```

Con `lToUtf8 = .T.`, `Row()` aplica `hb_StrToUtf8()` a los campos `C` y
`M` antes de devolverlos.

> Si lo activas, **escribe siempre desde UTF-8** o tendrás caracteres
> rotos. Lo mejor: configurar bien el codepage de Harbour en el `.prg`
> principal con `REQUEST HB_CODEPAGE_*` antes de tocar nada.

---

## Errores

`UDbf` captura errores xBase en `TRY/CATCH` y los reenruta a `HIX_Throw`,
que el dispatcher de HIX recoge para pintar la página de error
correspondiente.

```clipper
oDbf:lDoError := .F.    // desactiva el throw automático
oDbf:Open()
IF ! oDbf:lConnect
   ? "Error: " + oDbf:oError:description
ENDIF
```

---

## Buenas prácticas

1. **Un modelo `TXxx()` por tabla.** Encapsula `cPath`, `cDbf`, `cCdx`,
   `cTag`, `Hide/Visible` en una sola función reusable.
2. **Cierra lo que abras.** En workers HTTP, el alias vive en el thread
   pool. Usa `Close()` al final del request o confía en el GC del area
   ID por hilo.
3. **`Hide` campos sensibles.** Salarios, passwords, claves internas no
   deberían llegar nunca a un template o JSON.
4. **`lToStringWeb = .T.` para forms.** Evita strings xBase con espacios
   de relleno o fechas con formato local.
5. **Combina con el validator.** `oVal:DataFields()` → `oDbf:Update()`
   es el patrón directo, sin código adhoc.
6. **`Update` solo claves cambiadas.** Pasa solo los campos modificados
   en el hash - `Update()` recorre las claves del hash, no toca otras.
7. **`Rlock` no es eterno.** Default 3s - sube `oDbf:nTime` si tu app
   tiene mucha concurrencia, o decide reintentar a nivel controller.

