/*-----------------------------------------------------------
  File ......: hix_test_error.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — HIX error system
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "error.ch"

// Unique-named mock to avoid class symbol conflicts
CLASS TMockReqErr
   DATA cIP             INIT "127.0.0.1"
   DATA hHeaders        INIT { => }
   DATA lResponded      INIT .F.
   DATA lStreaming       INIT .F.
   DATA cEchoBuffer     INIT ""
   DATA cResponseMime   INIT "html"
   DATA nResponseStatus INIT 200
   DATA nStatus         INIT 0
   DATA cBody           INIT ""
   METHOD Header( cKey, xDef ) INLINE hb_HGetDef( ::hHeaders, Lower( cKey ), hb_defaultValue( xDef, "" ) )
   METHOD Respond( xData, nStatus, cMime, hExtra )
ENDCLASS

METHOD Respond( xData, nStatus, cMime, hExtra ) CLASS TMockReqErr
   hb_default( @nStatus, 200 )
   HB_SYMBOL_UNUSED( cMime ) ; HB_SYMBOL_UNUSED( hExtra )
   ::lResponded := .T.
   ::nStatus    := nStatus
   ::cBody      := iif( ValType( xData ) == "C", xData, "" )
RETURN Self

FUNCTION HIX_TestError_Run()
   LOCAL hCtx   := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cLogDir := "traces"

   HIX_LoggerInit( cLogDir + "/test_error.log", HIX_LOG_DEBUG, .F. )
   HIX_MetricsInit()

   _ErrNewError(   hCtx )
   _ErrThrow(      hCtx )
   _ErrShowError(  hCtx, cLogDir )
   _ErrErrorLog(   hCtx, cLogDir )
   _ErrExecError(  hCtx )
   _ErrSystemError( hCtx )

   HIX_MetricsClose()
   HIX_LoggerClose()
RETURN hCtx

STATIC PROCEDURE _ErrNewError( hCtx )
   LOCAL oErr

   oErr := HIX_NewError( "campo requerido", "Validation", 422, "UserCreate" )
   HixTU_Check( hCtx, ValType( oErr ) == "O",                "Error: tipo objeto",       "O",          ValType( oErr ) )
   HixTU_Check( hCtx, oErr:ClassName() == "ERROR",           "Error: clase ERROR nativa","ERROR",      oErr:ClassName() )
   HixTU_Check( hCtx, oErr:Description == "campo requerido", "Error: description",       "campo requerido", oErr:Description )
   HixTU_Check( hCtx, oErr:SubSystem == "Validation",        "Error: subsystem",         "Validation", oErr:SubSystem )
   HixTU_Check( hCtx, oErr:SubCode == 422,                   "Error: subcode 422",       "422",        hb_NToS( oErr:SubCode ) )
   HixTU_Check( hCtx, oErr:Operation == "UserCreate",        "Error: operation",         "UserCreate", oErr:Operation )
   HixTU_Check( hCtx, oErr:Severity == ES_ERROR,             "Error: severity ES_ERROR", hb_NToS( ES_ERROR ), hb_NToS( oErr:Severity ) )
   HixTU_Check( hCtx, ! Empty( oErr:FileName ),              "Error: filename relleno",  "non-empty",  iif( Empty(oErr:FileName), "empty", oErr:FileName ) )

   oErr := HIX_NewError( "solo mensaje" )
   HixTU_Check( hCtx, oErr:SubSystem == "HIX", "Error: subsystem default HIX", "HIX", oErr:SubSystem )
   HixTU_Check( hCtx, oErr:SubCode == 0,       "Error: subcode default 0",     "0",   hb_NToS( oErr:SubCode ) )
   HixTU_Check( hCtx, oErr:Operation == "",    "Error: operation default vacia","",   oErr:Operation )
RETURN

STATIC PROCEDURE _ErrThrow( hCtx )
   LOCAL oErr, oGot

   oErr := HIX_NewError( "error de prueba", "Test", 99, "TestOp" )
   oGot := NIL
   BEGIN SEQUENCE WITH {|e| Break(e)}
      HIX_Throw( oErr )
   RECOVER USING oGot
   END SEQUENCE
   HixTU_Check( hCtx, ValType( oGot ) == "O",                    "Throw: RECOVER recibe objeto", "O",              ValType( oGot ) )
   HixTU_Check( hCtx, oGot:Description == "error de prueba",     "Throw: description intacta",   "error de prueba", oGot:Description )
   HixTU_Check( hCtx, oGot:SubSystem == "Test",                  "Throw: subsystem intacto",     "Test",           oGot:SubSystem )
   HixTU_Check( hCtx, oGot:SubCode == 99,                        "Throw: subcode intacto",        "99",             hb_NToS( oGot:SubCode ) )
RETURN

STATIC PROCEDURE _ErrShowError( hCtx, cLogDir )
   LOCAL oErr, oReq
   HIX_ErrorLogInit( cLogDir )
   oErr := HIX_NewError( "fallo interno", "App", 500, "Proceso" )
   oReq := TMockReqErr():New()
   HIX_ShowError( oErr, oReq )
   HixTU_Check( hCtx, oReq:lResponded,             "ShowError: Respond llamado",   ".T.",  hb_CStr( oReq:lResponded ) )
   HixTU_Check( hCtx, oReq:nStatus == 500,         "ShowError: status 500",        "500",  hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, ! Empty( oReq:cBody ),       "ShowError: body no vacio",     "html", iif( Empty(oReq:cBody), "empty", "ok" ) )
   HixTU_Check( hCtx, "fallo interno" $ oReq:cBody,"ShowError: descripcion en HTML","fallo interno", "(no encontrado)" )
   HixTU_Check( hCtx, "500" $ oReq:cBody,          "ShowError: 500 en HTML body",  "500 en body", iif("500" $ oReq:cBody, "si", "no") )
RETURN

STATIC PROCEDURE _ErrErrorLog( hCtx, cLogDir )
   LOCAL oErr, oReq, cLogFile, nBefore, cContent
   HIX_ErrorLogClose()
   HIX_ErrorLogInit( cLogDir )
   cLogFile    := cLogDir + hb_ps() + "errors.log"
   nBefore     := iif( File( cLogFile ), hb_FSize( cLogFile ), 0 )
   oErr        := HIX_NewError( "error para log", "LogTest", 1, "TestLog" )
   oReq        := TMockReqErr():New()
   HIX_ShowError( oErr, oReq )
   cContent    := hb_MemoRead( cLogFile )
   HixTU_Check( hCtx, hb_FSize( cLogFile ) > nBefore,  "ErrLog: entrada escrita",  "> " + hb_NToS(nBefore), hb_NToS(hb_FSize(cLogFile)) )
   HixTU_Check( hCtx, "error para log" $ cContent,      "ErrLog: description en log","error para log", "(ausente)" )
   HixTU_Check( hCtx, "LogTest" $ cContent,             "ErrLog: subsystem en log",  "LogTest", "(ausente)" )
RETURN

STATIC PROCEDURE _ErrExecError( hCtx )
   LOCAL oGot, lHandled
   lHandled := .F. ; oGot := NIL
   BEGIN SEQUENCE WITH {|e| Break(e)}
      HIX_Throw( HIX_NewError( "acceso denegado", "Auth", 403, "CheckPermission" ) )
   RECOVER USING oGot
      lHandled := .T.
   END SEQUENCE
   HixTU_Check( hCtx, lHandled,                           "ExecErr: error capturado", ".T.",            hb_CStr( lHandled ) )
   HixTU_Check( hCtx, oGot:Description == "acceso denegado","ExecErr: description ok", "acceso denegado", oGot:Description )
   HixTU_Check( hCtx, oGot:SubCode == 403,                "ExecErr: subcode 403",     "403",            hb_NToS( oGot:SubCode ) )
RETURN

STATIC PROCEDURE _ErrSystemError( hCtx )
   LOCAL oGot, aArr, lHandled, oReq, xVal
   lHandled := .F. ; oGot := NIL ; aArr := { 1, 2, 3 } ; xVal := NIL
   BEGIN SEQUENCE WITH {|e| Break(e)}
      xVal := aArr[ 99 ]
   RECOVER USING oGot
      lHandled := .T.
   END SEQUENCE
   HB_SYMBOL_UNUSED( xVal )
   HixTU_Check( hCtx, lHandled,                       "SysErr: error nativo capturado",  ".T.",       hb_CStr( lHandled ) )
   HixTU_Check( hCtx, ValType( oGot ) == "O",         "SysErr: es objeto Error",         "O",         ValType( oGot ) )
   HixTU_Check( hCtx, ! Empty( oGot:Description ),    "SysErr: tiene description",       "non-empty", iif( Empty(oGot:Description), "empty", "ok" ) )
   oReq := TMockReqErr():New()
   HIX_ShowError( oGot, oReq )
   HixTU_Check( hCtx, oReq:nStatus == 500,            "SysErr: ShowError acepta nativo", "500",       hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, ! Empty( oReq:cBody ),          "SysErr: HTML generado",           "html",      iif( Empty(oReq:cBody), "empty", "ok" ) )
RETURN
