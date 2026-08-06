/*-----------------------------------------------------------
  File ......: myappauthedit.prg
  Author.....: Charly 9000
  Created....: 2026-05-27
  Modified...: 2026-07-17
  Version....: 1.4.0
  Description: Middleware group for authenticated CRUD POST routes.
               MyAppAuthRoleEdit = Session + IsAuth + HasRole + CsrfCheck.
               Uses HIX_MwCsrfCheck (stateless HMAC): matches the token
               emitted by @csrf / UCsrfToHtml() in views. TTL is set
               globally via HIX_MwCsrfSetup( ..., 3600 ) in src/app.prg.
  Usage      : "middleware": "MyAppAuthRoleEdit", "scope": "customers:edit"
 -----------------------------------------------------------*/

FUNCTION MyAppAuthRoleEdit( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )
   
   o:Add( UMiddleware():New( "HIX_MwSession"   ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"    ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole"   ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
   
RETURN o:Run()
