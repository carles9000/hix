/*-----------------------------------------------------------
  File ......: hix_accesslog.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-03
  Description: HTTP access log writer in Common Log Format (CLF).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#INCLUDE "fileio.ch"

STATIC snHandle := -1
STATIC slActive := .F.
STATIC shMutex  := NIL

STATIC saMonths := { "Jan", "Feb", "Mar", "Apr", "May", "Jun", ;
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

// ------------------------------------------------------------------------------
// Inicializa el access log. cFile: ruta del fichero. lEnabled: activa/desactiva.
// ------------------------------------------------------------------------------
FUNCTION HIX_AccessLogInit( cFile, lEnabled )

   LOCAL cDir

   hb_default( @cFile,    "logs/access.log" )
   hb_default( @lEnabled, .F.               )
   slActive := .F.

   IF ! lEnabled .OR. Empty( cFile )

      RETURN NIL

   ENDIF

   cDir := hb_FNameDir( cFile )

   IF ! Empty( cDir ) .AND. ! hb_DirExists( cDir )

      hb_DirCreate( cDir )

   ENDIF

   shMutex  := hb_mutexCreate()
   snHandle := FOpen( cFile, FO_WRITE + FO_SHARED )

   IF snHandle < 0

      snHandle := FCreate( cFile )
   ELSE
      FSeek( snHandle, 0, FS_END )

   ENDIF

   slActive := ( snHandle >= 0 )

RETURN NIL

// ------------------------------------------------------------------------------
// Cierra el fichero de access log.
// ------------------------------------------------------------------------------
FUNCTION HIX_AccessLogClose()

   IF snHandle >= 0

      FClose( snHandle )
      snHandle := -1

   ENDIF

   slActive := .F.

RETURN NIL

// ------------------------------------------------------------------------------
// Escribe una linea de acceso. Llamado desde THixRequest:Respond().
// ------------------------------------------------------------------------------
FUNCTION HIX_AccessLog( cIP, cMethod, cPath, cProtocol, nStatus )

   LOCAL cLine, dNow, cTime

   IF ! slActive

      RETURN NIL

   ENDIF

   hb_default( @cIP,       "-"       )
   hb_default( @cMethod,   "-"       )
   hb_default( @cPath,     "/"       )
   hb_default( @cProtocol, "HTTP/1.1" )
   hb_default( @nStatus,   200       )
   dNow  := Date()
   cTime := Time()
   cLine := cIP + " - - " + ;
      "[" + PadL( hb_NToS( Day( dNow ) ), 2, "0" ) + "/" + ;
      saMonths[ Month( dNow ) ] + "/" + ;
      hb_NToS( Year( dNow ) ) + ":" + ;
      cTime + " +0000] " + ;
      Chr( 34 ) + cMethod + " " + cPath + " " + cProtocol + Chr( 34 ) + " " + ;
      hb_NToS( nStatus ) + hb_eol()
   hb_mutexLock( shMutex )
   FWrite( snHandle, cLine )
   hb_mutexUnlock( shMutex )

RETURN NIL
