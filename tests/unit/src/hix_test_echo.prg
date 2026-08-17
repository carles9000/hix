/*-----------------------------------------------------------
  File ......: hix_test_echo.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — HIX_Echo / output buffering
 -----------------------------------------------------------*/
#include "hix_logger.ch"

STATIC FUNCTION _ExecAndFlush( oDisp, cPath )
   LOCAL cRet, cBuf
   HIX_EchoClear()
   cRet := oDisp:ExecutePrg( cPath )
   cBuf := HIX_EchoGet()
   IF ! Empty( cRet ) ; cBuf += cRet ; ENDIF
   HIX_EchoClear()
RETURN cBuf

FUNCTION HIX_TestEcho_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _EchoBuffer(     hCtx )
   _EchoTipos(      hCtx )
   _EchoDispatcher( hCtx )
RETURN hCtx

STATIC PROCEDURE _EchoBuffer( hCtx )
   HIX_EchoClear()
   HixTU_Check( hCtx, HIX_EchoGet() == "", "Echo: buffer vacio tras Clear", "", HIX_EchoGet() )
   HIX_Echo( "Hola" )
   HixTU_Check( hCtx, HIX_EchoGet() == "Hola", "Echo: string simple", "Hola", HIX_EchoGet() )
   HIX_Echo( " Mundo" )
   HixTU_Check( hCtx, HIX_EchoGet() == "Hola Mundo", "Echo: acumula", "Hola Mundo", HIX_EchoGet() )
   HIX_EchoClear()
   HixTU_Check( hCtx, HIX_EchoGet() == "", "Echo: Clear limpia", "", HIX_EchoGet() )
   HIX_Echo( "<p>A</p>", "<p>B</p>" )
   HixTU_Check( hCtx, HIX_EchoGet() == "<p>A</p><p>B</p>", "Echo: multi-param", "<p>A</p><p>B</p>", HIX_EchoGet() )
RETURN

STATIC PROCEDURE _EchoTipos( hCtx )
   HIX_EchoClear() ; HIX_Echo( 42 )
   HixTU_Check( hCtx, HIX_EchoGet() == "42", "Echo: numerico->string", "42", HIX_EchoGet() )
   HIX_EchoClear() ; HIX_Echo( .T. )
   HixTU_Check( hCtx, HIX_EchoGet() == ".T.", "Echo: .T.->''.T.''", ".T.", HIX_EchoGet() )
   HIX_EchoClear() ; HIX_Echo( .F. )
   HixTU_Check( hCtx, HIX_EchoGet() == ".F.", "Echo: .F.->''.F.''", ".F.", HIX_EchoGet() )
   HIX_EchoClear() ; HIX_Echo( NIL )
   HixTU_Check( hCtx, HIX_EchoGet() == "", "Echo: NIL->''", "", HIX_EchoGet() )
   HIX_EchoClear() ; HIX_Echo( { "k" => "v" } )
   HixTU_Check( hCtx, "{" $ HIX_EchoGet(), "Echo: Hash->JSON", "{...}", HIX_EchoGet() )
   HIX_EchoClear() ; HIX_Echo( { "a", "b" } )
   HixTU_Check( hCtx, "[" $ HIX_EchoGet(), "Echo: Array->JSON", "[...]", HIX_EchoGet() )
RETURN

STATIC PROCEDURE _EchoDispatcher( hCtx )
   LOCAL cRoot, cEol, oDisp, cResult

   cRoot := hb_DirTemp() + "hix_tm_echo" + hb_ps()
   cEol  := hb_eol()
   hb_DirCreate( cRoot )

   hb_MemoWrit( cRoot + "only_echo.prg",   "FUNCTION only_echo()"   + cEol + "HIX_Echo( '<h1>Hello</h1>' )" + cEol + "RETURN NIL" )
   hb_MemoWrit( cRoot + "only_return.prg", "FUNCTION only_return()"  + cEol + "RETURN '<p>World</p>'" )
   hb_MemoWrit( cRoot + "both.prg",        "FUNCTION both()"         + cEol + "HIX_Echo( 'A' )" + cEol + "HIX_Echo( 'B' )" + cEol + "RETURN 'C'" )
   hb_MemoWrit( cRoot + "multi.prg",       "FUNCTION multi()"        + cEol + "HIX_Echo( '<p>1</p>' )" + cEol + "HIX_Echo( '<p>2</p>' )" + cEol + "HIX_Echo( '<p>3</p>' )" + cEol + "RETURN NIL" )

   oDisp := THixDispatcher():New( cRoot )
   oDisp:nExecTimeout := 0

   cResult := _ExecAndFlush( oDisp, cRoot + "only_echo.prg" )
   HixTU_Check( hCtx, cResult == "<h1>Hello</h1>", "Echo+Disp: solo Echo -> body", "<h1>Hello</h1>", cResult )
   cResult := _ExecAndFlush( oDisp, cRoot + "only_return.prg" )
   HixTU_Check( hCtx, cResult == "<p>World</p>", "Echo+Disp: solo RETURN -> body", "<p>World</p>", cResult )
   cResult := _ExecAndFlush( oDisp, cRoot + "both.prg" )
   HixTU_Check( hCtx, cResult == "ABC", "Echo+Disp: Echo+RETURN -> ABC", "ABC", cResult )
   cResult := _ExecAndFlush( oDisp, cRoot + "multi.prg" )
   HixTU_Check( hCtx, cResult == "<p>1</p><p>2</p><p>3</p>", "Echo+Disp: multi-echo", "<p>1</p><p>2</p><p>3</p>", cResult )

   // Cleanup
   FErase( cRoot + "only_echo.prg" )
   FErase( cRoot + "only_return.prg" )
   FErase( cRoot + "both.prg" )
   FErase( cRoot + "multi.prg" )
   hb_DirDelete( cRoot )
RETURN
