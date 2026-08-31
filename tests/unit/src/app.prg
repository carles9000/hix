/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-06-03
  Modified...: 2026-06-05
  Description: HIX Test Master — web dashboard de tests
  Usage      : go.bat -> http://localhost:8099
 -----------------------------------------------------------*/
#INCLUDE "hbclass.ch"
#INCLUDE "fileio.ch"
#INCLUDE "hix_const.ch"
#INCLUDE "hix_logger.ch"
#INCLUDE "hbsocket.ch"

STATIC s_lRunning   := .F.
STATIC s_mtxRun     := NIL
STATIC s_cLogFile   := ""
STATIC s_cTestsLog  := ""
STATIC s_oPeer      := NIL
STATIC s_nPeerPort  := 8100
STATIC s_aActivity  := {}
STATIC s_mtxAct     := NIL
STATIC s_nActSeq    := 0
STATIC s_nTLogCount := 0
STATIC s_nTLogMax   := 1500

FUNCTION Main( ... )

   LOCAL oServer
   LOCAL cSep
   LOCAL cArg := iif( PCount() > 0, hb_PValue( 1 ), "" )

   s_mtxRun    := hb_mutexCreate()
   s_mtxAct    := hb_mutexCreate()

   // traces\ es el directorio unico de diagnostico de los tests: trazas
   // (_TLog), log del runner y logs que generan los propios tests. Si no
   // existe, hb_vfOpen() falla en silencio y se pierde todo el diagnostico.
   IF ! hb_vfDirExists( hb_DirBase() + "traces" )
      hb_vfDirMake( hb_DirBase() + "traces" )
   ENDIF

   s_cLogFile  := hb_DirBase() + "traces/hix.log"
   s_cTestsLog := hb_DirBase() + "traces/tests_run.log"
   hb_FileDelete( s_cLogFile )
   hb_FileDelete( s_cTestsLog )
   hb_FileDelete( hb_DirBase() + "traces/info.txt" )
   hb_FileDelete( hb_DirBase() + "traces/console.txt" )
   hb_FileDelete( hb_DirBase() + "traces/activity.log" )
   cSep := "=== RUN " + DToS( Date() ) + " " + Time() + " ===" + hb_eol()
   hb_MemoWrit( s_cTestsLog, cSep )

   // Headless CLI mode: run all tests and exit

   IF cArg == "--cli"

      _RunCli()
      RETURN NIL

   ENDIF

   s_oPeer := _PeerStart( s_nPeerPort )

   // Instalar hook de lifecycle: cada Start/Stop de cualquier THixServer
   // (principal + sub-servers de los tests) emite una nota de actividad.
   HIX_SetLifecycleHook( {| cState, cLabel | HixTM_Note( cLabel, cState ) } )

   oServer := THixServer():New()

   oServer:AddRouteGet( "index",     "/",             "index.html"         )
   oServer:AddRouteGet( "api_tests",   "/api/tests",    {|| RouteApiTests()   } )
   oServer:AddRouteGet( "api_run",    "/api/run",      {|| RouteApiRun()     } )
   oServer:AddRouteGet( "api_log",    "/api/log",      {|| RouteApiLog()     } )
   oServer:AddRouteGet( "api_testlog", "/api/testlog",  {|| RouteApiTestLog() } )
   oServer:AddRouteGet( "api_sse",    "/api/test-sse", {|| RouteTestSSE()    } )
   oServer:AddRouteGet( "api_reset",  "/api/reset",    {|| RouteApiReset()   } )
   oServer:AddRouteGet( "api_activity", "/api/activity", {|| RouteApiActivity() } )
   oServer:AddRoutePost( "api_tracedump", "/api/tracedump", {|| RouteApiTraceDump() } )

   oServer:Start( .F. )

   DO WHILE oServer:lRunning

      IF Inkey( 0.5 ) == 27

         EXIT

      ENDIF

   ENDDO

   oServer:Stop()

RETURN NIL

