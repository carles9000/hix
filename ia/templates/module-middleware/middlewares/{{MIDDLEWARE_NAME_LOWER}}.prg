/*-----------------------------------------------------------
  File ......: {{MIDDLEWARE_NAME_LOWER}}.prg
  Author.....: {{AUTHOR}}
  Created....: {{DATE}}
  Version....: 1.0.0
  Description: HixMw{{MIDDLEWARE_NAME}} middleware -- rejects any
               request without an X-Api-Key header. Skeleton for
               the user to replace with real logic.
 -----------------------------------------------------------*/

FUNCTION HixMw{{MIDDLEWARE_NAME}}( oCtx )
   LOCAL cKey := oCtx:oReq:Header( "X-Api-Key", "" )

   IF Empty( cKey )
      oCtx:lHandled := .T.
      oCtx:oReq:Respond( { "error" => "missing X-Api-Key" }, 401, "json" )
      RETURN .F.
   ENDIF

RETURN .T.
