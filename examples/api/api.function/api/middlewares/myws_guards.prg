/*-----------------------------------------------------------
  File ......: myws_guards.prg
  Author.....: Charly 9000
  Created....: 2026-07-19
  Modified...: 2026-07-23
  Version....: 2.0.0
  Description: Consolidated custom middleware for Fenix.WS.Lite.

               Public middlewares:
                 MyWsSecHeaders     -- HSTS + XCTO + XFO + ...
                 MyWsBearer         -- JWT bearer auth
                 MyWsRequireScope   -- OAuth2 scope check
                 MyWsRateLimitUser  -- per-JWT-sub throttle
                 MyWsGuardPublic    -- chain for anonymous endpoints
                 MyWsGuardAuth      -- chain for authenticated endpoints
                 MyWsGuardScope     -- authed + required scope check

               Public helper:
                 AuditLog( cEvent, hExtra )
                           -- write one JSON line to logs/audit.log
 -----------------------------------------------------------*/


STATIC s_hRateData := NIL
STATIC s_mtxRate   := NIL
STATIC s_mtxAudit  := NIL


// ============================================================
// MyWsSecHeaders -- hardening response headers
// ============================================================
FUNCTION MyWsSecHeaders( oCtx )

   LOCAL cHsts, cXct, cXf, cRef, cPerm

   HB_SYMBOL_UNUSED( oCtx )

   cXct  := UMwConfig( "secheaders", "x_content_type",  "nosniff"     )
   cXf   := UMwConfig( "secheaders", "x_frame",         "DENY"        )
   cRef  := UMwConfig( "secheaders", "referrer_policy", "no-referrer" )
   cPerm := UMwConfig( "secheaders", "permissions",     ""            )
   cHsts := UMwConfig( "secheaders", "hsts",            ""            )

   USetHeader( "X-Content-Type-Options", cXct )
   USetHeader( "X-Frame-Options",        cXf  )
   USetHeader( "Referrer-Policy",        cRef )

   IF ! Empty( cPerm )
      USetHeader( "Permissions-Policy", cPerm )
   ENDIF

   IF ! Empty( cHsts ) .AND. UIsHttps()
      USetHeader( "Strict-Transport-Security", cHsts )
   ENDIF

RETURN .T.


// ============================================================
// MyWsBearer -- JWT bearer authentication
// ============================================================
FUNCTION MyWsBearer( oCtx )

   LOCAL cAuth, cToken, hPayload

   cAuth := UHeader( "Authorization", "" )

   IF Empty( cAuth )
      RETURN _MyWsBearerReject( oCtx, "AUTH_MISSING_TOKEN", ;
         "Missing Authorization header" )
   ENDIF

   IF Left( Lower( cAuth ), 7 ) != "bearer "
      RETURN _MyWsBearerReject( oCtx, "AUTH_BAD_SCHEME", ;
         "Only 'Bearer' authorization scheme is accepted" )
   ENDIF

   cToken := AllTrim( SubStr( cAuth, 8 ) )

   IF Empty( cToken )
      RETURN _MyWsBearerReject( oCtx, "AUTH_EMPTY_TOKEN", ;
         "Bearer token is empty" )
   ENDIF

   hPayload := HIX_JwtValidate( cToken, HIX_KeyGet( "jwt" ) )

   IF ValType( hPayload ) != "H"
      RETURN _MyWsBearerReject( oCtx, "AUTH_INVALID_TOKEN", ;
         "Token is invalid or expired" )
   ENDIF

   oCtx:hData[ "jwt"  ] := hPayload
   oCtx:hData[ "user" ] := hPayload
   URequest():hData[ "user" ] := hPayload

RETURN .T.


STATIC FUNCTION _MyWsBearerReject( oCtx, cCode, cMsg )

   USendApiError( cCode, cMsg, 401, ;
      { "hint" => "Login via POST /login" } )
   oCtx:lHandled := .T.

RETURN .F.


// ============================================================
// MyWsRequireScope -- reads oCtx:cScope, matches against the
// JWT "scope" claim (space-separated OAuth2-style string).
// Empty scope on the route means "any authenticated user".
// ============================================================
FUNCTION MyWsRequireScope( oCtx )

   LOCAL hUser, cGranted, aGranted, cWanted

   cWanted := AllTrim( iif( ValType( oCtx:cScope ) == "C", oCtx:cScope, "" ) )

   IF Empty( cWanted )
      RETURN .T.
   ENDIF

   hUser := hb_HGetDef( oCtx:hData, "user", NIL )

   IF ValType( hUser ) != "H"
      USendApiError( "AUTH_UNAUTHENTICATED", ;
         "Authenticated request required for this scope", 401 )
      oCtx:lHandled := .T.
      RETURN .F.
   ENDIF

   cGranted := AllTrim( hb_HGetDef( hUser, "scope", "" ) )
   aGranted := hb_ATokens( cGranted, " " )

   IF AScan( aGranted, {| s | s == cWanted } ) == 0
      USendApiError( "AUTH_INSUFFICIENT_SCOPE", ;
         "Missing required scope: " + cWanted, 403, ;
         { "hint" => "Ask your admin to grant this scope" } )
      oCtx:lHandled := .T.
      RETURN .F.
   ENDIF

RETURN .T.