// -------------------------------------------------------
// CLI mode: run all tests, print summary, set ErrorLevel
// -------------------------------------------------------
STATIC PROCEDURE _RunCli()

   LOCAL aGroups := _TestGroups()
   LOCAL aGroup, aTest, hCtx, oErr
   LOCAL nTotal := 0, nPass := 0, nFail := 0
   LOCAL cStatus

   HIX_LoggerInit( s_cLogFile, HIX_LOG_INFO, .T. )
   HIX_MetricsInit()

   OutStd( "HIX Test Master — CLI mode" + hb_eol() )
   OutStd( Replicate( "-", 50 ) + hb_eol() )

   FOR EACH aGroup IN aGroups

      FOR EACH aTest IN aGroup[ 2 ]

         OutStd( "  " + aGroup[ 1 ] + "/" + aTest[ 1 ] + " ... " )
         hCtx := NIL

         TRY

            hCtx := Eval( aTest[ 2 ] )
         CATCH oErr
            OutStd( "[EXCEPTION] " + oErr:description + hb_eol() )
            hCtx := _ErrorCtx( oErr:description )

         END

         IF hCtx != NIL

            nTotal += hCtx[ "total" ]
            nPass  += hCtx[ "passed" ]
            nFail  += hCtx[ "failed" ]
            cStatus := iif( hCtx[ "failed" ] == 0, "ok", "FAIL (" + hb_ntos( hCtx[ "failed" ] ) + ")" )
         ELSE
            cStatus := "ERROR"
            nFail++

         ENDIF

         OutStd( cStatus + hb_eol() )

      NEXT

   NEXT

   OutStd( Replicate( "-", 50 ) + hb_eol() )
   OutStd( hb_ntos( nTotal ) + " total | " + hb_ntos( nPass ) + " passed | " + hb_ntos( nFail ) + " failed" + hb_eol() )
   OutStd( "End test..." + hb_eol() )

   ErrorLevel( iif( nFail == 0, 0, 1 ) )

RETURN

// -------------------------------------------------------
// GET /api/tests
// -------------------------------------------------------
FUNCTION RouteApiTests()

   LOCAL aGroups := _TestGroups()
   LOCAL aResult := {}
   LOCAL hGroup, aGroup, aTest

   FOR EACH aGroup IN aGroups

      hGroup := { "name" => aGroup[ 1 ], "tests" => {} }

      FOR EACH aTest IN aGroup[ 2 ]

         AAdd( hGroup[ "tests" ], { "name" => aTest[ 1 ], "exists" => .T. } )

      NEXT

      AAdd( aResult, hGroup )

   NEXT

   USendJson( aResult )

RETURN NIL

