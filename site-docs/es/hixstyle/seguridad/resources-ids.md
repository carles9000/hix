# 🆔 Resource IDs

## ¿Qué problema resuelve?

Un formulario de edición típico embebe el ID del recurso como hidden:

```html
<input type="hidden" name="recno" value="42">
```

Pero ese ID viaja **en claro**. Cualquier usuario puede inspeccionar el
HTML, cambiar el `42` por un `99` y enviar el POST a `/customer/edit`
para modificar un registro **que no es suyo**. Hace falta o:

1. Volver a chequear permisos sobre el `99` en el servidor _(lo correcto,
   pero costoso y fácil de olvidar)_.
2. **Firmar el ID** para que el cliente no lo pueda alterar - esa es la
   solución que ofrece `UResourceToHtml`.

```
Cliente recibe   <input ... value="MTAwfDE3MzQ...sig=abc123">  (firmado)
Cliente envía    _resource_id=MTAwfDE3MzQ...sig=abc123
Servidor         UGetResource() -> "100"  (válido, lo aceptamos)
Servidor         si el cliente alteró 1 byte -> UGetResource() -> ""
```

El token contiene el ID + timestamp + firma **HMAC** con `app_key`. Sin
saber el secret, el atacante no puede generar uno válido para otro ID.

---

## ¿Cuándo usarlo?

| Caso de uso | Resource IDs |
|---|---|
| Form de edición / borrado de un registro concreto | ✅ Sí |
| Listas con acciones tipo `<button data-id="42">` | ✅ Sí |
| ID de cliente / pedido / factura que viaja en URL | ⚠️ No - la URL es `/customer/:id`, ahí ya hay middleware de auth |
| Token de descarga de fichero one-shot | ✅ Sí |
| API REST con JWT | ❌ No - el JWT identifica al usuario; valida ownership con queries |

> **No sustituyen al chequeo de permisos.** Resource IDs garantizan
> *integridad* del ID (no fue manipulado), no *autorización*. Sigues
> necesitando comprobar que el usuario actual puede editar ese registro
> concreto.

---

## API

### Generar - en el controller / template

```clipper
USetView( "cResourceHtml", UResourceToHtml( nRecno ) )
```

```html
<form method="POST" action="/customer/edit">
  {{ UCsrfToHtml() }}
  {{ UResourceToHtml( nRecno ) }}
  <input name="first" value="{{ hRow['first'] }}">
  ...
  <button>Guardar</button>
</form>
```

`UResourceToHtml( "100" )` genera algo como:

```html
<input type="hidden" name="_resource_id" value="MTAwfDE3MzQ4OTAxMjM=.aBcD3f...">
```

### Validar - en el controller POST

```clipper
LOCAL cId := UGetResource()        // lee _resource_id de POST -> GET

IF Empty( cId )
   RETURN URedirect( URoute( "main" ) )      // token ausente / inválido
ENDIF

nId := Val( cId )                  // ID original recuperado
```

`UGetResource()` busca el token automáticamente:

1. `UPost( "_resource_id" )` - primero del body POST
2. `UGet( "_resource_id" )` - fallback en query string
3. Si no aparece o la firma es inválida → devuelve `""`

---

## Ejemplo real - `customer.prg` de Fenix

### Acción Update

```clipper
METHOD Update() CLASS Customer
   LOCAL cId := UGetResource()                 // ⬅ recupera el recno firmado
   LOCAL oVal, nId, cError, lSuccess

   // 1. ¿Tenemos token válido?
   IF Empty( cId )
      RETURN URedirect( URoute( "main" ) )     // forzado / corrupto -> main
   ENDIF

   // 2. ¿El ID es un número válido?
   oVal := UValidatorOne( "Id", cId, "required|number|min:0" )
   IF oVal:Fails()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF
   nId := oVal:Get()

   // 3. Validar el resto del form
   oVal := UValidatePost( { ;
      "first"  => "required|string|max:20|field", ;
      "last"   => "required|string|max:20|field", ;
      "city"   => "required|string|max:30|field", ;
      ... ;
   } )

   IF ! oVal:Make()
      UFlash( "customer" ):Set( { ;
         "type"   => "danger",      ;
         "errors" => oVal:GetErrors(), ;
         "input"  => oVal:Resume() } )
      RETURN URedirect( URoute( "customer.edit", nId ) )
   ENDIF

   // 4. Persistir
   lSuccess := TCustomers():Update( nId, oVal:DataFields(), @cError )
   ...
RETURN nil
```

