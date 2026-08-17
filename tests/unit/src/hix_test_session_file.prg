/*-----------------------------------------------------------
  File ......: hix_test_session_file.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — sessions in file mode
 -----------------------------------------------------------*/
#include "hbclass.ch"

// TMockIO2 / TMockRequest2 — unique names, no conflict with shared utils

CLASS TMockIO2
   DATA cWritten INIT ""
   METHOD Write( cData ) INLINE ( ::cWritten += iif( ValType(cData)=="C", cData, "" ), .T. )
ENDCLASS

CLASS TMockRequest2
   DATA cPath           INIT "/"
   DATA cMethod         INIT "GET"
   DATA cIP             INIT "127.0.0.1"
   DATA hHeaders        INIT { => }
   DATA hExtraHeaders   INIT { => }
   DATA hData           INIT { => }
   DATA hCookies        INIT NIL
   DATA lKeepAlive      INIT .F.
   DATA lResponded      INIT .F.
   DATA lStreaming       INIT .F.
   DATA cEchoBuffer     INIT ""
   DATA cResponseMime   INIT "html"
   DATA nResponseStatus INIT 200
   DATA nStatus         INIT 0
   DATA cBody           INIT ""
   DATA oIO

   METHOD New( cPath, cMethod, cIP )
   METHOD Respond( xData, cMime, nStatus, hExtra )
   METHOD Header( cKey, xDef )
   METHOD Cookie( cName, xDef )
ENDCLASS

METHOD New( cPath, cMethod, cIP ) CLASS TMockRequest2
   hb_default( @cPath,   "/" )
   hb_default( @cMethod, "GET" )
   hb_default( @cIP,     "127.0.0.1" )
   ::cPath         := cPath
   ::cMethod       := cMethod
   ::cIP           := cIP
   ::oIO           := TMockIO2():New()
   ::hExtraHeaders := { => }
   ::hData         := { => }
   ::hCookies      := NIL
RETURN Self

METHOD Header( cKey, xDef ) CLASS TMockRequest2
   hb_default( @xDef, "" )
RETURN hb_HGetDef( ::hHeaders, Lower( cKey ), xDef )

METHOD Cookie( cName, xDef ) CLASS TMockRequest2
   LOCAL cRaw, aPairs, cPair, nEq
   hb_default( @xDef, "" )
   IF ::hCookies == NIL
      ::hCookies := { => }
      cRaw := ::Header( "cookie", "" )
      IF ! Empty( cRaw )
         aPairs := hb_ATokens( cRaw, ";" )
         FOR EACH cPair IN aPairs
            cPair := AllTrim( cPair )
            nEq   := At( "=", cPair )
            IF nEq > 0
               ::hCookies[ AllTrim( Left( cPair, nEq - 1 ) ) ] := AllTrim( SubStr( cPair, nEq + 1 ) )
            ENDIF
         NEXT
      ENDIF
   ENDIF
RETURN hb_HGetDef( ::hCookies, cName, xDef )

METHOD Respond( xData, cMime, nStatus, hExtra ) CLASS TMockRequest2
   LOCAL hMerged
   hb_default( @cMime,   "json" )
   hb_default( @nStatus, 200 )
   hb_default( @hExtra,  { => } )
   IF ! Empty( ::hExtraHeaders )
      hMerged := hb_HClone( ::hExtraHeaders )
      hb_HMerge( hMerged, hExtra )
      hExtra := hMerged
   ENDIF
   ::lResponded := .T.
   ::nStatus    := nStatus
   ::cBody      := iif( ValType( xData ) == "C", xData, "" )
RETURN Self

STATIC FUNCTION _Ctx2( cSid )
   LOCAL oReq := TMockRequest2():New( "/", "GET" )
   IF ! Empty( cSid )
      oReq:hHeaders["cookie"] := "HIXSID=" + cSid
   ENDIF
RETURN THixContext():New( oReq )

