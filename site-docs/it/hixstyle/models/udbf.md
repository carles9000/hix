# 🗄️ UDbf - Accesso a tabelle DBF

## Cos'è?

`UDbf()` è il wrapper che HixStyle espone sulla classe `HIX_DBF` per parlare con **file DBF + CDX** (xBase / Clipper / Harbour) dai
controller come se fossero un data model moderno.

Incapsula le meccaniche xBase (alias, `DbGoTo`, `DbSeek`, `Rlock`, `FieldGet`)
dietro un'API orientata agli hash - i record entrano ed escono come
dizionari `{ "field" => valore }`, pronti da passare a JSON, un
template, o un validator.

```
www/models/tcustomers.prg     ──▶  restituisce oDbf configurato e aperto
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

È il **pattern Fenix Model**: un `TXxx()` per tabella, i controller
chiamano solo metodi.

---

## Quando usarlo

| Caso d'uso | UDbf |
|---|---|
| App gestionale su file DBF/CDX esistenti | ✅ Sì - pattern canonico |
| Migrazione progressiva da Clipper/Harbour classico | ✅ Sì |
| Reportistica su dati storici in DBF | ✅ Sì |
| Nuova app su PostgreSQL / MySQL | ❌ No - usa l'adattatore SQL |
| Dati in JSON / NoSQL | ❌ No |
| Cache / configurazione in memoria | ❌ No - usa il sistema di cache |

> UDbf non è un ORM. È un **wrapper diretto** sull'RDD `DBFCDX`.
> Non genera SQL, non migra schemi, non risolve relazioni; resta
> all'astrazione xBase classica.

---

## Creare un model

La convenzione Fenix: un `.prg` per tabella in `www/models/` che ritorna l'istanza
configurata e aperta.

```clipper
// www/models/tcustomers.prg
FUNCTION TCustomers()
   LOCAL oCustomers := UDbf()

   oCustomers:cPath := hb_dirbase() + "data"
   oCustomers:cDbf  := "customers.dbf"
   oCustomers:cCdx  := "customers.cdx"
   oCustomers:cTag  := "first"

   oCustomers:Hide( "salary" )    // questo campo non deve arrivare a hRow
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

> Il costruttore accetta anche gli argomenti su una sola riga:
> `UDbf( "customers.dbf", "customers.cdx", "first", NIL, .T. )`.
> Il pattern Fenix preferisce assegnare le proprietà per chiarezza.

---

## Proprietà

| Proprietà | Default | Scopo |
|---|---|---|
| `cPath` | `hb_dirbase()` | Cartella dove si trovano i file .dbf e .cdx |
| `cDbf` | `""` | Nome del file `.dbf` |
| `cCdx` | `""` | Nome del file indice `.cdx` |
| `cTag` | `""` | Tag attivo all'apertura |
| `cRdd` | `"DBFCDX"` | RDD (`DBFNTX`, `DBFCDX`, ...) |
| `lExclusive` | `.F.` | Apri in modalità esclusiva (multi-utente → `.F.`) |
| `lToUtf8` | `.F.` | Converte le stringhe a UTF-8 in lettura |
| `cAlias` | _(autogenerato)_ | Alias generato da `NewAlias()` |
| `hFields` | `{=>}` | Struttura: nome → `{name, type, len, dec}` |
| `nFields` | _(autocalcolato)_ | Numero di campi visibili |
| `lConnect` | `.F.` | `.T.` se la tabella è aperta |

---

## Aprire e chiudere

```clipper
oDbf:Open()              // apre e carica la struttura → ::lConnect = .T.
oDbf:Close()             // chiude l'area

oDbf:lExclusive := .T.
oDbf:Open()              // esclusiva (Zap, Pack, riparazione)
```

`Open()` ritorna `.T.` se l'apertura riesce. Se il file manca o il tag non esiste,
chiama `SetError()` e ritorna `.F.`.

---

## Navigazione

```clipper
oDbf:First()             // DbGoTop
oDbf:Last()              // DbGoBottom
oDbf:Next()              // DbSkip(1)
oDbf:Prev()              // DbSkip(-1)
oDbf:Skip( 5 )           // DbSkip(5)
oDbf:Goto( nRecno )      // DbGoTo(nRecno)

oDbf:Recno()             // numero di record corrente
oDbf:RecCount()          // totale record
oDbf:Bof() / oDbf:Eof()  // bordi
```

---

## Ricerca

```clipper
// Seek per la chiave dell'indice attivo
IF oDbf:Seek( "Carles" )
   ? "Trovato al recno " + Str( oDbf:Recno() )
ENDIF

// Seek in un altro indice senza perdere quello corrente
oDbf:Seek( "1234", .F., "id" )

// Cambia indice attivo
oDbf:Focus( "city" )
```

---

