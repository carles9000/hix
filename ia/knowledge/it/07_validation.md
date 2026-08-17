# Validazione

Validator integrato con stringhe di regole + risposta 422 automatica.

## Flusso rapido

    LOCAL oVal := UValidateOrFail( { ;
       "name"  => "required|string|max:100",  ;
       "email" => "required|string|email",    ;
       "age"   => "required|integer|min:18|max:99" ;
    } )
    IF oVal == NIL ; RETURN NIL ; ENDIF   // 422 già inviato

    LOCAL cName := oVal:Get( "name" )
    LOCAL nAge  := oVal:Get( "age" )    // già convertito in numero

## Sorgenti di input

| Helper | Sorgente |
|--------|--------|
| `UValidatePost( hRules )`    | Body POST: form / JSON |
| `UValidateGet( hRules )`     | Query string |
| `UValidateParams( hRules )`  | Query + parametri di route uniti |
| `UValidateJson( hRules )`    | Body JSON esplicito |
| `UValidateOrFail( hRules )`  | POST — auto 422 se qualche regola fallisce |

Tutti ritornano un `THixValidator` (tranne `UValidateOrFail` che può ritornare `NIL`).

## Vocabolario delle regole

    required            il campo deve essere presente e non vuoto
    string              il valore è di tipo stringa
    integer             il valore è un intero (o convertibile)
    numeric             qualsiasi numero (int o decimale)
    boolean             il valore è .T./.F. o convertibile
    array               il valore è un array

    min:N               stringa: length >= N ; numero: valore >= N
    max:N               stringa: length <= N ; numero: valore <= N
    minlen:N            lunghezza stringa >= N
    maxlen:N            lunghezza stringa <= N
    between:N:M         numero tra N e M inclusi

    email               corrisponde a un pattern email
    url                 inizia con http:// o https://
    ip                  indirizzo IPv4
    regex:PATTERN       corrisponde a regex PCRE
    in:a,b,c            valore nella lista data
    notin:a,b           valore non nella lista

    field               (marker) include in DataFields() quando valido

## Sanitizzazione (applicata prima della validazione)

    trim                AllTrim()
    lower               Lower()
    upper               Upper()

Combina con le pipe:

    "email" => "required|trim|lower|email"
    "name"  => "required|trim|max:100"

## Gestione manuale degli errori

    LOCAL oVal := UValidatePost( hRules )
    IF ! oVal:Make()
       USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
       RETURN NIL
    ENDIF

`GetErrorsJson()` ritorna un hash indicizzato per nome campo:

    { "email" => "non è un'email valida", "age" => "deve essere almeno 18" }

## Accesso ai dati validati

    oVal:Get( "name" )               // singolo campo
    oVal:GetAll()                    // hash di tutti i campi validati
    oVal:DataFields()                // hash dei campi marcati con la regola `field`
                                    // (utile per payload INSERT/UPDATE)

## Regole custom

Estendi ereditando o wrappando. Approccio semplice — valida manualmente dopo:

    LOCAL oVal := UValidatePost( hRules )
    IF ! oVal:Make()
       RETURN USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
    ENDIF

    IF ! _IsCorporateEmail( oVal:Get("email") )
       RETURN USendJson( { "errors" => { "email" => "dominio non consentito" } }, 422 )
    ENDIF

## Trappola comune

Le regole operano sull'input RAW PRIMA della sanificazione per i controlli di esistenza. Se fai affidamento su `trim` per far passare un campo vuoto a `required`, aggiungi `trim` prima: `"required|trim|min:3"` non aiuta — `required` viene eseguito su `"   "` (non vuoto) e passa. L'ordine conta solo per la sanificazione vs. regole successive. Testa i casi limite.
