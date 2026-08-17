/*-----------------------------------------------------------
  File ......: hix_test_sse.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Integrated test — SSE bus
               (HIX_SseSetup/Count/Broadcast + _HixSseRegister)
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[SSE] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

FUNCTION HIX_TestSSE_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestSSE_Run start ===" )
   _SseSetup(        hCtx )
   _SseRegister(     hCtx )
   _SseBroadcast(    hCtx )
   _SseMultiClient(  hCtx )
   _SseWrongChannel( hCtx )
   _SseCountMulti(   hCtx )
   _TLog( "=== HIX_TestSSE_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _SseSetup( hCtx )
   LOCAL oError
   _TLog( "_SseSetup" )
   TRY
      HIX_SseSetup()
      HixTU_Check( hCtx, .T., "SSE: Setup no crash", "ok", "ok" )
   CATCH oError
      _TLog( "Setup error: " + oError:description )
      HixTU_Check( hCtx, .F., "SSE: Setup no crash", "ok", oError:description )
   END
   _TLog( "Count nuevo canal = " + hb_NToS( HIX_SseCount( "test_sse_new_" + hb_NToS( Seconds() ) ) ) )
   HixTU_Check( hCtx, HIX_SseCount( "test_sse_new" ) == 0, "SSE: Count canal nuevo = 0", "0", hb_NToS( HIX_SseCount( "test_sse_new" ) ) )
RETURN

STATIC PROCEDURE _SseRegister( hCtx )
   LOCAL oIO, oConn, nCount
   _TLog( "_SseRegister" )
   oIO   := TMockIO():New( "", "" )
   oConn := _HixSseRegister( oIO, "test_sse_reg", 0 )
   _TLog( "Conn type=" + ValType( oConn ) )
   HixTU_Check( hCtx, ValType( oConn ) == "O", "SSE: Register devuelve objeto", "O", ValType( oConn ) )
   nCount := HIX_SseCount( "test_sse_reg" )
   _TLog( "Count tras Register = " + hb_NToS( nCount ) )
   HixTU_Check( hCtx, nCount == 1, "SSE: Count tras Register = 1", "1", hb_NToS( nCount ) )
   _HixSseUnregister( oConn )
   nCount := HIX_SseCount( "test_sse_reg" )
   _TLog( "Count tras Unregister = " + hb_NToS( nCount ) )
   HixTU_Check( hCtx, nCount == 0, "SSE: Count tras Unregister = 0", "0", hb_NToS( nCount ) )
RETURN

STATIC PROCEDURE _SseBroadcast( hCtx )
   LOCAL oIO, oConn, nNotified, cWritten
   _TLog( "_SseBroadcast" )
   oIO   := TMockIO():New( "", "" )
   oConn := _HixSseRegister( oIO, "test_sse_bc", 0 )

   // Broadcast texto plano
   nNotified := HIX_SseBroadcast( "test_sse_bc", "hola mundo" )
   cWritten  := oIO:cWritten
   _TLog( "Broadcast notified=" + hb_NToS( nNotified ) + " written=" + cWritten )
   HixTU_Check( hCtx, nNotified == 1,                   "SSE: Broadcast -> 1 notificado",          "1",  hb_NToS( nNotified ) )
   HixTU_Check( hCtx, "data: hola mundo" $ cWritten,    "SSE: Frame contiene data: hola mundo",    "data: hola mundo",    iif( "data: hola mundo" $ cWritten, "ok", cWritten ) )
   HixTU_Check( hCtx, Chr(10)+Chr(10) $ cWritten,       "SSE: Frame termina con doble newline",    "LF+LF",               iif( Chr(10)+Chr(10) $ cWritten, "ok", "no" ) )

   // Broadcast con event= y id=
   oIO:cWritten := ""
   nNotified := HIX_SseBroadcast( "test_sse_bc", "msg_data", "ping", 7 )
   cWritten  := oIO:cWritten
   _TLog( "Broadcast event+id written=" + cWritten )
   HixTU_Check( hCtx, "event: ping" $ cWritten,  "SSE: Frame con event=ping",  "event: ping",  iif( "event: ping"  $ cWritten, "ok", cWritten ) )
   HixTU_Check( hCtx, "id: 7"       $ cWritten,  "SSE: Frame con id=7",        "id: 7",        iif( "id: 7"        $ cWritten, "ok", cWritten ) )
   HixTU_Check( hCtx, "data: msg_data" $ cWritten,"SSE: Frame con data=msg_data","data: msg_data",iif( "data: msg_data" $ cWritten, "ok", cWritten ) )

   // Unregister y broadcast -> 0
   _HixSseUnregister( oConn )
   nNotified := HIX_SseBroadcast( "test_sse_bc", "post" )
   _TLog( "Broadcast tras unregister -> " + hb_NToS( nNotified ) )
   HixTU_Check( hCtx, nNotified == 0, "SSE: Broadcast tras unregister -> 0", "0", hb_NToS( nNotified ) )
RETURN

STATIC PROCEDURE _SseMultiClient( hCtx )
   LOCAL oIO1, oIO2, oIO3, oC1, oC2, oC3, nNotified
   _TLog( "_SseMultiClient" )
   oIO1 := TMockIO():New( "", "" ) ; oC1 := _HixSseRegister( oIO1, "test_sse_multi", 0 )
   oIO2 := TMockIO():New( "", "" ) ; oC2 := _HixSseRegister( oIO2, "test_sse_multi", 0 )
   oIO3 := TMockIO():New( "", "" ) ; oC3 := _HixSseRegister( oIO3, "test_sse_multi", 0 )
   nNotified := HIX_SseBroadcast( "test_sse_multi", "todos" )
   _TLog( "Multi notified=" + hb_NToS( nNotified ) )
   HixTU_Check( hCtx, nNotified == 3,                   "SSE: Broadcast multi -> 3 notificados", "3", hb_NToS( nNotified ) )
   HixTU_Check( hCtx, "data: todos" $ oIO1:cWritten,    "SSE: Multi cliente 1 recibio",          "data: todos", iif( "data: todos" $ oIO1:cWritten, "ok", oIO1:cWritten ) )
   HixTU_Check( hCtx, "data: todos" $ oIO2:cWritten,    "SSE: Multi cliente 2 recibio",          "data: todos", iif( "data: todos" $ oIO2:cWritten, "ok", oIO2:cWritten ) )
   HixTU_Check( hCtx, "data: todos" $ oIO3:cWritten,    "SSE: Multi cliente 3 recibio",          "data: todos", iif( "data: todos" $ oIO3:cWritten, "ok", oIO3:cWritten ) )
   _HixSseUnregister( oC1 ) ; _HixSseUnregister( oC2 ) ; _HixSseUnregister( oC3 )
RETURN

STATIC PROCEDURE _SseWrongChannel( hCtx )
   LOCAL oIO, oConn, nNotified
   _TLog( "_SseWrongChannel" )
   oIO   := TMockIO():New( "", "" )
   oConn := _HixSseRegister( oIO, "test_sse_chA", 0 )
   nNotified := HIX_SseBroadcast( "test_sse_chB", "canal_b" )
   HixTU_Check( hCtx, nNotified == 0, "SSE: Broadcast canal equivocado -> 0", "0", hb_NToS( nNotified ) )
   _HixSseUnregister( oConn )
RETURN

STATIC PROCEDURE _SseCountMulti( hCtx )
   LOCAL oIO1, oIO2, oIO3, oC1, oC2, oC3, nCA, nCB
   _TLog( "_SseCountMulti" )
   oIO1 := TMockIO():New( "", "" ) ; oC1 := _HixSseRegister( oIO1, "test_sse_cnt_a", 0 )
   oIO2 := TMockIO():New( "", "" ) ; oC2 := _HixSseRegister( oIO2, "test_sse_cnt_a", 0 )
   oIO3 := TMockIO():New( "", "" ) ; oC3 := _HixSseRegister( oIO3, "test_sse_cnt_b", 0 )
   nCA := HIX_SseCount( "test_sse_cnt_a" )
   nCB := HIX_SseCount( "test_sse_cnt_b" )
   _TLog( "CountMulti nCA=" + hb_NToS( nCA ) + " nCB=" + hb_NToS( nCB ) )
   HixTU_Check( hCtx, nCA == 2, "SSE: Count canal A con 2 = 2", "2", hb_NToS( nCA ) )
   HixTU_Check( hCtx, nCB == 1, "SSE: Count canal B con 1 = 1", "1", hb_NToS( nCB ) )
   _HixSseUnregister( oC1 ) ; _HixSseUnregister( oC2 ) ; _HixSseUnregister( oC3 )
RETURN
