/*-----------------------------------------------------------
  File ......: hix_context.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-13
  Description: Thread-local HIX context accessor.
               Stores the active THixContext per worker thread,
               enabling helpers to access session, JWT payload
               and route params without explicit oCtx passing.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_REQUEST
#INCLUDE "hix_logger.ch"

THREAD STATIC s_oCurrentCtx := NIL

// ------------------------------------------------------------
FUNCTION HIX_SetContext( oCtx )

   s_oCurrentCtx := oCtx

RETURN NIL

FUNCTION HIX_GetContext()
RETURN s_oCurrentCtx

// ------------------------------------------------------------
// HIX_Session — access session hash from middleware context.
// No args  : full session hash (empty hash if none).
// cKey     : specific key value, or xDef if not found.
// ------------------------------------------------------------
FUNCTION HIX_Session( cKey, xDef )

   LOCAL oCtx := HIX_GetContext()
   LOCAL hSess

   IF oCtx == NIL

      RETURN iif( cKey == NIL, { => }, xDef )

   ENDIF

   hSess := hb_HGetDef( oCtx:hData, "session", NIL )

   IF cKey == NIL

      RETURN iif( hSess == NIL, { => }, hSess )

   ENDIF

   IF hSess == NIL

      RETURN xDef

   ENDIF

RETURN hb_HGetDef( hSess, cKey, xDef )

// ------------------------------------------------------------
// HIX_JwtPayload — access JWT payload hash from context.
// No args  : full payload hash (empty hash if none).
// cKey     : specific claim value, or xDef if not found.
// ------------------------------------------------------------
FUNCTION HIX_JwtPayload( cKey, xDef )

   LOCAL oCtx := HIX_GetContext()
   LOCAL hJwt

   IF oCtx == NIL

      RETURN iif( cKey == NIL, { => }, xDef )

   ENDIF

   hJwt := hb_HGetDef( oCtx:hData, "jwt", NIL )

   IF cKey == NIL

      RETURN iif( hJwt == NIL, { => }, hJwt )

   ENDIF

   IF hJwt == NIL

      RETURN xDef

   ENDIF

RETURN hb_HGetDef( hJwt, cKey, xDef )

// ------------------------------------------------------------
// HIX_RouteParam — route parameter from oCtx:oReq:hParam.
// Falls back to HIX_GetRequest():hParam when context is NIL.
// ------------------------------------------------------------
FUNCTION HIX_RouteParam( cKey, xDef )

   LOCAL oCtx := HIX_GetContext()
   LOCAL oReq

   hb_default( @xDef, "" )
   oReq := iif( oCtx != NIL, oCtx:oReq, HIX_GetRequest() )

   IF oReq == NIL

      RETURN xDef

   ENDIF

RETURN hb_HGetDef( oReq:hParam, cKey, xDef )