STATIC PROCEDURE _CleanDir( cDir )
   LOCAL aFiles, aEntry
   IF ! hb_DirExists( cDir ) ; RETURN ; ENDIF
   aFiles := Directory( cDir + hb_ps() + "*.*" )
   FOR EACH aEntry IN aFiles
      FErase( cDir + hb_ps() + aEntry[1] )
   NEXT
   hb_DirDelete( cDir )
RETURN

FUNCTION HIX_TestSessionFile_Run()
   LOCAL hCtx    := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTestDir
   cTestDir := hb_DirTemp() + "hix_tm_sessfile"
   IF ! hb_DirExists( cTestDir ) ; hb_DirCreate( cTestDir ) ; ENDIF
   HIX_MwSessionSetup( "HIXSID", 3600, 500, "file", cTestDir, "sess_", .F., "", 3 )
   _TestFileCreateNew(   hCtx, cTestDir )
   _TestFilePersistData( hCtx, cTestDir )
   _TestFileGetSet(      hCtx )
   _TestFileSaveCookie(  hCtx, cTestDir )
   _TestFileDestroy(     hCtx, cTestDir )
   _TestFileExpiry(      hCtx, cTestDir )
   _TestFileMultiple(    hCtx, cTestDir )
   _TestFileCrypt(       hCtx, cTestDir )
   _CleanDir( cTestDir )
   HIX_MwSessionSetup( "HIXSID", 3600, 500, "memory" )
RETURN hCtx

STATIC PROCEDURE _TestFileCreateNew( hCtx, cDir )
   LOCAL oCtx, cSid, cFile, lResult
   oCtx    := _Ctx2( "" )
   lResult := HIX_MwSession( oCtx )
   cSid    := hb_HGetDef( oCtx:hData, "_sid", "" )
   HIX_SessionSet( oCtx, "init", "1" )
   HIX_SessionSave( oCtx )
   cFile := cDir + hb_ps() + "sess_" + cSid
   HixTU_Check( hCtx, lResult,                              "SessFile T01: MW retorna .T.",       ".T.",       hb_CStr( lResult ) )
   HixTU_Check( hCtx, ! Empty( cSid ),                      "SessFile T01: SID asignado",         "non-empty", iif( Empty(cSid),"empty","ok" ) )
   HixTU_Check( hCtx, File( cFile ),                        "SessFile T01: fichero creado",       ".T.",       hb_CStr( File(cFile) ) )
   HixTU_Check( hCtx, hb_HHasKey( oCtx:hData, "session" ), "SessFile T01: session en hData",     ".T.",       ".F." )
RETURN

STATIC PROCEDURE _TestFilePersistData( hCtx, cDir )
   LOCAL oCtx1, oCtx2, cSid, cVal
   HB_SYMBOL_UNUSED( cDir )
   oCtx1 := _Ctx2( "" )
   HIX_MwSession( oCtx1 )
   cSid := oCtx1:hData["_sid"]
   HIX_SessionSet( oCtx1, "user", "carles" )
   HIX_SessionSave( oCtx1 )
   oCtx2 := _Ctx2( cSid )
   HIX_MwSession( oCtx2 )
   cVal := HIX_SessionGet( oCtx2, "user" )
   HixTU_Check( hCtx, oCtx2:hData["_sid"] == cSid, "SessFile T02: mismo SID",    cSid,     oCtx2:hData["_sid"] )
   HixTU_Check( hCtx, cVal == "carles",             "SessFile T02: dato persiste","carles", cVal )
RETURN