// -------------------------------------------------------
// GET /api/run?group=all|Core|...   (SSE stream)
// -------------------------------------------------------
FUNCTION RouteApiRun()

   LOCAL cGroup  := UGet( "group", "all" )
   LOCAL aGroups := _TestGroups()
   LOCAL aToRun  := {}
   LOCAL aGroup, aTest, hCtx, oErr
   LOCAL hEvent, hRes, cLine, cOut
   LOCAL oSavedReq, oSavedCtx, hSavedRoutes
   LOCAL nT0, nLap

   hb_mutexLock( s_mtxRun )

   IF s_lRunning

      hb_mutexUnlock( s_mtxRun )
      _TLog( "RouteApiRun 409 - s_lRunning busy" )
      USendError( 409, "Run already in progress" )
      RETURN NIL

   ENDIF

   s_lRunning := .T.
   hb_mutexUnlock( s_mtxRun )

   HixTM_ActivityReset()

   FOR EACH aGroup IN aGroups

      IF cGroup == "all" .OR. Lower( cGroup ) == Lower( aGroup[ 1 ] )

         FOR EACH aTest IN aGroup[ 2 ]

            AAdd( aToRun, { aGroup[ 1 ], aTest[ 1 ], aTest[ 2 ] } )

         NEXT

      ENDIF

   NEXT

   _TLog( "RouteApiRun start group=" + cGroup + " count=" + hb_ntos( Len( aToRun ) ) )

   TRY

      IF Empty( aToRun )

         USendError( 404, "Group not found: " + cGroup )
      ELSE

         USendStreamStart( "text/event-stream", 200, { ;
            "Cache-Control"     => "no-cache", ;
            "X-Accel-Buffering" => "no"        ;
            } )

         _SseEvent( { "type" => "init", "count" => Len( aToRun ) } )

         FOR EACH aTest IN aToRun

            _SseEvent( { "type" => "running", "group" => aTest[ 1 ], "test" => aTest[ 2 ] } )

            oSavedReq    := HIX_GetRequest()
            oSavedCtx    := HIX_GetContext()
            hSavedRoutes := HIX_RoutesSnapshot()
            hCtx := NIL
            HIX_EchoClear()
            _TLog( "Eval " + aTest[ 1 ] + "/" + aTest[ 2 ] + " [echo=" + hb_ntos( Len( oSavedReq:cEchoBuffer ) ) + " lResp=" + hb_ValToStr( oSavedReq:lResponded ) + "]" )

            nT0 := hb_MilliSeconds()

            TRY

               hCtx := Eval( aTest[ 3 ] )
            CATCH oErr
               _TLog( "Test " + aTest[ 2 ] + " exception: " + oErr:description )
               hCtx := _ErrorCtx( oErr:description )

            END

            nLap := Int( hb_MilliSeconds() - nT0 )

            HIX_EchoClear()
            _TLog( "Eval done " + aTest[ 2 ] + " [echo=" + hb_ntos( Len( oSavedReq:cEchoBuffer ) ) + " lResp=" + hb_ValToStr( oSavedReq:lResponded ) + "]" )
            // Restore thread-local request/context and router state
            HIX_SetRequest( oSavedReq )
            HIX_SetContext( oSavedCtx )
            HIX_RoutesRestore( hSavedRoutes )
            // Restore global logger/metrics that tests may have closed
            HIX_LoggerInit( s_cLogFile, HIX_LOG_INFO, .T. )
            HIX_MetricsInit()

            IF hCtx == NIL

               hCtx := _ErrorCtx( "Run() returned NIL" )

            ENDIF

            FOR EACH hRes IN hCtx[ "results" ]

               cLine := iif( hRes[ "status" ] == "pass", "[PASS] ", "[FAIL] " ) + hRes[ "name" ]
               IF hb_HHasKey( hRes, "ms" )
                  cLine += " (" + hb_NToS( hRes[ "ms" ] ) + "ms)"
               ENDIF
               _SseEvent( { "type" => "line", "test" => aTest[ 2 ], "line" => cLine } )

               IF ! Empty( hRes[ "msg" ] )

                  _SseEvent( { "type" => "line", "test" => aTest[ 2 ], "line" => "       " + hRes[ "msg" ] } )

               ENDIF

            NEXT

            cOut   := _HCtxToOutput( hCtx, aTest[ 2 ] )
            hb_MemoWrit( s_cTestsLog, hb_MemoRead( s_cTestsLog ) + "[" + aTest[ 1 ] + "] " + cOut + hb_eol() )
            hEvent := { ;
               "type"   => "result",                                                          ;
               "group"  => aTest[ 1 ],                                                          ;
               "test"   => aTest[ 2 ],                                                          ;
               "status" => iif( hCtx[ "failed" ] > 0 .OR. hCtx[ "total" ] == 0, "fail", "ok" ), ;
               "total"  => hCtx[ "total" ],                                                     ;
               "passed" => hCtx[ "passed" ],                                                    ;
               "failed" => hCtx[ "failed" ],                                                    ;
               "ms"     => nLap,                                                                ;
               "output" => cOut                                                               ;
               }
            _SseEvent( hEvent )

         NEXT

         _SseEvent( { "type" => "done" } )
         USendStreamEnd()

      ENDIF

   CATCH oErr
      _TLog( "RouteApiRun outer exception: " + oErr:description )

      FINALLY
      hb_mutexLock( s_mtxRun )
      s_lRunning := .F.
      hb_mutexUnlock( s_mtxRun )
      _TLog( "RouteApiRun end - s_lRunning released" )

   END

RETURN NIL