## Leggere un record come hash

`Row()` è il cuore del wrapper: converte il record corrente in un
hash pronto all'uso.

```clipper
hRow := oDbf:Row()                       // tutti i campi visibili
hRow := oDbf:Row( { "first", "last" } )  // solo quei campi
hRow := oDbf:Row( NIL, .T. )             // convertito a stringa web
```

L'hash aggiunge sempre due campi di controllo:

| Chiave | Valore |
|---|---|
| `_recno` | Numero di record fisico |
| `_deleted` | `.T.` / `.F.` (flag di cancellazione) |

### Modalità web string

Quando `lToStringWeb = .T.`, i valori vengono **serializzati a stringa** pronti
da mettere in un `<input value="...">`:

| Tipo DBF | Risultato |
|---|---|
| `C`, `M` | `AllTrim(valore)` (opzionalmente UTF-8 se `lToUtf8`) |
| `D` | `UDateToHtml( dValore )` → `"2026-06-26"` |
| `N` | `Str( valore, len, dec )` |
| `L` | `ULogicToHtmlChecked( valore )` → `"checked"` / `""` |

> È la modalità che i controller usano per riempire i form HTML.

---

## CRUD di base

### Create - `Insert`

```clipper
LOCAL hFields := { ;
   "first"  => "Carles",  ;
   "last"   => "Aubia",   ;
   "city"   => "Barcelona" ;
}
LOCAL cError, nNewRecno

IF oDbf:Insert( hFields, @cError, @nNewRecno )
   ? "Creato recno " + Str( nNewRecno )
ELSE
   ? "Errore: " + cError
ENDIF
```

`Insert` esegue `Append()` + `Update()` in un'unica chiamata.

### Read - `GetRecno` / `GetId`

```clipper
LOCAL hRow := {=>}

// Per recno fisico
IF oDbf:GetRecno( 42, @hRow, NIL, .T. )
   ? hRow[ "first" ], hRow[ "city" ]
ENDIF

// Per chiave dell'indice attivo
IF oDbf:GetId( "Carles", @hRow )
   ? hRow[ "_recno" ]
ENDIF
```

Entrambi ritornano `.T.` se il record esiste e riempiono `@hRow` per
riferimento. Il quarto parametro (`lToStringWeb`) è lo stesso di `Row()`.

### Update - `Update`

```clipper
LOCAL hChanges := { "city" => "Madrid", "salary" => 50000 }
LOCAL cError

IF oDbf:Update( 42, hChanges, @cError )
   ? "Aggiornato"
ELSE
   ? "Errore: " + cError
ENDIF
```

`Update` esegue `Rlock` → `FieldPut` per ogni chiave dell'hash → `DbCommit` →
`DbUnlock`.

### Delete - `Delete`

```clipper
oDbf:Delete( nRecno )                      // marca come cancellato
oDbf:Delete( nRecno, .T. )                 // toggle: se cancellato, lo recupera
oDbf:Delete( nRecno, .F., @lIsDeleted )    // @lIsDeleted con lo stato finale

oDbf:Recall()                              // rimuove il flag di cancellazione (record corrente)
oDbf:Pack( @cError )                       // rimuove fisicamente le righe cancellate
oDbf:Zap()                                 // svuota la tabella - ⚠️ esclusiva
```

### Record vuoto per i form

```clipper
hBlank := oDbf:Blank()              // hash con valori vuoti per tipo
hBlank := oDbf:Blank( .T. )         // web string (per il form di creazione)
```

Utile quando disegni un form di creazione: il template legge dallo stesso hash che
userà un form di modifica.

---

## Lista

### Tutti i record

```clipper
aRows := oDbf:LoadAll()                            // tutti i campi visibili
aRows := oDbf:LoadAll( { "first", "city" } )       // solo quelli
aRows := oDbf:LoadAll( NIL, "A", "C" )             // scope: da "A" a "C"
aRows := oDbf:LoadAll( NIL, , , {|a| !Deleted() } ) // con condizione codeblock
```

Ritorna un array di hash (uno per record). Applica `OrdScope` se
vengono passati `cScopeTop`/`cScopeBottom`.

### Paginazione

```clipper
LOCAL nTotalPages
LOCAL aRows := oDbf:Page( 1, 20, NIL, @nTotalPages )

// nTotalPages ritornato per riferimento
? "Pagina 1/" + Str( nTotalPages ) + " - " + Str( Len( aRows ) ) + " righe"
```

`Page( nPage, nRows, aFields, @nTotalPages )`:

- Calcola `nTotalPages` arrotondando per eccesso.
- Se `nPage > nTotalPages`, riposiziona sull'ultima pagina.
- Usa `OrdKeyGoto` se c'è un indice attivo, `DbGoto` altrimenti.

---

## Visibilità dei campi