### Acción Delete

Idéntico patrón - el token viene del form de confirmación de borrado:

```clipper
METHOD Delete() CLASS Customer
   LOCAL cId := UGetResource()
   ...
```

---

## Anatomía del token

```
  payload (base64)        .   signature (HMAC-SHA256)
┌─────────────────────────┐.┌──────────────────────┐
  MTAwfDE3MzQ4OTAxMjM=    .   aBcD3f9eGgHhIi...
└─────────────────────────┘ └──────────────────────┘
        │
        └── base64Decode -> "100|1734890123"
                             │      │
                             │      └── unix timestamp
                             └── ID original
```

- El **payload** lleva el ID original separado por `|` del timestamp.
- La **firma** se calcula como `HMAC-SHA256( payload, app_key )`.
- Si alguien altera un solo byte del payload, la firma deja de cuadrar y
  `HIX_TokenValid` retorna `.F.`.
- El **timestamp** permite implementar caducidad (no usado por
  `UGetResource`, que valida con `nLapsus = 0`).

---

## El secret - `app_key`

`UResourceToHtml` y `UGetResource` comparten **el mismo `app_key`** que
[CSRF](csrf.md). Se configura una sola vez:

```clipper
HIX_ConfigAppSet( "app_key", "clave_secreta_de_app" )
```

> ⚠️ Cambiar `app_key` invalida **todos** los tokens firmados:
> CSRF, Resource IDs y cualquier otro `HIX_TokenMake` colgado del mismo
> secret. Los forms abiertos en pestañas activas darán error hasta refresh.

---

## Patrón completo edit/update con Fenix

### GET /customer/42/edit - pinta el form

```clipper
METHOD Edit() CLASS Customer
   LOCAL oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" } } )
   LOCAL hRow

   IF ! oVal:Make()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF

   TCustomers():GetRecno( oVal:Get( "id" ), @hRow, NIL, .T. )

RETURN UView( "masters/customer/edit.html", .T., hRow )
```

### Template - edit.html

```html
@args lEdit, hRow

<form method="POST" action="{{ URoute('customer.update', hRow['recno']) }}">
  {{ UCsrfToHtml() }}
  {{ UResourceToHtml( hRow['recno'] ) }}

  <label>Nombre <input name="first" value="{{ hRow['first'] }}"></label>
  <label>City   <input name="city"  value="{{ hRow['city']  }}"></label>
  ...
  <button>Guardar</button>
</form>
```

### POST /customer/42/edit - recibe el form

```clipper
METHOD Update() CLASS Customer
   LOCAL cId := UGetResource()           // 42 firmado y validado
   ...
```

---

## Comparación con CSRF

| | CSRF token | Resource ID token |
|---|---|---|
| Qué firma | _nada_ - solo timestamp aleatorio | El ID del recurso |
| Field name | `_csrf` | `_resource_id` |
| Propósito | "Este form lo lanzó nuestra página, no un atacante" | "Este ID es el que yo te entregué, no uno manipulado" |
| Helper render | `UCsrfToHtml()` | `UResourceToHtml( cId )` |
| Helper read | _(automático por middleware)_ | `UGetResource()` |
| Comparten secret | ✅ `app_key` | ✅ `app_key` |

Los dos suelen ir **juntos** en cada form (CSRF + Resource ID).

---

## Buenas prácticas

1. **CSRF + Resource ID en cada form de edit/delete.** Son complementarios.
2. **No reemplaza el chequeo de permisos.** Un token Resource ID válido
   solo dice "este es el ID que te di"; sigue tocando comprobar que el
   user puede editar ese recurso.
3. **No metas datos sensibles en el ID.** El payload es solo base64, no
   está encriptado - cualquiera puede leer el ID original. Solo es
   *tamper-proof*, no confidencial.
4. **Cambia `app_key` en producción.** Si te quedas con el default
   publicado en el repo, cualquiera puede generar tokens válidos.

