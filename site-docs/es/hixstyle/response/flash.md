# ⚡ Flash messages


Un **flash** es un mensaje que vive **un solo request**: se guarda en la
sesión durante un POST, sobrevive a un redirect, y se consume (auto-borra)
al leerlo en el siguiente GET.

Es la pieza que cierra el patrón **PRG (Post / Redirect / Get)**: el
usuario manda un POST, el servidor procesa, redirige y el siguiente GET
muestra el resultado - sin re-enviar el form si refresca la página.

```
POST /customer/update
      │
      │  oVal:Make()   → falla
      │  UFlash("customer"):Set({ errors, input })
      │  URedirect( "/customer/edit/42" )
      ▼
GET /customer/edit/42
      │
      │  oFlash := UFlash("customer")
      │  hErrors := oFlash:Get("errors")   ← lee y borra
      │  hInput  := oFlash:Get("input")    ← lee y borra
      │  USendView( "edit.html", hRow, hErrors, hInput )
      ▼
HTML con los errores + valores que el usuario había escrito
```

> Si el usuario refresca el GET, los flashes **ya no están** - el browser
> no re-envía el POST y no se muestra el banner "Cliente actualizado!"
> dos veces.

---

## Cuándo usarlo

| Caso | Flash |
|---|---|
| Mensaje "✅ Cliente creado" tras redirect | ✅ Sí |
| Mostrar errores de validación al volver al form | ✅ Sí |
| Repoblar el form con `oVal:Resume()` tras un error | ✅ Sí |
| Datos persistentes (preferencias) | ❌ No - usa cookies o BD |
| Datos compartidos entre pestañas | ❌ No - flash es por sesión |
| Mensaje informativo en el mismo request | ❌ No - solo pásalo a la view |

---

## API básica

```clipper
UFlash( cFormId )   // devuelve un TFlash
```

`cFormId` es el namespace dentro de la sesión: cada formulario / módulo
tiene su propio "bag", para que dos flujos abiertos en pestañas distintas
no se pisen.

```clipper
LOCAL oFlash := UFlash( "customer" )

oFlash:Set( "type",    "success" )
oFlash:Set( "message", "Cliente actualizado" )
oFlash:Save()
```

Si llamas con un **hash** completo, hace `merge` y **auto-Save**:

```clipper
UFlash("customer"):Set( { ;
   "type"    => "success",                     ;
   "message" => "Cliente actualizado"          ;
} )
// Save() implícito - ya está en sesión
```

Si llamas con `(cKey, xVal)`, marca dirty pero **no guarda** hasta
`Save()`. Cuando el objeto sale de scope, el destructor llama a `Save()`
automáticamente si hay cambios pendientes.

---

## Métodos

### `Set( cKey, xVal )` / `Set( hHash )`

```clipper
oFlash:Set( "name", "Carles" )
oFlash:Set( "age",  42 )
oFlash:Save()    // explícito

// O todo en una línea - auto-save
UFlash("login"):Set( { "error" => "Bad password", "input" => { "user" => cUser } } )
```

### `Get( cKey, xDef )` - **one-shot**

Devuelve el valor y lo **borra** del bag. Próxima llamada → `xDef`.

```clipper
cMessage := oFlash:Get( "message", "" )    // primera vez → texto
cMessage := oFlash:Get( "message", "" )    // segunda vez → ""
```

> `Get` deja el bag `dirty` para que el destructor lo persista vacío - el
> mensaje queda definitivamente consumido aunque haya otro flujo lectura/escritura.

### `Has( cKey )`

Comprueba si hay valor **sin** consumirlo:

```clipper
IF oFlash:Has( "message" )
   USetHeader( "X-Has-Notice", "1" )
ENDIF
```

### `Delete( cKey )`

Borra explícitamente sin leer:

```clipper
oFlash:Delete( "old_state" )
```

### `Clear()`

Vacía todo el bag de ese `cFormId`:

```clipper
UFlash("customer"):Clear()
```

### `Save()`

Persiste el bag a sesión. **No hace falta** llamarlo si:

- Usaste `Set(hHash)` (auto-save).
- El objeto sale de scope (destructor lo llama si `lDirty`).

### `GetId()`

Devuelve el `cFormId` que usa este flash:

```clipper
oFlash:GetId()   // "customer"
```

---

## Almacenamiento

- El flash se guarda en la **sesión**, bajo la clave `_flash`.
- `_flash` es un hash `{ cFormId => hBag }` - cada formulario tiene su
  propio bag.
- Bag vacío → se elimina la entrada de `_flash` en `Save()` - la sesión
  no se llena de basura.
- **Requiere `HIX_MwSession`** activo en la ruta. Sin sesión, no hay flash.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "memory" )
oSrv:Use( "HIX_MwSession" )

// Ya puedes usar UFlash() en cualquier action
```

---

## Patrón PRG completo (Fenix)

### POST → Update con flash

```clipper
METHOD Update() CLASS Customer

   LOCAL oVal, oCustomers, lSuccess, nId, cError := ""

   nId := Val( UParam( "id", "0" ) )

   oVal := UValidatePost( { ;
      "first" => "required|string|max:20|field", ;
      "last"  => "required|string|max:20|field", ;
      "city"  => "required|string|max:30|field"  ;
   } )

   IF ! oVal:Make()
      // Validación falla - flash errores + input + redirect al edit
      UFlash("customer"):Set( { ;
         "type"   => "danger",          ;
         "errors" => oVal:GetErrors(),  ;
         "input"  => oVal:Resume()      ;
      } )
      RETURN URedirect( URoute( "customer.edit", nId ) )
   ENDIF

   oCustomers := TCustomers()
   lSuccess   := oCustomers:Update( nId, oVal:DataFields(), @cError )

   IF lSuccess
      UFlash("customer"):Set( { ;
         "type"    => "success",                                     ;
         "message" => "Cliente " + LTrim( Str( nId ) ) + " actualizado!" ;
      } )
      RETURN URedirect( URoute( "customer.show", nId ) )
   ELSE
      // Error BD - flash error + input (no perder lo escrito)
      UFlash("customer"):Set( { ;
         "type"    => "danger",        ;
         "message" => cError,          ;
         "input"   => oVal:Resume()    ;
      } )
      RETURN URedirect( URoute( "customer.edit", nId ) )
   ENDIF

