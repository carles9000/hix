/*-----------------------------------------------------------
  File ......: myappauthrole.prg
  Author.....: Charly 9000
  Created....: 2026-07-17
  Modified...: 2026-07-17
  Version....: 1.0.0
  Description: Session-based auth + role/scope middleware group for Fenix.
               MyAppAuthRole — Session + HIX_MwIsAuth + HIX_MwHasRole.
  Usage      : "middleware": "MyAppAuthRole", "scope": "customers"
               "middleware": "MyAppAuthRole", "scope": "customers:edit"
 -----------------------------------------------------------*/

FUNCTION MyAppAuthRole( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )
   
   o:Add( UMiddleware():New( "HIX_MwSession"  ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"   ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole"  ) )
   
RETURN o:Run()
