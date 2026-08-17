/*-----------------------------------------------------------
  File ......: hix_test_flash.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — TFlash / UFlash() flash messages
 -----------------------------------------------------------*/
#include "hbclass.ch"
#include "hix_logger.ch"

STATIC FUNCTION _Str( xVal )
RETURN iif( xVal == NIL, "NIL", hb_CStr( xVal ) )

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _NewReq( hCookies )
   LOCAL oReq, oCtx
   hb_default( @hCookies, {=>} )
   oReq          := TMockRequest():New()
   oReq:hCookies := hCookies
   oCtx          := THixContext():New( oReq )
   oReq:hData[ "_ctx" ] := oCtx
   HIX_SetRequest( oReq )
RETURN { oReq, oCtx }

STATIC FUNCTION _Sid( aRC )
RETURN hb_HGetDef( aRC[2]:hData, "_sid", "" )

STATIC PROCEDURE _CleanDir( cDir )
   LOCAL aFiles, aEntry
   IF ! hb_DirExists( cDir )
      RETURN
   ENDIF
   aFiles := Directory( cDir + hb_ps() + "*.*" )
   FOR EACH aEntry IN aFiles
      FErase( cDir + hb_ps() + aEntry[1] )
   NEXT
   hb_DirDelete( cDir )
RETURN

