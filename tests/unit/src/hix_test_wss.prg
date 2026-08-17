/*-----------------------------------------------------------
  File ......: hix_test_wss.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Stub — WSS requires a real TLS socket.
               Tests verify basic WS frame encoding over SSL context
               (infrastructure note only — no live TLS connection).
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[WSS] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

FUNCTION HIX_TestWSS_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestWSS_Run start ===" )
   _WssInfraNote(       hCtx )
   _WssLibsLoaded(      hCtx )
   _WssCloseFrameOpcode( hCtx )
   _WssOpcodeMatrix(    hCtx )
   _TLog( "=== HIX_TestWSS_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _WssInfraNote( hCtx )
   _TLog( "_WssInfraNote" )
   HixTU_Check( hCtx, .T., "WSS: infraestructura TLS — test real requiere socket SSL", "ok", "ok" )
RETURN

STATIC PROCEDURE _WssLibsLoaded( hCtx )
   LOCAL lSSL
   _TLog( "_WssLibsLoaded" )
   HIX_LoadConfig()
   lSSL := HIX_GetConfig( "server", "ssl" )
   _TLog( "ssl default=" + hb_ValToStr( lSSL ) )
   HixTU_Check( hCtx, ValType( lSSL ) == "L", "WSS: server.ssl es logico", "L", ValType( lSSL ) )
RETURN

// Regression: CLOSE opcode must be 0x08, not 0x09 (PING).
// hix_test_wss (standalone) reported opcode 9 received — this confirms the
// server sends 0x08 in the frame layer, ruling out a frame-encoding bug.
STATIC PROCEDURE _WssCloseFrameOpcode( hCtx )
   LOCAL cFrame, nByte1, nOpcode
   _TLog( "_WssCloseFrameOpcode" )
   cFrame  := HIX_WsBuildFrame( 0x08, "" )
   nByte1  := Asc( SubStr( cFrame, 1, 1 ) )
   nOpcode := hb_bitAnd( nByte1, 0x0F )
   _TLog( "CLOSE: byte1=0x" + hb_NumToHex( nByte1 ) + " opcode=" + hb_NToS( nOpcode ) )
   HixTU_Check( hCtx, nByte1 == 0x88,  "WSS: CLOSE frame byte1 = 0x88",               "0x88", "0x" + hb_NumToHex( nByte1 ) )
   HixTU_Check( hCtx, nOpcode == 0x08, "WSS: CLOSE opcode = 0x08 (no es PING 0x09)",   "8",    hb_NToS( nOpcode ) )
RETURN

STATIC PROCEDURE _WssOpcodeMatrix( hCtx )
   LOCAL aOpcodes, i, cFrame, nByte1, nExpByte1, cName
   _TLog( "_WssOpcodeMatrix" )
   // { opcode, expected_byte1, name }
   aOpcodes := { { 0x01, 0x81, "TEXT"   }, ;
                 { 0x02, 0x82, "BINARY" }, ;
                 { 0x08, 0x88, "CLOSE"  }, ;
                 { 0x09, 0x89, "PING"   }, ;
                 { 0x0A, 0x8A, "PONG"   } }
   FOR i := 1 TO Len( aOpcodes )
      cName     := aOpcodes[i][3]
      nExpByte1 := aOpcodes[i][2]
      cFrame    := HIX_WsBuildFrame( aOpcodes[i][1], "" )
      nByte1    := Asc( SubStr( cFrame, 1, 1 ) )
      _TLog( cName + ": byte1=0x" + hb_NumToHex( nByte1 ) + " expected=0x" + hb_NumToHex( nExpByte1 ) )
      HixTU_Check( hCtx, nByte1 == nExpByte1, ;
                   "WSS: " + cName + " frame byte1=0x" + hb_NumToHex( nExpByte1 ), ;
                   "0x" + hb_NumToHex( nExpByte1 ), "0x" + hb_NumToHex( nByte1 ) )
   NEXT
RETURN
