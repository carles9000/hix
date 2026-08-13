# 🆔 Resource IDs

## Quale problema risolvono?

Un tipico form di modifica incorpora l'ID della risorsa come campo nascosto:

```html
<input type="hidden" name="recno" value="42">
```

Ma quell'ID viaggia **in chiaro**. Qualsiasi utente può ispezionare l'HTML, cambiare il `42` in un `99` e inviare il POST a `/customer/edit` per modificare un record **che non è suo**. Hai bisogno di:

1. **Ricontrollare i permessi** sul `99` lato server _(l'approccio giusto, ma costoso e facile da dimenticare)_.
2. **Firmare l'ID** così che il client non possa alterarlo - questa è la soluzione che `UResourceToHtml` fornisce.

```
Client riceve    <input ... value="MTAwfDE3MzQ...sig=abc123">  (firmato)
Client invia     _resource_id=MTAwfDE3MzQ...sig=abc123
Server           UGetResource() -> "100"  (valido, accettalo)
Server           se il client altera 1 byte -> UGetResource() -> ""
```

Il token contiene l'ID + timestamp + **HMAC** firmato con `app_key`. Senza conoscere il segreto, l'attaccante non può generarne uno valido per un ID diverso.

---

## Quando usarlo?

| Caso d'uso | Resource IDs |
|---|---|
| Form di edit/delete per un record specifico | ✅ Sì |
| Liste con azioni come `<button data-id="42">` | ✅ Sì |
| ID di client / ordine / fattura che viaggia nell'URL | ⚠️ No - l'URL è `/customer/:id`, c'è già il middleware di auth |
| Token monouso per il download di file | ✅ Sì |
| API REST con JWT | ❌ No - il JWT identifica l'utente; convalida l'ownership con query |

> **Non sostituiscono i controlli di permesso.** I Resource IDs garantiscono l'*integrità* dell'ID (non manomesso), non l'*autorizzazione*. Devi comunque verificare che l'utente corrente possa modificare quello specifico record.

---

## API

### Generare - nel controller / template

```clipper
USetView( "cResourceHtml", UResourceToHtml( nRecno ) )
```

```html
<form method="POST" action="/customer/edit">
  {{ UCsrfToHtml() }}
  {{ UResourceToHtml( nRecno ) }}
  <input name="first" value="{{ hRow['first'] }}">
  ...
  <button>Salva</button>
</form>
```

`UResourceToHtml( "100" )` genera qualcosa come:

```html
<input type="hidden" name="_resource_id" value="MTAwfDE3MzQ4OTAxMjM=.aBcD3f...">
```

### Validare - nel controller POST

```clipper
LOCAL cId := UGetResource()        // legge _resource_id da POST -> GET

IF Empty( cId )
   RETURN URedirect( URoute( "main" ) )      // token mancante / non valido
ENDIF

nId := Val( cId )                  // ID originale recuperato
```

`UGetResource()` cerca il token automaticamente:

1. `UPost( "_resource_id" )` - prima dal body del POST
2. `UGet( "_resource_id" )` - fallback nella query string
3. Se non trovato o la firma non è valida → ritorna `""`

---

## Esempio reale - `customer.prg` di Fenix

### Action Update

```clipper
METHOD Update() CLASS Customer
   LOCAL cId := UGetResource()                 // ⬅ recupera il recno firmato
   LOCAL oVal, nId, cError, lSuccess

   // 1. Abbiamo un token valido?
   IF Empty( cId )
      RETURN URedirect( URoute( "main" ) )     // forgiato / corrotto -> main
   ENDIF

   // 2. L'ID è un numero valido?
   oVal := UValidatorOne( "Id", cId, "required|number|min:0" )
   IF oVal:Fails()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF
   nId := oVal:Get()

   // 3. Valida il resto del form
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

   // 4. Persisti
   lSuccess := TCustomers():Update( nId, oVal:DataFields(), @cError )
   ...
RETURN nil
```

### Action Delete

Stesso pattern - il token viene dal form di conferma di cancellazione:

```clipper
METHOD Delete() CLASS Customer
   LOCAL cId := UGetResource()
   ...
```

---

## Anatomia del token

```
   payload (base64)        .   firma (HMAC-SHA256)
┌─────────────────────────┐.┌──────────────────────┐
  MTAwfDE3MzQ4OTAxMjM=    .   aBcD3f9eGgHhIi...
└─────────────────────────┘ └──────────────────────┘
        │
        └── base64Decode -> "100|1734890123"
                           │      │
                           │      └── timestamp unix
                           └── ID originale
```

- Il **payload** porta l'ID originale separato da `|` dal timestamp.
- La **firma** è calcolata come `HMAC-SHA256( payload, app_key )`.
- Se qualcuno altera anche solo un byte del payload, la firma non corrisponde più e `HIX_TokenValid` ritorna `.F.`.
- Il **timestamp** permette di implementare la scadenza (non usato da `UGetResource`, che valida con `nLapsus = 0`).

---

## Il segreto - `app_key`

`UResourceToHtml` e `UGetResource` condividono **lo stesso `app_key`** del [CSRF](csrf.md). Configuralo una volta:

```clipper
HIX_ConfigAppSet( "app_key", "my_secret_app_key" )
```

> ⚠️ Cambiare `app_key` invalida **tutti** i token firmati: CSRF, Resource IDs e qualsiasi altro `HIX_TokenMake` legato allo stesso segreto. I form aperti in tab attive daranno errore finché non si aggiorna.

---

## Pattern completo di edit/update con Fenix

### GET /customer/42/edit - renderizza il form

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

  <label>Nome <input name="first" value="{{ hRow['first'] }}"></label>
  <label>Città  <input name="city"  value="{{ hRow['city']  }}"></label>
  ...
  <button>Salva</button>
</form>
```

### POST /customer/42/edit - riceve il form

```clipper
METHOD Update() CLASS Customer
   LOCAL cId := UGetResource()           // 42 firmato e validato
   ...
```

---

## Confronto con CSRF

| | Token CSRF | Token Resource ID |
|---|---|---|
| Cosa firma | _niente_ - solo timestamp random | L'ID della risorsa |
| Nome campo | `_csrf` | `_resource_id` |
| Scopo | "Questo form è stato lanciato dalla nostra pagina, non da un attaccante" | "Questo ID è quello che ti ho dato io, non uno manipolato" |
| Helper di render | `UCsrfToHtml()` | `UResourceToHtml( cId )` |
| Helper di lettura | _(automatico via middleware)_ | `UGetResource()` |
| Segreto condiviso | ✅ `app_key` | ✅ `app_key` |

Di solito vanno **insieme** in ogni form (CSRF + Resource ID).

---

## Best practice

1. **CSRF + Resource ID in ogni form di edit/delete.** Sono complementari.
2. **Non sostituisce i controlli di permesso.** Un token Resource ID valido dice solo "questo è l'ID che ti ho dato"; devi comunque controllare che l'utente possa modificare quella risorsa.
3. **Non mettere dati sensibili nell'ID.** Il payload è solo base64, non cifrato - chiunque può leggere l'ID originale. È solo *tamper-proof*, non confidenziale.
4. **Cambia `app_key` in produzione.** Se mantieni il default pubblicato nel repo, chiunque può generare token validi.
