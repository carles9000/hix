/*-----------------------------------------------------------
  File ......: myapplogin.prg
  Author.....: Charly 9000
  Created....: 2026-05-27
  Modified...: 2026-07-17
  Version....: 1.1.0
  Description: Middleware group for unauthenticated login POST.
               Session + rate-limit (brute-force) + CSRF.
  Usage      : "middleware": "MyAppLogin"   (POST /auth)
  Notes      : Rate-limit is global (HIX_MwRateLimitSetup in
               src/app.prg). Currently applied only on /auth so
               global == per-route in this app. Add per-route
               factory if reused elsewhere.
 -----------------------------------------------------------*/

FUNCTION MyAppLogin( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )
   
   o:Add( UMiddleware():New( "HIX_MwSession"   ) )
   o:Add( UMiddleware():New( "HIX_MwRateLimit" ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
   
RETURN o:Run()