STATIC PROCEDURE _TestFileGetSet( hCtx )
   LOCAL oCtx, cStr, nNum, lBool
   oCtx := _Ctx2( "" )
   HIX_MwSession( oCtx )
   HIX_SessionSet( oCtx, "str",  "hola" )
   HIX_SessionSet( oCtx, "num",  42     )
   HIX_SessionSet( oCtx, "bool", .T.    )
   cStr  := HIX_SessionGet( oCtx, "str"  )
   nNum  := HIX_SessionGet( oCtx, "num"  )
   lBool := HIX_SessionGet( oCtx, "bool" )
   HixTU_Check( hCtx, cStr == "hola",  "SessFile T03: string ok",  "hola", cStr )
   HixTU_Check( hCtx, nNum == 42,      "SessFile T03: numeric ok", "42",   hb_NToS( nNum ) )
   HixTU_Check( hCtx, lBool == .T.,    "SessFile T03: logical ok", ".T.",  hb_CStr( lBool ) )
   HixTU_Check( hCtx, HIX_SessionGet( oCtx, "nokey" ) == "", "SessFile T03: missing -> ''", "", HIX_SessionGet( oCtx, "nokey" ) )
RETURN

STATIC PROCEDURE _TestFileSaveCookie( hCtx, cDir )
   LOCAL oCtx, cSid, cCookieLine, lHasCookie, lHasSid
   HB_SYMBOL_UNUSED( cDir )
   oCtx := _Ctx2( "" )
   HIX_MwSession( oCtx )
   cSid := oCtx:hData["_sid"]
   HIX_SessionSave( oCtx )
   lHasCookie  := hb_HHasKey( oCtx:oReq:hExtraHeaders, "Set-Cookie" )
   cCookieLine := hb_HGetDef( oCtx:oReq:hExtraHeaders, "Set-Cookie", "" )
   lHasSid     := ( cSid $ cCookieLine )
   HixTU_Check( hCtx, lHasCookie,               "SessFile T04: Set-Cookie presente", ".T.",      hb_CStr( lHasCookie ) )
   HixTU_Check( hCtx, lHasSid,                  "SessFile T04: SID en Set-Cookie",   cSid,       cCookieLine )
   HixTU_Check( hCtx, "HttpOnly" $ cCookieLine, "SessFile T04: HttpOnly flag",        "HttpOnly", cCookieLine )
RETURN

STATIC PROCEDURE _TestFileDestroy( hCtx, cDir )
   LOCAL oCtx1, oCtx2, cSid, cNewSid, cCookieLine, cFile
   oCtx1 := _Ctx2( "" )
   HIX_MwSession( oCtx1 )
   cSid  := oCtx1:hData["_sid"]
   cFile := cDir + hb_ps() + "sess_" + cSid
   HIX_SessionSet( oCtx1, "x", "datos" )
   HIX_SessionSave( oCtx1 )
   HixTU_Check( hCtx, File( cFile ), "SessFile T05: fichero existe antes destroy", ".T.", hb_CStr( File(cFile) ) )
   HIX_SessionDestroy( oCtx1 )
   cCookieLine := hb_HGetDef( oCtx1:oReq:hExtraHeaders, "Set-Cookie", "" )
   HixTU_Check( hCtx, ! File( cFile ),               "SessFile T05: fichero borrado",    ".F.",      hb_CStr( File(cFile) ) )
   HixTU_Check( hCtx, Empty( oCtx1:hData["_sid"] ),  "SessFile T05: SID vacio",          "",         oCtx1:hData["_sid"] )
   HixTU_Check( hCtx, "Max-Age=0" $ cCookieLine,     "SessFile T05: cookie expirada",    "Max-Age=0",cCookieLine )
   oCtx2   := _Ctx2( cSid )
   HIX_MwSession( oCtx2 )
   cNewSid := oCtx2:hData["_sid"]
   HixTU_Check( hCtx, cNewSid != cSid,                    "SessFile T05: nuevo SID generado",  "distinto", cNewSid )
   HixTU_Check( hCtx, HIX_SessionGet( oCtx2, "x" ) == "", "SessFile T05: datos no persisten",  "",         HIX_SessionGet( oCtx2, "x" ) )
RETURN