// -------------------------------------------------------
// GET /api/log?from=N — lineas del hix.log desde cursor N
// Returns: { file, total, lines[] }
// -------------------------------------------------------
FUNCTION RouteApiLog()

   LOCAL cLog, aLines, nFrom, nTotal, aResult, i

   nFrom  := Val( UGet( "from", "0" ) )
   cLog   := hb_MemoRead( s_cLogFile )
   aLines := hb_ATokens( StrTran( cLog, Chr( 13 ), "" ), Chr( 10 ) )
   // Trim trailing empty lines
   nTotal := Len( aLines )

   DO WHILE nTotal > 0 .AND. Empty( AllTrim( aLines[ nTotal ] ) )

      nTotal--

   ENDDO

   // If cursor is beyond current total (e.g. log was reset), restart from 0

   IF nFrom > nTotal ; nFrom := 0 ; ENDIF

   aResult := {}

   FOR i := nFrom + 1 TO nTotal

      AAdd( aResult, aLines[ i ] )

   NEXT

   USendJson( { "file" => s_cLogFile, "total" => nTotal, "lines" => aResult } )

RETURN NIL

// -------------------------------------------------------
// GET /api/testlog?from=N — lineas del tests_run.log desde cursor N
// -------------------------------------------------------
FUNCTION RouteApiTestLog()

   LOCAL cLog, aLines, nFrom, nTotal, aResult, i

   nFrom  := Val( UGet( "from", "0" ) )
   cLog   := hb_MemoRead( s_cTestsLog )
   aLines := hb_ATokens( StrTran( cLog, Chr( 13 ), "" ), Chr( 10 ) )
   nTotal := Len( aLines )

   DO WHILE nTotal > 0 .AND. Empty( AllTrim( aLines[ nTotal ] ) )

      nTotal--

   ENDDO

   IF nFrom > nTotal ; nFrom := 0 ; ENDIF

   aResult := {}

   FOR i := nFrom + 1 TO nTotal

      AAdd( aResult, aLines[ i ] )

   NEXT

   USendJson( { "file" => s_cTestsLog, "total" => nTotal, "lines" => aResult } )

RETURN NIL

// -------------------------------------------------------
// GET /api/reset — libera s_lRunning si un run quedo colgado
// -------------------------------------------------------
FUNCTION RouteApiReset()

   hb_mutexLock( s_mtxRun )
   s_lRunning := .F.
   hb_mutexUnlock( s_mtxRun )
   USendJson( { "ok" => .T. } )

RETURN NIL

// -------------------------------------------------------
// GET /api/test-sse — diagnostico SSE (5 pings 500ms)
// -------------------------------------------------------
FUNCTION RouteTestSSE()

   LOCAL i

   USendStreamStart( "text/event-stream", 200, { ;
      "Cache-Control"     => "no-cache", ;
      "X-Accel-Buffering" => "no"        ;
      } )

   FOR i := 1 TO 5

      hb_idleSleep( 0.5 )
      _SseEvent( { "type" => "ping", "i" => i } )

   NEXT

   _SseEvent( { "type" => "done" } )
   USendStreamEnd()

RETURN NIL

// -------------------------------------------------------
// Helpers internos
// -------------------------------------------------------
STATIC FUNCTION _ErrorCtx( cMsg )
RETURN { "total" => 1, "passed" => 0, "failed" => 1, ;
      "results" => { { "status" => "fail", "name" => "ERROR", "msg" => cMsg } } }

STATIC FUNCTION _Pending()
RETURN { "total" => 1, "passed" => 0, "failed" => 1, ;
      "results" => { { "status" => "fail", "name" => "Pendiente de implementar", "msg" => "" } } }

STATIC FUNCTION _HCtxToOutput( hCtx, cName )

   LOCAL cOut := "--- " + cName + " ---" + hb_eol()
   LOCAL hRes

   FOR EACH hRes IN hCtx[ "results" ]

      cOut += iif( hRes[ "status" ] == "pass", "[PASS] ", "[FAIL] " ) + hRes[ "name" ]
      IF hb_HHasKey( hRes, "ms" )
         cOut += " (" + hb_NToS( hRes[ "ms" ] ) + "ms)"
      ENDIF
      cOut += hb_eol()

      IF ! Empty( hRes[ "msg" ] )

         cOut += "       " + hRes[ "msg" ] + hb_eol()
      ELSEIF hRes[ "status" ] == "pass" .AND. ! Empty( hb_HGetDef( hRes, "exp", "" ) )
         cOut += "       Expected: " + hRes[ "exp" ] + "  Got: " + hRes[ "got" ] + hb_eol()

      ENDIF

   NEXT

   cOut += hb_eol() + hb_ntos( hCtx[ "total" ] ) + " total | " + ;
      hb_ntos( hCtx[ "passed" ] ) + " passed | " + ;
      hb_ntos( hCtx[ "failed" ] ) + " failed" + hb_eol()