// ============================================================
// MyWsRateLimitUser -- fixed-window per-JWT-sub throttle.
// Adds X-RateLimit-* headers to every authenticated response.
// ============================================================
FUNCTION MyWsRateLimitUser( oCtx )

   LOCAL hUser, cSub, nNow, aEntry, nMax, nWin, nCount, nStart, lAllow

   hUser := hb_HGetDef( oCtx:hData, "user", NIL )

   IF ValType( hUser ) != "H"
      RETURN .T.
   ENDIF

   cSub := hb_HGetDef( hUser, "sub", "" )

   IF Empty( cSub )
      RETURN .T.
   ENDIF

   nMax := UMwConfig( "ratelimit", "user_per_min", 600 )
   IF ! HB_ISNUMERIC( nMax ) .OR. nMax <= 0
      nMax := 600
   ENDIF
   nWin := 60

   IF s_hRateData == NIL
      s_hRateData := { => }
      s_mtxRate   := hb_mutexCreate()
   ENDIF

   nNow := Int( hb_TToSec( hb_DateTime() ) )

   hb_mutexLock( s_mtxRate )

   IF hb_HHasKey( s_hRateData, cSub )
      aEntry := s_hRateData[ cSub ]
      nCount := aEntry[ 1 ]
      nStart := aEntry[ 2 ]
      IF ( nNow - nStart ) >= nWin
         nCount := 1
         nStart := nNow
      ELSE
         nCount++
      ENDIF
   ELSE
      nCount := 1
      nStart := nNow
   ENDIF

   s_hRateData[ cSub ] := { nCount, nStart }
   lAllow := ( nCount <= nMax )

   hb_mutexUnlock( s_mtxRate )

   USetHeader( "X-RateLimit-Limit",     hb_NToS( nMax ) )
   USetHeader( "X-RateLimit-Remaining", hb_NToS( Max( 0, nMax - nCount ) ) )
   USetHeader( "X-RateLimit-Reset",     hb_NToS( nStart + nWin ) )

   IF ! lAllow
      USetHeader( "Retry-After", hb_NToS( ( nStart + nWin ) - nNow ) )
      USendApiError( "RATE_LIMIT_USER", "Per-user rate limit exceeded", 429, ;
         { "hint" => "Slow down; window resets soon" } )
      oCtx:lHandled := .T.
      RETURN .F.
   ENDIF

RETURN .T.


// ============================================================
// AuditLog -- write one JSON event line to logs/audit.log.
// Thread-safe via s_mtxAudit.
// ============================================================
FUNCTION AuditLog( cEvent, hExtra )

   LOCAL cFile, hEntry, oReq, hUser, cLine, cKey

   cFile := UMwConfig( "audit", "file", "logs/audit.log" )

   IF s_mtxAudit == NIL
      s_mtxAudit := hb_mutexCreate()
   ENDIF

   oReq := URequest()

   hEntry := { ;
      "ts"    => hb_TSToStr( hb_DateTime(), .T. ), ;
      "event" => cEvent ;
   }

   IF oReq != NIL
      hEntry[ "req_id" ] := hb_HGetDef( oReq:hData, "_req_id", "" )
      hEntry[ "ip"     ] := UIP()
      hEntry[ "path"   ] := UPath()
      hEntry[ "method" ] := UMethod()
      hUser := hb_HGetDef( oReq:hData, "user", NIL )
      IF ValType( hUser ) == "H"
         hEntry[ "sub"  ] := hb_HGetDef( hUser, "sub",  "" )
         hEntry[ "name" ] := hb_HGetDef( hUser, "name", "" )
      ENDIF
   ENDIF

   IF ValType( hExtra ) == "H"
      FOR EACH cKey IN hb_HKeys( hExtra )
         hEntry[ cKey ] := hExtra[ cKey ]
      NEXT
   ENDIF

   cLine := hb_jsonEncode( hEntry ) + hb_eol()

   hb_mutexLock( s_mtxAudit )
   TRY
      hb_MemoWrit( cFile, iif( hb_FileExists( cFile ), ;
         hb_MemoRead( cFile ) + cLine, cLine ) )
   CATCH
   END
   hb_mutexUnlock( s_mtxAudit )

RETURN NIL


// ============================================================
// Composite guards
// ============================================================

FUNCTION MyWsGuardPublic( oCtx )

   IF ! HIX_MwRateLimit( oCtx ) ; RETURN .F. ; ENDIF
   IF ! HIX_MwCors     ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! MyWsSecHeaders ( oCtx ) ; RETURN .F. ; ENDIF

RETURN .T.


FUNCTION MyWsGuardAuth( oCtx )

   IF ! HIX_MwRateLimit   ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! HIX_MwCors        ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! MyWsSecHeaders    ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! MyWsBearer        ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! MyWsRateLimitUser ( oCtx ) ; RETURN .F. ; ENDIF

RETURN .T.


FUNCTION MyWsGuardScope( oCtx )

   IF ! HIX_MwRateLimit   ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! HIX_MwCors        ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! MyWsSecHeaders    ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! MyWsBearer        ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! MyWsRequireScope  ( oCtx ) ; RETURN .F. ; ENDIF
   IF ! MyWsRateLimitUser ( oCtx ) ; RETURN .F. ; ENDIF

RETURN .T.