STATIC PROCEDURE _TestFileExpiry( hCtx, cDir )
   LOCAL oCtx1, oCtx2, cSid, cNewSid
   HIX_MwSessionSetup( "HIXSID", 1, 500, "file", cDir, "sess_", .F., "", 3 )
   oCtx1 := _Ctx2( "" )
   HIX_MwSession( oCtx1 )
   cSid := oCtx1:hData["_sid"]
   HIX_SessionSet( oCtx1, "key", "valor" )
   HIX_SessionSave( oCtx1 )
   hb_idleSleep( 2 )
   oCtx2 := _Ctx2( cSid )
   HIX_MwSession( oCtx2 )
   cNewSid := oCtx2:hData["_sid"]
   HixTU_Check( hCtx, cNewSid != cSid,                     "SessFile T06: SID distinto tras expiry", "distinto", cNewSid )
   HixTU_Check( hCtx, HIX_SessionGet( oCtx2, "key" ) == "", "SessFile T06: datos expirados",          "",         HIX_SessionGet( oCtx2, "key" ) )
   HIX_MwSessionSetup( "HIXSID", 3600, 500, "file", cDir, "sess_", .F., "", 3 )
RETURN

STATIC PROCEDURE _TestFileMultiple( hCtx, cDir )
   LOCAL oCtxA, oCtxB, oCtxA2, cSidA, cSidB
   HB_SYMBOL_UNUSED( cDir )
   oCtxA := _Ctx2( "" )
   HIX_MwSession( oCtxA )
   cSidA := oCtxA:hData["_sid"]
   HIX_SessionSet( oCtxA, "user", "alice" )
   HIX_SessionSave( oCtxA )
   oCtxB := _Ctx2( "" )
   HIX_MwSession( oCtxB )
   cSidB := oCtxB:hData["_sid"]
   HIX_SessionSet( oCtxB, "user", "bob" )
   HIX_SessionSave( oCtxB )
   HixTU_Check( hCtx, cSidA != cSidB,                             "SessFile T07: SIDs distintos",     "distintos", iif(cSidA==cSidB,"iguales","distintos") )
   HixTU_Check( hCtx, HIX_SessionGet( oCtxA, "user" ) == "alice", "SessFile T07: sesion A = alice",   "alice",     HIX_SessionGet( oCtxA, "user" ) )
   HixTU_Check( hCtx, HIX_SessionGet( oCtxB, "user" ) == "bob",   "SessFile T07: sesion B = bob",     "bob",       HIX_SessionGet( oCtxB, "user" ) )
   oCtxA2 := _Ctx2( cSidA )
   HIX_MwSession( oCtxA2 )
   HixTU_Check( hCtx, HIX_SessionGet( oCtxA2, "user" ) == "alice","SessFile T07: A persiste en disco","alice",     HIX_SessionGet( oCtxA2, "user" ) )
RETURN

STATIC PROCEDURE _TestFileCrypt( hCtx, cDir )
   LOCAL oCtx1, oCtx2, cSid, cVal, cFile, cRaw
   HIX_MwSessionSetup( "HIXSID", 3600, 500, "file", cDir, "sess_", .T., "semilla_test", 3 )
   oCtx1 := _Ctx2( "" )
   HIX_MwSession( oCtx1 )
   cSid := oCtx1:hData["_sid"]
   HIX_SessionSet( oCtx1, "secret", "datos_privados" )
   HIX_SessionSave( oCtx1 )
   cFile := cDir + hb_ps() + "sess_" + cSid
   cRaw  := hb_MemoRead( cFile )
   HixTU_Check( hCtx, File( cFile ),                  "SessFile T08: fichero existe cifrado",     ".T.",    hb_CStr( File(cFile) ) )
   HixTU_Check( hCtx, ! ( "datos_privados" $ cRaw ),  "SessFile T08: dato no visible en fichero", ".F.",    "visible" )
   oCtx2 := _Ctx2( cSid )
   HIX_MwSession( oCtx2 )
   cVal  := HIX_SessionGet( oCtx2, "secret" )
   HixTU_Check( hCtx, cVal == "datos_privados", "SessFile T08: dato descifrado correctamente", "datos_privados", cVal )
   HIX_MwSessionSetup( "HIXSID", 3600, 500, "file", cDir, "sess_", .F., "", 3 )
RETURN