RETURN cOut

STATIC PROCEDURE _SseEvent( hData )

   USendChunk( "data: " + hb_jsonEncode( hData ) + Chr( 10 ) + Chr( 10 ) )

RETURN

// Encola una "nota" de actividad. Se persiste en un fichero para
// que el UI la lea via poll HTTP simple (/api/activity), sin depender
// de streams SSE que puedan bloquearse con el lifecycle de mini-servers.
// cLabel: texto corto para el badge (ej. "Server On", "Waiting...")
// cKind : "start" | "on" | "stop" | "off" | "wait" | "info" (por defecto "info")
FUNCTION HixTM_Note( cLabel, cKind )

   LOCAL nSeq, cLine, cFile, lOk, oErr

   hb_default( @cLabel, "" )
   hb_default( @cKind,  "info" )

   IF s_mtxAct == NIL

      _TLog( "HixTM_Note SKIP (mtx=NIL) label=" + cLabel + " kind=" + cKind )
      RETURN NIL

   ENDIF

   hb_mutexLock( s_mtxAct )
   s_nActSeq++
   nSeq := s_nActSeq
   AAdd( s_aActivity, { nSeq, hb_MilliSeconds(), cLabel, cKind } )

   DO WHILE Len( s_aActivity ) > 200

      hb_ADel( s_aActivity, 1, .T. )

   ENDDO

   hb_mutexUnlock( s_mtxAct )

   // Persistir en fichero (append line) — el UI hace poll de esto.
   cFile := _ActFilePath()
   cLine := hb_ntos( nSeq ) + Chr( 9 ) + hb_CStr( cKind ) + Chr( 9 ) + hb_CStr( cLabel ) + hb_eol()
   lOk := .F.

   TRY

      hb_MemoWrit( cFile, iif( hb_FileExists( cFile ), hb_MemoRead( cFile ), "" ) + cLine )
      lOk := .T.
   CATCH oErr
      _TLog( "HixTM_Note WRITE FAIL seq=" + hb_ntos( nSeq ) + " err=" + oErr:description )

   END

   _TLog( "HixTM_Note seq=" + hb_ntos( nSeq ) + " kind=" + cKind + " label=" + cLabel + ;
      " file=" + iif( lOk, "OK", "FAIL" ) + " queue=" + hb_ntos( Len( s_aActivity ) ) )

RETURN NIL

STATIC FUNCTION _ActFilePath()
RETURN hb_DirBase() + "traces" + hb_ps() + "activity.log"

// GET /api/activity?from=N — poll simple. Devuelve JSON con notas > from.
FUNCTION RouteApiActivity()

   LOCAL nFrom := Val( UGet( "from", "0" ) )
   LOCAL aRes := {}, aLines, cLine, aParts, nSeq
   LOCAL lExists := hb_FileExists( _ActFilePath() )
   LOCAL nFileSize := iif( lExists, hb_FSize( _ActFilePath() ), - 1 )

   IF lExists

      aLines := hb_ATokens( StrTran( hb_MemoRead( _ActFilePath() ), Chr( 13 ), "" ), Chr( 10 ) )

      FOR EACH cLine IN aLines

         IF Empty( cLine ) ; LOOP ; ENDIF

         aParts := hb_ATokens( cLine, Chr( 9 ) )

         IF Len( aParts ) < 3 ; LOOP ; ENDIF

         nSeq := Val( aParts[ 1 ] )

         IF nSeq > nFrom

            AAdd( aRes, { "seq" => nSeq, "kind" => aParts[ 2 ], "label" => aParts[ 3 ] } )

         ENDIF

      NEXT

   ENDIF

   _TLog( "RouteApiActivity from=" + hb_ntos( nFrom ) + " last=" + hb_ntos( s_nActSeq ) + ;
      " notes=" + hb_ntos( Len( aRes ) ) + " fileExists=" + iif( lExists, "T", "F" ) + ;
      " size=" + hb_ntos( nFileSize ) )

   USendJson( { "notes" => aRes, "last" => s_nActSeq } )

RETURN NIL