Utile per nascondere campi sensibili (`salary`, `password`) dall'hash che
viaggia verso i template / JSON:

```clipper
oDbf:Hide( "salary" )                      // singolo campo
oDbf:Hide( { "salary", "ssn", "passwd" } ) // multipli

oDbf:Visible( { "id", "first", "last" } )  // whitelist: solo questi
```

| Metodo | Comportamento |
|---|---|
| `Hide( aFields )` | Blacklist - tutti tranne quelli |
| `Visible( aFields )` | Whitelist - solo quelli |

Applica **prima** di `Open()`. La struttura `hFields` viene tagliata all'apertura
secondo la selezione.

---

## Locking

```clipper
IF oDbf:Rlock()
   oDbf:FieldPut( "city", "Madrid" )
   oDbf:Unlock()
ENDIF
```

`Rlock()` riprova fino a `nTime` secondi (default 3s) prima di fallire.
Se fallisce, chiama `SetError( DBF_ERR_LOCK )` e ritorna `.F.`.

> `Update()` e `Insert()` gestiscono già lock/unlock - ti serve chiamare
> `Rlock()` direttamente solo quando fai operazioni manuali di `FieldPut`.

---

## Pattern Fenix completo - Edit Customer

### Il controller chiama il model

```clipper
METHOD Edit() CLASS Customer
   LOCAL oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" } } )
   LOCAL oCustomers, oStates, hRow := {=>}
   LOCAL aStates, lFound

   IF ! oVal:Make()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF

   oStates := TStates()                    // ← UDbf per gli stati
   aStates := oStates:LoadAll()

   oCustomers := TCustomers()              // ← UDbf per i clienti
   lFound := oCustomers:GetRecno( oVal:Get( "id" ), @hRow, NIL, .T. )

   IF ! lFound
      hRow := oCustomers:Blank( .T. )      // vuoto per "crea"
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
      UFlash( "customer" ):Set( { "message" => "Aggiornato" } )
      RETURN URedirect( URoute( "customer.show", Val( cId ) ) )
   ELSE
      UFlash( "customer" ):Set( { "message" => cError } )
      RETURN URedirect( URoute( "customer.edit", Val( cId ) ) )
   ENDIF
RETURN
```

Nota la simbiosi con il **validator**:

| Helper | Ritorna |
|---|---|
| `oVal:DataFields()` | Solo le chiavi marcate con `field` nelle regole |
| `oVal:Resume()` | Tutto l'input originale (per ridisegnare il form) |

`DataFields` è pensato per alimentare direttamente `oDbf:Update()`.

---

## UTF-8 e encoding

I file DBF classici sono di solito in **CP437** o **CP850**. Affinché le stringhe
arrivino come UTF-8 nel browser:

```clipper
oDbf:lToUtf8 := .T.
oDbf:Open()
```

Con `lToUtf8 = .T.`, `Row()` applica `hb_StrToUtf8()` ai campi `C` e
`M` prima di restituirli.

> Se lo attivi, **scrivi sempre da UTF-8** o avrai caratteri rovinati. Meglio: configura
> correttamente la codepage di Harbour nel `.prg` principale con `REQUEST HB_CODEPAGE_*`
> prima di toccare qualsiasi cosa.

---

## Errori

`UDbf` cattura gli errori xBase in `TRY/CATCH` e li reinstrada a `HIX_Throw`,
che il dispatcher di HIX cattura per disegnare la pagina di errore corrispondente.

```clipper
oDbf:lDoError := .F.    // disabilita il throw automatico
oDbf:Open()
IF ! oDbf:lConnect
   ? "Errore: " + oDbf:oError:description
ENDIF
```

---

## Best practice

1. **Un model `TXxx()` per tabella.** Incapsula `cPath`, `cDbf`, `cCdx`,
   `cTag`, `Hide/Visible` in un'unica funzione riutilizzabile.
2. **Chiudi ciò che apri.** Nei worker HTTP, l'alias vive nel thread
   pool. Usa `Close()` alla fine della request o affidati al GC dell'ID area
   per thread.
3. **`Hide` per i campi sensibili.** Salari, password, chiavi interne non devono mai
   arrivare a un template o JSON.
4. **`lToStringWeb = .T.` per i form.** Evita stringhe xBase con spazi di padding
   o date con formattazione locale.
5. **Combina con il validator.** `oVal:DataFields()` → `oDbf:Update()`
   è il pattern diretto, senza codice ad hoc.
6. **`Update` solo delle chiavi modificate.** Passa solo i campi modificati
   nell'hash - `Update()` itera sulle chiavi dell'hash, non tocca gli altri.
7. **`Rlock` non è eterno.** Default 3s - alza `oDbf:nTime` se la tua app
   ha alta concorrenza, o decidi di fare retry a livello di controller.
