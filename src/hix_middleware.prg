/*-----------------------------------------------------------
  File ......: hix_middleware.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-25
  Description: Middleware pipeline classes for HIX — THixContext,
               THixMiddleware, THixBaseMiddleware.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hbclass.ch"
#INCLUDE "hix_const.ch"

// ============================================================
// CLASS THixContext
//
// Created by the router before executing the middleware.
// Middlewares read and enrich hData in cascade.
//
// oCtx:oReq        — current THixRequest
// oCtx:hData       — free hash to pass data between middlewares
// oCtx:cMw         — middleware function name for this route
// oCtx:cScope      — scope string defined in the route
// oCtx:lHandled    — .T. if middleware already sent a response
// ============================================================
CLASS THixContext

   DATA oReq                       // THixRequest of current request
   DATA cMw         INIT ""        // middleware function name
   DATA cScope      INIT ""        // route scope (free metadata)
   DATA hData       INIT { => }    // free hash — enriched in cascade
   DATA lHandled    INIT .F.       // .T. if MW already responded
   DATA cOnFail     INIT ""        // route to dispatch if MW returns .F.

   METHOD New( oReq, cMw, cScope )

ENDCLASS

METHOD New( oReq, cMw, cScope ) CLASS THixContext

   hb_default( @cMw,    "" )
   hb_default( @cScope, "" )
   ::oReq     := oReq
   ::cMw      := cMw
   ::cScope   := cScope
   ::hData    := { => }
   ::lHandled := .F.
   ::cOnFail  := ""

RETURN Self

// ============================================================
// CLASS UMiddleware
//
// Wraps a single middleware function. Accepts:
// - Codeblock : {|oCtx| ... RETURN .T./.F. }
// - String    : function name resolved at runtime via macro
// - @FuncRef  : function pointer obtained with @FuncName()
//
// Usage:
// UMiddleware():New( "Mw_Session",     "session" )
// UMiddleware():New( {|oCtx| ... },    "custom"  )
// ============================================================
CLASS UMiddleware

   DATA xFunc             // codeblock or function name string
   DATA cName   INIT ""   // descriptive name for logs
   DATA cOnFail INIT ""   // route to dispatch if this MW returns .F.

   METHOD New( xFunc, cName, cOnFail ) CONSTRUCTOR
   METHOD Run( oCtx )

ENDCLASS

METHOD New( xFunc, cName, cOnFail ) CLASS UMiddleware

   hb_default( @cName,   "" )
   hb_default( @cOnFail, "" )
   ::xFunc   := xFunc
   ::cName   := cName
   ::cOnFail := cOnFail

RETURN Self

METHOD Run( oCtx ) CLASS UMiddleware

   LOCAL lAccept := .F.
   LOCAL bEval   := NIL
   LOCAL oErr

   DO CASE

      CASE ValType( ::xFunc ) == "B"
         bEval := ::xFunc
      CASE ValType( ::xFunc ) == "C" .AND. ! Empty( ::xFunc )
         bEval := &( "{|oCtx|" + AllTrim( ::xFunc ) + "(oCtx)}" )
      OTHERWISE
         ld( "UMiddleware [" + ::cName + "]: invalid xFunc — blocking" )
         RETURN .F.

   ENDCASE

   TRY

      lAccept := Eval( bEval, oCtx )

      IF ValType( lAccept ) != "L"

         lw( "UMiddleware [" + ::cName + "]: must return .T./.F." )
         lAccept := .F.

      ENDIF

   CATCH oErr
      lw( "UMiddleware [" + ::cName + "] exception: " + oErr:description )
      lAccept := .F.

   END

RETURN lAccept

// ============================================================
// CLASS UBaseMiddleware
//
// Pipeline container. Executes each UMiddleware in order.
// Short-circuit: if one returns .F., rest are not executed.
//
// Usage:
// FUNCTION MyAuth( oCtx )
// LOCAL o := UBaseMiddleware():New( oCtx )
// o:Add( UMiddleware():New( "Mw_Session",     "session" ) )
// o:Add( UMiddleware():New( @Mw_RequireAuth(), "auth"    ) )
// RETURN o:Run()
// ============================================================
CLASS UBaseMiddleware

   DATA oCtx               // THixContext passed at construction
   DATA aItems  INIT {}    // array of UMiddleware objects

   METHOD New( oCtx ) CONSTRUCTOR
   METHOD Add( oMw )
   METHOD Run()

ENDCLASS

METHOD New( oCtx ) CLASS UBaseMiddleware

   ::oCtx  := oCtx
   ::aItems := {}

RETURN Self

METHOD Add( oMw ) CLASS UBaseMiddleware

   AAdd( ::aItems, oMw )

RETURN Self

METHOD Run() CLASS UBaseMiddleware

   LOCAL oItem

   FOR EACH oItem IN ::aItems

      IF ! oItem:Run( ::oCtx )

         ld( "UBaseMiddleware: pipeline cut by [" + oItem:cName + "]" )

         IF ! Empty( oItem:cOnFail ) .AND. Empty( ::oCtx:cOnFail )

            ::oCtx:cOnFail := oItem:cOnFail

         ENDIF

         RETURN .F.

      ENDIF

   NEXT

RETURN .T.
