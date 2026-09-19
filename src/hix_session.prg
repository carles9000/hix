/*-----------------------------------------------------------
  File ......: hix_session.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-26
  Description: HTTP session store — memory (volatile) and file (persistent)
               backends.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_hStore    := NIL
STATIC s_mtxStore  := NIL
STATIC s_cName     := "HIXSID"
STATIC s_nTtl      := 3600
STATIC s_nGcEvery  := 500
STATIC s_nGcCount  := 0
// Modo fichero
STATIC s_nSidCounter := 0
STATIC s_mtxSidCtr   := NIL
STATIC s_cStorage  := "memory"
STATIC s_cRoute    := ""       // Route suffix for Apache LB stickysession (e.g. "i1")
STATIC s_cPath     := "sessions"
STATIC s_cPrefix   := "sess_"
STATIC s_lCrypt    := .F.
STATIC s_cSeed     := ""
STATIC s_nGcDays   := 3
STATIC s_lConfigApplied := .F.

// ============================================================
// HIX_MwSessionSetup — configura el módulo de sesiones.
// Llamar una sola vez antes de THixServer:Start().
// nTtl en segundos; nTtl=0 admite "sin caducidad" (cookie de sesión).
// ============================================================
FUNCTION HIX_MwSessionSetup( cName, nTtl, nGcEvery, cStorage, cPath, cPrefix, lCrypt, cSeed, nGcDays )

   IF ValType( cName     ) == "C" .AND. ! Empty( cName     ) ; s_cName     := cName     ; ENDIF

   IF ValType( nTtl      ) == "N" .AND. nTtl     >= 0        ; s_nTtl      := nTtl      ; ENDIF

   IF ValType( nGcEvery  ) == "N" .AND. nGcEvery  > 0        ; s_nGcEvery  := nGcEvery  ; ENDIF

   IF ValType( cStorage  ) == "C" .AND. ! Empty( cStorage  ) ; s_cStorage  := Lower( cStorage ) ; ENDIF

   IF ValType( cPath     ) == "C" .AND. ! Empty( cPath     )
      s_cPath := cPath
      // Session storage may live outside HIX_AppRoot() (e.g. hb_DirTemp()).
      // Register it so HIX_SafeErase accepts our own session files.
      HIX_SafeRegisterDir( cPath )
   ENDIF

   IF ValType( cPrefix   ) == "C"                            ; s_cPrefix   := cPrefix   ; ENDIF

   IF ValType( lCrypt    ) == "L"                            ; s_lCrypt    := lCrypt    ; ENDIF

   // Precedencia: cSeed pasado por parametro > HIX_Keys("session") > "".
   IF ValType( cSeed     ) == "C" .AND. ! Empty( cSeed     ) ; s_cSeed     := cSeed     ; ENDIF

   IF Empty( s_cSeed )                                       ; s_cSeed     := HIX_KeyGet( "session", "H!x@SESSION@2026" ) ; ENDIF

   IF ValType( nGcDays   ) == "N" .AND. nGcDays   > 0        ; s_nGcDays   := nGcDays   ; ENDIF

   s_lConfigApplied := .T.
   _HixSessionInitStore()

RETURN NIL

// ============================================================
// _HixSessionExp — expiración de una entrada.
// s_nTtl = 0 (indefinido) → devuelve marca lejana (~10 años).
// ============================================================
STATIC FUNCTION _HixSessionExp( nNow )
RETURN iif( s_nTtl > 0, nNow + s_nTtl, nNow + 315360000 )

// ============================================================
// HIX_MwSessionSetRoute — optional route suffix for Apache stickysession.
// Call after HIX_MwSessionSetup() with the BalancerMember route value (e.g. "i1").
// When set, HIXSID cookie is emitted as "<sid>.<route>" so Apache can read
// the backend route and enforce stickiness via stickysession=HIXSID.
// ============================================================
FUNCTION HIX_MwSessionSetRoute( cRoute )

   IF ValType( cRoute ) == "C"

      s_cRoute := cRoute

   ENDIF

RETURN NIL

// ============================================================
// HIX_MwSession — middleware de sesiones.
// ============================================================
FUNCTION HIX_MwSession( oCtx )

   LOCAL cSid, hEntry, nNow

   _HixSessionInitStore()

   cSid := _HixSidStrip( oCtx:oReq:Cookie( s_cName, "" ) )
   nNow := _HixNow()

   IF s_cStorage == "file"

      IF ! Empty( cSid )

         hEntry := _HixSessionFileLoad( cSid, nNow )

      ENDIF

      IF hEntry == NIL

         cSid   := _HixSessionNewId()
         hEntry := { "exp" => _HixSessionExp( nNow ), "data" => { => } }

      ENDIF

   ELSE
      hb_mutexLock( s_mtxStore )

      IF ! Empty( cSid ) .AND. hb_HHasKey( s_hStore, cSid )

         hEntry := s_hStore[ cSid ]

         IF hEntry[ "exp" ] < nNow

            hb_HDel( s_hStore, cSid )
            hEntry := NIL

         ENDIF

      ELSE
         hEntry := NIL

      ENDIF

      IF hEntry == NIL

         cSid   := _HixSessionNewId()
         hEntry := { "exp" => _HixSessionExp( nNow ), "data" => { => } }
         s_hStore[ cSid ] := hEntry

      ENDIF

      hb_mutexUnlock( s_mtxStore )

   ENDIF

   oCtx:hData[ "_sid"    ] := cSid
   oCtx:hData[ "session" ] := hEntry[ "data" ]

RETURN .T.

// ============================================================
// HIX_SessionGet
// ============================================================
FUNCTION HIX_SessionGet( oCtx, cKey )

   LOCAL hData

   hb_default( @cKey, "" )

   IF ! hb_HHasKey( oCtx:hData, "session" )

      RETURN ""

   ENDIF

   hData := oCtx:hData[ "session" ]

RETURN hb_HGetDef( hData, cKey, "" )

// ============================================================
// HIX_SessionSet
// ============================================================
FUNCTION HIX_SessionSet( oCtx, cKey, uValue )

   LOCAL hData

   IF Empty( cKey ) .OR. ! hb_HHasKey( oCtx:hData, "session" )

      RETURN NIL

   ENDIF

   hData       := oCtx:hData[ "session" ]
   hData[ cKey ] := uValue

RETURN NIL

// ============================================================
// HIX_SessionSave — renueva TTL + emite Set-Cookie.
// ============================================================
FUNCTION HIX_SessionSave( oCtx )

   LOCAL cSid, nNow, lGc, hEntry

   IF ! hb_HHasKey( oCtx:hData, "_sid" )

      RETURN NIL

   ENDIF

   cSid := oCtx:hData[ "_sid" ]
   nNow := _HixNow()
   lGc  := .F.

   IF s_cStorage == "file"

      hEntry := { "exp" => _HixSessionExp( nNow ), "data" => oCtx:hData[ "session" ] }
      _HixSessionFileWrite( cSid, hEntry )

      hb_mutexLock( s_mtxStore )
      s_nGcCount++

      IF s_nGcCount >= s_nGcEvery

         s_nGcCount := 0
         lGc := .T.

      ENDIF

      hb_mutexUnlock( s_mtxStore )

      IF lGc

         _HixSessionFileGc()

      ENDIF

   ELSE
      hb_mutexLock( s_mtxStore )

      IF hb_HHasKey( s_hStore, cSid )

         s_hStore[ cSid ][ "exp" ] := _HixSessionExp( nNow )

      ENDIF

      s_nGcCount++

      IF s_nGcCount >= s_nGcEvery

         s_nGcCount := 0
         lGc := .T.

      ENDIF

      hb_mutexUnlock( s_mtxStore )

      IF lGc

         _HixSessionGc( nNow )

      ENDIF

   ENDIF

   HIX_SetCookie( oCtx:oReq, s_cName, _HixSidWithRoute( cSid ), s_nTtl )

RETURN NIL

// ============================================================
// HIX_SessionDestroy — elimina la sesión y expira la cookie.
// ============================================================
FUNCTION HIX_SessionDestroy( oCtx )

   LOCAL cSid

   IF ! hb_HHasKey( oCtx:hData, "_sid" )

      RETURN NIL

   ENDIF

   cSid := oCtx:hData[ "_sid" ]

   IF s_cStorage == "file"

      _HixSessionFileDelete( cSid )
   ELSE
      hb_mutexLock( s_mtxStore )

      IF hb_HHasKey( s_hStore, cSid )

         hb_HDel( s_hStore, cSid )

      ENDIF

      hb_mutexUnlock( s_mtxStore )

   ENDIF

   oCtx:hData[ "_sid"    ] := ""
   oCtx:hData[ "session" ] := { => }

   HIX_SetCookie( oCtx:oReq, s_cName, "", - 1 )

RETURN NIL

// ============================================================
// HIX_SessionRotate — generate a new SID preserving session data.
// Must be called after a privilege change (login, sudo) to prevent
// session fixation attacks (A1.19). The old SID is deleted atomically
// and oCtx:hData["_sid"] is updated to the new one.
// ============================================================
FUNCTION HIX_SessionRotate( oCtx )

   LOCAL cOldSid, cNewSid, nNow, hEntry

   IF ! hb_HHasKey( oCtx:hData, "_sid" ) .OR. Empty( oCtx:hData[ "_sid" ] )

      RETURN NIL

   ENDIF

   cOldSid := oCtx:hData[ "_sid" ]
   cNewSid := _HixSessionNewId()
   nNow    := _HixNow()

   IF s_cStorage == "file"

      hEntry := { "exp" => _HixSessionExp( nNow ), "data" => oCtx:hData[ "session" ] }
      _HixSessionFileWrite( cNewSid, hEntry )
      _HixSessionFileDelete( cOldSid )

   ELSE

      hb_mutexLock( s_mtxStore )
      s_hStore[ cNewSid ] := { "exp" => _HixSessionExp( nNow ), "data" => oCtx:hData[ "session" ] }

      IF hb_HHasKey( s_hStore, cOldSid )

         hb_HDel( s_hStore, cOldSid )

      ENDIF

      hb_mutexUnlock( s_mtxStore )

   ENDIF

   oCtx:hData[ "_sid" ] := cNewSid
   HIX_SetCookie( oCtx:oReq, s_cName, _HixSidWithRoute( cNewSid ), s_nTtl )

RETURN NIL

// ============================================================
// Helpers internos — modo memory
// ============================================================

STATIC FUNCTION _HixSessionInitStore()

   LOCAL nLifetime

   IF ! s_lConfigApplied

      nLifetime := UConfig( "session", "lifetime", 60 )
      s_nTtl    := nLifetime * 60
      s_nGcDays := UConfig( "session", "gc_days", s_nGcDays )
      s_lConfigApplied := .T.

   ENDIF

   IF s_mtxStore == NIL

      s_mtxStore := hb_mutexCreate()

   ENDIF

   IF s_mtxSidCtr == NIL

      s_mtxSidCtr := hb_mutexCreate()

   ENDIF

   IF s_cStorage == "memory" .AND. s_hStore == NIL

      s_hStore := { => }

   ENDIF

   IF s_cStorage == "file" .AND. ! hb_DirExists( s_cPath )

      hb_DirCreate( s_cPath )

   ENDIF

RETURN NIL

// Strip Apache route suffix from SID cookie value (e.g. "abc.i1" -> "abc").
// MD5 IDs are hex-only so any dot marks a route suffix added by Apache.
STATIC FUNCTION _HixSidStrip( cSid )

   LOCAL nDot := RAt( ".", cSid )

   IF nDot > 0

      RETURN Left( cSid, nDot - 1 )

   ENDIF

RETURN cSid

// Append route suffix to SID for Apache stickysession cookie (e.g. "abc" -> "abc.i1").
STATIC FUNCTION _HixSidWithRoute( cSid )

   IF ! Empty( s_cRoute )

      RETURN cSid + "." + s_cRoute

   ENDIF

RETURN cSid

// Session ID generator: HMAC-SHA256(timestamp:counter:prng, secret).
// Even if the message components are observable, the SID is computationally
// unpredictable without the session key — closes weak-RNG enumeration (A1.11).
STATIC FUNCTION _HixSessionNewId()

   LOCAL nCount, cMsg, cKey

   IF s_mtxSidCtr == NIL ; s_mtxSidCtr := hb_mutexCreate() ; ENDIF

   hb_mutexLock( s_mtxSidCtr )
   s_nSidCounter++
   nCount := s_nSidCounter
   hb_mutexUnlock( s_mtxSidCtr )

   cKey := iif( ! Empty( s_cSeed ), s_cSeed, HIX_KeyGet( "session", "H!x@SESSION@2026" ) )
   cMsg := hb_NToS( Int( hb_TToSec( hb_DateTime() ) ) ) + ":" + ;
           hb_NToS( hb_MilliSeconds()                 ) + ":" + ;
           hb_NToS( nCount                            ) + ":" + ;
           hb_NToS( Int( hb_Random() * 1000000       ) )

RETURN hb_HMAC_SHA256( cMsg, cKey )

// Public wrapper — test hook only. Not part of the public API.
FUNCTION HIX_SessionNewId()
RETURN _HixSessionNewId()

// Test hooks — expose internal STATIC functions for unit tests.
FUNCTION HIX_SessionFileWriteForTest( cSid, hEntry )
RETURN _HixSessionFileWrite( cSid, hEntry )

FUNCTION HIX_SessionFileLoadForTest( cSid, nNow )
RETURN _HixSessionFileLoad( cSid, nNow )

FUNCTION HIX_SessionMemSetForTest( cSid, hEntry )

   IF s_hStore == NIL ; s_hStore := { => } ; ENDIF
   IF s_mtxStore == NIL ; s_mtxStore := hb_mutexCreate() ; ENDIF

   hb_mutexLock( s_mtxStore )
   s_hStore[ cSid ] := hEntry
   hb_mutexUnlock( s_mtxStore )

RETURN NIL

FUNCTION HIX_SessionFileGcForTest()
RETURN _HixSessionFileGc()

STATIC FUNCTION _HixNow()
RETURN Int( hb_TToSec( hb_DateTime() ) )

STATIC FUNCTION _HixSessionGc( nNow )

   LOCAL aKeys, cKey, i

   hb_mutexLock( s_mtxStore )
   aKeys := hb_HKeys( s_hStore )

   FOR i := 1 TO Len( aKeys )

      cKey := aKeys[ i ]

      IF hb_HHasKey( s_hStore, cKey ) .AND. s_hStore[ cKey ][ "exp" ] < nNow

         hb_HDel( s_hStore, cKey )

      ENDIF

   NEXT

   hb_mutexUnlock( s_mtxStore )

RETURN NIL

// ============================================================
// Helpers internos — modo file
// ============================================================

STATIC FUNCTION _HixSessionFilePath( cSid )
RETURN s_cPath + hb_ps() + s_cPrefix + cSid

STATIC FUNCTION _HixSessionFileLoad( cSid, nNow )

   LOCAL cFile, cData, hEntry, cMac, nSep

   cFile := _HixSessionFilePath( cSid )

   IF ! File( cFile )

      RETURN NIL

   ENDIF

   cData := hb_MemoRead( cFile )

   IF Empty( cData )

      RETURN NIL

   ENDIF

   // Format: base64( HMAC_HEX "|" payload ) where payload may be
   // Blowfish-encrypted JSON. HMAC is computed on the raw payload bytes
   // (Encrypt-then-MAC) so tampering detection runs before decryption (A1.18).
   cData := hb_base64Decode( cData )

   nSep := At( "|", cData )

   IF nSep == 0

      // Legacy format without MAC — reject to prevent deserialization attacks.
      lw( "Session file: no MAC — rejecting " + cSid )
      HIX_SafeErase( cFile )
      RETURN NIL

   ENDIF

   cMac  := Left( cData, nSep - 1 )
   cData := SubStr( cData, nSep + 1 )

   IF ! HIX_TokenConstantEq( cMac, hb_HMAC_SHA256( cData, s_cSeed ) )

      lw( "Session file: HMAC mismatch — rejecting " + cSid )
      HIX_SafeErase( cFile )
      RETURN NIL

   ENDIF

   IF s_lCrypt

      cData := hb_blowfishDecrypt( hb_blowfishKey( s_cSeed ), cData )

   ENDIF

   // JSON instead of hb_Deserialize — prevents object/codeblock injection (A1.18).
   hb_jsonDecode( cData, @hEntry )

   IF ValType( hEntry ) != "H"

      RETURN NIL

   ENDIF

   IF ! hb_HHasKey( hEntry, "exp" ) .OR. ! hb_HHasKey( hEntry, "data" )

      RETURN NIL

   ENDIF

   IF hEntry[ "exp" ] < nNow

      HIX_SafeErase( cFile )
      RETURN NIL

   ENDIF

RETURN hEntry

STATIC FUNCTION _HixSessionFileWrite( cSid, hEntry )

   LOCAL cData, cMac

   // JSON serialization prevents codeblock/object injection on read (A1.18).
   cData := hb_jsonEncode( hEntry )

   IF s_lCrypt

      cData := hb_blowfishEncrypt( hb_blowfishKey( s_cSeed ), cData )

   ENDIF

   // Prepend HMAC-SHA256 for integrity (Encrypt-then-MAC) (A1.18).
   cMac := hb_HMAC_SHA256( cData, s_cSeed )
   hb_MemoWrit( _HixSessionFilePath( cSid ), hb_base64Encode( cMac + "|" + cData ) )

RETURN NIL

STATIC FUNCTION _HixSessionFileDelete( cSid )

   LOCAL cFile

   cFile := _HixSessionFilePath( cSid )

   IF File( cFile )

      HIX_SafeErase( cFile )

   ENDIF

RETURN NIL

STATIC FUNCTION _HixSessionFileGc()

   LOCAL aFiles, aEntry, cFile, cData, hSess, nNow, oErr
   LOCAL nSep2, cPayload, hSessChk

   // The exp field is authoritative (A1.20): no date-based pre-filter.
   // We read every file and delete only when exp < now or unreadable.
   nNow   := _HixNow()
   aFiles := Directory( s_cPath + hb_ps() + s_cPrefix + "*" )

   FOR EACH aEntry IN aFiles

      cFile := s_cPath + hb_ps() + aEntry[ 1 ]
      cData := hb_MemoRead( cFile )

      IF Empty( cData )

         // Unreadable / empty — safe to delete.
         oErr := NIL
         TRY ; HIX_SafeErase( cFile ) ; CATCH oErr ; END

         LOOP

      ENDIF

      // Parse to get the real exp timestamp.
      hSess := NIL
      cData := hb_base64Decode( cData )
      nSep2 := At( "|", cData )

      IF nSep2 > 0

         cPayload := SubStr( cData, nSep2 + 1 )

         IF s_lCrypt

            cPayload := hb_blowfishDecrypt( hb_blowfishKey( s_cSeed ), cPayload )

         ENDIF

         hSessChk := NIL
         hb_jsonDecode( cPayload, @hSessChk )
         hSess := hSessChk

      ENDIF

      IF ValType( hSess ) == "H" .AND. hb_HHasKey( hSess, "exp" ) .AND. hSess[ "exp" ] >= nNow

         // Session is still valid — do not delete.
         LOOP

      ENDIF

      // Expired or unreadable: delete with TOCTOU guard (file may have
      // been updated by another thread between Directory() and here).
      oErr := NIL
      TRY
         HIX_SafeErase( cFile )
      CATCH oErr
      END

   NEXT

RETURN NIL