// Vaciar el log de actividad al arrancar un run nuevo.
FUNCTION HixTM_ActivityReset()

   LOCAL lExisted := hb_FileExists( _ActFilePath() )
   LOCAL lDeleted := .F.

   IF s_mtxAct != NIL ; hb_mutexLock( s_mtxAct ) ; ENDIF

   s_aActivity := {}
   s_nActSeq   := 0

   IF s_mtxAct != NIL ; hb_mutexUnlock( s_mtxAct ) ; ENDIF

   IF lExisted

      lDeleted := hb_FileDelete( _ActFilePath() )

   ENDIF

   // Reset trazas: reactivar TLog y limpiar ficheros de diagnostico.
   s_nTLogCount := 0
   hb_FileDelete( hb_DirBase() + "traces" + hb_ps() + "info.txt" )
   hb_FileDelete( hb_DirBase() + "traces" + hb_ps() + "console.txt" )
   _TLog( "HixTM_ActivityReset existed=" + iif( lExisted, "T", "F" ) + ;
      " deleted=" + iif( lDeleted, "T", "F" ) + " path=" + _ActFilePath() )

RETURN NIL

STATIC PROCEDURE _TLog( cMsg )

   LOCAL nH

   IF s_nTLogCount >= s_nTLogMax

      RETURN

   ENDIF

   s_nTLogCount++
   nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )

   IF nH != NIL

      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[App] " + hb_ntos( hb_MilliSeconds() ) + " " + cMsg + hb_eol() )

      IF s_nTLogCount == s_nTLogMax

         hb_vfWrite( nH, "[App] --- TLog CAP REACHED (" + hb_ntos( s_nTLogMax ) + " lines) ---" + hb_eol() )

      ENDIF

      hb_vfClose( nH )

   ENDIF

RETURN

// POST /api/tracedump — el navegador vuelca su console.log aqui.
// Sirve para que Claude pueda leer las trazas del cliente sin depender
// del DevTools que va rodando en pantalla.
FUNCTION RouteApiTraceDump()

   LOCAL cBody := UBody()
   LOCAL cFile := hb_DirBase() + "traces" + hb_ps() + "console.txt"

   IF Empty( cBody )

      USendJson( { "ok" => .F., "empty" => .T. } )
      RETURN NIL

   ENDIF

   TRY

      hb_MemoWrit( cFile, iif( hb_FileExists( cFile ), hb_MemoRead( cFile ), "" ) + cBody )
   CATCH

   END

   USendJson( { "ok" => .T., "bytes" => Len( cBody ) } )

RETURN NIL

// -------------------------------------------------------
// Peer server (port 8100) — HTTP/1.0 raw TCP, sin THixServer.
// No toca config global, logger ni metrics del servidor principal.
// Arranca en hilo propio; muere con el proceso.
// -------------------------------------------------------

FUNCTION HIX_TestPeer_Port()
RETURN s_nPeerPort

STATIC FUNCTION _PeerStart( nPort )

   LOCAL oSock

   oSock := hb_socketOpen()

   IF oSock == NIL

      _TLog( "Peer: socket open failed" )
      RETURN NIL

   ENDIF

   hb_socketSetReuseAddr( oSock, .T. )

   IF ! hb_socketBind( oSock, { HB_SOCKET_AF_INET, "0.0.0.0", nPort } )

      _TLog( "Peer: bind port " + hb_ntos( nPort ) + " failed" )
      hb_socketClose( oSock )
      RETURN NIL

   ENDIF

   IF ! hb_socketListen( oSock, 16 )

      _TLog( "Peer: listen failed" )
      hb_socketClose( oSock )
      RETURN NIL

   ENDIF

   _TLog( "Peer listening on :" + hb_ntos( nPort ) )

RETURN hb_threadStart( {|| _PeerAcceptLoop( oSock ) } )

STATIC PROCEDURE _PeerAcceptLoop( oSock )

   LOCAL oClient, aAddr

   DO WHILE .T.

      oClient := hb_socketAccept( oSock, @aAddr, 500 )

      IF ! Empty( oClient )

         hb_threadStart( {|| _PeerServe( oClient ) } )

      ENDIF

   ENDDO

RETURN