RETURN NIL
```

### GET → Edit consume flash

```clipper
METHOD Edit() CLASS Customer

   LOCAL oVal, oCustomers, lFound, oFlash, hInput, nId
   LOCAL hRow     := {=>}
   LOCAL hMessage := {=>}
   LOCAL hErrors  := {=>}

   oVal := UValidateParams( { "id" => "required|numeric" } )
   IF ! oVal:Make()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF
   nId := oVal:Get( "id" )

   oCustomers := TCustomers()
   lFound     := oCustomers:GetRecno( nId, @hRow, NIL, .T. )

   IF ! lFound
      hRow := oCustomers:Blank( .T. )
   ENDIF

   // Consumir flash en el controller, la view solo pinta
   oFlash := UFlash( "customer" )

   hMessage[ "type" ]    := oFlash:Get( "type" )
   hMessage[ "message" ] := oFlash:Get( "message" )
   hErrors               := oFlash:Get( "errors" )

   // Si hay input flasheado → tiene prioridad sobre BD (repoblar form)
   hInput := oFlash:Get( "input" )
   IF hb_IsHash( hInput )
      hRow := hInput
   ENDIF

RETURN USendView( "views/masters/customer/edit.html", ;
                  lFound, hRow, hMessage, hErrors )
```

> **Procesa el flash en el controller, no en la view.** La view es
> "tonta": recibe `hRow`, `hMessage` y `hErrors` ya preparados. Eso
> permite que el mismo template sirva para CREATE (sin flash) y EDIT
> (con o sin flash) sin que la view sepa nada.

---

## Patrones útiles

### Banner de éxito tras login

```clipper
FUNCTION _LoginAction()
   LOCAL hUser := _CheckCredentials( UPost("user"), UPost("pass") )

   IF hUser == NIL
      UFlash("login"):Set( { ;
         "type"    => "danger",                ;
         "message" => "Credenciales inválidas" ;
      } )
      RETURN URedirect( URoute( "auth.login" ) )
   ENDIF

   USession():Set( "user_id", hUser["id"] )
   USession():Save()

   UFlash("dashboard"):Set( { ;
      "type"    => "success",                            ;
      "message" => "Hola " + hUser["name"] + ", bienvenido!" ;
   } )

   RETURN URedirect( URoute( "dashboard" ) )
```

### Flash entre dominios distintos

Cada formulario / módulo usa su `cFormId` propio para no pisarse:

```clipper
UFlash("customer"):Set( { "message" => "Cliente OK" } )
UFlash("invoice"):Set(  { "message" => "Factura OK" } )

// El controller customer lee solo "customer", invoice solo "invoice"
```

### Flash multi-paso (wizard)

Conserva input durante varios pasos pasando `_HixCheckpoint` entre ellos:

```clipper
// Paso 1
UFlash("wizard"):Set( { "step1" => oVal:Resume() } )
URedirect( "/wizard/step2" )

// Paso 2 - lee step1 y añade step2
LOCAL hStep1 := UFlash("wizard"):Get( "step1" )
UFlash("wizard"):Set( { "step1" => hStep1, "step2" => oVal:Resume() } )
URedirect( "/wizard/step3" )
```

> Cada `Get` consume - si quieres conservar, re-flasealo. Hay frameworks
> que tienen `keep()` / `reflash()`; en HIX el patrón es leer + volver a
> setear.

---

## Errores típicos

| Síntoma | Causa |
|---|---|
| Flash no aparece tras redirect | Falta `HIX_MwSession` en la ruta GET destino |
| El mensaje se muestra dos veces | Llamaste `Get()` y luego `USendView` sin guardarlo en variable; lo consumiste sin enviarlo |
| Datos persisten entre logins distintos | Usaste mismo `cFormId` en ambos - sesiones son aisladas pero el bag se reusa si no lo limpias |
| `Get()` devuelve `""` aunque acabas de hacer `Set()` | El `Set` se hizo en otro hilo / proceso; flash vive en la sesión del request actual |
| Cookie `HIXSID` no llega al GET | Después del `Save()` la sesión se serializa, pero si haces `URedirect` sin retornar, el Set-Cookie no se envía |

---

## Buenas prácticas

1. **Un `cFormId` por contexto.** `"customer"`, `"invoice"`, `"login"` -
   nombres semánticos, no genéricos como `"main"`.
2. **Procesa flash en el controller.** La view solo pinta lo que recibe;
   si lee de flash directamente, deja de ser reutilizable.
3. **Siempre flash de input en errores.** Junto con `errors`, flashea
   `oVal:Resume()` para repoblar el form. Nada peor que un usuario
   reescribiendo 20 campos.
4. **Mensajes cortos y tipados.** Convención `{ "type" => "success|danger|warning|info", "message" => "..." }` - la view pinta el banner según `type`.
5. **No abuses.** Flash es para "una sola lectura". Si necesitas mostrar
   un mensaje muchas veces, guárdalo en sesión / cookie / BD directamente.
6. **Logout limpia.** Al cerrar sesión, llama `USession():Destroy()` - el
   flash desaparece con la sesión.

