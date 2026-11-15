/*-----------------------------------------------------------
  File ......: api_verbs.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.0.0
  Description: Multi-verb webservice. Answers GET, POST, PUT,
               DELETE, PATCH and HEAD echoing back the verb,
               the query string and the request body. Used by
               the /http-test screen to check verb dispatching
               and status codes.
  Usage      : GET|POST|PUT|DELETE|PATCH|HEAD /api/verbs
  Notes      : POST answers 201 Created, every other verb 200.
               Falls back to form data when body is not JSON.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL cMethod := UMethod()
   LOCAL xBody   := UJson()
   LOCAL nStatus := 200

   IF xBody == NIL
      xBody := UPost()
   ENDIF

   IF cMethod == 'POST'
      nStatus := 201                                  // Created
   ENDIF

RETURN USendJson( { 'ok'     => .T.,       ;
                    'method' => cMethod,   ;
                    'query'  => UGet(),    ;
                    'body'   => xBody,     ;
                    'time'   => Time()     }, nStatus )