STATIC PROCEDURE _PeerServe( oSock )

   LOCAL cBuf    := Space( 8192 )
   LOCAL nRead, cLine, cMethod, cPath, cQuery, cBody, cResp, nStatus, nMs, nQ, nSp
   LOCAL cCrLf   := Chr( 13 ) + Chr( 10 )

   nRead := hb_socketRecv( oSock, @cBuf, 8192, 0, 3000 )

   IF nRead <= 0 ; hb_socketClose( oSock ) ; RETURN ; ENDIF

   cBuf := Left( cBuf, nRead )

   // "GET /path?q=v HTTP/1.0"
   cLine   := Left( cBuf, At( Chr( 13 ), cBuf ) - 1 )
   nSp     := At( " ", cLine )
   cMethod := Left( cLine, nSp - 1 )
   cPath   := AllTrim( SubStr( cLine, nSp + 1 ) )
   nSp     := At( " ", cPath )

   IF nSp > 0 ; cPath := Left( cPath, nSp - 1 ) ; ENDIF

   nQ := At( "?", cPath )

   IF nQ > 0

      cQuery := SubStr( cPath, nQ + 1 )
      cPath  := Left( cPath, nQ - 1 )
   ELSE
      cQuery := ""

   ENDIF

   nStatus := 200

   DO CASE

      CASE cPath == "/ping"
         cBody := hb_jsonEncode( { "ok" => .T., "port" => s_nPeerPort } )
      CASE cPath == "/echo"
         cBody := hb_jsonEncode( { "method" => cMethod, "path" => cPath, "query" => cQuery } )
      CASE cPath == "/slow"
         nMs := Val( _PQParam( cQuery, "ms", "100" ) )

      IF nMs < 0 ; nMs := 0 ; ENDIF ; IF nMs > 5000 ; nMs := 5000 ; ENDIF

         hb_idleSleep( nMs / 1000 )
         cBody := hb_jsonEncode( { "waited" => nMs } )
      OTHERWISE
         nStatus := 404
         cBody   := hb_jsonEncode( { "error" => "not found" } )

   ENDCASE

   cResp  := "HTTP/1.0 " + hb_ntos( nStatus ) + " OK"  + cCrLf
   cResp  += "Content-Type: application/json"            + cCrLf
   cResp  += "Content-Length: " + hb_ntos( Len( cBody ) ) + cCrLf
   cResp  += "Connection: close" + cCrLf + cCrLf
   cResp  += cBody

   hb_socketSend( oSock, cResp, Len( cResp ), 0, 3000 )
   hb_socketClose( oSock )

RETURN

STATIC FUNCTION _PQParam( cQuery, cKey, cDef )

   LOCAL aPairs, cPair, nEq

   hb_default( @cDef, "" )

   IF Empty( cQuery ) ; RETURN cDef ; ENDIF

   aPairs := hb_ATokens( cQuery, "&" )

   FOR EACH cPair IN aPairs

      nEq := At( "=", cPair )

      IF nEq > 0 .AND. Left( cPair, nEq - 1 ) == cKey

         RETURN SubStr( cPair, nEq + 1 )

      ENDIF

   NEXT

RETURN cDef

