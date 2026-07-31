/*-----------------------------------------------------------
  File ......: hix_bootlog.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-07-09
  Modified...: 2026-07-09
  Version....: 1.0.0
  Description: Structured boot log for HIX. Captures every step of the
               server startup (loaders, middlewares, routes, config,
               server subsystems) into a static hash accessible at runtime.
               Each entry is a 4-element array: { cAction, lStatus, cValue, xCargo }
                 cAction : "file" | "config" | "init" | "route" | ...
                 lStatus : .T. success / .F. error
                 cValue  : human readable resource identifier
                 xCargo  : optional payload (error description, extra info, NIL)
  Usage      : HIX_BootLogAdd( "loaders", "file", .T., "myapp.prg" )
               HIX_BootLogAdd( "loaders", "file", .F., "bad.prg", oErr:description )
               USendJson( HIX_BootLog() )
  Notes      : Thread-safe. Owned by the process that owns HIX globals.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE "bootlog"
#INCLUDE "hix_logger.ch"

STATIC s_hBootLog := { => }
STATIC s_mtxBootLog := NIL
STATIC s_lVerbose := .F.
STATIC s_bAction  := NIL   // codeblock invocado tras cada HIX_BootLogAdd

// ============================================================
// _BootLogMutex — mutex lazy init
// ============================================================
STATIC FUNCTION _BootLogMutex()

   IF s_mtxBootLog == NIL

      s_mtxBootLog := hb_mutexCreate()

   ENDIF

RETURN s_mtxBootLog

// ============================================================
// HIX_BootLog — devuelve el hash completo del boot log.
// ============================================================
FUNCTION HIX_BootLog()

   LOCAL hCopy

   hb_mutexLock( _BootLogMutex() )
   hCopy := hb_HClone( s_hBootLog )
   hb_mutexUnlock( _BootLogMutex() )

RETURN hCopy

// ============================================================
// HIX_BootLogSection — devuelve el array de una seccion, o {} si no existe.
// ============================================================
FUNCTION HIX_BootLogSection( cKey )

   LOCAL aRet

   IF ValType( cKey ) != "C" .OR. Empty( cKey )

      RETURN {}

   ENDIF

   hb_mutexLock( _BootLogMutex() )

   IF hb_HHasKey( s_hBootLog, cKey )

      aRet := AClone( s_hBootLog[ cKey ] )
   ELSE
      aRet := {}

   ENDIF

   hb_mutexUnlock( _BootLogMutex() )

RETURN aRet

// ============================================================
// HIX_BootLogAdd — anade un evento a una seccion.
// cKey    : "config" | "server" | "loaders" | "middlewares" | "routes"
// cAction : "file" | "config" | "route" | "setup" | "init" | ...
// lStatus : .T. exito / .F. error (default .T.)
// cValue  : descripcion legible del recurso
// xCargo  : payload libre (descripcion del error, info extra, NIL por defecto)
// ============================================================
FUNCTION HIX_BootLogAdd( cKey, cAction, lStatus, cValue, xCargo )

   hb_default( @lStatus, .T. )

   IF ValType( cKey ) != "C" .OR. Empty( cKey )

      RETURN NIL

   ENDIF

   IF ValType( cAction ) != "C"

      cAction := ""

   ENDIF

   IF ValType( cValue ) != "C"

      cValue := ""

   ENDIF

   // Blindaje: si es un error sin cargo, forzar un placeholder para que
   // los consumidores (HIX_BootLogShow, JSON, UI) nunca vean NIL en errores.
   // Nota: usamos ValType(xCargo)=="U" en lugar de xCargo==NIL porque
   // bajo SET EXACT OFF la comparacion "==" con NIL puede dar falsos positivos.

   IF ValType( xCargo ) == "U" .AND. ! lStatus

      xCargo := _( "BOOT_ERR_NO_DESC" )

   ENDIF

   hb_mutexLock( _BootLogMutex() )

   IF ! hb_HHasKey( s_hBootLog, cKey )

      s_hBootLog[ cKey ] := {}

   ENDIF

   AAdd( s_hBootLog[ cKey ], { cAction, lStatus, cValue, xCargo } )
   hb_mutexUnlock( _BootLogMutex() )
   
   // Callback opcional: se invoca fuera del mutex para no bloquear
   // si el usuario hace operaciones lentas dentro del codeblock.

   IF HB_IsBlock( s_bAction )

      Eval( s_bAction, cKey, cAction, lStatus, cValue, xCargo )

   ENDIF

RETURN NIL

// ============================================================
// HIX_BootLogReset — vacia el boot log. Se llama al inicio de _Init().
// ============================================================
FUNCTION HIX_BootLogReset()

   hb_mutexLock( _BootLogMutex() )
   s_hBootLog := { => }
   hb_mutexUnlock( _BootLogMutex() )

RETURN NIL

// ============================================================
// HIX_BootLogVerbose — activa/desactiva el registro detallado
// (por ejemplo, ruta a ruta en HIX_LoadRoutes).
// ============================================================
FUNCTION HIX_BootLogVerbose( lOn )

   LOCAL lPrev := s_lVerbose

   IF ValType( lOn ) == "L"

      s_lVerbose := lOn

   ENDIF

RETURN lPrev

// ============================================================
// HIX_BootLogAction — registra un codeblock que se ejecuta cada vez
// que HIX_BootLogAdd anade una entrada. Recibe:
// cKey, cAction, lStatus, cValue, xCargo
// Pasar NIL para desactivar. Devuelve el codeblock anterior.
// ============================================================
FUNCTION HIX_BootLogAction( bAction )

   LOCAL bPrev := s_bAction

   IF PCount() > 0

      IF HB_IsBlock( bAction ) .OR. bAction == NIL

         s_bAction := bAction

      ENDIF

   ENDIF

RETURN bPrev

// ============================================================
// HIX_BootLogIsVerbose — accessor para los callers.
// ============================================================
FUNCTION HIX_BootLogIsVerbose()
RETURN s_lVerbose

// ============================================================
// HIX_BootLogShow — vuelca por consola en orden logico.
// ============================================================
FUNCTION HIX_BootLogShow()

   LOCAL aOrder := { "config", "server", "loaders", "middlewares", "routes" }
   LOCAL cKey, aItems, aItem, cLine
   LOCAL hCopy := HIX_BootLog()
   LOCAL aExtra, i

   QQout( _( "BOOT_LOG_TITLE" ) + hb_eol() )

   // Primero las secciones en el orden canonico

   FOR EACH cKey IN aOrder

      IF hb_HHasKey( hCopy, cKey )

         _BootLogDumpSection( cKey, hCopy[ cKey ] )

      ENDIF

   NEXT

   // Luego cualquier otra seccion no listada
   aExtra := hb_HKeys( hCopy )

   FOR i := 1 TO Len( aExtra )

      IF AScan( aOrder, {| c | c == aExtra[ i ] } ) == 0

         _BootLogDumpSection( aExtra[ i ], hCopy[ aExtra[ i ] ] )

      ENDIF

   NEXT

   QQout( _( "BOOT_LOG_END" ) + hb_eol() )

RETURN NIL

// ============================================================
STATIC FUNCTION _BootLogDumpSection( cKey, aItems )

   LOCAL aItem, cLine, cFlag, xCargo

   QQout( "[" + cKey + "]" + hb_eol() )

   FOR EACH aItem IN aItems

      cFlag := iif( aItem[ 2 ], "OK ", "ERR" )
      cLine := "  " + cFlag + " " + PadR( aItem[ 1 ], 8 ) + " " + aItem[ 3 ]
      xCargo := aItem[ 4 ]

      IF xCargo != NIL

         cLine += "  -> " + hb_CStr( xCargo )
      ELSEIF ! aItem[ 2 ]
         cLine += "  -> " + _( "BOOT_ERR_UNKNOWN" )

      ENDIF

      QQout( cLine + hb_eol() )

   NEXT

RETURN NIL
