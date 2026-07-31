/*-----------------------------------------------------------
  File ......: hix_mw_jwt.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-07-14
  Version....: 1.1.0
  Description: JWT HS256 authentication middleware for HIX.
               Validates Bearer tokens in the Authorization header
               and exposes payload as oCtx:hData["jwt"]. Uses the
               engine in src/hix_jwt.prg (HIX_JwtEncode / Validate).
  Usage      : HIX_MwJwtSetup( "my-secret", 3600 )
               oSrv:AddRouteGet( "api", "/api/data", {||...}, { "HIX_MwJwt" } )
  Notes      : Web: optional | API: yes (stateless auth)
 -----------------------------------------------------------*/

// ============================================================
// JWT HS256 — JSON Web Token authentication (middleware layer)
//
// This file is the router-facing side of JWT. The token engine
// (encode / validate / signing) lives in src/hix_jwt.prg so it
// can be reused outside the pipeline.
//
// Flow:
// 1. Client logs in -> server calls HIX_JwtEncode() -> returns token
// 2. Client sends: Authorization: Bearer <token>
// 3. HIX_MwJwt validates signature + expiry -> sets hData["jwt"]
// 4. Route handler reads: oCtx:hData["jwt"]["user_id"]
//
// Example — protect a route:
// oSrv:AddRouteGet( "me", "/api/me", ;
// {|| USendJson( UContext():hData["jwt"] ) }, ;
// { "HIX_MwJwt" } )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER

#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

// ============================================================
// HIX_MwJwt — validates Bearer token using the global key.
// Rejects with 401 if missing or invalid.
// ============================================================
FUNCTION HIX_MwJwt( oCtx )
RETURN _HixMwJwtRun( oCtx, HIX_JwtDefaultKey() )

// ============================================================
// HIX_MwJwtFactory — returns a codeblock with a per-route key.
// ============================================================
FUNCTION HIX_MwJwtFactory( cKey )
RETURN {| oCtx | _HixMwJwtRun( oCtx, cKey ) }

// ============================================================
// HIX_MwJwtScope — enforces the scope declared in the route.
//
// Reads oCtx:cScope (set by the router from the route definition)
// and verifies every space-separated token is present in the
// JWT payload claim "scope".
//
// Pass if oCtx:cScope is empty (no restriction on that route).
// Rejects with 403 if scope is required but missing or insufficient.
//
// Must run after HIX_MwJwt in the pipeline (needs hData["jwt"]).
//
// Example:
// // Token carries: { "scope" => "read:products write:orders" }
// oSrv:AddRouteGet( "list", "/api/products", action, "MW_API_JWT", "read:products" )  // OK
// oSrv:AddRouteGet( "del",  "/api/products", action, "MW_API_JWT", "delete:products" ) // 403
// ============================================================
FUNCTION HIX_MwJwtScope( oCtx )

   LOCAL cRequired, hJwt, cGranted

   cRequired := AllTrim( oCtx:cScope )

   IF Empty( cRequired )

      RETURN .T.

   ENDIF

   hJwt := hb_HGetDef( oCtx:hData, "jwt", NIL )

   IF ValType( hJwt ) != "H"

      HIX_HttpError( oCtx:oReq, 403 )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   cGranted := AllTrim( hb_HGetDef( hJwt, "scope", "" ) )

   IF ! _HixScopeGranted( cRequired, cGranted )

      HIX_HttpError( oCtx:oReq, 403 )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

RETURN .T.

// ---- private helpers ----

STATIC FUNCTION _HixMwJwtRun( oCtx, cKey )

   LOCAL cAuth, cToken, hPayload

   cAuth := oCtx:oReq:Header( "authorization", "" )

   IF Upper( Left( cAuth, 7 ) ) == "BEARER "

      cToken := AllTrim( SubStr( cAuth, 8 ) )
   ELSE
      cToken := ""

   ENDIF

   IF Empty( cToken )

      HIX_HttpError( oCtx:oReq, 401 )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   hPayload := HIX_JwtValidate( cToken, cKey )

   IF hPayload == NIL

      HIX_HttpError( oCtx:oReq, 401 )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   oCtx:hData[ "jwt" ] := hPayload

RETURN .T.

// Returns .T. if all space-separated tokens in cRequired are in cGranted.
STATIC FUNCTION _HixScopeGranted( cRequired, cGranted )

   LOCAL aRequired, aGranted, n

   aRequired := hb_ATokens( cRequired, " " )
   aGranted  := hb_ATokens( cGranted,  " " )

   FOR n := 1 TO Len( aRequired )

      IF AScan( aGranted, {| s | s == aRequired[ n ] } ) == 0

         RETURN .F.

      ENDIF

   NEXT

RETURN .T.