// -------------------------------------------------------
// Grupos de tests — codeblocks directos (in-process)
// -------------------------------------------------------
STATIC FUNCTION _TestGroups()
RETURN { ;
      { "Core", { ;
      { "Server",       {|| HIX_TestServer_Run()       } }, ;
      { "Core",         {|| HIX_TestCore_Run()         } }, ;
      { "Pool",         {|| HIX_TestPool_Run()         } }, ;
      { "PoolHix",      {|| HIX_TestPoolHix_Run()      } }, ;
      { "DataPool",     {|| HIX_TestDataPool_Run()     } }, ;
      { "NewOverrides", {|| HIX_TestNewOverrides_Run() } }  ;
      } }, ;
      { "Routing", { ;
      { "Router",        {|| HIX_TestRouter_Run()        } }, ;
      { "Dispatcher",    {|| HIX_TestDispatcher_Run()    } }, ;
      { "Helpers",       {|| HIX_TestHelpers_Run()       } }, ;
      { "Request",       {|| HIX_TestRequest_Run()       } }, ;
      { "OptionalParam", {|| HIX_TestOptionalParam_Run() } }, ;
      { "Context",       {|| HIX_TestContext_Run()       } }, ;
      { "Resource",      {|| HIX_TestResource_Run()      } }, ;
      { "LoadRoutes",    {|| HIX_TestLoadRoutes_Run()    } }  ;
      } }, ;
      { "HixStyle", { ;
      { "Acl",              {|| HIX_TestHixstyleAcl_Run()          } }, ;
      { "Sets",             {|| HIX_TestHixstyleHarbourSets_Run() } }, ;
      { "ConfigAutocreate", {|| HIX_TestConfigAutocreate_Run()    } }, ;
      { "UserHooks",        {|| HIX_TestUserHooks_Run()           } }  ;
      } }, ;
      { "Auth & Security", { ;
      { "JWT",          {|| HIX_TestJwt_Run()         } }, ;
      { "JwtScope",     {|| HIX_TestJwtScope_Run()    } }, ;
      { "Sessions",     {|| HIX_TestSession_Run()     } }, ;
      { "Sessions-File", {|| HIX_TestSessionFile_Run() } }, ;
      { "AuthSession",  {|| HIX_TestAuthSession_Run() } }, ;
      { "Csrf",         {|| HIX_TestCsrf_Run()        } }, ;
      { "Keys",         {|| HIX_TestKeys_Run()        } }, ;
      { "Permissions",  {|| HIX_TestPermissions_Run() } }, ;
      { "Pentest",      {|| HIX_TestSecurity_Run()    } }  ;
      } }, ;
      { "Middleware", { ;
      { "MW-Built-In", {|| HIX_TestMw_Run()          } }, ;
      { "MwAutoApply", {|| HIX_TestMwAutoApply_Run() } }, ;
      { "MwFlush",     {|| HIX_TestMwFlush_Run()     } }, ;
      { "MwSystem",    {|| HIX_TestMwSystem_Run()    } }, ;
      { "Flash",       {|| HIX_TestFlash_Run()       } }, ;
      { "Validator",   {|| HIX_TestValidator_Run()   } }  ;
      } }, ;
      { "Transport", { ;
      { "WebSocket", {|| HIX_TestWebSocket_Run() } }, ;
      { "WSS",       {|| HIX_TestWSS_Run()       } }, ;
      { "SSL",       {|| HIX_TestSSL_Run()       } }, ;
      { "LongPoll",  {|| HIX_TestLongPoll_Run()  } }, ;
      { "SSE",       {|| HIX_TestSSE_Run()        } }, ;
      { "Chunked",   {|| HIX_TestChunked_Run()   } }, ;
      { "Multipart", {|| HIX_TestMultipart_Run() } }, ;
      { "Gzip",      {|| HIX_TestGzip_Run()      } }  ;
      } }, ;
      { "Network", { ;
      { "IP",       {|| HIX_TestIP_Run()       } }, ;
      { "Proxied",  {|| HIX_TestProxied_Run()  } }, ;
      { "Firewall", {|| HIX_TestFirewall_Run() } }, ;
      { "Proxy",    {|| HIX_TestProxy_Run()    } }, ;
      { "Accept",   {|| HIX_TestAccept_Run()   } }  ;
      } }, ;
      { "Views & Exec", { ;
      { "ExecutePrg",   {|| HIX_TestExecutePrg_Run() } }, ;
      { "Views",        {|| HIX_TestViews_Run()         } }, ;
      { "ViewPerf",     {|| HIX_TestViewPerf_Run()         } }, ;
      { "VCacheMetrics", {|| HIX_TestVCacheMetrics_Run()  } }, ;
      { "ViewErrors",   {|| HIX_TestViewErrors_Run()  } }, ;
      { "ViewCodeErr",  {|| HIX_TestViewCodeErr_Run() } }, ;
      { "ViewCrossHrb", {|| HIX_TestViewCrossHrb_Run() } }  ;
      } }, ;
      { "Other", { ;
      { "Error",  {|| HIX_TestError_Run()  } }, ;
      { "Echo",   {|| HIX_TestEcho_Run()   } }, ;
      { "Abort",  {|| HIX_TestAbort_Run()  } }, ;
      { "Zombie", {|| HIX_TestZombie_Run() } }  ;
      } }  ;
      }
