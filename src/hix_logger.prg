/*-----------------------------------------------------------
  File ......: hix_logger.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: Centralized thread-safe logger with file rotation
               (HIX_LoggerInit, ld/l/lw/le macros).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_LOGGER
#INCLUDE "hix_logger.ch"

STATIC s_oLogger := NIL
STATIC s_hTrace  := { => }   // módulo → .T./.F.
STATIC s_oTrace  := NIL      // mutex para s_hTrace

FUNCTION HIX_LoggerInit( cFile, nLevel, lConsole, nMaxSize, nMaxFiles )

   IF s_oTrace == NIL

      s_oTrace := hb_mutexCreate()

   ENDIF

   hb_default( @cFile,     "logs/hix.log"   )
   hb_default( @nLevel,    HIX_LOG_INFO      )
   hb_default( @lConsole,  .T.               )
   hb_default( @nMaxSize,  HIX_LOG_ROTATE    )
   hb_default( @nMaxFiles, 0                 )
   s_oLogger := THixLogger():New( cFile, nLevel, lConsole, nMaxSize, nMaxFiles )

RETURN NIL

FUNCTION HIX_LoggerClose()

   IF s_oLogger != NIL

      s_oLogger:Close()
      s_oLogger := NIL

   ENDIF

RETURN NIL

FUNCTION HIX_LogLevelFromStr( cLevel )

   DO CASE

      CASE Lower( cLevel ) == "debug" ; RETURN HIX_LOG_DEBUG
      CASE Lower( cLevel ) == "warn"  ; RETURN HIX_LOG_WARN
      CASE Lower( cLevel ) == "error" ; RETURN HIX_LOG_ERROR
      CASE Lower( cLevel ) == "fatal" ; RETURN HIX_LOG_FATAL

   ENDCASE

RETURN HIX_LOG_INFO

// ============================================================
// Tracing — control por módulo
// WARN/ERROR/FATAL siempre pasan. DEBUG/INFO filtrados por hash.
// ============================================================

FUNCTION HIX_TraceSet( cModule, lEnabled )

   hb_default( @lEnabled, .T. )
   hb_mutexLock( s_oTrace )
   s_hTrace[ cModule ] := lEnabled
   hb_mutexUnlock( s_oTrace )

RETURN NIL

FUNCTION HIX_TraceAll( lEnabled )

   LOCAL cKey

   hb_default( @lEnabled, .T. )
   hb_mutexLock( s_oTrace )

   FOR EACH cKey IN hb_HKeys( s_hTrace )

      s_hTrace[ cKey ] := lEnabled

   NEXT

   hb_mutexUnlock( s_oTrace )

RETURN NIL

FUNCTION HIX_TraceEnabled( cModule )

   LOCAL lRet

   hb_mutexLock( s_oTrace )
   lRet := hb_HGetDef( s_hTrace, cModule, .F. )
   hb_mutexUnlock( s_oTrace )

RETURN lRet

FUNCTION HIX_TraceGetAll()

   LOCAL hCopy := { => }
   LOCAL cKey

   hb_mutexLock( s_oTrace )

   FOR EACH cKey IN hb_HKeys( s_hTrace )

      hCopy[ cKey ] := s_hTrace[ cKey ]

   NEXT

   hb_mutexUnlock( s_oTrace )

RETURN hCopy

// ============================================================
FUNCTION _l( cMsg, nLevel, cModule )

   hb_default( @nLevel,  HIX_LOG_INFO )
   hb_default( @cModule, "unknown"    )
   // WARN, ERROR, FATAL siempre pasan sin importar el trace

   IF nLevel < HIX_LOG_WARN .AND. s_oTrace != NIL

      IF ! HIX_TraceEnabled( cModule )

         RETURN NIL

      ENDIF

   ENDIF

   IF s_oLogger != NIL

      s_oLogger:Write( cMsg, nLevel, cModule )

   ENDIF

RETURN NIL

// ============================================================
CLASS THixLogger

   DATA cFile     INIT ""
   DATA nLevel    INIT HIX_LOG_INFO
   DATA lConsole  INIT .T.
   DATA hFile     INIT NIL
   DATA oMutex    INIT NIL
   DATA nMaxSize  INIT HIX_LOG_ROTATE
   DATA nMaxFiles INIT 0

   METHOD New( cFile, nLevel, lConsole, nMaxSize, nMaxFiles )
   METHOD Write( cMsg, nLevel, cContext )
   METHOD Close()
   HIDDEN:
   METHOD _Format( cMsg, nLevel, cContext )
   METHOD _LevelName( nLevel )
   METHOD _LevelColor( nLevel )

ENDCLASS

METHOD New( cFile, nLevel, lConsole, nMaxSize, nMaxFiles ) CLASS THixLogger

   ::cFile    := cFile
   ::nLevel   := nLevel
   ::lConsole := lConsole
   ::nMaxSize  := nMaxSize
   ::nMaxFiles := nMaxFiles
   ::oMutex   := hb_mutexCreate()

   IF ! Empty( cFile )

      IF ! hb_DirExists( hb_FNameDir( cFile ) )

         hb_DirCreate( hb_FNameDir( cFile ) )

      ENDIF

      ::hFile := FOpen( cFile, FO_READWRITE + FO_SHARED )

      IF ::hFile == F_ERROR

         ::hFile := FCreate( cFile )

      ENDIF

      IF ::hFile != F_ERROR

         FSeek( ::hFile, 0, FS_END )

      ENDIF

   ENDIF

RETURN Self

METHOD Write( cMsg, nLevel, cContext ) CLASS THixLogger

   LOCAL cLine, cNewName, cDir, aFiles

   IF nLevel < ::nLevel

      RETURN Self

   ENDIF

   cLine := ::_Format( cMsg, nLevel, cContext )
   hb_mutexLock( ::oMutex )

   IF ::lConsole

      // Redirigido a _d() para no contaminar la consola del servidor
      _d( cLine )

   ENDIF

   IF ::hFile != NIL .AND. ::hFile != F_ERROR

      FWrite( ::hFile, cLine + hb_eol() )

      IF FSeek( ::hFile, 0, FS_RELATIVE ) > ::nMaxSize

         FClose( ::hFile )
         cNewName := hb_FNameDir( ::cFile ) + hb_FNameName( ::cFile ) + "_" + ;
            StrTran( hb_TToS( hb_DateTime() ), ".", "" ) + hb_FNameExt( ::cFile )
         hb_vfRename( ::cFile, cNewName )
         ::hFile := FCreate( ::cFile )

         IF ::nMaxFiles > 0

            cDir   := hb_FNameDir( ::cFile )
            aFiles := hb_vfDirectory( cDir + hb_FNameName( ::cFile ) + "_*" + hb_FNameExt( ::cFile ) )
            ASort( aFiles,,,, {| a, b | a[ 1 ] < b[ 1 ] } )

            DO WHILE Len( aFiles ) > ::nMaxFiles

               hb_vfErase( cDir + aFiles[ 1 ][ 1 ] )
               ADel( aFiles, 1 )
               ASize( aFiles, Len( aFiles ) - 1 )

            ENDDO

         ENDIF

      ENDIF

   ENDIF

   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD _Format( cMsg, nLevel, cContext ) CLASS THixLogger
RETURN "[" + _HixLogTs() + "]" + ;
      " [" + alltrim( ::_LevelName( nLevel ), 5 ) + "]" + ;
      " [" + alltrim( cContext, 30 ) + "] " + cMsg

// Timestamp para el log: "YYYY-MM-DD HH:MM:SS"
STATIC FUNCTION _HixLogTs()

   LOCAL cTs := hb_TToS( hb_DateTime() )   // "YYYYMMDDHHMMSSTTT"

RETURN SubStr( cTs, 1, 4 ) + "-" + SubStr( cTs, 5, 2 ) + "-" + SubStr( cTs, 7, 2 ) + " " + ;
      SubStr( cTs, 9, 2 ) + ":" + SubStr( cTs, 11, 2 ) + ":" + SubStr( cTs, 13, 2 )

METHOD _LevelName( nLevel ) CLASS THixLogger

   DO CASE

      CASE nLevel == HIX_LOG_DEBUG ; RETURN "DEBUG"
      CASE nLevel == HIX_LOG_INFO  ; RETURN "INFO"
      CASE nLevel == HIX_LOG_WARN  ; RETURN "WARN"
      CASE nLevel == HIX_LOG_ERROR ; RETURN "ERROR"
      CASE nLevel == HIX_LOG_FATAL ; RETURN "FATAL"

   ENDCASE

RETURN "?????"

METHOD _LevelColor( nLevel ) CLASS THixLogger

   DO CASE

      CASE nLevel == HIX_LOG_DEBUG ; RETURN Chr( 27 ) + "[90m"
      CASE nLevel == HIX_LOG_INFO  ; RETURN Chr( 27 ) + "[0m"
      CASE nLevel == HIX_LOG_WARN  ; RETURN Chr( 27 ) + "[33m"
      CASE nLevel == HIX_LOG_ERROR ; RETURN Chr( 27 ) + "[31m"
      CASE nLevel == HIX_LOG_FATAL ; RETURN Chr( 27 ) + "[1;31m"

   ENDCASE

RETURN ""

METHOD Close() CLASS THixLogger

   IF ::hFile != NIL .AND. ::hFile != F_ERROR

      FClose( ::hFile )
      ::hFile := NIL

   ENDIF

   ::oMutex := NIL

RETURN Self
