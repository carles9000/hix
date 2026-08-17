/*-----------------------------------------------------------
  File ......: hix_test_session.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — in-memory session system
 -----------------------------------------------------------*/
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _CtxS( cSid )
   LOCAL oReq := TMockRequest():New( "/", "GET" )
   IF ! Empty( cSid )
      oReq:hHeaders["cookie"] := "HIXSID=" + cSid
   ENDIF
RETURN THixContext():New( oReq )

FUNCTION HIX_TestSession_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MwSessionSetup( "HIXSID", 3600, 500, "memory" )
   _TestSessCreateNew(     hCtx )
   _TestSessPersistData(   hCtx )
   _TestSessGetSet(        hCtx )
   _TestSessSaveCookie(    hCtx )
   _TestSessDestroy(       hCtx )
   _TestSessExpiry(        hCtx )
   _TestSessMultiple(      hCtx )
RETURN hCtx

STATIC PROCEDURE _TestSessCreateNew( hCtx )
   LOCAL oCtx, cSid, lResult
   oCtx    := _CtxS( "" )
   lResult := HIX_MwSession( oCtx )
   cSid    := hb_HGetDef( oCtx:hData, "_sid", "" )
   HixTU_Check( hCtx, lResult,                                  "Sess T01: MW retorna .T.",       ".T.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, ! Empty( cSid ),                          "Sess T01: SID asignado",          "non-empty", iif( Empty(cSid), "empty", "ok" ) )
   HixTU_Check( hCtx, hb_HHasKey( oCtx:hData, "session" ),     "Sess T01: session en hData",      ".T.", ".F." )
   HixTU_Check( hCtx, ValType( oCtx:hData["session"] ) == "H", "Sess T01: session es hash",       "H",   ValType( oCtx:hData["session"] ) )
RETURN

STATIC PROCEDURE _TestSessPersistData( hCtx )
   LOCAL oCtx1, oCtx2, cSid, cVal
   oCtx1 := _CtxS( "" )
   HIX_MwSession( oCtx1 )
   cSid := oCtx1:hData["_sid"]
   HIX_SessionSet( oCtx1, "user", "carles" )
   HIX_SessionSave( oCtx1 )
   oCtx2 := _CtxS( cSid )
   HIX_MwSession( oCtx2 )
   cVal := HIX_SessionGet( oCtx2, "user" )
   HixTU_Check( hCtx, oCtx2:hData["_sid"] == cSid, "Sess T02: mismo SID",    cSid,     oCtx2:hData["_sid"] )
   HixTU_Check( hCtx, cVal == "carles",             "Sess T02: dato persiste","carles", cVal )
RETURN

STATIC PROCEDURE _TestSessGetSet( hCtx )
   LOCAL oCtx, cStr, nNum, lBool, hHash
   oCtx := _CtxS( "" )
   HIX_MwSession( oCtx )
   HIX_SessionSet( oCtx, "str",  "hola" )
   HIX_SessionSet( oCtx, "num",  42     )
   HIX_SessionSet( oCtx, "bool", .T.    )
   HIX_SessionSet( oCtx, "sub",  { "k" => "v" } )
   cStr  := HIX_SessionGet( oCtx, "str"  )
   nNum  := HIX_SessionGet( oCtx, "num"  )
   lBool := HIX_SessionGet( oCtx, "bool" )
   hHash := HIX_SessionGet( oCtx, "sub"  )
   HixTU_Check( hCtx, cStr == "hola",                   "Sess T03: string ok",  "hola", cStr )
   HixTU_Check( hCtx, nNum == 42,                       "Sess T03: numeric ok", "42",   hb_NToS( nNum ) )
   HixTU_Check( hCtx, lBool == .T.,                     "Sess T03: logical ok", ".T.",  hb_CStr( lBool ) )
   HixTU_Check( hCtx, ValType( hHash ) == "H",          "Sess T03: hash ok",    "H",    ValType( hHash ) )
   HixTU_Check( hCtx, HIX_SessionGet( oCtx, "nokey" ) == "", "Sess T03: missing -> ''", "", HIX_SessionGet( oCtx, "nokey" ) )
RETURN

STATIC PROCEDURE _TestSessSaveCookie( hCtx )
   LOCAL oCtx, cSid, cCookieLine, lHasCookie, lHasSid
   oCtx := _CtxS( "" )
   HIX_MwSession( oCtx )
   cSid := oCtx:hData["_sid"]
   HIX_SessionSave( oCtx )
   lHasCookie  := hb_HHasKey( oCtx:oReq:hExtraHeaders, "Set-Cookie" )
   cCookieLine := hb_HGetDef( oCtx:oReq:hExtraHeaders, "Set-Cookie", "" )
   lHasSid     := ( cSid $ cCookieLine )
   HixTU_Check( hCtx, lHasCookie,              "Sess T04: Set-Cookie presente", ".T.", hb_CStr( lHasCookie ) )
   HixTU_Check( hCtx, lHasSid,                "Sess T04: SID en Set-Cookie",   cSid,  cCookieLine )
   HixTU_Check( hCtx, "HttpOnly" $ cCookieLine, "Sess T04: HttpOnly flag",      "HttpOnly", cCookieLine )
RETURN

STATIC PROCEDURE _TestSessDestroy( hCtx )
   LOCAL oCtx1, oCtx2, cSid, cNewSid, cCookieLine
   oCtx1 := _CtxS( "" )
   HIX_MwSession( oCtx1 )
   cSid := oCtx1:hData["_sid"]
   HIX_SessionSet( oCtx1, "x", "datos" )
   HIX_SessionSave( oCtx1 )
   HIX_SessionDestroy( oCtx1 )
   cCookieLine := hb_HGetDef( oCtx1:oReq:hExtraHeaders, "Set-Cookie", "" )
   HixTU_Check( hCtx, Empty( oCtx1:hData["_sid"] ),    "Sess T05: SID vacio tras destroy", "", oCtx1:hData["_sid"] )
   HixTU_Check( hCtx, "Max-Age=0" $ cCookieLine,       "Sess T05: cookie expirada",        "Max-Age=0", cCookieLine )
   oCtx2  := _CtxS( cSid )
   HIX_MwSession( oCtx2 )
   cNewSid := oCtx2:hData["_sid"]
   HixTU_Check( hCtx, cNewSid != cSid,                    "Sess T05: nuevo SID",         "distinto", cNewSid )
   HixTU_Check( hCtx, HIX_SessionGet( oCtx2, "x" ) == "", "Sess T05: datos no persisten","",  HIX_SessionGet( oCtx2, "x" ) )
RETURN

STATIC PROCEDURE _TestSessExpiry( hCtx )
   LOCAL oCtx1, oCtx2, cSid, cNewSid
   HIX_MwSessionSetup( "HIXSID", 1, 500, "memory" )
   oCtx1 := _CtxS( "" )
   HIX_MwSession( oCtx1 )
   cSid := oCtx1:hData["_sid"]
   HIX_SessionSet( oCtx1, "key", "valor" )
   HIX_SessionSave( oCtx1 )
   hb_idleSleep( 2 )
   oCtx2 := _CtxS( cSid )
   HIX_MwSession( oCtx2 )
   cNewSid := oCtx2:hData["_sid"]
   HixTU_Check( hCtx, cNewSid != cSid,                      "Sess T06: SID distinto tras expiry", "distinto", cNewSid )
   HixTU_Check( hCtx, HIX_SessionGet( oCtx2, "key" ) == "", "Sess T06: datos expirados",          "", HIX_SessionGet( oCtx2, "key" ) )
   HIX_MwSessionSetup( "HIXSID", 3600, 500, "memory" )
RETURN

STATIC PROCEDURE _TestSessMultiple( hCtx )
   LOCAL oCtxA, oCtxB, oCtxA2, cSidA, cSidB
   oCtxA := _CtxS( "" )
   HIX_MwSession( oCtxA )
   cSidA := oCtxA:hData["_sid"]
   HIX_SessionSet( oCtxA, "user", "alice" )
   HIX_SessionSave( oCtxA )
   oCtxB := _CtxS( "" )
   HIX_MwSession( oCtxB )
   cSidB := oCtxB:hData["_sid"]
   HIX_SessionSet( oCtxB, "user", "bob" )
   HIX_SessionSave( oCtxB )
   HixTU_Check( hCtx, cSidA != cSidB,                            "Sess T07: SIDs distintos",  "distintos", iif( cSidA==cSidB, "iguales", "distintos" ) )
   HixTU_Check( hCtx, HIX_SessionGet( oCtxA, "user" ) == "alice","Sess T07: sesion A = alice","alice", HIX_SessionGet( oCtxA, "user" ) )
   HixTU_Check( hCtx, HIX_SessionGet( oCtxB, "user" ) == "bob",  "Sess T07: sesion B = bob",  "bob",   HIX_SessionGet( oCtxB, "user" ) )
   oCtxA2 := _CtxS( cSidA )
   HIX_MwSession( oCtxA2 )
   HixTU_Check( hCtx, HIX_SessionGet( oCtxA2, "user" ) == "alice", "Sess T07: A persiste en store", "alice", HIX_SessionGet( oCtxA2, "user" ) )
RETURN