FUNCTION HIX_TestFlash_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   HIX_MwSessionSetup( "HIXSID", 3600, 100, "memory" )
   _FlashGetId(          hCtx )
   _FlashSetGet(         hCtx )
   _FlashHasDelete(      hCtx )
   _FlashClear(          hCtx )
   _FlashSaveNextReq(    hCtx )
   _FlashMultiForm(      hCtx )
   _FlashChaining(       hCtx )
   _FlashDestroy(        hCtx )
   _FlashFileStorage(    hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _FlashGetId( hCtx )
   LOCAL oFlash, cId
   _NewReq()
   oFlash := UFlash()
   cId    := oFlash:GetId()
   HixTU_Check( hCtx, Len( cId ) == 32,           "Flash: auto-ID 32 chars",       "32",       hb_NToS( Len( cId ) ) )
   oFlash := UFlash( "myForm123" )
   HixTU_Check( hCtx, oFlash:GetId() == "myForm123","Flash: manual formId",         "myForm123",oFlash:GetId() )
   oFlash := UFlash( "" )
   cId    := oFlash:GetId()
   HixTU_Check( hCtx, Len( cId ) == 32,           "Flash: empty -> auto-ID 32",    "32",       hb_NToS( Len( cId ) ) )
RETURN

STATIC PROCEDURE _FlashSetGet( hCtx )
   LOCAL oFlash, xVal
   _NewReq()
   oFlash := UFlash( "f1" )
   HixTU_Check( hCtx, ! oFlash:Has( "error" ),             "Flash: Has antes de Set .F.", ".F.", _Str( oFlash:Has( "error" ) ) )
   oFlash:Set( "error", "Wrong password" )
   HixTU_Check( hCtx, oFlash:Has( "error" ),               "Flash: Has tras Set .T.",    ".T.", _Str( oFlash:Has( "error" ) ) )
   xVal := oFlash:Get( "error" )
   HixTU_Check( hCtx, xVal == "Wrong password",            "Flash: Get valor correcto",  "Wrong password", _Str( xVal ) )
   xVal := oFlash:Get( "error" )
   HixTU_Check( hCtx, xVal == "",                          "Flash: Get 2a vez -> ''",   "''", _Str( xVal ) )
   HixTU_Check( hCtx, ! oFlash:Has( "error" ),             "Flash: Has tras Get .F.",   ".F.", _Str( oFlash:Has( "error" ) ) )
   xVal := oFlash:Get( "nonexistent" )
   HixTU_Check( hCtx, xVal == "",                          "Flash: Get missing -> ''",  "''", _Str( xVal ) )
RETURN

STATIC PROCEDURE _FlashHasDelete( hCtx )
   LOCAL oFlash
   _NewReq()
   oFlash := UFlash( "f2" )
   oFlash:Delete( "ghost" )
   HixTU_Check( hCtx, .T., "Flash: Delete missing no crash", "ok", "ok" )
   oFlash:Set( "key", "val" )
   oFlash:Delete( "key" )
   HixTU_Check( hCtx, ! oFlash:Has( "key" ), "Flash: Delete quita key", ".F.", _Str( oFlash:Has( "key" ) ) )
   oFlash:Set( "a", "1" )
   oFlash:Set( "b", "2" )
   oFlash:Delete( "a" )
   HixTU_Check( hCtx, ! oFlash:Has( "a" ) .AND. oFlash:Has( "b" ), "Flash: Delete uno hermano sobrevive", ".T.", iif( ! oFlash:Has( "a" ) .AND. oFlash:Has( "b" ), ".T.", ".F." ) )
RETURN

STATIC PROCEDURE _FlashClear( hCtx )
   LOCAL oFlash
   _NewReq()
   oFlash := UFlash( "f3" )
   oFlash:Set( "a", "1" )
   oFlash:Set( "b", "2" )
   oFlash:Set( "c", "3" )
   oFlash:Clear()
   HixTU_Check( hCtx, ! oFlash:Has( "a" ), "Flash: Clear key a gone", ".F.", _Str( oFlash:Has( "a" ) ) )
   HixTU_Check( hCtx, ! oFlash:Has( "b" ), "Flash: Clear key b gone", ".F.", _Str( oFlash:Has( "b" ) ) )
   HixTU_Check( hCtx, ! oFlash:Has( "c" ), "Flash: Clear key c gone", ".F.", _Str( oFlash:Has( "c" ) ) )
RETURN

STATIC PROCEDURE _FlashSaveNextReq( hCtx )
   LOCAL aR, cSid, oFlash, xVal, xInput
   aR     := _NewReq()
   oFlash := UFlash( "login" )
   oFlash:Set( "error", "Invalid credentials" )
   oFlash:Set( "input", "admin" )
   oFlash:Save()
   cSid := _Sid( aR )
   HixTU_Check( hCtx, ! Empty( cSid ), "Flash: SID generado tras Save", "non-empty", cSid )
   _NewReq( { "HIXSID" => cSid } )
   oFlash := UFlash( "login" )
   xVal   := oFlash:Get( "error" )
   xInput := oFlash:Get( "input" )
   HixTU_Check( hCtx, xVal   == "Invalid credentials", "Flash: R2 Get error correcto", "Invalid credentials", _Str( xVal ) )
   HixTU_Check( hCtx, xInput == "admin",               "Flash: R2 Get input correcto", "admin", _Str( xInput ) )
   oFlash:Save()
   _NewReq( { "HIXSID" => cSid } )
   oFlash := UFlash( "login" )
   xVal   := oFlash:Get( "error" )
   HixTU_Check( hCtx, xVal == "", "Flash: R3 consumido -> ''", "''", _Str( xVal ) )
   aR     := _NewReq()
   oFlash := UFlash( "clr" )
   oFlash:Set( "msg", "hello" )
   oFlash:Save()
   cSid := _Sid( aR )
   _NewReq( { "HIXSID" => cSid } )
   oFlash := UFlash( "clr" )
   oFlash:Clear()
   oFlash:Save()
   _NewReq( { "HIXSID" => cSid } )
   oFlash := UFlash( "clr" )
   HixTU_Check( hCtx, ! oFlash:Has( "msg" ), "Flash: Clear+Save key gone R3", ".F.", _Str( oFlash:Has( "msg" ) ) )
RETURN

STATIC PROCEDURE _FlashMultiForm( hCtx )
   LOCAL aR, cSid, oF1, oF2, xVal
   aR := _NewReq()
   UFlash( "seed" ):Save()
   cSid := _Sid( aR )
   _NewReq( { "HIXSID" => cSid } )
   oF1 := UFlash( "form1" )
   oF2 := UFlash( "form2" )
   oF1:Set( "key1", "val1" )
   oF2:Set( "key2", "val2" )
   oF1:Save()
   oF2:Save()
   _NewReq( { "HIXSID" => cSid } )
   oF1 := UFlash( "form1" )
   oF2 := UFlash( "form2" )
   xVal := oF1:Get( "key1" )
   HixTU_Check( hCtx, xVal == "val1", "Flash: form1 key1 aislado",       "val1", _Str( xVal ) )
   xVal := oF2:Get( "key2" )
   HixTU_Check( hCtx, xVal == "val2", "Flash: form2 key2 aislado",       "val2", _Str( xVal ) )
   xVal := oF1:Get( "key2" )
   HixTU_Check( hCtx, xVal == "",     "Flash: form1 no ve form2 key",    "''",   _Str( xVal ) )
   xVal := oF2:Get( "key1" )
   HixTU_Check( hCtx, xVal == "",     "Flash: form2 no ve form1 key",    "''",   _Str( xVal ) )
RETURN

STATIC PROCEDURE _FlashChaining( hCtx )
   LOCAL oFlash, oSelf
   _NewReq()
   oFlash := UFlash( "ch" )
   oSelf  := oFlash:Set( "a", "1" )
   HixTU_Check( hCtx, oSelf == oFlash, "Flash: Set returns Self",    "Self", iif( oSelf == oFlash, "Self", "other" ) )
   oSelf  := oFlash:Delete( "a" )
   HixTU_Check( hCtx, oSelf == oFlash, "Flash: Delete returns Self", "Self", iif( oSelf == oFlash, "Self", "other" ) )
   oSelf  := oFlash:Clear()
   HixTU_Check( hCtx, oSelf == oFlash, "Flash: Clear returns Self",  "Self", iif( oSelf == oFlash, "Self", "other" ) )
   oSelf  := oFlash:Save()
   HixTU_Check( hCtx, oSelf == oFlash, "Flash: Save returns Self",   "Self", iif( oSelf == oFlash, "Self", "other" ) )
RETURN

STATIC PROCEDURE _FlashDestroy( hCtx )
   LOCAL aR, cSid, oFlash, xVal
   aR     := _NewReq()
   oFlash := UFlash( "dstr" )
   oFlash:Set( "msg", "auto-saved" )
   oFlash:Destroy()
   cSid := _Sid( aR )
   _NewReq( { "HIXSID" => cSid } )
   oFlash := UFlash( "dstr" )
   xVal   := oFlash:Get( "msg" )
   HixTU_Check( hCtx, xVal == "auto-saved", "Flash: Destroy auto-flush survives", "auto-saved", _Str( xVal ) )
   oFlash:Save()
   _NewReq()
   oFlash := UFlash( "clean" )
   oFlash:Destroy()
   HixTU_Check( hCtx, .T., "Flash: Destroy clean no crash", "ok", "ok" )
RETURN

STATIC PROCEDURE _FlashFileStorage( hCtx )
   LOCAL cDir, aR, cSid, oFlash, xVal
   cDir := hb_DirTemp() + "hix_tm_flash_sess"
   IF ! hb_DirExists( cDir ) ; hb_DirCreate( cDir ) ; ENDIF
   HIX_MwSessionSetup( "HIXSID", 3600, 500, "file", cDir, "sess_", .F., "", 3 )
   aR     := _NewReq()
   oFlash := UFlash( "ffile" )
   oFlash:Set( "msg", "persisted" )
   oFlash:Save()
   cSid := _Sid( aR )
   HixTU_Check( hCtx, ! Empty( cSid ), "Flash: File SID generado", "non-empty", cSid )
   HixTU_Check( hCtx, File( cDir + hb_ps() + "sess_" + cSid ), "Flash: File session file existe", ".T.", iif( File( cDir + hb_ps() + "sess_" + cSid ), ".T.", ".F." ) )
   _NewReq( { "HIXSID" => cSid } )
   oFlash := UFlash( "ffile" )
   xVal   := oFlash:Get( "msg" )
   HixTU_Check( hCtx, xVal == "persisted", "Flash: File next request lee valor", "persisted", _Str( xVal ) )
   oFlash:Save()
   _NewReq( { "HIXSID" => cSid } )
   oFlash := UFlash( "ffile" )
   xVal   := oFlash:Get( "msg" )
   HixTU_Check( hCtx, xVal == "", "Flash: File consumido -> ''", "''", _Str( xVal ) )
   _CleanDir( cDir )
   HIX_MwSessionSetup( "HIXSID", 3600, 100, "memory" )
RETURN
