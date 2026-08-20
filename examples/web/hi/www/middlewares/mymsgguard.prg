/*-----------------------------------------------------------
  File ......: mymsgguard.prg
  Author.....: Charly 9000
  Created....: 2026-08-20
  Modified...: 2026-08-20
  Version....: 1.0.0
  Description: Composite middleware group for POST /api/message.
               MyMsgGuard = HIX_MwCsrfCheck + MyMsgThrottle.
  Usage      : "middleware": "MyMsgGuard"   (POST /api/message)
  Notes      : HIX_MwCsrfCheck is the stateless HMAC variant, so no
               session is needed: it matches the token emitted by
               @csrf / UCsrfToHtml() in message.html. The form is
               posted as JSON, so the page sends the token in the
               X-CSRF-Token header instead of the _csrf field.

               Order matters. CSRF runs FIRST on purpose: the
               throttle is a business quota (one message per minute),
               so a forged or expired request must not burn the
               caller's slot. This differs from myapplogin.prg in the
               crud example, where the rate limit guards against
               brute force and every attempt has to be counted.
 -----------------------------------------------------------*/

FUNCTION MyMsgGuard( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
   o:Add( UMiddleware():New( "MyMsgThrottle"   ) )

RETURN o:Run()
