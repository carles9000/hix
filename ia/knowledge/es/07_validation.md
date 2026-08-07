# Validación

Validador integrado con strings de reglas + respuesta 422 automática.

## Flujo rápido

    LOCAL oVal := UValidateOrFail( { ;
       "name"  => "required|string|max:100",  ;
       "email" => "required|string|email",    ;
       "age"   => "required|integer|min:18|max:99" ;
    } )
    IF oVal == NIL ; RETURN NIL ; ENDIF   // 422 ya enviado

    LOCAL cName := oVal:Get( "name" )
    LOCAL nAge  := oVal:Get( "age" )    // ya coercionado a número

## Fuentes de entrada

| Helper | Fuente |
|--------|--------|
| `UValidatePost( hRules )`    | Form POST / body JSON |
| `UValidateGet( hRules )`     | Query string |
| `UValidateParams( hRules )`  | Query + params de ruta fusionados |
| `UValidateJson( hRules )`    | Body JSON explícito |
| `UValidateOrFail( hRules )`  | POST — 422 automático si alguna regla falla |

Todos devuelven un `THixValidator` (excepto `UValidateOrFail` que puede devolver `NIL`).

## Vocabulario de reglas

    required            campo obligatorio, no vacío
    string              tipo string
    integer             entero (o coercible)
    numeric             cualquier número (int o decimal)
    boolean             valor .T./.F. o coercible
    array               valor es array

    min:N               string: longitud >= N ; número: valor >= N
    max:N               string: longitud <= N ; número: valor <= N
    minlen:N            longitud string >= N
    maxlen:N            longitud string <= N
    between:N:M         número entre N y M incluidos

    email               coincide con patrón de email
    url                 empieza por http:// o https://
    ip                  dirección IPv4
    regex:PATRON        coincide con regex PCRE
    in:a,b,c            valor en lista
    notin:a,b           valor no en lista

    field               (marca) incluir en salida de DataFields() si válido

## Sanitización (se aplica antes de validar)

    trim                AllTrim()
    lower               Lower()
    upper               Upper()

Combina con pipes:

    "email" => "required|trim|lower|email"
    "name"  => "required|trim|max:100"

## Manejo manual de errores

    LOCAL oVal := UValidatePost( hRules )
    IF ! oVal:Make()
       USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
       RETURN NIL
    ENDIF

`GetErrorsJson()` devuelve un hash indexado por nombre de campo:

    { "email" => "no es un email válido", "age" => "debe ser al menos 18" }

## Acceder a datos validados

    oVal:Get( "name" )               // un campo
    oVal:GetAll()                    // hash de todos los validados
    oVal:DataFields()                // hash de campos marcados con `field`
                                     // (útil para payloads INSERT/UPDATE)

## Reglas personalizadas

Extiende heredando o envolviendo. Enfoque simple — validar manualmente después:

    LOCAL oVal := UValidatePost( hRules )
    IF ! oVal:Make()
       RETURN USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
    ENDIF

    IF ! _IsCorporateEmail( oVal:Get("email") )
       RETURN USendJson( { "errors" => { "email" => "dominio no permitido" } }, 422 )
    ENDIF

## Gotcha común

Las reglas operan sobre el input CRUDO ANTES de la sanitización para las checks de existencia. Si dependes de `trim` para que un valor en blanco pase `required`, ponlo primero: `"required|trim|min:3"` no ayuda — `required` se ejecuta sobre `"   "` (no vacío) y pasa. El orden solo importa entre sanitización y reglas posteriores. Prueba casos límite.
