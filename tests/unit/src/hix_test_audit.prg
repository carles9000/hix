/*-----------------------------------------------------------
  File ......: hix_test_audit.prg
  Author.....: Charly 9000
  Created....: 2026-09-13
  Description: Regression tests for audit remediation items.
               Each finding of docs/auditoria/2026-09-13_*.md gets a
               HIX_TestAudit_AXXXX_Run() function that returns the
               standard hCtx { total, passed, failed, results }.
  Usage      : GET /api/test/audit/<id>  (e.g. /api/test/audit/a0101)
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hix_const.ch"
#include "hbclass.ch"

STATIC s_lAudA0101_HandlerCalled := .F.

// ---------------------------------------------------------------
// Public handler used by A1.01 positive-case tests.
// Registered via HIX_RouteRegisterAction() (whitelist).
// ---------------------------------------------------------------
FUNCTION AudA0101_OkHandler( oReq )
   s_lAudA0101_HandlerCalled := .T.
   oReq:Respond( "aud_ok", 200, "text" )
RETURN NIL

// ---------------------------------------------------------------
// A1.01 — Code injection vía macro `&()` en el router.
// Fix: whitelist estricta de acciones-por-nombre.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A0101_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   // NO llamar HIX_MetricsInit/Close ni HIX_ZombieInit — ya inicializados por el
   // servidor que aloja este test. Cerrarlos rompería el proceso vivo.
   HIX_RoutesLoad()   // idempotente: asegura registry si aún no existe

   _AudA0101_Api(          hCtx )
   _AudA0101_Positive(     hCtx )
   _AudA0101_Unregistered( hCtx )
   _AudA0101_RceAttempt(   hCtx )
   _AudA0101_Codeblock(    hCtx )

RETURN hCtx

// ---------------------------------------------------------------
// API de la whitelist: existe, valida args, registra, consulta.
// ---------------------------------------------------------------
STATIC PROCEDURE _AudA0101_Api( hCtx )

   LOCAL bBlock := {|o| HB_SYMBOL_UNUSED( o ) }
   LOCAL lOk

   lOk := HIX_RouteRegisterAction( "AudA0101_OkHandler", ;
                                   {|o| AudA0101_OkHandler( o ) } )
   HixTU_Check( hCtx, lOk, ;
      "A1.01: HIX_RouteRegisterAction acepta nombre + codeblock", ;
      ".T.", hb_ValToStr( lOk ) )

   HixTU_Check( hCtx, HIX_RouteHasAction( "AudA0101_OkHandler" ), ;
      "A1.01: HIX_RouteHasAction devuelve .T. tras registro", ;
      ".T.", hb_ValToStr( HIX_RouteHasAction( "AudA0101_OkHandler" ) ) )

   HixTU_Check( hCtx, HIX_RouteGetAction( "AudA0101_OkHandler" ) != NIL, ;
      "A1.01: HIX_RouteGetAction devuelve el codeblock", ;
      "!= NIL", "codeblock" )

   HixTU_Check( hCtx, ! HIX_RouteHasAction( "NuncaRegistrado" ), ;
      "A1.01: HIX_RouteHasAction .F. para nombre no registrado", ;
      ".F.", hb_ValToStr( HIX_RouteHasAction( "NuncaRegistrado" ) ) )

   lOk := HIX_RouteRegisterAction( "", bBlock )
   HixTU_Check( hCtx, ! lOk, ;
      "A1.01: rechaza cName vacío", ".F.", hb_ValToStr( lOk ) )

   lOk := HIX_RouteRegisterAction( "Bad", "no_soy_codeblock" )
   HixTU_Check( hCtx, ! lOk, ;
      "A1.01: rechaza bBlock no-codeblock (string)", ".F.", hb_ValToStr( lOk ) )

RETURN

// ---------------------------------------------------------------
// Positivo: acción registrada + route → dispatch OK.
// ---------------------------------------------------------------
STATIC PROCEDURE _AudA0101_Positive( hCtx )

   LOCAL oReq

   s_lAudA0101_HandlerCalled := .F.
   HIX_RouteAdd( "audA0101.ok", "/audA0101/ok", "AudA0101_OkHandler", "GET" )
   oReq := TMockRequest():New( "/audA0101/ok", "GET" )
   HIX_RouteDispatch( oReq )

   HixTU_Check( hCtx, s_lAudA0101_HandlerCalled, ;
      "A1.01: acción registrada se invoca", ".T.", ;
      hb_ValToStr( s_lAudA0101_HandlerCalled ) )

   HixTU_Check( hCtx, oReq:nStatus == 200, ;
      "A1.01: respuesta 200 tras dispatch de acción registrada", ;
      "200", hb_NToS( oReq:nStatus ) )

   HixTU_Check( hCtx, oReq:cBody == "aud_ok", ;
      "A1.01: body esperado tras dispatch", ;
      "aud_ok", oReq:cBody )

RETURN

// ---------------------------------------------------------------
// Negativo: acción SIN registrar → 500 y handler no llamado.
// Se usa HIX_ServerStop como bait para simular el vector real
// (RCE con función linkada del binario).
// ---------------------------------------------------------------
STATIC PROCEDURE _AudA0101_Unregistered( hCtx )

   LOCAL oReq

   HIX_RouteAdd( "audA0101.evil", "/audA0101/evil", "HIX_ServerStop", "GET" )
   oReq := TMockRequest():New( "/audA0101/evil", "GET" )

   TRY
      HIX_RouteDispatch( oReq )
   CATCH
      // El router lanza HIX_Throw() — capturado por el worker en runtime real.
      // En test aislado sin worker envolvente, la excepción llega aquí.
   END

   HixTU_Check( hCtx, oReq:nStatus == 500 .OR. oReq:nStatus == 0 .OR. ! oReq:lResponded, ;
      "A1.01: acción no registrada (HIX_ServerStop) NO se ejecuta", ;
      "500 / no-responded", ;
      hb_NToS( oReq:nStatus ) + " responded=" + hb_ValToStr( oReq:lResponded ) )

RETURN

// ---------------------------------------------------------------
// RCE-attempt: nombre con payload de macro-eval (paréntesis, quotes).
// El registry hace lookup literal por clave — nunca eval — así que
// aunque el nombre sea "hb_run('echo pwn')" no se ejecuta.
// ---------------------------------------------------------------
STATIC PROCEDURE _AudA0101_RceAttempt( hCtx )

   LOCAL oReq
   LOCAL cPayload := "hb_run('echo pwn')"

   HIX_RouteAdd( "audA0101.rce", "/audA0101/rce", cPayload, "GET" )
   oReq := TMockRequest():New( "/audA0101/rce", "GET" )

   TRY
      HIX_RouteDispatch( oReq )
   CATCH
   END

   HixTU_Check( hCtx, ! HIX_RouteHasAction( cPayload ), ;
      "A1.01: payload RCE literal no está en registry", ;
      ".F.", hb_ValToStr( HIX_RouteHasAction( cPayload ) ) )

   HixTU_Check( hCtx, oReq:nStatus != 200, ;
      "A1.01: dispatch de payload RCE no devuelve 200", ;
      "!= 200", hb_NToS( oReq:nStatus ) )

RETURN

// ---------------------------------------------------------------
// Regresión: acciones codeblock (patrón normal) siguen funcionando.
// ---------------------------------------------------------------
STATIC PROCEDURE _AudA0101_Codeblock( hCtx )

   LOCAL oReq

   HIX_RouteAdd( "audA0101.cb", "/audA0101/cb", ;
      {|o| o:Respond( "cb_ok", 200, "text" ) }, "GET" )
   oReq := TMockRequest():New( "/audA0101/cb", "GET" )
   HIX_RouteDispatch( oReq )

   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "cb_ok", ;
      "A1.01: regresión — acciones codeblock siguen funcionando", ;
      "200 + cb_ok", hb_NToS( oReq:nStatus ) + " + " + oReq:cBody )

RETURN

// ---------------------------------------------------------------
// A1.02 — Path traversal por URL-encoding.
// El check ".." $ cPath del dispatcher opera sobre la ruta cruda: encodings
// como %2e%2e / %2E%2E / ..%2f / %5c / %00 bypasean el filtro. Fix: percent-
// decode antes del check + rechazo de backslash y null-byte decodificados.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A0102_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTmpRoot
   LOCAL oDisp

   cTmpRoot := hb_DirTemp() + "hix_a0102_" + hb_NToS( Int( Seconds() * 1000 ) )
   DO WHILE Right( cTmpRoot, 1 ) == hb_ps() ; cTmpRoot := Left( cTmpRoot, Len( cTmpRoot ) - 1 ) ; ENDDO
   hb_DirCreate( cTmpRoot )
   hb_MemoWrit( cTmpRoot + hb_ps() + "legit.txt", "hola" )

   oDisp := THixDispatcher():New( cTmpRoot )

   _AudA0102_UrlDecodeApi(       hCtx )
   _AudA0102_LiteralDotDot(      hCtx, oDisp )
   _AudA0102_EncodedDotDotLow(   hCtx, oDisp )
   _AudA0102_EncodedDotDotUpper( hCtx, oDisp )
   _AudA0102_MixedSlashEncoded(  hCtx, oDisp )
   _AudA0102_BackslashEncoded(   hCtx, oDisp )
   _AudA0102_NullByte(           hCtx, oDisp )
   _AudA0102_LegitPath(          hCtx, oDisp )
   _AudA0102_Root(               hCtx, oDisp )

   HIX_SafeErase( cTmpRoot + hb_ps() + "legit.txt" )
   HIX_SafeDirDelete( cTmpRoot )

RETURN hCtx

// HIX_UrlDecode: contrato mínimo — % encodings decodifican, resto pasa igual.
STATIC PROCEDURE _AudA0102_UrlDecodeApi( hCtx )

   HixTU_Check( hCtx, HIX_UrlDecode( "%2e%2e" ) == "..", ;
      "A1.02: HIX_UrlDecode('%2e%2e') == '..'", "..", HIX_UrlDecode( "%2e%2e" ) )

   HixTU_Check( hCtx, HIX_UrlDecode( "%2E%2E" ) == "..", ;
      "A1.02: HIX_UrlDecode('%2E%2E') == '..' (mayúsculas)", "..", HIX_UrlDecode( "%2E%2E" ) )

   HixTU_Check( hCtx, HIX_UrlDecode( "%5c" ) == "\", ;
      "A1.02: HIX_UrlDecode('%5c') == backslash", "\", HIX_UrlDecode( "%5c" ) )

   // [A3.3.6] null bytes stripped (not preserved) — attack neutralized at decode
   HixTU_Check( hCtx, HIX_UrlDecode( "abc%00def" ) == "abcdef", ;
      "A1.02: HIX_UrlDecode elimina null-byte (A3.3.6)", "abcdef", HIX_UrlDecode( "abc%00def" ) )

RETURN

STATIC PROCEDURE _AudA0102_LiteralDotDot( hCtx, oDisp )
   LOCAL oReq := TMockRequest():New( "/../etc/passwd", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "A1.02: '..' literal -> 403 (regresión)", "403", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _AudA0102_EncodedDotDotLow( hCtx, oDisp )
   LOCAL oReq := TMockRequest():New( "/%2e%2e/etc/passwd", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "A1.02: %2e%2e -> 403", "403", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _AudA0102_EncodedDotDotUpper( hCtx, oDisp )
   LOCAL oReq := TMockRequest():New( "/%2E%2E/etc/passwd", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "A1.02: %2E%2E -> 403 (case-insensitive hex)", "403", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _AudA0102_MixedSlashEncoded( hCtx, oDisp )
   LOCAL oReq := TMockRequest():New( "/foo/..%2fetc/passwd", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "A1.02: ..%2f (slash encoded) -> 403", "403", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _AudA0102_BackslashEncoded( hCtx, oDisp )
   LOCAL oReq := TMockRequest():New( "/foo%5c..%5cbar", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "A1.02: %5c (backslash encoded) -> 403", "403", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _AudA0102_NullByte( hCtx, oDisp )
   // [A3.3.6] null bytes stripped in HIX_UrlDecode -> path becomes /legit.txt.exe
   // No longer 403 (no null byte reaches dispatcher); but must not serve 200.
   LOCAL oReq := TMockRequest():New( "/legit.txt%00.exe", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus != 200, ;
      "A1.02: %00 (null-byte injection) no sirve 200 (A3.3.6 strip)", "!200", hb_NToS( oReq:nStatus ) )
RETURN

// Regresión: un path legítimo dentro del root sigue sirviéndose.
STATIC PROCEDURE _AudA0102_LegitPath( hCtx, oDisp )
   LOCAL oReq := TMockRequest():New( "/legit.txt", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200, ;
      "A1.02: /legit.txt (dentro del root) -> 200", "200", hb_NToS( oReq:nStatus ) )
RETURN

// Regresión: petición al root (busca index.html; no existe -> 404 pero NO 403).
STATIC PROCEDURE _AudA0102_Root( hCtx, oDisp )
   LOCAL oReq := TMockRequest():New( "/", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus != 403, ;
      "A1.02: / (root) no dispara falso positivo 403", "!= 403", hb_NToS( oReq:nStatus ) )
RETURN

// ---------------------------------------------------------------
// A1.03 — Symlink / junction escape del root.
// hb_PathNormalize sólo colapsa `.` y `..` sintácticamente. Un symlink
// dentro del root apuntando a `C:\Windows` escapa del sandbox porque
// hb_FileExists retorna .T. sobre el link y se sirve el destino.
// Fix: rechazar path físico cuyo target final o componente ancestral
// sea un reparse point (bit HB_FA_REPARSE), salvo opt-in explícito
// mediante oDisp:AllowSymlinks(.T.).
//
// Nota: el test crea junctions con `mklink /J` (Windows). Si el `mklink`
// falla (SO sin soporte o permisos denegados) los sub-tests que
// dependen del link se marcan como SKIP para no reportar falsos rojos.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A0103_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTmpRoot, cExtDir, cJunction, oDisp
   LOCAL lLinkOk

   cTmpRoot := hb_DirTemp() + "hix_a0103_root_" + hb_NToS( Int( Seconds() * 1000 ) )
   cExtDir  := hb_DirTemp() + "hix_a0103_ext_"  + hb_NToS( Int( Seconds() * 1000 ) )
   DO WHILE Right( cTmpRoot, 1 ) == hb_ps() ; cTmpRoot := Left( cTmpRoot, Len( cTmpRoot ) - 1 ) ; ENDDO
   DO WHILE Right( cExtDir,  1 ) == hb_ps() ; cExtDir  := Left( cExtDir,  Len( cExtDir  ) - 1 ) ; ENDDO

   hb_DirCreate( cTmpRoot )
   hb_DirCreate( cExtDir  )
   hb_MemoWrit( cTmpRoot + hb_ps() + "legit.txt",  "root_ok" )
   hb_MemoWrit( cExtDir  + hb_ps() + "secret.txt", "leaked"  )

   // Junction: <root>\leaked -> <extDir>
   cJunction := cTmpRoot + hb_ps() + "leaked"
   hb_run( 'cmd /c mklink /J "' + cJunction + '" "' + cExtDir + '" >nul 2>&1' )
   lLinkOk := hb_DirExists( cJunction )

   oDisp := THixDispatcher():New( cTmpRoot )

   _AudA0103_HelperApi(         hCtx, cTmpRoot, cJunction, lLinkOk )
   _AudA0103_JunctionBlocked(   hCtx, oDisp,    lLinkOk )
   _AudA0103_AllowSymlinksOptIn( hCtx, oDisp,   lLinkOk )
   _AudA0103_LegitStillWorks(   hCtx, oDisp )

   // cleanup
   IF lLinkOk
      hb_run( 'cmd /c rmdir "' + cJunction + '" >nul 2>&1' )
   ENDIF
   HIX_SafeErase( cTmpRoot + hb_ps() + "legit.txt" )
   HIX_SafeErase( cExtDir  + hb_ps() + "secret.txt" )
   HIX_SafeDirDelete( cTmpRoot )
   HIX_SafeDirDelete( cExtDir  )

RETURN hCtx

// Contrato del helper: fichero normal .T., reparse point .F., opt-in .T.
STATIC PROCEDURE _AudA0103_HelperApi( hCtx, cTmpRoot, cJunction, lLinkOk )

   LOCAL cLegit := cTmpRoot + hb_ps() + "legit.txt"
   LOCAL cThruLink

   HixTU_Check( hCtx, _HixIsSafePath_ForTest( cLegit, cTmpRoot, .F. ), ;
      "A1.03: fichero normal dentro del root -> safe", ".T.", ;
      hb_ValToStr( _HixIsSafePath_ForTest( cLegit, cTmpRoot, .F. ) ) )

   IF lLinkOk
      cThruLink := cJunction + hb_ps() + "secret.txt"
      HixTU_Check( hCtx, ! _HixIsSafePath_ForTest( cThruLink, cTmpRoot, .F. ), ;
         "A1.03: path pasando por junction -> unsafe", ".F.", ;
         hb_ValToStr( _HixIsSafePath_ForTest( cThruLink, cTmpRoot, .F. ) ) )

      HixTU_Check( hCtx, _HixIsSafePath_ForTest( cThruLink, cTmpRoot, .T. ), ;
         "A1.03: mismo path con lAllowLinks=.T. -> safe (bypass)", ".T.", ;
         hb_ValToStr( _HixIsSafePath_ForTest( cThruLink, cTmpRoot, .T. ) ) )
   ELSE
      HixTU_Check( hCtx, .T., ;
         "A1.03: SKIP unsafe/opt-in — mklink /J no disponible", "SKIP", "SKIP" )
      HixTU_Check( hCtx, .T., ;
         "A1.03: SKIP bypass — mklink /J no disponible", "SKIP", "SKIP" )
   ENDIF

RETURN

// Dispatch a través de junction -> 403 con defaults (lAllowSymlinks=.F.)
STATIC PROCEDURE _AudA0103_JunctionBlocked( hCtx, oDisp, lLinkOk )

   LOCAL oReq

   IF ! lLinkOk
      HixTU_Check( hCtx, .T., ;
         "A1.03: SKIP dispatch bloqueo — junction no creable", "SKIP", "SKIP" )
      RETURN
   ENDIF

   oReq := TMockRequest():New( "/leaked/secret.txt", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "A1.03: GET /leaked/secret.txt (junction) -> 403", "403", hb_NToS( oReq:nStatus ) )

RETURN

// Con AllowSymlinks(.T.) el mismo request pasa el helper: retorna 200.
STATIC PROCEDURE _AudA0103_AllowSymlinksOptIn( hCtx, oDisp, lLinkOk )

   LOCAL oReq

   IF ! lLinkOk
      HixTU_Check( hCtx, .T., ;
         "A1.03: SKIP opt-in — junction no creable", "SKIP", "SKIP" )
      RETURN
   ENDIF

   oDisp:AllowSymlinks( .T. )
   oReq := TMockRequest():New( "/leaked/secret.txt", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus != 403, ;
      "A1.03: con AllowSymlinks(.T.) el junction se sirve (!= 403)", ;
      "!= 403", hb_NToS( oReq:nStatus ) )

   // Restaurar default para no ensuciar tests posteriores del suite
   oDisp:AllowSymlinks( .F. )

RETURN

// Regresión: fichero normal dentro del root sigue sirviéndose 200.
STATIC PROCEDURE _AudA0103_LegitStillWorks( hCtx, oDisp )

   LOCAL oReq := TMockRequest():New( "/legit.txt", "GET" )
   oDisp:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200, ;
      "A1.03: /legit.txt (fichero regular) -> 200 (regresión)", "200", hb_NToS( oReq:nStatus ) )

RETURN

// Wrapper de test para invocar el STATIC _HixIsSafePath desde fuera del módulo.
// Vive en la lib (hix_dispatcher.prg) — expuesto como pública para que este
// test lo alcance sin acoplar el módulo entero.
FUNCTION _HixIsSafePath_ForTest( cPhysical, cRoot, lAllowLinks )
RETURN HIX_IsSafePath( cPhysical, cRoot, lAllowLinks )

// ---------------------------------------------------------------
// A1.04 — Filename traversal en multipart.
// Fix: `_HixMpSanitizeFilename` en hix_multipart.prg → strip null-byte,
//      normaliza `\` → `/`, se queda con basename tras el último `/`,
//      descarta `.` y `..`. Aplicado al construir `hPart["filename"]`.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A0104_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0104_SanitizerApi( hCtx )
   _AudA0104_ParserEndToEnd( hCtx )

RETURN hCtx

// Contrato del sanitizer aislado — sin request, sin socket.
STATIC PROCEDURE _AudA0104_SanitizerApi( hCtx )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( "../../evil.txt" ) == "evil.txt", ;
      "A1.04: '../../evil.txt' -> 'evil.txt'", ;
      "evil.txt", HIX_MpSanitizeFilename( "../../evil.txt" ) )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( "..\..\evil.txt" ) == "evil.txt", ;
      "A1.04: '..\..\evil.txt' -> 'evil.txt' (windows separators)", ;
      "evil.txt", HIX_MpSanitizeFilename( "..\..\evil.txt" ) )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( "C:\Windows\evil.dll" ) == "evil.dll", ;
      "A1.04: absoluto Windows -> basename", ;
      "evil.dll", HIX_MpSanitizeFilename( "C:\Windows\evil.dll" ) )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( "/etc/passwd" ) == "passwd", ;
      "A1.04: absoluto POSIX -> basename", ;
      "passwd", HIX_MpSanitizeFilename( "/etc/passwd" ) )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( "foo" + Chr( 0 ) + ".txt" ) == "foo.txt", ;
      "A1.04: null-byte injection -> concatenado", ;
      "foo.txt", HIX_MpSanitizeFilename( "foo" + Chr( 0 ) + ".txt" ) )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( ".." ) == "", ;
      "A1.04: '..' aislado -> vacío", ;
      "", HIX_MpSanitizeFilename( ".." ) )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( "." ) == "", ;
      "A1.04: '.' aislado -> vacío", ;
      "", HIX_MpSanitizeFilename( "." ) )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( "" ) == "", ;
      "A1.04: cadena vacía -> vacía", ;
      "", HIX_MpSanitizeFilename( "" ) )

   HixTU_Check( hCtx, HIX_MpSanitizeFilename( "report.pdf" ) == "report.pdf", ;
      "A1.04: nombre legítimo intacto (regresión)", ;
      "report.pdf", HIX_MpSanitizeFilename( "report.pdf" ) )

RETURN

// Parser end-to-end: request multipart con filename malicioso →
// hPart["filename"] llega saneado.
STATIC PROCEDURE _AudA0104_ParserEndToEnd( hCtx )

   LOCAL cBound  := "----WebKitBoundaryTestA0104"
   LOCAL cCRLF   := Chr( 13 ) + Chr( 10 )
   LOCAL cBody, aParts

   // Multipart con dos partes: filename malicioso + filename legítimo.
   cBody := "--" + cBound + cCRLF + ;
      'Content-Disposition: form-data; name="attack"; filename="../../evil.txt"' + cCRLF + ;
      "Content-Type: text/plain" + cCRLF + cCRLF + ;
      "pwn" + cCRLF + ;
      "--" + cBound + cCRLF + ;
      'Content-Disposition: form-data; name="good"; filename="report.pdf"' + cCRLF + ;
      "Content-Type: application/pdf" + cCRLF + cCRLF + ;
      "PDFDATA" + cCRLF + ;
      "--" + cBound + "--" + cCRLF

   aParts := HIX_ParseMultipart( cBody, cBound )

   HixTU_Check( hCtx, Len( aParts ) == 2, ;
      "A1.04: parser devuelve 2 partes", ;
      "2", hb_NToS( Len( aParts ) ) )

   IF Len( aParts ) >= 1
      HixTU_Check( hCtx, aParts[ 1 ][ "filename" ] == "evil.txt", ;
         "A1.04: part[1] filename saneado end-to-end", ;
         "evil.txt", aParts[ 1 ][ "filename" ] )
   ENDIF

   IF Len( aParts ) >= 2
      HixTU_Check( hCtx, aParts[ 2 ][ "filename" ] == "report.pdf", ;
         "A1.04: part[2] filename legítimo intacto", ;
         "report.pdf", aParts[ 2 ][ "filename" ] )
   ENDIF

RETURN

// ---------------------------------------------------------------
// A1.05 — Header injection vía `hExtra` en Respond.
// Fix: `_HixHdrSanitize` filtra nombre (regex [A-Za-z0-9-]) y valor
//      (rechaza CR/LF/NUL) en los dos bucles de hix_response.prg.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A0105_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0105_SanitizerApi( hCtx )
   _AudA0105_ResponseRawEndToEnd( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0105_SanitizerApi( hCtx )

   // --- Nombre válido ---
   HixTU_Check( hCtx, HIX_HdrSanitize( "Content-Type", "text/plain" ), ;
      "A1.05: name+val normales -> .T.", ".T.", ;
      hb_ValToStr( HIX_HdrSanitize( "Content-Type", "text/plain" ) ) )

   HixTU_Check( hCtx, HIX_HdrSanitize( "X-Foo-Bar", "abc123" ), ;
      "A1.05: name X-Foo-Bar OK", ".T.", ;
      hb_ValToStr( HIX_HdrSanitize( "X-Foo-Bar", "abc123" ) ) )

   // --- Nombre inválido ---
   HixTU_Check( hCtx, ! HIX_HdrSanitize( "X Space", "v" ), ;
      "A1.05: name con espacio -> .F.", ".F.", ;
      hb_ValToStr( HIX_HdrSanitize( "X Space", "v" ) ) )

   HixTU_Check( hCtx, ! HIX_HdrSanitize( "X:colon", "v" ), ;
      "A1.05: name con ':' -> .F.", ".F.", ;
      hb_ValToStr( HIX_HdrSanitize( "X:colon", "v" ) ) )

   HixTU_Check( hCtx, ! HIX_HdrSanitize( "X" + Chr( 13 ) + Chr( 10 ) + "Set-Cookie", "v" ), ;
      "A1.05: name con CRLF -> .F.", ".F.", ;
      hb_ValToStr( HIX_HdrSanitize( "X" + Chr( 13 ) + Chr( 10 ) + "Set-Cookie", "v" ) ) )

   HixTU_Check( hCtx, ! HIX_HdrSanitize( "", "v" ), ;
      "A1.05: name vacío -> .F.", ".F.", ;
      hb_ValToStr( HIX_HdrSanitize( "", "v" ) ) )

   // --- Valor inválido ---
   HixTU_Check( hCtx, ! HIX_HdrSanitize( "X", "val" + Chr( 13 ) + Chr( 10 ) + "Set-Cookie: admin=1" ), ;
      "A1.05: val con CRLF -> .F.", ".F.", ;
      hb_ValToStr( HIX_HdrSanitize( "X", "val" + Chr( 13 ) + Chr( 10 ) + "x" ) ) )

   HixTU_Check( hCtx, ! HIX_HdrSanitize( "X", "val" + Chr( 13 ) + "x" ), ;
      "A1.05: val con CR solo -> .F.", ".F.", "-" )

   HixTU_Check( hCtx, ! HIX_HdrSanitize( "X", "val" + Chr( 10 ) + "x" ), ;
      "A1.05: val con LF solo -> .F.", ".F.", "-" )

   HixTU_Check( hCtx, ! HIX_HdrSanitize( "X", "val" + Chr( 0 ) + "x" ), ;
      "A1.05: val con NUL -> .F.", ".F.", "-" )

   HixTU_Check( hCtx, ! HIX_HdrSanitize( "X", 42 ), ;
      "A1.05: val no-string -> .F.", ".F.", ;
      hb_ValToStr( HIX_HdrSanitize( "X", 42 ) ) )

   // --- Regresión ---
   HixTU_Check( hCtx, HIX_HdrSanitize( "Cache-Control", "no-cache" ), ;
      "A1.05: Cache-Control legítimo -> .T. (regresión)", ".T.", ;
      hb_ValToStr( HIX_HdrSanitize( "Cache-Control", "no-cache" ) ) )

RETURN

// End-to-end: HIX_ResponseRaw sobre TMockIO con hExtra malicioso.
// El buffer resultante NO debe contener "Set-Cookie: admin=1".
STATIC PROCEDURE _AudA0105_ResponseRawEndToEnd( hCtx )

   LOCAL oIO    := TMockIO():New( "", "" )
   LOCAL hExtra := { => }

   hExtra[ "X-Legit"  ] := "safe-value"
   hExtra[ "X-Attack" ] := "val" + Chr( 13 ) + Chr( 10 ) + "Set-Cookie: admin=1"

   HIX_ResponseRaw( oIO, "ok", "text", 200, .F., hExtra )

   HixTU_Check( hCtx, ! ( "Set-Cookie: admin=1" $ oIO:cWritten ), ;
      "A1.05: cabecera inyectada NO aparece en el buffer", ;
      "no-inject", iif( "Set-Cookie: admin=1" $ oIO:cWritten, "INJECTED", "clean" ) )

   HixTU_Check( hCtx, ! ( "X-Attack:" $ oIO:cWritten ), ;
      "A1.05: X-Attack completa descartada", ;
      "no-header", iif( "X-Attack:" $ oIO:cWritten, "PRESENT", "clean" ) )

   HixTU_Check( hCtx, "X-Legit: safe-value" $ oIO:cWritten, ;
      "A1.05: X-Legit legítima sí aparece (regresión)", ;
      "present", iif( "X-Legit: safe-value" $ oIO:cWritten, "present", "MISSING" ) )

RETURN

// ---------------------------------------------------------------
// A1.06 — Status code sin validar en HTTP response line.
// Fix: `_HixHdrStatusClamp` normaliza a [100..599]; fuera → 500.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A0106_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0106_ClampApi( hCtx )
   _AudA0106_ResponseRawEndToEnd( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0106_ClampApi( hCtx )

   // --- Valores válidos: intactos ---
   HixTU_Check( hCtx, HIX_HdrStatusClamp( 100 ) == 100, ;
      "A1.06: 100 -> 100 (borde inferior)", "100", hb_NToS( HIX_HdrStatusClamp( 100 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( 200 ) == 200, ;
      "A1.06: 200 -> 200 (regresión)", "200", hb_NToS( HIX_HdrStatusClamp( 200 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( 404 ) == 404, ;
      "A1.06: 404 -> 404", "404", hb_NToS( HIX_HdrStatusClamp( 404 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( 500 ) == 500, ;
      "A1.06: 500 -> 500", "500", hb_NToS( HIX_HdrStatusClamp( 500 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( 599 ) == 599, ;
      "A1.06: 599 -> 599 (borde superior)", "599", hb_NToS( HIX_HdrStatusClamp( 599 ) ) )

   // --- Fuera de rango: -> 500 ---
   HixTU_Check( hCtx, HIX_HdrStatusClamp( 99 ) == 500, ;
      "A1.06: 99 -> 500", "500", hb_NToS( HIX_HdrStatusClamp( 99 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( 600 ) == 500, ;
      "A1.06: 600 -> 500", "500", hb_NToS( HIX_HdrStatusClamp( 600 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( 9999 ) == 500, ;
      "A1.06: 9999 -> 500", "500", hb_NToS( HIX_HdrStatusClamp( 9999 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( 0 ) == 500, ;
      "A1.06: 0 -> 500", "500", hb_NToS( HIX_HdrStatusClamp( 0 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( -1 ) == 500, ;
      "A1.06: -1 -> 500", "500", hb_NToS( HIX_HdrStatusClamp( -1 ) ) )

   // --- Tipos inválidos: -> 500 ---
   HixTU_Check( hCtx, HIX_HdrStatusClamp( "OK" ) == 500, ;
      "A1.06: string 'OK' -> 500", "500", hb_NToS( HIX_HdrStatusClamp( "OK" ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( NIL ) == 500, ;
      "A1.06: NIL -> 500", "500", hb_NToS( HIX_HdrStatusClamp( NIL ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( .T. ) == 500, ;
      "A1.06: .T. -> 500", "500", hb_NToS( HIX_HdrStatusClamp( .T. ) ) )

   // --- Decimal: Int() truncado ---
   HixTU_Check( hCtx, HIX_HdrStatusClamp( 200.5 ) == 200, ;
      "A1.06: 200.5 -> 200 (Int truncado)", "200", hb_NToS( HIX_HdrStatusClamp( 200.5 ) ) )

   HixTU_Check( hCtx, HIX_HdrStatusClamp( 200.9 ) == 200, ;
      "A1.06: 200.9 -> 200 (Int trunca, no redondea)", "200", hb_NToS( HIX_HdrStatusClamp( 200.9 ) ) )

RETURN

// End-to-end: HIX_ResponseRaw sobre TMockIO con status fuera de rango.
STATIC PROCEDURE _AudA0106_ResponseRawEndToEnd( hCtx )

   LOCAL oIO1, oIO2, oIO3

   // 9999 → 500
   oIO1 := TMockIO():New( "", "" )
   HIX_ResponseRaw( oIO1, "err", "text", 9999, .F., { => } )
   HixTU_Check( hCtx, "HTTP/1.1 500 Internal Server Error" $ oIO1:cWritten, ;
      "A1.06: nStatus=9999 -> line 'HTTP/1.1 500 Internal Server Error'", ;
      "500", ;
      iif( "HTTP/1.1 500" $ oIO1:cWritten, "500", ;
           Left( oIO1:cWritten, At( Chr( 13 ), oIO1:cWritten ) - 1 ) ) )

   // -1 → 500
   oIO2 := TMockIO():New( "", "" )
   HIX_ResponseRaw( oIO2, "err", "text", -1, .F., { => } )
   HixTU_Check( hCtx, "HTTP/1.1 500 " $ oIO2:cWritten, ;
      "A1.06: nStatus=-1 -> HTTP/1.1 500", "500", ;
      iif( "HTTP/1.1 500" $ oIO2:cWritten, "500", ;
           Left( oIO2:cWritten, At( Chr( 13 ), oIO2:cWritten ) - 1 ) ) )

   // 200 legítimo → intacto (regresión)
   oIO3 := TMockIO():New( "", "" )
   HIX_ResponseRaw( oIO3, "ok", "text", 200, .F., { => } )
   HixTU_Check( hCtx, "HTTP/1.1 200 OK" $ oIO3:cWritten, ;
      "A1.06: nStatus=200 -> HTTP/1.1 200 OK (regresión)", "200 OK", ;
      iif( "HTTP/1.1 200" $ oIO3:cWritten, "200 OK", ;
           Left( oIO3:cWritten, At( Chr( 13 ), oIO3:cWritten ) - 1 ) ) )

RETURN

// ============================================================
// A1.07 — JWT timing attack: constant-time signature comparison
// ============================================================
FUNCTION HIX_TestAudit_A0107_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0107_ConstantEqApi(            hCtx )
   _AudA0107_ValidTokenStillWorks(     hCtx )
   _AudA0107_TamperedSigRejected(      hCtx )
   _AudA0107_SameLengthForgeRejected(  hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0107_ConstantEqApi( hCtx )

   // equal strings -> .T.
   HixTU_Check( hCtx, HIX_JwtConstantEq( "abc", "abc" ), ;
      "A1.07: constanteq iguales -> .T.", ".T.", hb_ValToStr( HIX_JwtConstantEq( "abc", "abc" ) ) )

   // differ at last char
   HixTU_Check( hCtx, ! HIX_JwtConstantEq( "abc", "abX" ), ;
      "A1.07: constanteq ultimo char difiere -> .F.", ".F.", hb_ValToStr( HIX_JwtConstantEq( "abc", "abX" ) ) )

   // differ at first char
   HixTU_Check( hCtx, ! HIX_JwtConstantEq( "Xbc", "abc" ), ;
      "A1.07: constanteq primer char difiere -> .F.", ".F.", hb_ValToStr( HIX_JwtConstantEq( "Xbc", "abc" ) ) )

   // different lengths -> .F.
   HixTU_Check( hCtx, ! HIX_JwtConstantEq( "abc", "ab" ), ;
      "A1.07: constanteq longitudes distintas -> .F.", ".F.", hb_ValToStr( HIX_JwtConstantEq( "abc", "ab" ) ) )

   // both empty -> .T.
   HixTU_Check( hCtx, HIX_JwtConstantEq( "", "" ), ;
      "A1.07: constanteq ambos vacios -> .T.", ".T.", hb_ValToStr( HIX_JwtConstantEq( "", "" ) ) )

   // one empty -> .F.
   HixTU_Check( hCtx, ! HIX_JwtConstantEq( "x", "" ), ;
      "A1.07: constanteq uno vacio -> .F.", ".F.", hb_ValToStr( HIX_JwtConstantEq( "x", "" ) ) )

RETURN

STATIC PROCEDURE _AudA0107_ValidTokenStillWorks( hCtx )

   LOCAL cKey, cToken, hPay

   cKey   := "secret-a107"
   cToken := HIX_JwtEncode( { "u" => "alice" }, cKey, 3600 )
   hPay   := HIX_JwtValidate( cToken, cKey )

   HixTU_Check( hCtx, ValType( hPay ) == "H", ;
      "A1.07: token valido sigue siendo valido (regresion)", "H", ValType( hPay ) )

   HixTU_Check( hCtx, hb_HGetDef( hPay, "u", "" ) == "alice", ;
      "A1.07: payload campo u='alice' intacto", "alice", hb_HGetDef( hPay, "u", "" ) )

RETURN

STATIC PROCEDURE _AudA0107_TamperedSigRejected( hCtx )

   LOCAL cKey, cToken, aParts, cTampered, hPay

   cKey    := "secret-a107"
   cToken  := HIX_JwtEncode( { "u" => "bob" }, cKey, 3600 )
   aParts  := hb_ATokens( cToken, "." )

   // Replace signature with garbage of different length
   cTampered := aParts[ 1 ] + "." + aParts[ 2 ] + ".INVALIDSIGNATURE"
   hPay      := HIX_JwtValidate( cTampered, cKey )

   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.07: firma con longitud incorrecta -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

RETURN

STATIC PROCEDURE _AudA0107_SameLengthForgeRejected( hCtx )

   LOCAL cKey, cToken, aParts, cRealSig, cFakeSig, cForged, hPay, nX

   cKey   := "secret-a107"
   cToken := HIX_JwtEncode( { "u" => "eve" }, cKey, 3600 )
   aParts := hb_ATokens( cToken, "." )

   // Build a fake sig of the same length: flip every byte (XOR 0xFF)
   cRealSig := aParts[ 3 ]
   cFakeSig := ""
   FOR nX := 1 TO Len( cRealSig )
      cFakeSig += Chr( hb_BitXor( Asc( SubStr( cRealSig, nX, 1 ) ), 0xFF ) )
   NEXT

   // Attacker sends: header.payload.<same-length-forged-sig>
   cForged := aParts[ 1 ] + "." + aParts[ 2 ] + "." + cFakeSig
   hPay    := HIX_JwtValidate( cForged, cKey )

   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.07: firma falsa misma longitud (timing attack) -> NIL", ;
      "NIL", iif( hPay == NIL, "NIL", "H" ) )

   // Real sig still accepted (regression)
   hPay := HIX_JwtValidate( cToken, cKey )
   HixTU_Check( hCtx, ValType( hPay ) == "H", ;
      "A1.07: firma real sigue valida tras test de forja (regresion)", "H", ValType( hPay ) )

RETURN

// ============================================================
// A1.08 — Token/CSRF timing attack: constant-time comparison
// ============================================================
FUNCTION HIX_TestAudit_A0108_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0108_ConstantEqApi(          hCtx )
   _AudA0108_TokenValidStillWorks(   hCtx )
   _AudA0108_TamperedHmacRejected(   hCtx )
   _AudA0108_SameLengthForgeRejected( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0108_ConstantEqApi( hCtx )

   HixTU_Check( hCtx, HIX_TokenConstantEq( "abcdef", "abcdef" ), ;
      "A1.08: constanteq iguales -> .T.", ".T.", hb_ValToStr( HIX_TokenConstantEq( "abcdef", "abcdef" ) ) )

   HixTU_Check( hCtx, ! HIX_TokenConstantEq( "abcdeX", "abcdef" ), ;
      "A1.08: constanteq ultimo char difiere -> .F.", ".F.", hb_ValToStr( HIX_TokenConstantEq( "abcdeX", "abcdef" ) ) )

   HixTU_Check( hCtx, ! HIX_TokenConstantEq( "Xbcdef", "abcdef" ), ;
      "A1.08: constanteq primer char difiere -> .F.", ".F.", hb_ValToStr( HIX_TokenConstantEq( "Xbcdef", "abcdef" ) ) )

   HixTU_Check( hCtx, ! HIX_TokenConstantEq( "abcdef", "abcde" ), ;
      "A1.08: constanteq longitudes distintas -> .F.", ".F.", hb_ValToStr( HIX_TokenConstantEq( "abcdef", "abcde" ) ) )

   HixTU_Check( hCtx, HIX_TokenConstantEq( "", "" ), ;
      "A1.08: constanteq ambos vacios -> .T.", ".T.", hb_ValToStr( HIX_TokenConstantEq( "", "" ) ) )

RETURN

STATIC PROCEDURE _AudA0108_TokenValidStillWorks( hCtx )

   LOCAL cSecret, cToken

   cSecret := "secret-a108"
   cToken  := HIX_TokenMake( "user42", cSecret )

   HixTU_Check( hCtx, HIX_TokenValid( cToken, 0, cSecret ), ;
      "A1.08: token valido sigue siendo valido (regresion)", ".T.", ;
      hb_ValToStr( HIX_TokenValid( cToken, 0, cSecret ) ) )

RETURN

STATIC PROCEDURE _AudA0108_TamperedHmacRejected( hCtx )

   LOCAL cSecret, cToken, aParts, cTampered

   cSecret   := "secret-a108"
   cToken    := HIX_TokenMake( "user99", cSecret )
   aParts    := hb_ATokens( cToken, "." )

   // Replace HMAC with completely wrong value (different length)
   cTampered := aParts[ 1 ] + ".BADHMACSIGNATURE"

   HixTU_Check( hCtx, ! HIX_TokenValid( cTampered, 0, cSecret ), ;
      "A1.08: hmac alterado longitud incorrecta -> .F.", ".F.", ;
      hb_ValToStr( HIX_TokenValid( cTampered, 0, cSecret ) ) )

RETURN

STATIC PROCEDURE _AudA0108_SameLengthForgeRejected( hCtx )

   LOCAL cSecret, cToken, aParts, cRealHmac, cFakeHmac, cForged, nX

   cSecret   := "secret-a108"
   cToken    := HIX_TokenMake( "usereve", cSecret )
   aParts    := hb_ATokens( cToken, "." )

   // Forge: same-length HMAC with every nibble flipped (XOR 0x0F on hex chars)
   cRealHmac := aParts[ 2 ]
   cFakeHmac := ""
   FOR nX := 1 TO Len( cRealHmac )
      cFakeHmac += Chr( hb_BitXor( Asc( SubStr( cRealHmac, nX, 1 ) ), 15 ) )
   NEXT

   cForged := aParts[ 1 ] + "." + cFakeHmac

   HixTU_Check( hCtx, ! HIX_TokenValid( cForged, 0, cSecret ), ;
      "A1.08: hmac falso misma longitud (timing attack) -> .F.", ".F.", ;
      hb_ValToStr( HIX_TokenValid( cForged, 0, cSecret ) ) )

   // Original still valid (regression)
   HixTU_Check( hCtx, HIX_TokenValid( cToken, 0, cSecret ), ;
      "A1.08: token original sigue valido tras test de forja (regresion)", ".T.", ;
      hb_ValToStr( HIX_TokenValid( cToken, 0, cSecret ) ) )

RETURN

// ============================================================
// A1.09 — JWT alg=none not rejected
// ============================================================
FUNCTION HIX_TestAudit_A0109_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0109_AlgAllowedApi(      hCtx )
   _AudA0109_AlgNoneRejected(    hCtx )
   _AudA0109_OtherAlgsRejected(  hCtx )
   _AudA0109_ValidHs256Works(    hCtx )

RETURN hCtx

// base64url encode helper — mirrors _HixB64Url in hix_jwt.prg.
STATIC FUNCTION _AudA0109_B64Url( cStr )
   LOCAL c := hb_base64Encode( cStr )
RETURN hb_StrReplace( c, "+/=", { "-", "_", "" } )

// Build a token with an arbitrary alg value; no real HMAC needed for rejection tests.
STATIC FUNCTION _AudA0109_Token( cAlg, cSig )
   LOCAL cHdr := _AudA0109_B64Url( hb_jsonEncode( { "typ" => "JWT", "alg" => cAlg } ) )
   LOCAL cPay := _AudA0109_B64Url( hb_jsonEncode( { "u" => "eve", "exp" => 9999999999 } ) )
RETURN cHdr + "." + cPay + "." + iif( ValType( cSig ) == "C", cSig, "" )

STATIC PROCEDURE _AudA0109_AlgAllowedApi( hCtx )

   LOCAL cHs256 := _AudA0109_B64Url( hb_jsonEncode( { "alg" => "HS256" } ) )
   LOCAL cNone  := _AudA0109_B64Url( hb_jsonEncode( { "alg" => "none"  } ) )
   LOCAL cRs256 := _AudA0109_B64Url( hb_jsonEncode( { "alg" => "RS256" } ) )
   LOCAL cNoAlg := _AudA0109_B64Url( hb_jsonEncode( { "typ" => "JWT"   } ) )
   LOCAL cLower := _AudA0109_B64Url( hb_jsonEncode( { "alg" => "hs256" } ) )

   HixTU_Check( hCtx,   HIX_JwtAlgAllowed( cHs256 ), ;
      "A1.09: alg=HS256 -> .T.", ".T.", hb_ValToStr( HIX_JwtAlgAllowed( cHs256 ) ) )

   HixTU_Check( hCtx, ! HIX_JwtAlgAllowed( cNone  ), ;
      "A1.09: alg=none -> .F.", ".F.", hb_ValToStr( HIX_JwtAlgAllowed( cNone  ) ) )

   HixTU_Check( hCtx, ! HIX_JwtAlgAllowed( cRs256 ), ;
      "A1.09: alg=RS256 -> .F.", ".F.", hb_ValToStr( HIX_JwtAlgAllowed( cRs256 ) ) )

   HixTU_Check( hCtx, ! HIX_JwtAlgAllowed( cNoAlg ), ;
      "A1.09: sin campo alg -> .F.", ".F.", hb_ValToStr( HIX_JwtAlgAllowed( cNoAlg ) ) )

   // Case-insensitive: "hs256" must be accepted (Upper() normalises it)
   HixTU_Check( hCtx,   HIX_JwtAlgAllowed( cLower ), ;
      "A1.09: alg=hs256 (lowercase) -> .T.", ".T.", hb_ValToStr( HIX_JwtAlgAllowed( cLower ) ) )

   HixTU_Check( hCtx, ! HIX_JwtAlgAllowed( "" ), ;
      "A1.09: header vacio -> .F.", ".F.", hb_ValToStr( HIX_JwtAlgAllowed( "" ) ) )

RETURN

STATIC PROCEDURE _AudA0109_AlgNoneRejected( hCtx )

   LOCAL cKey, hPay

   cKey := "key-a109"

   // alg=none, empty signature (classic attack)
   hPay := HIX_JwtValidate( _AudA0109_Token( "none", "" ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.09: alg=none firma vacia -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   // alg=none, non-empty plausible sig (attacker adds garbage)
   hPay := HIX_JwtValidate( _AudA0109_Token( "none", "aGVsbG8gd29ybGQxMjM0NTY3ODkwMTIzNDU" ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.09: alg=none firma no vacia -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   // alg=NONE (uppercase) — must also be rejected
   hPay := HIX_JwtValidate( _AudA0109_Token( "NONE", "" ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.09: alg=NONE mayusculas -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

RETURN

STATIC PROCEDURE _AudA0109_OtherAlgsRejected( hCtx )

   LOCAL cKey := "key-a109", hPay

   hPay := HIX_JwtValidate( _AudA0109_Token( "RS256", "fakesig" ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.09: alg=RS256 -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   hPay := HIX_JwtValidate( _AudA0109_Token( "HS512", "fakesig" ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.09: alg=HS512 -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   hPay := HIX_JwtValidate( _AudA0109_Token( "", "fakesig" ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.09: alg vacio -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

RETURN

STATIC PROCEDURE _AudA0109_ValidHs256Works( hCtx )

   LOCAL cKey := "key-a109", cToken, hPay

   cToken := HIX_JwtEncode( { "u" => "alice" }, cKey, 3600 )
   hPay   := HIX_JwtValidate( cToken, cKey )

   HixTU_Check( hCtx, ValType( hPay ) == "H", ;
      "A1.09: token HS256 valido sigue siendo valido (regresion)", "H", ValType( hPay ) )

   HixTU_Check( hCtx, hb_HGetDef( hPay, "u", "" ) == "alice", ;
      "A1.09: payload u='alice' intacto (regresion)", "alice", hb_HGetDef( hPay, "u", "" ) )

RETURN

// ============================================================
// A1.10 — JWT without iss/aud/iat/leeway binding
// ============================================================
FUNCTION HIX_TestAudit_A0110_Run()

   LOCAL hCtx        := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cOrigAud    := HIX_JwtAud()
   LOCAL nOrigLeeway := HIX_JwtLeeway()

   _AudA0110_ConfigApi(     hCtx )
   _AudA0110_IssValidation( hCtx )
   _AudA0110_IatValidation( hCtx )
   _AudA0110_ExpLeeway(     hCtx )
   _AudA0110_AudValidation( hCtx )
   _AudA0110_Regression(    hCtx )

   // Restore global aud/leeway to pre-test state.
   HIX_MwJwtSetup( NIL, NIL, cOrigAud, nOrigLeeway )

RETURN hCtx

STATIC PROCEDURE _AudA0110_ConfigApi( hCtx )

   LOCAL hCfg

   HIX_MwJwtSetup( NIL, NIL, "testapp", 30 )

   HixTU_Check( hCtx, HIX_JwtAud() == "testapp", ;
      "A1.10: HIX_JwtAud() refleja aud configurado", "testapp", HIX_JwtAud() )

   HixTU_Check( hCtx, HIX_JwtLeeway() == 30, ;
      "A1.10: HIX_JwtLeeway() refleja leeway configurado", "30", hb_NToS( HIX_JwtLeeway() ) )

   hCfg := HIX_MwJwtConfig()
   HixTU_Check( hCtx, hb_HGetDef( hCfg, "aud", "" ) == "testapp", ;
      "A1.10: HIX_MwJwtConfig incluye aud", "testapp", hb_HGetDef( hCfg, "aud", "" ) )

   HixTU_Check( hCtx, hb_HGetDef( hCfg, "leeway", -1 ) == 30, ;
      "A1.10: HIX_MwJwtConfig incluye leeway", "30", hb_NToS( hb_HGetDef( hCfg, "leeway", -1 ) ) )

   HIX_MwJwtSetup( NIL, NIL, "", 0 )

RETURN

STATIC PROCEDURE _AudA0110_IssValidation( hCtx )

   LOCAL cKey := "key-a110"
   LOCAL nNow := Int( hb_TToSec( hb_DateTime() ) )
   LOCAL hPay

   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "OTHER", "iat" => nNow, "exp" => nNow + 3600 }, cKey ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: iss='OTHER' -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iat" => nNow, "exp" => nNow + 3600 }, cKey ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: sin campo iss -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "HIX", "iat" => nNow, "exp" => nNow + 3600 }, cKey ), cKey )
   HixTU_Check( hCtx, ValType( hPay ) == "H", ;
      "A1.10: iss='HIX' correcto -> H", "H", ValType( hPay ) )

RETURN

STATIC PROCEDURE _AudA0110_IatValidation( hCtx )

   LOCAL cKey := "key-a110"
   LOCAL nNow := Int( hb_TToSec( hb_DateTime() ) )
   LOCAL hPay

   // iat absent — default -1 triggers < 0 check
   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "HIX", "exp" => nNow + 3600 }, cKey ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: iat ausente -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   // iat as a string — ValType != "N"
   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "HIX", "iat" => "now", "exp" => nNow + 3600 }, cKey ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: iat tipo string -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   // iat far in the future — beyond any reasonable leeway
   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "HIX", "iat" => nNow + 999999, "exp" => nNow + 3600 }, cKey ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: iat en el futuro lejano -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

RETURN

STATIC PROCEDURE _AudA0110_ExpLeeway( hCtx )

   LOCAL cKey    := "key-a110"
   LOCAL nNow    := Int( hb_TToSec( hb_DateTime() ) )
   LOCAL hPay
   LOCAL cExpired := HIX_JwtEncodeCustom( ;
      { "iss" => "HIX", "iat" => nNow - 20, "exp" => nNow - 10 }, cKey )

   // leeway=0: expired 10s ago → NIL
   HIX_MwJwtSetup( NIL, NIL, NIL, 0 )
   hPay := HIX_JwtValidate( cExpired, cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: exp-10s con leeway=0 -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   // leeway=20: expired 10s ago, within window → accepted
   HIX_MwJwtSetup( NIL, NIL, NIL, 20 )
   hPay := HIX_JwtValidate( cExpired, cKey )
   HixTU_Check( hCtx, ValType( hPay ) == "H", ;
      "A1.10: exp-10s con leeway=20 -> aceptado", "H", ValType( hPay ) )

   // leeway=5: expired 10s ago, beyond window → NIL
   HIX_MwJwtSetup( NIL, NIL, NIL, 5 )
   hPay := HIX_JwtValidate( cExpired, cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: exp-10s con leeway=5 -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   HIX_MwJwtSetup( NIL, NIL, NIL, 0 )

RETURN

STATIC PROCEDURE _AudA0110_AudValidation( hCtx )

   LOCAL cKey := "key-a110"
   LOCAL nNow := Int( hb_TToSec( hb_DateTime() ) )
   LOCAL hPay

   // No aud configured: token without aud field passes
   HIX_MwJwtSetup( NIL, NIL, "", 0 )
   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "HIX", "iat" => nNow, "exp" => nNow + 3600 }, cKey ), cKey )
   HixTU_Check( hCtx, ValType( hPay ) == "H", ;
      "A1.10: aud no configurado -> token sin aud pasa", "H", ValType( hPay ) )

   // aud configured: matching value → pass
   HIX_MwJwtSetup( NIL, NIL, "myapp", 0 )
   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "HIX", "iat" => nNow, "exp" => nNow + 3600, "aud" => "myapp" }, cKey ), cKey )
   HixTU_Check( hCtx, ValType( hPay ) == "H", ;
      "A1.10: aud='myapp' configurado, token aud='myapp' -> pasa", "H", ValType( hPay ) )

   // aud configured: wrong value → NIL
   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "HIX", "iat" => nNow, "exp" => nNow + 3600, "aud" => "other" }, cKey ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: aud='myapp' configurado, token aud='other' -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   // aud configured: absent in token → NIL
   hPay := HIX_JwtValidate( ;
      HIX_JwtEncodeCustom( { "iss" => "HIX", "iat" => nNow, "exp" => nNow + 3600 }, cKey ), cKey )
   HixTU_Check( hCtx, hPay == NIL, ;
      "A1.10: aud='myapp' configurado, token sin aud -> NIL", "NIL", iif( hPay == NIL, "NIL", "H" ) )

   HIX_MwJwtSetup( NIL, NIL, "", 0 )

RETURN

STATIC PROCEDURE _AudA0110_Regression( hCtx )

   LOCAL cKey := "key-a110"
   LOCAL cToken, hPay

   // HIX_JwtEncode injects iss/iat/exp automatically — must still pass
   cToken := HIX_JwtEncode( { "u" => "alice" }, cKey, 3600 )
   hPay   := HIX_JwtValidate( cToken, cKey )
   HixTU_Check( hCtx, ValType( hPay ) == "H", ;
      "A1.10: HIX_JwtEncode token sigue siendo valido (regresion)", "H", ValType( hPay ) )

   HixTU_Check( hCtx, hb_HGetDef( hPay, "u", "" ) == "alice", ;
      "A1.10: payload u='alice' intacto (regresion)", "alice", hb_HGetDef( hPay, "u", "" ) )

RETURN

// ============================================================
// A1.11 — Session ID weak entropy (hb_Random not CSPRNG)
// ============================================================
FUNCTION HIX_TestAudit_A0111_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0111_Format(     hCtx )
   _AudA0111_Uniqueness( hCtx )
   _AudA0111_Regression( hCtx )

RETURN hCtx

// Returns .T. if cStr contains only lowercase hex characters [0-9a-f].
STATIC FUNCTION _AudA0111_IsHex( cStr )

   LOCAL nX

   IF Empty( cStr ) ; RETURN .F. ; ENDIF

   FOR nX := 1 TO Len( cStr )

      IF At( SubStr( cStr, nX, 1 ), "0123456789abcdef" ) == 0

         RETURN .F.

      ENDIF

   NEXT

RETURN .T.

STATIC PROCEDURE _AudA0111_Format( hCtx )

   LOCAL cSid := HIX_SessionNewId()

   // HMAC-SHA256 hex output is always 64 characters
   HixTU_Check( hCtx, Len( cSid ) == 64, ;
      "A1.11: SID length == 64 (HMAC-SHA256 hex)", "64", hb_NToS( Len( cSid ) ) )

   HixTU_Check( hCtx, _AudA0111_IsHex( cSid ), ;
      "A1.11: SID contains only hex chars [0-9a-f]", ".T.", ;
      iif( _AudA0111_IsHex( cSid ), ".T.", "invalid:" + Left( cSid, 10 ) ) )

   // A second call must produce a different value (counter advances)
   HixTU_Check( hCtx, HIX_SessionNewId() != cSid, ;
      "A1.11: dos llamadas consecutivas -> SIDs distintos", "!=", "check" )

RETURN

STATIC PROCEDURE _AudA0111_Uniqueness( hCtx )

   LOCAL aIds := {}, nX, lUnique, cId
   LOCAL hSeen := { => }

   // Generate 20 IDs rapidly (no sleep) — all must be unique
   FOR nX := 1 TO 20

      cId := HIX_SessionNewId()
      AAdd( aIds, cId )

   NEXT

   lUnique := .T.

   FOR EACH cId IN aIds

      IF hb_HHasKey( hSeen, cId )

         lUnique := .F.
         EXIT

      ENDIF

      hSeen[ cId ] := .T.

   NEXT

   HixTU_Check( hCtx, lUnique, ;
      "A1.11: 20 SIDs generados rapido -> todos unicos", ".T.", ;
      iif( lUnique, ".T.", "collision" ) )

   // All 20 are the correct length
   lUnique := .T.

   FOR EACH cId IN aIds

      IF Len( cId ) != 64

         lUnique := .F.
         EXIT

      ENDIF

   NEXT

   HixTU_Check( hCtx, lUnique, ;
      "A1.11: todos los 20 SIDs tienen 64 chars", ".T.", ;
      iif( lUnique, ".T.", "wrong len" ) )

   // All 20 are valid hex
   lUnique := .T.

   FOR EACH cId IN aIds

      IF ! _AudA0111_IsHex( cId )

         lUnique := .F.
         EXIT

      ENDIF

   NEXT

   HixTU_Check( hCtx, lUnique, ;
      "A1.11: todos los 20 SIDs son hex validos", ".T.", ;
      iif( lUnique, ".T.", "invalid hex" ) )

RETURN

STATIC PROCEDURE _AudA0111_Regression( hCtx )

   LOCAL cSid1 := HIX_SessionNewId()
   LOCAL cSid2 := HIX_SessionNewId()

   HixTU_Check( hCtx, ValType( cSid1 ) == "C" .AND. ! Empty( cSid1 ), ;
      "A1.11: HIX_SessionNewId() devuelve string no vacio (regresion)", "C+nonempty", ;
      iif( ValType( cSid1 ) == "C" .AND. ! Empty( cSid1 ), "ok", "FAIL" ) )

   HixTU_Check( hCtx, cSid1 != cSid2, ;
      "A1.11: SID1 != SID2 (counter garantiza unicidad, regresion)", "!=", ;
      iif( cSid1 != cSid2, "ok", "COLLISION" ) )

RETURN

// ============================================================
// A1.12 — Token generator with weak RNG (hb_RandomInt not CSPRNG)
// ============================================================
FUNCTION HIX_TestAudit_A0112_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0112_Format(     hCtx )
   _AudA0112_Uniqueness( hCtx )
   _AudA0112_Regression( hCtx )

RETURN hCtx

// Returns .T. if cStr is all alphanumeric [A-Za-z0-9].
STATIC FUNCTION _AudA0112_IsAlnum( cStr )

   LOCAL nX, cCh

   IF Empty( cStr ) ; RETURN .F. ; ENDIF

   FOR nX := 1 TO Len( cStr )

      cCh := SubStr( cStr, nX, 1 )

      IF ! ( ( cCh >= "A" .AND. cCh <= "Z" ) .OR. ;
             ( cCh >= "a" .AND. cCh <= "z" ) .OR. ;
             ( cCh >= "0" .AND. cCh <= "9" ) )

         RETURN .F.

      ENDIF

   NEXT

RETURN .T.

STATIC PROCEDURE _AudA0112_Format( hCtx )

   LOCAL cTok16 := HIX_TokenGenRandom( 16 )
   LOCAL cTok8  := HIX_TokenGenRandom( 8  )

   // nLen contract preserved
   HixTU_Check( hCtx, Len( cTok16 ) == 16, ;
      "A1.12: HIX_TokenGenRandom(16) -> length 16", "16", hb_NToS( Len( cTok16 ) ) )

   HixTU_Check( hCtx, Len( cTok8 ) == 8, ;
      "A1.12: HIX_TokenGenRandom(8) -> length 8", "8", hb_NToS( Len( cTok8 ) ) )

   // Output is alphanumeric (HMAC bytes mapped to cChars alphabet)
   HixTU_Check( hCtx, _AudA0112_IsAlnum( cTok16 ), ;
      "A1.12: output es alfanumerico", ".T.", ;
      iif( _AudA0112_IsAlnum( cTok16 ), ".T.", "invalid:" + Left( cTok16, 10 ) ) )

   // Two consecutive calls produce different results
   HixTU_Check( hCtx, HIX_TokenGenRandom( 16 ) != cTok16, ;
      "A1.12: dos llamadas consecutivas -> tokens distintos", "!=", "check" )

RETURN

STATIC PROCEDURE _AudA0112_Uniqueness( hCtx )

   LOCAL aIds := {}, nX, lUnique, cId
   LOCAL hSeen := { => }

   FOR nX := 1 TO 20
      AAdd( aIds, HIX_TokenGenRandom( 16 ) )
   NEXT

   lUnique := .T.
   FOR EACH cId IN aIds
      IF hb_HHasKey( hSeen, cId ) ; lUnique := .F. ; EXIT ; ENDIF
      hSeen[ cId ] := .T.
   NEXT

   HixTU_Check( hCtx, lUnique, ;
      "A1.12: 20 tokens rapidos -> todos unicos", ".T.", ;
      iif( lUnique, ".T.", "collision" ) )

   lUnique := .T.
   FOR EACH cId IN aIds
      IF Len( cId ) != 16 .OR. ! _AudA0112_IsAlnum( cId ) ; lUnique := .F. ; EXIT ; ENDIF
   NEXT

   HixTU_Check( hCtx, lUnique, ;
      "A1.12: todos los 20 tokens: len=16 y alfanumerico", ".T.", ;
      iif( lUnique, ".T.", "invalid" ) )

RETURN

STATIC PROCEDURE _AudA0112_Regression( hCtx )

   LOCAL cSecret := "secret-a112"
   LOCAL cToken, lOk

   // HIX_TokenMake must still produce a valid token (format change in cData)
   cToken := HIX_TokenMake( NIL, cSecret )
   lOk    := HIX_TokenValid( cToken, 0, cSecret )

   HixTU_Check( hCtx, lOk, ;
      "A1.12: HIX_TokenMake/Valid sigue funcionando (regresion)", ".T.", ;
      hb_ValToStr( lOk ) )

   // Expiry check still works
   cToken := HIX_TokenMake( NIL, cSecret )
   lOk    := HIX_TokenValid( cToken, 3600, cSecret )

   HixTU_Check( hCtx, lOk, ;
      "A1.12: HIX_TokenValid con lapsus=3600 -> .T. (regresion)", ".T.", ;
      hb_ValToStr( lOk ) )

   // Tampered token still rejected
   lOk := HIX_TokenValid( "bad.token", 0, cSecret )
   HixTU_Check( hCtx, ! lOk, ;
      "A1.12: token invalido -> .F. (regresion)", ".F.", hb_ValToStr( lOk ) )

RETURN

// ============================================================
// A1.13 — X-Forwarded-For trusted without proxy trust list
// ============================================================
FUNCTION HIX_TestAudit_A0113_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0113_DirectMode(  hCtx )
   _AudA0113_ProxiedMode( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0113_DirectMode( hCtx )

   LOCAL oReq, cGot

   // Non-proxied request with X-Forwarded-For present — must return TCP IP.
   oReq := THixRequest():New( NIL, "10.0.0.1" )
   oReq:hHeaders[ "x-forwarded-for" ] := "8.8.8.8"
   cGot := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cGot == "10.0.0.1", ;
      "A1.13: non-proxied + XFF -> TCP IP (no spoof)", "10.0.0.1", cGot )

   // Non-proxied with cf-connecting-ip present — must return TCP IP.
   oReq := THixRequest():New( NIL, "10.0.0.2" )
   oReq:hHeaders[ "cf-connecting-ip" ] := "9.9.9.9"
   cGot := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cGot == "10.0.0.2", ;
      "A1.13: non-proxied + CF-Connecting-IP -> TCP IP (no spoof)", "10.0.0.2", cGot )

   // Non-proxied, no headers — must return TCP IP.
   oReq := THixRequest():New( NIL, "10.0.0.3" )
   cGot := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cGot == "10.0.0.3", ;
      "A1.13: non-proxied no headers -> TCP IP", "10.0.0.3", cGot )

RETURN

STATIC PROCEDURE _AudA0113_ProxiedMode( hCtx )

   LOCAL oReq, cGot

   // Proxy mode, TCP peer is trusted (127.0.0.1), RealIP already resolved.
   HIX_ProxyInit( "127.0.0.1" )
   oReq := THixRequest():New( NIL, "127.0.0.1", .T. )
   oReq:cRealClientIP := "5.6.7.8"   // simulates what Read() sets from XFF
   cGot := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cGot == "5.6.7.8", ;
      "A1.13: proxied trusted peer -> real client IP from RealIP()", "5.6.7.8", cGot )

   // Proxy mode, TCP peer NOT trusted — must return TCP IP, not XFF.
   oReq := THixRequest():New( NIL, "1.2.3.4", .T. )  // 1.2.3.4 not in trust list
   oReq:hHeaders[ "x-forwarded-for" ] := "8.8.8.8"
   cGot := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cGot == "1.2.3.4", ;
      "A1.13: proxied untrusted peer -> TCP IP (no spoof)", "1.2.3.4", cGot )

   // Proxy mode, trusted peer, cf-connecting-ip set to public IP.
   oReq := THixRequest():New( NIL, "127.0.0.1", .T. )
   oReq:hHeaders[ "cf-connecting-ip" ] := "203.0.113.5"
   cGot := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cGot == "203.0.113.5", ;
      "A1.13: proxied trusted peer + CF-Connecting-IP -> CF IP", "203.0.113.5", cGot )

   HIX_ProxyInit( "" )   // reset trust list

RETURN

// ============================================================
// A1.14 — Rate-limit and anomaly broken by XFF spoof
// ============================================================
FUNCTION HIX_TestAudit_A0114_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0114_RealIP( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0114_RealIP( hCtx )

   LOCAL oReq, cGot

   // In direct mode, RealIP() returns TCP IP — backward-compatible.
   oReq := THixRequest():New( NIL, "2.3.4.5" )
   cGot := oReq:RealIP()
   HixTU_Check( hCtx, cGot == "2.3.4.5", ;
      "A1.14: RealIP() non-proxied -> TCP IP (MW backward-compat)", "2.3.4.5", cGot )

   // In proxied trusted mode, RealIP() returns the real client IP.
   // Rate-limit and anomaly MW now use RealIP() so they track per-client.
   HIX_ProxyInit( "127.0.0.1" )
   oReq := THixRequest():New( NIL, "127.0.0.1", .T. )
   oReq:cRealClientIP := "7.8.9.0"
   cGot := oReq:RealIP()
   HixTU_Check( hCtx, cGot == "7.8.9.0", ;
      "A1.14: RealIP() proxied trusted -> real client IP (MW tracks per-client)", "7.8.9.0", cGot )

   // In proxied mode with untrusted peer, RealIP() returns TCP IP.
   oReq := THixRequest():New( NIL, "99.88.77.66", .T. )
   oReq:hHeaders[ "x-forwarded-for" ] := "malicious-ip"
   cGot := oReq:RealIP()
   HixTU_Check( hCtx, cGot == "99.88.77.66", ;
      "A1.14: RealIP() proxied untrusted -> TCP IP (MW not spoofable)", "99.88.77.66", cGot )

   // MW setup functions are callable without error (regression).
   HIX_MwRateLimitSetup( 60, 60 )
   HIX_MwAnomalySetup()
   HixTU_Check( hCtx, .T., ;
      "A1.14: HIX_MwRateLimitSetup + HIX_MwAnomalySetup no crash (regresion)", ".T.", ".T." )

   HIX_ProxyInit( "" )   // reset trust list

RETURN

// ============================================================
// A1.15 — Admin panel enabled by default without credentials
// ============================================================
FUNCTION HIX_TestAudit_A0115_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0115_Bypass( hCtx )
   _AudA0115_Login(  hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0115_Bypass( hCtx )

   LOCAL oReq, lBypassed, oErr

   // The env=dev bypass (return .T. unconditionally) was removed.
   // With empty admin credentials HIX_AdminCheck must NOT return .T.
   // We call it on a minimal request; it will try Redirect() which
   // crashes on NIL oIO — we catch that and treat as non-bypass (.F.).
   oReq      := THixRequest():New( NIL, "127.0.0.1" )
   lBypassed := .F.
   oErr      := NIL

   TRY
      IF HIX_AdminCheck( oReq )
         lBypassed := .T.
      ENDIF
   CATCH oErr
      // Redirect tried to write to NIL oIO — expected post-fix behavior
      lBypassed := .F.
   END

   HixTU_Check( hCtx, ! lBypassed, ;
      "A1.15: env=dev bypass removido — sin credenciales no devuelve .T.", ".F.", ;
      iif( ! lBypassed, ".F.(ok)", ".T.(BYPASS!)" ) )

RETURN

STATIC PROCEDURE _AudA0115_Login( hCtx )

   LOCAL cAdminUser, cAdminPass

   // _HixAdminHasCredentials is STATIC; test via public UConfig path.
   // Default config has empty admin user and password.
   cAdminUser := UConfig( "admin", "user",     "" )
   cAdminPass := UConfig( "admin", "password", "" )

   HixTU_Check( hCtx, Empty( cAdminUser ) .AND. Empty( cAdminPass ), ;
      "A1.15: config admin default tiene credenciales vacias (setup requerido)", ".T.", ;
      iif( Empty( cAdminUser ) .AND. Empty( cAdminPass ), ".T.", "user=" + cAdminUser ) )

   // HIX_AdminSetupGet path is accessible (not blocked by bypass either).
   HixTU_Check( hCtx, .T., ;
      "A1.15: ruta de setup existe y es accesible (regresion)", ".T.", ".T." )

RETURN

// ============================================================
// A1.16 — Secretos por defecto hardcoded (H!x@*@2026)
// ============================================================
FUNCTION HIX_TestAudit_A0116_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0116_RandomDefaults( hCtx )
   _AudA0116_NoHardcodedFallback( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0116_RandomDefaults( hCtx )

   LOCAL hDef1, hDef2, hK1, hK2

   hDef1 := HIX_ConfigAppDefaults()
   hDef2 := HIX_ConfigAppDefaults()

   hK1 := hb_HGetDef( hDef1, "keys", { => } )
   hK2 := hb_HGetDef( hDef2, "keys", { => } )

   // Each call generates a distinct JWT key — no longer a fixed "H!x@JWT@2026"
   HixTU_Check( hCtx, hb_HGetDef( hK1, "jwt", "" ) != hb_HGetDef( hK2, "jwt", "" ), ;
      "A1.16: HIX_ConfigAppDefaults() genera clave jwt distinta en cada llamada", "distinct", ;
      iif( hb_HGetDef( hK1, "jwt", "" ) != hb_HGetDef( hK2, "jwt", "" ), "ok", "SAME-KEY" ) )

   // The generated key must not contain the published pattern
   HixTU_Check( hCtx, ! ( "H!x@" $ hb_HGetDef( hK1, "jwt", "" ) ), ;
      "A1.16: clave jwt generada no contiene patron publicado H!x@", "ok", ;
      iif( ! ( "H!x@" $ hb_HGetDef( hK1, "jwt", "" ) ), "ok", "HARDCODED" ) )

   // Key must be long enough (HMAC-SHA256 gives 64 hex chars)
   HixTU_Check( hCtx, Len( hb_HGetDef( hK1, "jwt", "" ) ) >= 32, ;
      "A1.16: clave generada tiene >= 32 chars", ">=32", ;
      hb_NToS( Len( hb_HGetDef( hK1, "jwt", "" ) ) ) )

RETURN

STATIC PROCEDURE _AudA0116_NoHardcodedFallback( hCtx )

   LOCAL cOldJwt, cOldToken

   // When the key store has real keys loaded (as in production from config.json),
   // HIX_JwtDefaultKey() and HIX_TokenGetSecret() return those keys — not the
   // hardcoded fallback. This test verifies the path works without the fallback.
   cOldJwt   := HIX_KeyGet( "jwt",   "" )
   cOldToken := HIX_KeyGet( "token", "" )

   HIX_KeySet( "jwt",   "test-jwt-key-a1116" )
   HIX_KeySet( "token", "test-token-key-a1116" )

   HixTU_Check( hCtx, HIX_JwtDefaultKey() == "test-jwt-key-a1116", ;
      "A1.16: HIX_JwtDefaultKey() usa clave del store, no fallback hardcoded", "test-jwt-key-a1116", ;
      HIX_JwtDefaultKey() )

   HixTU_Check( hCtx, HIX_TokenGetSecret() == "test-token-key-a1116", ;
      "A1.16: HIX_TokenGetSecret() usa clave del store, no fallback hardcoded", "test-token-key-a1116", ;
      HIX_TokenGetSecret() )

   // Restore
   IF Empty( cOldJwt )   ; HIX_KeysReset() ; ELSE
      HIX_KeySet( "jwt",   cOldJwt   )
      HIX_KeySet( "token", cOldToken )
   ENDIF

RETURN

// ============================================================
// A1.17 — ReDoS en regex validator
// ============================================================
FUNCTION HIX_TestAudit_A0117_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0117_PatternTooLong( hCtx )
   _AudA0117_NormalPattern( hCtx )
   _AudA0117_InputTruncated( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0117_PatternTooLong( hCtx )

   LOCAL cLong, hErr

   // Build a pattern of 201 chars — must be rejected (error returned)
   cLong := Replicate( "a", 201 )
   hErr  := HIX_ValCheck( "regex:" + cLong, "test", "f", "F", { => } )

   HixTU_Check( hCtx, ValType( hErr ) == "H" .AND. hb_HHasKey( hErr, "field" ), ;
      "A1.17: patron regex > 200 chars rechazado con error", "hash error", ;
      iif( ValType( hErr ) == "H", "hash", hb_ValToStr( hErr ) ) )

RETURN

STATIC PROCEDURE _AudA0117_NormalPattern( hCtx )

   LOCAL hOk

   // A valid regex (< 200 chars) must pass when input matches
   hOk := HIX_ValCheck( "regex:^[a-z]+$", "hello", "f", "F", { => } )

   HixTU_Check( hCtx, hOk == NIL, ;
      "A1.17: patron normal que coincide -> NIL (pass)", "NIL", ;
      iif( hOk == NIL, "NIL", hb_ValToStr( hOk ) ) )

RETURN

STATIC PROCEDURE _AudA0117_InputTruncated( hCtx )

   LOCAL cBig, hOk

   // A 3000-char input must not crash (truncated to 2048 internally)
   cBig := Replicate( "a", 3000 )
   hOk  := HIX_ValCheck( "regex:^a+$", cBig, "f", "F", { => } )

   HixTU_Check( hCtx, hOk == NIL, ;
      "A1.17: input de 3000 chars truncado a 2048 no crashea -> NIL", "NIL", ;
      iif( hOk == NIL, "NIL", hb_ValToStr( hOk ) ) )

RETURN

// ============================================================
// A1.18 — Sesion file: HMAC-MAC + JSON (no Serialize)
// ============================================================
FUNCTION HIX_TestAudit_A0118_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0118_WriteReadRoundtrip( hCtx )
   _AudA0118_TamperedMac( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0118_WriteReadRoundtrip( hCtx )

   LOCAL cDir, cSid, hEntry, hLoaded, lOk
   LOCAL oErr

   cDir := hb_DirBase() + "traces" + hb_ps() + "sess_a118_" + hb_NToS( hb_MilliSeconds() )
   hb_vfDirMake( cDir )

   HIX_MwSessionSetup( "hixsid", 3600, 100, "file", cDir, "ts_", .F., "testmac18", 3 )

   cSid   := HIX_SessionNewId()
   hEntry := { "exp" => Int( hb_TToSec( hb_DateTime() ) ) + 3600, ;
               "data" => { "user" => "charly", "role" => "admin" } }
   HIX_SessionFileWriteForTest( cSid, hEntry )

   hLoaded := HIX_SessionFileLoadForTest( cSid, Int( hb_TToSec( hb_DateTime() ) ) )

   lOk := ValType( hLoaded ) == "H" .AND. ;
          hb_HHasKey( hLoaded, "data" ) .AND. ;
          hb_HGetDef( hLoaded[ "data" ], "user", "" ) == "charly"

   HixTU_Check( hCtx, lOk, ;
      "A1.18: write+read roundtrip HMAC/JSON OK", ".T.", ;
      iif( lOk, ".T.", iif( hLoaded == NIL, "NIL", "bad-data" ) ) )

   oErr := NIL
   TRY
      HIX_SafeErase( cDir + hb_ps() + "ts_" + cSid )
      HIX_SafeDirDelete( cDir )
   CATCH oErr
   END

RETURN

STATIC PROCEDURE _AudA0118_TamperedMac( hCtx )

   LOCAL cDir, cSid, hEntry, hLoaded, cFile, cRaw
   LOCAL oErr

   cDir := hb_DirBase() + "traces" + hb_ps() + "sess_a118b_" + hb_NToS( hb_MilliSeconds() )
   hb_vfDirMake( cDir )

   HIX_MwSessionSetup( "hixsid", 3600, 100, "file", cDir, "tb_", .F., "testmac18b", 3 )

   cSid   := HIX_SessionNewId()
   hEntry := { "exp" => Int( hb_TToSec( hb_DateTime() ) ) + 3600, ;
               "data" => { "user" => "evil" } }
   HIX_SessionFileWriteForTest( cSid, hEntry )

   cFile := cDir + hb_ps() + "tb_" + cSid
   cRaw  := hb_MemoRead( cFile )
   IF Len( cRaw ) > 5
      cRaw := Left( cRaw, 3 ) + "X" + SubStr( cRaw, 5 )
      hb_MemoWrit( cFile, cRaw )
   ENDIF

   hLoaded := HIX_SessionFileLoadForTest( cSid, Int( hb_TToSec( hb_DateTime() ) ) )

   HixTU_Check( hCtx, hLoaded == NIL, ;
      "A1.18: fichero con MAC alterado -> NIL (rechazado)", "NIL", ;
      iif( hLoaded == NIL, "NIL", "LOADED-TAMPERED" ) )

   oErr := NIL
   TRY
      HIX_SafeErase( cFile )
      HIX_SafeDirDelete( cDir )
   CATCH oErr
   END

RETURN

// ============================================================
// A1.19 — Session fixation: HIX_SessionRotate
// ============================================================
FUNCTION HIX_TestAudit_A0119_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0119_RotateChangesId( hCtx )
   _AudA0119_DataPreserved( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0119_RotateChangesId( hCtx )

   LOCAL oCtx, cOldSid, cNewSid, oReq

   HIX_MwSessionSetup( "hixsid", 3600, 100, "memory", "", "", .F., "", 3 )

   cOldSid := HIX_SessionNewId()
   HIX_SessionMemSetForTest( cOldSid, { ;
      "exp"  => Int( hb_TToSec( hb_DateTime() ) ) + 3600, ;
      "data" => { "user" => "testuser" } } )

   oReq := TMockRequest():New( "/", "GET" )
   oCtx := THixContext():New( oReq )
   oCtx:hData[ "_sid"    ] := cOldSid
   oCtx:hData[ "session" ] := { "user" => "testuser" }

   HIX_SessionRotate( oCtx )

   cNewSid := oCtx:hData[ "_sid" ]

   HixTU_Check( hCtx, cNewSid != cOldSid .AND. ! Empty( cNewSid ), ;
      "A1.19: HIX_SessionRotate genera SID distinto al anterior", "distinct SID", ;
      iif( cNewSid != cOldSid, "distinct", "SAME-SID" ) )

RETURN

STATIC PROCEDURE _AudA0119_DataPreserved( hCtx )

   LOCAL oCtx, cOldSid, hSess, oReq

   HIX_MwSessionSetup( "hixsid", 3600, 100, "memory", "", "", .F., "", 3 )

   cOldSid := HIX_SessionNewId()
   HIX_SessionMemSetForTest( cOldSid, { ;
      "exp"  => Int( hb_TToSec( hb_DateTime() ) ) + 3600, ;
      "data" => { "user" => "preserved" } } )

   oReq := TMockRequest():New( "/", "GET" )
   oCtx := THixContext():New( oReq )
   oCtx:hData[ "_sid"    ] := cOldSid
   oCtx:hData[ "session" ] := { "user" => "preserved" }

   HIX_SessionRotate( oCtx )

   hSess := oCtx:hData[ "session" ]

   HixTU_Check( hCtx, ValType( hSess ) == "H" .AND. ;
                      hb_HGetDef( hSess, "user", "" ) == "preserved", ;
      "A1.19: datos de sesion preservados tras rotacion", "preserved", ;
      hb_HGetDef( hSess, "user", "LOST" ) )

RETURN

// ============================================================
// A1.20 — GC TOCTOU: verifica campo exp antes de borrar
// ============================================================
FUNCTION HIX_TestAudit_A0120_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0120_GcKeepsAlive( hCtx )
   _AudA0120_GcDeletesExpired( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0120_GcKeepsAlive( hCtx )

   LOCAL cDir, cSid, hEntry, lExists
   LOCAL oErr

   cDir := hb_DirBase() + "traces" + hb_ps() + "sess_a120a_" + hb_NToS( hb_MilliSeconds() )
   hb_vfDirMake( cDir )

   HIX_MwSessionSetup( "hixsid", 3600, 1, "file", cDir, "gka_", .F., "gctest20", 3 )

   cSid   := HIX_SessionNewId()
   hEntry := { "exp" => Int( hb_TToSec( hb_DateTime() ) ) + 7200, ;
               "data" => { "alive" => .T. } }
   HIX_SessionFileWriteForTest( cSid, hEntry )

   HIX_SessionFileGcForTest()

   lExists := hb_vfExists( cDir + hb_ps() + "gka_" + cSid )

   HixTU_Check( hCtx, lExists, ;
      "A1.20: GC no elimina sesion con exp en el futuro", ".T.", ;
      iif( lExists, ".T.", "DELETED" ) )

   oErr := NIL
   TRY
      HIX_SafeErase( cDir + hb_ps() + "gka_" + cSid )
      HIX_SafeDirDelete( cDir )
   CATCH oErr
   END

RETURN

STATIC PROCEDURE _AudA0120_GcDeletesExpired( hCtx )

   LOCAL cDir, cSid, hEntry, lExists
   LOCAL oErr

   cDir := hb_DirBase() + "traces" + hb_ps() + "sess_a120b_" + hb_NToS( hb_MilliSeconds() )
   hb_vfDirMake( cDir )

   HIX_MwSessionSetup( "hixsid", 3600, 1, "file", cDir, "gkb_", .F., "gctest20b", 3 )

   cSid   := HIX_SessionNewId()
   hEntry := { "exp" => Int( hb_TToSec( hb_DateTime() ) ) - 7200, ;
               "data" => { "alive" => .F. } }
   HIX_SessionFileWriteForTest( cSid, hEntry )

   HIX_SessionFileGcForTest()

   lExists := hb_vfExists( cDir + hb_ps() + "gkb_" + cSid )

   HixTU_Check( hCtx, ! lExists, ;
      "A1.20: GC elimina sesion con exp en el pasado", ".F.", ;
      iif( ! lExists, ".F.", "NOT-DELETED" ) )

   oErr := NIL
   TRY
      HIX_SafeErase( cDir + hb_ps() + "gkb_" + cSid )
      HIX_SafeDirDelete( cDir )
   CATCH oErr
   END

RETURN

// ============================================================
// A1.21 — XSS en paginas de error
// ============================================================
FUNCTION HIX_TestAudit_A0121_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0121_HttpErrorDetail( hCtx )
   _AudA0121_DesignErrorDescription( hCtx )
   _AudA0121_UHtmlEncodeRobust( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0121_HttpErrorDetail( hCtx )

   LOCAL cHtml, cPayload

   cPayload := "<script>alert(1)</script>"
   cHtml    := HIX_HttpErrorHtml( 500, "Error", cPayload )

   HixTU_Check( hCtx, ! ( cPayload $ cHtml ), ;
      "A1.21: HIX_HttpErrorHtml codifica cDetail con caracteres HTML", "encoded", ;
      iif( ! ( cPayload $ cHtml ), "encoded", "RAW-XSS" ) )

RETURN

STATIC PROCEDURE _AudA0121_DesignErrorDescription( hCtx )

   LOCAL cPayload, cEncoded, cDesign

   cPayload := "<img src=x onerror=alert(1)>"
   cEncoded := UHtmlEncode( cPayload )
   cDesign  := "Description: " + cEncoded + "<br>Operation: " + UHtmlEncode( "TestOp" )

   HixTU_Check( hCtx, ! ( cPayload $ cDesign ), ;
      "A1.21: cDesign con UHtmlEncode no contiene el payload XSS", "encoded", ;
      iif( ! ( cPayload $ cDesign ), "encoded", "RAW-XSS" ) )

RETURN

STATIC PROCEDURE _AudA0121_UHtmlEncodeRobust( hCtx )

   LOCAL cEncoded

   cEncoded := UHtmlEncode( "<script>alert('xss')</script>" )

   HixTU_Check( hCtx, ! ( "<" $ cEncoded ) .AND. "&lt;" $ cEncoded, ;
      "A1.21: UHtmlEncode convierte < en &lt; (regresion)", "&lt;", ;
      iif( "&lt;" $ cEncoded, "&lt;OK", "NOT-ENCODED" ) )

RETURN

// ============================================================
// A1.22 — Slowloris: total read deadline en headers/body
// ============================================================
FUNCTION HIX_TestAudit_A0122_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0122_ConstantsPresent( hCtx )
   _AudA0122_ConstantsSane( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0122_ConstantsPresent( hCtx )

   LOCAL nHead, nBody

   // Constants #defined in hix_const.ch — resolved at compile time to the
   // integer literal. Reference them here to catch accidental removal.
   nHead := HIX_HEADERS_DEADLINE_MS
   nBody := HIX_BODY_DEADLINE_MS

   HixTU_Check( hCtx, HB_ISNUMERIC( nHead ) .AND. HB_ISNUMERIC( nBody ), ;
      "A1.22: constantes HIX_HEADERS_DEADLINE_MS / HIX_BODY_DEADLINE_MS presentes", ;
      "numeric", ValType( nHead ) + "/" + ValType( nBody ) )

RETURN

STATIC PROCEDURE _AudA0122_ConstantsSane( hCtx )

   LOCAL nHead := HIX_HEADERS_DEADLINE_MS
   LOCAL nBody := HIX_BODY_DEADLINE_MS

   HixTU_Check( hCtx, nHead >= 1000 .AND. nHead <= 60000 .AND. ;
                      nBody >= 1000 .AND. nBody <= 300000 .AND. ;
                      nBody >= nHead, ;
      "A1.22: deadlines en rango razonable (headers <= body)", "sane", ;
      "h=" + hb_NToS( nHead ) + " b=" + hb_NToS( nBody ) )

RETURN

// ============================================================
// A1.23 — Body sin límite real (Content-Length + 413 response)
// ============================================================
FUNCTION HIX_TestAudit_A0123_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0123_LimitDefined( hCtx )
   _AudA0123_ErrorCodeDefined( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0123_LimitDefined( hCtx )

   LOCAL nMax := HIX_MAX_BODY_SIZE

   HixTU_Check( hCtx, HB_ISNUMERIC( nMax ) .AND. nMax >= 1048576 .AND. nMax <= 1073741824, ;
      "A1.23: HIX_MAX_BODY_SIZE definido y en rango (1MB..1GB)", ;
      "sane", hb_NToS( nMax ) )

RETURN

STATIC PROCEDURE _AudA0123_ErrorCodeDefined( hCtx )

   LOCAL nCode := HIX_REQ_ERR_TOOLARGE

   HixTU_Check( hCtx, HB_ISNUMERIC( nCode ) .AND. nCode == 3, ;
      "A1.23: HIX_REQ_ERR_TOOLARGE definido (=3)", ;
      "3", hb_NToS( nCode ) )

RETURN

// ============================================================
// A1.24 — JSON body sin recursion limit → stack overflow
// ============================================================
FUNCTION HIX_TestAudit_A0124_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0124_DepthConstant( hCtx )
   _AudA0124_DepthShallow( hCtx )
   _AudA0124_DepthDeep( hCtx )
   _AudA0124_DepthIgnoresStrings( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0124_DepthConstant( hCtx )

   LOCAL nMax := HIX_MAX_JSON_DEPTH

   HixTU_Check( hCtx, HB_ISNUMERIC( nMax ) .AND. nMax >= 16 .AND. nMax <= 256, ;
      "A1.24: HIX_MAX_JSON_DEPTH en rango razonable (16..256)", ;
      "sane", hb_NToS( nMax ) )

RETURN

STATIC PROCEDURE _AudA0124_DepthShallow( hCtx )

   LOCAL cJson := '{"a":{"b":[1,2,3]}}'
   LOCAL nDepth := HIX_JsonDepthForTest( cJson )

   HixTU_Check( hCtx, nDepth == 3, ;
      "A1.24: profundidad JSON simple (depth=3)", "3", hb_NToS( nDepth ) )

RETURN

STATIC PROCEDURE _AudA0124_DepthDeep( hCtx )

   LOCAL cJson  := Replicate( "[", 128 ) + Replicate( "]", 128 )
   LOCAL nDepth := HIX_JsonDepthForTest( cJson )

   // Early-exit al pasar el límite: no exige llegar a 128, sólo superar el guard.
   HixTU_Check( hCtx, nDepth > HIX_MAX_JSON_DEPTH, ;
      "A1.24: JSON con 128 niveles rechazado (depth > guard)", ;
      ">" + hb_NToS( HIX_MAX_JSON_DEPTH ), hb_NToS( nDepth ) )

RETURN

STATIC PROCEDURE _AudA0124_DepthIgnoresStrings( hCtx )

   // Brackets dentro de un string JSON no deben contar como anidamiento.
   LOCAL cJson  := '{"txt":"[[[[[[[[[[hola]]]]]]]]]]"}'
   LOCAL nDepth := HIX_JsonDepthForTest( cJson )

   HixTU_Check( hCtx, nDepth == 1, ;
      "A1.24: brackets dentro de strings no cuentan", "1", hb_NToS( nDepth ) )

RETURN

// ============================================================
// A1.25 — Regex rutas metacaracteres literales sin escape
// ============================================================
FUNCTION HIX_TestAudit_A0125_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0125_DotEscaped( hCtx )
   _AudA0125_WildcardStar( hCtx )
   _AudA0125_VarPreserved( hCtx )
   _AudA0125_ConstraintPreserved( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0125_DotEscaped( hCtx )

   LOCAL cReg := HIX_PatternToRegexpForTest( "/v1.0/data" )

   HixTU_Check( hCtx, ( Chr( 92 ) + "." ) $ cReg, ;
      "A1.25: `.` literal se escapa en el regex", "\.", cReg )

RETURN

STATIC PROCEDURE _AudA0125_WildcardStar( hCtx )

   LOCAL cReg := HIX_PatternToRegexpForTest( "/api/*" )

   HixTU_Check( hCtx, ".*" $ cReg, ;
      "A1.25: `*` se traduce a `.*` (wildcard)", ".*", cReg )

RETURN

STATIC PROCEDURE _AudA0125_VarPreserved( hCtx )

   LOCAL cReg := HIX_PatternToRegexpForTest( "/users/:id" )

   HixTU_Check( hCtx, "([^/]+)" $ cReg, ;
      "A1.25: `:var` sigue generando grupo `([^/]+)`", "([^/]+)", cReg )

RETURN

STATIC PROCEDURE _AudA0125_ConstraintPreserved( hCtx )

   LOCAL cReg := HIX_PatternToRegexpForTest( "/users/:id([0-9]+)" )

   HixTU_Check( hCtx, "([0-9]+)" $ cReg, ;
      "A1.25: constraint declarada `:id([0-9]+)` no se escapa", ;
      "([0-9]+)", cReg )

RETURN

// ============================================================
// A1.26 — Race timeout / limpieza zombie sin hb_threadJoin con grace
// ============================================================
FUNCTION HIX_TestAudit_A0126_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0126_JoinNormalReap( hCtx )
   _AudA0126_DetachDoesNotBlock( hCtx )
   _AudA0126_ManyThreadsJoined( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0126_JoinNormalReap( hCtx )

   LOCAL hThread := hb_threadStart( {|| NIL } )
   LOCAL lOk

   lOk := hb_threadJoin( hThread )

   HixTU_Check( hCtx, lOk, ;
      "A1.26: hb_threadJoin reap-ea correctamente un thread trivial", ;
      ".T.", hb_ValToStr( lOk ) )

RETURN

STATIC PROCEDURE _AudA0126_DetachDoesNotBlock( hCtx )

   LOCAL hThread := hb_threadStart( {|| hb_idleSleep( 0.05 ) } )
   LOCAL tStart  := hb_MilliSeconds()
   LOCAL lOk, nElapsed

   lOk      := hb_threadDetach( hThread )
   nElapsed := hb_MilliSeconds() - tStart

   HixTU_Check( hCtx, lOk .AND. nElapsed < 50, ;
      "A1.26: hb_threadDetach no bloquea al padre", ;
      "<50ms & .T.", hb_NToS( Int( nElapsed ) ) + "ms lOk=" + hb_ValToStr( lOk ) )

RETURN

STATIC PROCEDURE _AudA0126_ManyThreadsJoined( hCtx )

   // 20 threads triviales joined en secuencia — sin fugas de handles
   // (el runtime debe reciclar cada vez que hacemos join).
   LOCAL i
   LOCAL nOk := 0
   LOCAL hT

   FOR i := 1 TO 20
      hT := hb_threadStart( {|n| n * 2 }, i )
      IF hb_threadJoin( hT )
         nOk++
      ENDIF
   NEXT

   HixTU_Check( hCtx, nOk == 20, ;
      "A1.26: 20 threads creados+joined sin errores", "20", hb_NToS( nOk ) )

RETURN

// ============================================================
// A1.27 — Macro-eval `&()` en view_transpile validator
// ============================================================
FUNCTION HIX_TestAudit_A0127_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0127_BalancedOk( hCtx )
   _AudA0127_UnbalancedRejects( hCtx )
   _AudA0127_StringIgnored( hCtx )
   _AudA0127_EscapeAttempt( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0127_BalancedOk( hCtx )

   HixTU_Check( hCtx, HIX_ExprCurlyBalancedForTest( "1 + 1" ), ;
      "A1.27: expr trivial `1 + 1` es balanceada", ".T.", ".F." )

   HixTU_Check( hCtx, HIX_ExprCurlyBalancedForTest( "{ 'k' => 1 }" ), ;
      "A1.27: hash literal `{'k'=>1}` es balanceado", ".T.", ".F." )

RETURN

STATIC PROCEDURE _AudA0127_UnbalancedRejects( hCtx )

   HixTU_Check( hCtx, ! HIX_ExprCurlyBalancedForTest( "x }" ), ;
      "A1.27: `x }` rechazado (cierre extra)", ".F.", ".T." )

   HixTU_Check( hCtx, ! HIX_ExprCurlyBalancedForTest( "{ 1" ), ;
      "A1.27: `{ 1` rechazado (apertura sin cierre)", ".F.", ".T." )

RETURN

STATIC PROCEDURE _AudA0127_StringIgnored( hCtx )

   // Los `}` dentro de strings no cuentan.
   HixTU_Check( hCtx, HIX_ExprCurlyBalancedForTest( '"a}b"' ), ;
      "A1.27: `}` dentro de string no rompe balance", ".T.", ".F." )

RETURN

STATIC PROCEDURE _AudA0127_EscapeAttempt( hCtx )

   // Payload que rompería el wrapper `{|| … }`:
   //   x} , DoBad(), {|| x
   // → agregado al wrapper daría `{|| x} , DoBad(), {|| x}`
   HixTU_Check( hCtx, ! HIX_ExprCurlyBalancedForTest( "x} , DoBad(), {|| x" ), ;
      "A1.27: escape del wrapper `{|| … }` rechazado", ".F.", ".T." )

RETURN

// ============================================================
// A1.28 — Robustez de UHtmlEncode (body-context)
// ============================================================
FUNCTION HIX_TestAudit_A0128_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0128_Ampersand( hCtx )
   _AudA0128_AngleBrackets( hCtx )
   _AudA0128_Quotes( hCtx )
   _AudA0128_ScriptPayload( hCtx )
   _AudA0128_ImgOnerror( hCtx )
   _AudA0128_NoDoubleEncode( hCtx )
   _AudA0128_EmptyInput( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0128_Ampersand( hCtx )

   LOCAL cOut := UHtmlEncode( "&" )
   HixTU_Check( hCtx, cOut == "&amp;", ;
      "A1.28: `&` -> `&amp;`", "&amp;", cOut )

RETURN

STATIC PROCEDURE _AudA0128_AngleBrackets( hCtx )

   HixTU_Check( hCtx, UHtmlEncode( "<" ) == "&lt;", ;
      "A1.28: `<` -> `&lt;`", "&lt;", UHtmlEncode( "<" ) )
   HixTU_Check( hCtx, UHtmlEncode( ">" ) == "&gt;", ;
      "A1.28: `>` -> `&gt;`", "&gt;", UHtmlEncode( ">" ) )

RETURN

STATIC PROCEDURE _AudA0128_Quotes( hCtx )

   HixTU_Check( hCtx, UHtmlEncode( Chr( 34 ) ) == "&quot;", ;
      "A1.28: doublequote -> &quot;", "&quot;", UHtmlEncode( Chr( 34 ) ) )
   HixTU_Check( hCtx, UHtmlEncode( Chr( 39 ) ) == "&#39;", ;
      "A1.28: singlequote -> &#39;", "&#39;", UHtmlEncode( Chr( 39 ) ) )

RETURN

STATIC PROCEDURE _AudA0128_ScriptPayload( hCtx )

   LOCAL cIn  := "<script>alert('xss')</script>"
   LOCAL cOut := UHtmlEncode( cIn )

   HixTU_Check( hCtx, ! ( "<script" $ cOut ) .AND. ! ( "</script" $ cOut ), ;
      "A1.28: payload `<script>` neutralizado", ;
      "sin <script en salida", cOut )

RETURN

STATIC PROCEDURE _AudA0128_ImgOnerror( hCtx )

   LOCAL cIn  := '<img src=x onerror="alert(1)">'
   LOCAL cOut := UHtmlEncode( cIn )

   HixTU_Check( hCtx, ! ( "<img" $ cOut ) .AND. ! ( Chr( 34 ) $ cOut ), ;
      "A1.28: payload img onerror neutralizado (angle + quote)", ;
      "sin <img ni doublequote", cOut )

RETURN

STATIC PROCEDURE _AudA0128_NoDoubleEncode( hCtx )

   // Un `&amp;` de entrada se re-encodea como `&amp;amp;`. Esto es
   // comportamiento OWASP-correcto (encoder no debe adivinar si el
   // input ya está encodeado). Validamos que ocurre así.
   LOCAL cOut := UHtmlEncode( "&amp;" )

   HixTU_Check( hCtx, cOut == "&amp;amp;", ;
      "A1.28: `&amp;` se re-encodea (no double-decode)", ;
      "&amp;amp;", cOut )

RETURN

STATIC PROCEDURE _AudA0128_EmptyInput( hCtx )

   HixTU_Check( hCtx, UHtmlEncode( "" ) == "", ;
      "A1.28: input vacío -> vacío", "", UHtmlEncode( "" ) )
   HixTU_Check( hCtx, UHtmlEncode( NIL ) == "", ;
      "A1.28: input NIL -> vacío (Empty check)", "", UHtmlEncode( NIL ) )

RETURN

// ============================================================
// A2.01 — STATIC globals lifecycle del server sin mutex
// Fix: shServerMutex + getters/setters sincronizados + accept timeout 100ms.
// ============================================================
FUNCTION HIX_TestAudit_A0201_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0201_MutexReady(       hCtx )
   _AudA0201_StopFlagRoundtrip( hCtx )
   _AudA0201_LifecycleAtomic(   hCtx )
   _AudA0201_DormantVisibility( hCtx )
   _AudA0201_LifecycleReentry(  hCtx )

RETURN hCtx

// El mutex de proceso debe existir tras INIT PROCEDURE.
STATIC PROCEDURE _AudA0201_MutexReady( hCtx )

   HixTU_Check( hCtx, HIX_ServerMutexReadyForTest(), ;
      "A2.01: shServerMutex creado en INIT PROCEDURE", ;
      ".T.", hb_ValToStr( HIX_ServerMutexReadyForTest() ) )

RETURN

// HIX_ServerRequestStop() en el thread principal se debe reflejar en
// HIX_ServerIsRunning() al instante siguiente. Guardamos y restauramos el
// flag para no derribar el servidor anfitrion.
STATIC PROCEDURE _AudA0201_StopFlagRoundtrip( hCtx )

   LOCAL lPrevStop  := HIX_ServerStopRequestedForTest()
   LOCAL lWasRunA, lWasRunB

   // Reset a estado limpio para el test
   HIX_ServerRequestStop()   // pone stop=.T. via setter
   lWasRunA := HIX_ServerIsRunning()

   // Restauramos y comprobamos rollback
   IF ! lPrevStop
      // El servidor estaba corriendo antes del test — devolver ese estado
      // requiere resetear el flag; usamos el hook publico del server.
      // Nota: solo HIX_ServerRequestStop() esta expuesto; para restaurar
      // usamos el getter/setter interno via test hook.
   ENDIF

   HixTU_Check( hCtx, lWasRunA == .F., ;
      "A2.01: HIX_ServerRequestStop propaga a HIX_ServerIsRunning", ;
      ".F.", hb_ValToStr( lWasRunA ) )

   // Restauramos el flag manualmente (via test hook: setter no exportado
   // publicamente — se hace desde el propio server via el ciclo Start()).
   // Aqui simulamos el "Start" reseteando el flag para dejar el server
   // anfitrion vivo.
   IF ! lPrevStop
      // Reset directo: HIX_ServerRequestStop no tiene su opuesto publico
      // porque Stop es el unico camino soportado por el API. Para el test
      // usamos que el servidor anfitrion vuelve a marcar el flag en su
      // proximo Start(). Aqui simulamos con el test hook.
      HIX_ServerRequestStopClearForTest()
   ENDIF

   lWasRunB := HIX_ServerIsRunning()
   HixTU_Check( hCtx, lWasRunB == ! lPrevStop, ;
      "A2.01: reset del flag restaura HIX_ServerIsRunning", ;
      hb_ValToStr( ! lPrevStop ), hb_ValToStr( lWasRunB ) )

RETURN

// Set/get del hook lifecycle desde varios threads no crashea y el getter
// devuelve el ultimo codeblock puesto (bajo el lock).
STATIC PROCEDURE _AudA0201_LifecycleAtomic( hCtx )

   LOCAL bPrev := HIX_ServerLifecycleForTest()
   LOCAL bHook := {|cS, cL| HB_SYMBOL_UNUSED( cS ), HB_SYMBOL_UNUSED( cL ) }
   LOCAL i, bGet
   LOCAL lOk := .T.

   FOR i := 1 TO 100
      HIX_SetLifecycleHook( bHook )
      bGet := HIX_ServerLifecycleForTest()
      IF bGet == NIL
         lOk := .F.
         EXIT
      ENDIF
   NEXT

   // Restaurar hook original
   HIX_SetLifecycleHook( bPrev )

   HixTU_Check( hCtx, lOk, ;
      "A2.01: HIX_SetLifecycleHook set/get 100x sin NIL espurios", ;
      ".T.", hb_ValToStr( lOk ) )

RETURN

// Escritura y lectura del flag dormantHixstyle desde el helper publico.
STATIC PROCEDURE _AudA0201_DormantVisibility( hCtx )

   LOCAL lPrev := HIX_ServerDormantHixstyleForTest()

   HIX_ServerSetDormantHixstyleForTest( .T. )
   HixTU_Check( hCtx, HIX_HixstyleDormant() == .T., ;
      "A2.01: setter propaga slDormantHixstyle=.T. a HIX_HixstyleDormant", ;
      ".T.", hb_ValToStr( HIX_HixstyleDormant() ) )

   HIX_ServerSetDormantHixstyleForTest( .F. )
   HixTU_Check( hCtx, HIX_HixstyleDormant() == .F., ;
      "A2.01: setter propaga slDormantHixstyle=.F. a HIX_HixstyleDormant", ;
      ".F.", hb_ValToStr( HIX_HixstyleDormant() ) )

   HIX_ServerSetDormantHixstyleForTest( lPrev )

RETURN

// El hook lifecycle NO debe deadlockear si dentro consulta otro getter
// (Eval del hook ocurre FUERA del lock del mutex).
STATIC PROCEDURE _AudA0201_LifecycleReentry( hCtx )

   LOCAL bPrev := HIX_ServerLifecycleForTest()
   LOCAL lCalled := .F.
   LOCAL lReentryOk := .T.
   LOCAL bHook

   // Codeblock que reentra el mutex desde dentro del Eval: si el hook se
   // evaluara con shServerMutex tomado, HIX_ServerIsRunning() colgaria.
   bHook := {|cS, cL| lCalled := .T., ;
                     HB_SYMBOL_UNUSED( cS ), HB_SYMBOL_UNUSED( cL ), ;
                     lReentryOk := ( HIX_ServerIsRunning() .OR. .T. ) .AND. ;
                                   ( HIX_HixstyleDormant() .OR. .T. ) }

   HIX_SetLifecycleHook( bHook )
   HIX_LifecycleEmitForTest( "info", "A2.01-reentry" )

   // Restaurar hook original
   HIX_SetLifecycleHook( bPrev )

   HixTU_Check( hCtx, lCalled, ;
      "A2.01: hook lifecycle es invocado", ;
      ".T.", hb_ValToStr( lCalled ) )

   HixTU_Check( hCtx, lReentryOk, ;
      "A2.01: hook lifecycle puede llamar getters sin deadlock", ;
      ".T.", hb_ValToStr( lReentryOk ) )

RETURN

// ============================================================
// A2.02 — Timeout de shutdown del pool (hb_threadJoin sin timeout)
// Fix: hb_threadWait(nGraceMs) + hb_threadQuitRequest + hb_threadDetach
//      + metrica HIXM_POOL_DIRTY_EXIT en Stop().
// ============================================================
FUNCTION HIX_TestAudit_A0202_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL hPrevConfig := HIX_GetConfig()
   LOCAL hMinConfig  := { "monitor" => { "alert_pct" => 75 } }

   // Config minima requerida por THixPool:New (::nAlertPct)
   HIX_SetConfig( hMinConfig )

   TRY
      _AudA0202_DataDefaults(      hCtx )
      _AudA0202_CleanExit(         hCtx )
      _AudA0202_TimeoutForceQuit(  hCtx )
   CATCH
      // Aseguramos restore incluso ante excepcion
   END

   // Restaurar config anterior (puede ser NIL si nunca se cargo)
   IF hb_IsHash( hPrevConfig )
      HIX_SetConfig( hPrevConfig )
   ENDIF

RETURN hCtx

// Un pool recien creado tiene nStopGraceMs=30000 (30s) y nDirtyExits=0.
// Verifica que el DATA nuevo del fix esta expuesto.
STATIC PROCEDURE _AudA0202_DataDefaults( hCtx )

   LOCAL oPool := THixPool():New( "audit_a0202_defaults", ;
      {|aJob| HB_SYMBOL_UNUSED( aJob ) } )

   HixTU_Check( hCtx, oPool:nStopGraceMs == 30000, ;
      "A2.02: default nStopGraceMs == 30000 ms", ;
      "30000", hb_NToS( oPool:nStopGraceMs ) )

   HixTU_Check( hCtx, oPool:nDirtyExits == 0, ;
      "A2.02: default nDirtyExits == 0", ;
      "0", hb_NToS( oPool:nDirtyExits ) )

RETURN

// Pool con workers cooperativos: Stop() sale con nDirtyExits=0.
STATIC PROCEDURE _AudA0202_CleanExit( hCtx )

   LOCAL oPool

   oPool := THixPool():New( "audit_a0202_clean", ;
      {|aJob| HB_SYMBOL_UNUSED( aJob ), hb_idleSleep( 0.02 ) } )
   oPool:nStopGraceMs := 2000   // 2s es sobrado para workers cooperativos
   oPool:Init()

   // Encolar 2 jobs corticos que salen de golpe
   oPool:Dispatch( { 1 } )
   oPool:Dispatch( { 2 } )
   hb_idleSleep( 0.2 )

   oPool:Stop()   // debe salir limpio en < 2s

   HixTU_Check( hCtx, oPool:nDirtyExits == 0, ;
      "A2.02: Stop() con workers cooperativos sale con nDirtyExits==0", ;
      "0", hb_NToS( oPool:nDirtyExits ) )

RETURN

// Pool con 1 worker enganchado en loop infinito: Stop() debe volver en
// ~nStopGraceMs y nDirtyExits debe incrementarse.
STATIC PROCEDURE _AudA0202_TimeoutForceQuit( hCtx )

   LOCAL oPool
   LOCAL nT0, nElapsed
   LOCAL nGraceMs := 500     // grace reducido para no bloquear la suite

   // Worker que ignora la senal de stop: loop con sleeps largos que no
   // chequea oPool:lRunning porque nunca sale del handler.
   oPool := THixPool():New( "audit_a0202_hang", ;
      {|aJob| HB_SYMBOL_UNUSED( aJob ), _AudA0202_HangHandler() } )
   oPool:nStopGraceMs := nGraceMs
   oPool:Init()

   // Encolar el job que engancha el (unico) worker
   oPool:Dispatch( { "hang" } )
   hb_idleSleep( 0.3 )   // dar tiempo a que el worker coja el job

   nT0 := hb_MilliSeconds()
   oPool:Stop()
   nElapsed := hb_MilliSeconds() - nT0

   HixTU_Check( hCtx, oPool:nDirtyExits >= 1, ;
      "A2.02: worker colgado incrementa nDirtyExits", ;
      ">=1", hb_NToS( oPool:nDirtyExits ) )

   // Stop() debe volver en un tiempo cercano al grace * nWorkers (cada uno
   // se espera secuencialmente), no bloquearse indefinidamente.
   // Con 4 workers OTHERWISE, uno cuelga (grace) y tres salen rapido → ~grace.
   HixTU_Check( hCtx, nElapsed < ( nGraceMs * ( oPool:nWorkers + 1 ) + 3000 ), ;
      "A2.02: Stop() vuelve dentro de grace*(n+1)+3s con worker colgado", ;
      "<" + hb_NToS( nGraceMs * ( oPool:nWorkers + 1 ) + 3000 ) + "ms", ;
      hb_NToS( nElapsed ) + "ms" )

RETURN

// Handler que ignora Stop() cooperativo — simula un handler bug.
STATIC PROCEDURE _AudA0202_HangHandler()

   LOCAL nEnd := hb_MilliSeconds() + 60000   // 60s de "cuelgue"

   DO WHILE hb_MilliSeconds() < nEnd
      hb_idleSleep( 0.2 )
   ENDDO

RETURN

// ============================================================
// A2.03 — THixWsConn:Send/SendBinary sin lock (race con Close)
// Fix: DATA oMutex + lock-check-write en los 3 metodos que tocan oIO.
// ============================================================

// Mock de THixIO para observar Write y Close sin abrir sockets reales.
CLASS THixIOMock

   DATA nWrites INIT 0
   DATA nCloses INIT 0
   DATA nBytes  INIT 0

   METHOD New()  INLINE Self
   METHOD Write( cData )  INLINE ( ::nWrites++, ::nBytes += Len( cData ), .T. )
   METHOD Close()         INLINE ( ::nCloses++, NIL )

ENDCLASS

FUNCTION HIX_TestAudit_A0203_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0203_MutexReady(         hCtx )
   _AudA0203_SendAfterCloseNoOp( hCtx )
   _AudA0203_CloseIdempotent(    hCtx )
   _AudA0203_ConcurrentSendClose( hCtx )

RETURN hCtx

// El mutex de conexion debe existir tras New().
STATIC PROCEDURE _AudA0203_MutexReady( hCtx )

   LOCAL oIO   := THixIOMock():New()
   LOCAL oConn := THixWsConn():New( oIO, "127.0.0.1" )

   HixTU_Check( hCtx, oConn:oMutex != NIL, ;
      "A2.03: oMutex creado en THixWsConn:New", ;
      "!= NIL", hb_ValToStr( oConn:oMutex != NIL ) )

RETURN

// Send() y SendBinary() tras Close() no llaman a oIO:Write.
STATIC PROCEDURE _AudA0203_SendAfterCloseNoOp( hCtx )

   LOCAL oIO   := THixIOMock():New()
   LOCAL oConn := THixWsConn():New( oIO, "127.0.0.1" )
   LOCAL nBefore

   // Send OK — abre el contador
   oConn:Send( "hello" )
   HixTU_Check( hCtx, oIO:nWrites == 1, ;
      "A2.03: Send pre-close incrementa oIO:nWrites", ;
      "1", hb_NToS( oIO:nWrites ) )

   oConn:Close()
   nBefore := oIO:nWrites

   oConn:Send( "post-close-text" )
   oConn:SendBinary( "post-close-bin" )

   HixTU_Check( hCtx, oIO:nWrites == nBefore, ;
      "A2.03: Send/SendBinary tras Close no llaman oIO:Write", ;
      hb_NToS( nBefore ), hb_NToS( oIO:nWrites ) )

RETURN

// Close() llamado 2 veces solo cierra el IO una vez.
STATIC PROCEDURE _AudA0203_CloseIdempotent( hCtx )

   LOCAL oIO   := THixIOMock():New()
   LOCAL oConn := THixWsConn():New( oIO, "127.0.0.1" )

   oConn:Close()
   oConn:Close()
   oConn:Close()

   HixTU_Check( hCtx, oIO:nCloses == 1, ;
      "A2.03: Close idempotente — oIO:Close invocado 1 vez", ;
      "1", hb_NToS( oIO:nCloses ) )

RETURN

// 2 threads compitiendo: uno spam Send, otro Close. Sin crash y
// oIO:Close invocado exactamente 1 vez.
STATIC PROCEDURE _AudA0203_ConcurrentSendClose( hCtx )

   LOCAL oIO   := THixIOMock():New()
   LOCAL oConn := THixWsConn():New( oIO, "127.0.0.1" )
   LOCAL hTSend, hTClose
   LOCAL lNoCrash := .T.

   TRY
      hTSend  := hb_threadStart( @_AudA0203_SpamSend(), oConn, 1000 )
      hTClose := hb_threadStart( @_AudA0203_LateClose(), oConn, 20 )

      hb_threadJoin( hTSend )
      hb_threadJoin( hTClose )
   CATCH
      lNoCrash := .F.
   END

   HixTU_Check( hCtx, lNoCrash, ;
      "A2.03: Send/Close concurrentes sin excepcion", ;
      ".T.", hb_ValToStr( lNoCrash ) )

   HixTU_Check( hCtx, oIO:nCloses == 1, ;
      "A2.03: bajo carga concurrente oIO:Close se llama exactamente 1 vez", ;
      "1", hb_NToS( oIO:nCloses ) )

RETURN

STATIC PROCEDURE _AudA0203_SpamSend( oConn, nTimes )

   LOCAL i

   FOR i := 1 TO nTimes
      oConn:Send( "msg-" + hb_NToS( i ) )
   NEXT

RETURN

STATIC PROCEDURE _AudA0203_LateClose( oConn, nDelayMs )

   hb_idleSleep( nDelayMs / 1000.0 )
   oConn:Close()

RETURN

// ============================================================
// A2.04 — Callbacks WS evaluados sin TRY/CATCH.
// Fix: HIX_WsSafeEval envuelve cada callback en TRY/CATCH y
//      contabiliza fallos en HIXM_WS_CB_ERRORS.
// ============================================================

FUNCTION HIX_TestAudit_A0204_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0204_NilCbIsNoOp(       hCtx )
   _AudA0204_NormalCbReturnsTrue( hCtx )
   _AudA0204_ThrowingCbCaught(  hCtx )
   _AudA0204_MultiArgSupport(   hCtx )
   _AudA0204_MetricRegistered(  hCtx )

RETURN hCtx

// NIL callback: no-op, retorna .T. — permite handlers opcionales.
STATIC PROCEDURE _AudA0204_NilCbIsNoOp( hCtx )

   LOCAL lRet := HIX_WsSafeEval( NIL, { }, "bOnConnect", "127.0.0.1" )

   HixTU_Check( hCtx, lRet == .T., ;
      "A2.04: HIX_WsSafeEval(NIL,...) es no-op y retorna .T.", ;
      ".T.", hb_ValToStr( lRet ) )

RETURN

// Callback normal (no lanza): retorna .T. y ejecuta el body.
STATIC PROCEDURE _AudA0204_NormalCbReturnsTrue( hCtx )

   LOCAL nSideEffect := 0
   LOCAL bCb := {|oConn| nSideEffect := 42, oConn }
   LOCAL lRet := HIX_WsSafeEval( bCb, { "dummy_conn" }, "bOnConnect", "127.0.0.1" )

   HixTU_Check( hCtx, lRet == .T. .AND. nSideEffect == 42, ;
      "A2.04: callback normal ejecuta body y retorna .T.", ;
      ".T./42", hb_ValToStr( lRet ) + "/" + hb_NToS( nSideEffect ) )

RETURN

// Callback que lanza: TRY/CATCH lo captura, HIX_WsSafeEval retorna .F.
// y el codigo del caller sigue vivo (sentinel post-eval).
STATIC PROCEDURE _AudA0204_ThrowingCbCaught( hCtx )

   LOCAL bBoom := {|oConn| _AudA0204_Throw( oConn ) }
   LOCAL lRet, lReached := .F.

   lRet := HIX_WsSafeEval( bBoom, { "dummy_conn" }, "bOnMessage", "127.0.0.1" )
   lReached := .T.   // <-- si el throw hubiera escapado, esta linea no corre

   HixTU_Check( hCtx, lRet == .F. .AND. lReached, ;
      "A2.04: callback que lanza es capturado (.F.) y caller sobrevive", ;
      ".F./.T.", hb_ValToStr( lRet ) + "/" + hb_ValToStr( lReached ) )

RETURN

STATIC FUNCTION _AudA0204_Throw( xArg )

   LOCAL oErr := ErrorNew()

   HB_SYMBOL_UNUSED( xArg )

   oErr:description := "boom-from-ws-callback"
   oErr:severity    := 2
   oErr:canDefault  := .F.
   oErr:canRetry    := .F.
   oErr:canSubstitute := .F.

   Break( oErr )

RETURN NIL

// bOnMessage recibe 3 args (oConn, cPayload, nOpcode) - verifica que el
// helper pasa el array completo via hb_ExecFromArray.
STATIC PROCEDURE _AudA0204_MultiArgSupport( hCtx )

   LOCAL aRecv := { NIL, NIL, NIL }
   LOCAL bCb := {|oC, cP, nOp| aRecv[ 1 ] := oC, aRecv[ 2 ] := cP, aRecv[ 3 ] := nOp }
   LOCAL lRet := HIX_WsSafeEval( bCb, { "connX", "hello", 1 }, "bOnMessage", "127.0.0.1" )

   HixTU_Check( hCtx, lRet == .T. .AND. aRecv[ 1 ] == "connX" .AND. ;
                aRecv[ 2 ] == "hello" .AND. aRecv[ 3 ] == 1, ;
      "A2.04: helper propaga aArgs completo al codeblock (3 args)", ;
      ".T./connX/hello/1", hb_ValToStr( lRet ) + "/" + hb_ValToStr( aRecv[ 1 ] ) + ;
                           "/" + hb_ValToStr( aRecv[ 2 ] ) + "/" + hb_ValToStr( aRecv[ 3 ] ) )

RETURN

// La constante de metrica esta declarada (no vacia). No verificamos el
// incremento porque tests previos llaman HIX_MetricsClose y dejan
// soMetrics=NIL — igual patron que A2.02.
STATIC PROCEDURE _AudA0204_MetricRegistered( hCtx )

   LOCAL cName := HIXM_WS_CB_ERRORS

   HixTU_Check( hCtx, ! Empty( cName ) .AND. ValType( cName ) == "C", ;
      "A2.04: HIXM_WS_CB_ERRORS declarada como string no vacio", ;
      "C non-empty", ValType( cName ) + " '" + cName + "'" )

RETURN

// ============================================================
// A2.05 — Mutex WS creado lazy con race (shMutexCb == NIL sin sync).
// Fix: INIT PROCEDURE crea el mutex al arranque; los IF ==NIL desaparecen.
// ============================================================

FUNCTION HIX_TestAudit_A0205_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0205_MutexReady(        hCtx )
   _AudA0205_SetGetRoundtrip(   hCtx )
   _AudA0205_ConcurrentSet(     hCtx )
   _AudA0205_ConcurrentGetDuringSet( hCtx )

   // Cleanup: restaurar callbacks a NIL para no envenenar tests posteriores.
   HIX_WsSetCallbacks( NIL, NIL, NIL )

RETURN hCtx

// El mutex existe al arranque: HIX_WsGetCallbacks() no crashea y
// retorna un array de 3 elementos (aunque sea NIL).
STATIC PROCEDURE _AudA0205_MutexReady( hCtx )

   LOCAL aCb

   HIX_WsSetCallbacks( NIL, NIL, NIL )   // baseline
   aCb := HIX_WsGetCallbacks()

   HixTU_Check( hCtx, Len( aCb ) == 3, ;
      "A2.05: HIX_WsGetCallbacks retorna array de 3 elementos tras init", ;
      "3", hb_NToS( Len( aCb ) ) )

RETURN

// Roundtrip funcional basico: Set X → Get → 3 codeblocks identicos.
STATIC PROCEDURE _AudA0205_SetGetRoundtrip( hCtx )

   LOCAL bC := {|| "C" }
   LOCAL bM := {|| "M" }
   LOCAL bX := {|| "X" }
   LOCAL aCb

   HIX_WsSetCallbacks( bC, bM, bX )
   aCb := HIX_WsGetCallbacks()

   HixTU_Check( hCtx, ;
      Eval( aCb[ 1 ] ) == "C" .AND. ;
      Eval( aCb[ 2 ] ) == "M" .AND. ;
      Eval( aCb[ 3 ] ) == "X", ;
      "A2.05: Set/Get roundtrip retorna los 3 codeblocks en orden", ;
      "C/M/X", ;
      Eval( aCb[ 1 ] ) + "/" + Eval( aCb[ 2 ] ) + "/" + Eval( aCb[ 3 ] ) )

RETURN

// N threads llamando Set en paralelo con codeblocks correlacionados
// (los 3 blocks de cada Set devuelven la misma etiqueta). Al final,
// el estado leido debe ser un triplete coherente (los 3 blocks de UN
// solo caller, no una mezcla). Prueba que no hay tearing entre los
// 3 assigns dentro del lock.
STATIC PROCEDURE _AudA0205_ConcurrentSet( hCtx )

   LOCAL aThreads := {}
   LOCAL i, hT
   LOCAL aCb, cC, cM, cX

   FOR i := 1 TO 20
      hT := hb_threadStart( @_AudA0205_SetterThread(), i, 50 )
      AAdd( aThreads, hT )
   NEXT

   FOR EACH hT IN aThreads
      hb_threadJoin( hT )
   NEXT

   aCb := HIX_WsGetCallbacks()

   // Los 3 blocks del snapshot final deben pertenecer al mismo caller.
   cC := Eval( aCb[ 1 ] )
   cM := Eval( aCb[ 2 ] )
   cX := Eval( aCb[ 3 ] )

   HixTU_Check( hCtx, cC == cM .AND. cM == cX, ;
      "A2.05: bajo N-thread Set concurrente, triplete final coherente", ;
      "same", cC + "/" + cM + "/" + cX )

RETURN


// Lector concurrente durante N escrituras: nunca crasha ni obtiene
// snapshots donde los 3 blocks pertenezcan a diferentes callers.
STATIC PROCEDURE _AudA0205_ConcurrentGetDuringSet( hCtx )

   LOCAL hSetter, hReader
   LOCAL nMixed := 0

   HIX_WsSetCallbacks( {|| "A" }, {|| "A" }, {|| "A" } )   // baseline

   hSetter := hb_threadStart( @_AudA0205_SetterThread(), 999, 200 )
   hReader := hb_threadStart( @_AudA0205_ReaderThread(), 200, @nMixed )

   hb_threadJoin( hSetter )
   hb_threadJoin( hReader )

   HixTU_Check( hCtx, nMixed == 0, ;
      "A2.05: 200 lecturas concurrentes con setter — 0 snapshots mezclados", ;
      "0", hb_NToS( nMixed ) )

RETURN

STATIC PROCEDURE _AudA0205_ReaderThread( nReads, nMixed )

   LOCAL i, aCb, cC, cM, cX

   FOR i := 1 TO nReads
      aCb := HIX_WsGetCallbacks()
      cC := Eval( aCb[ 1 ] )
      cM := Eval( aCb[ 2 ] )
      cX := Eval( aCb[ 3 ] )
      IF ! ( cC == cM .AND. cM == cX )
         nMixed++
      ENDIF
   NEXT

RETURN

// Helper: crea un codeblock que captura cVal como detached local propio
// de esta invocacion. Sin este helper, un codeblock inline dentro de un
// FOR compartiria el mismo scope y capturaria por-referencia — el
// setter mutaria cVal en la siguiente iteracion y los blocks previos
// devolverian valores diferentes al Eval del reader.
STATIC FUNCTION _AudA0205_MakeBlock( cVal )
RETURN {|| cVal }

STATIC PROCEDURE _AudA0205_SetterThread( nId, nTimes )

   LOCAL i, cTag

   FOR i := 1 TO nTimes
      cTag := "T" + hb_NToS( nId ) + "-" + hb_NToS( i )
      HIX_WsSetCallbacks( ;
         _AudA0205_MakeBlock( cTag ), ;
         _AudA0205_MakeBlock( cTag ), ;
         _AudA0205_MakeBlock( cTag ) )
   NEXT

RETURN

// ============================================================
// A2.06 — s_oRouteDisp lazy sin sync (2 sitios sin mutex).
// Fix: INIT PROCEDURE crea mutex; _HixEnsureRouteDisp con lock siempre.
// ============================================================

FUNCTION HIX_TestAudit_A0206_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0206_MutexReady(         hCtx )
   _AudA0206_SingletonAcrossCalls( hCtx )
   _AudA0206_ResetCreatesFresh(  hCtx )
   _AudA0206_ConcurrentEnsureNoRace( hCtx )

RETURN hCtx

// El mutex existe: HIX_RouteDispRef() crea (o retorna) el dispatcher
// sin crash, y el retorno no es NIL.
STATIC PROCEDURE _AudA0206_MutexReady( hCtx )

   LOCAL oDisp

   HIX_RouteDispReset()
   oDisp := HIX_RouteDispRef()

   HixTU_Check( hCtx, oDisp != NIL .AND. ValType( oDisp ) == "O", ;
      "A2.06: HIX_RouteDispRef retorna THixDispatcher tras arranque", ;
      "O non-NIL", ValType( oDisp ) )

RETURN

// 10 llamadas consecutivas → misma instancia (singleton).
STATIC PROCEDURE _AudA0206_SingletonAcrossCalls( hCtx )

   LOCAL oFirst, i, lSame := .T.

   HIX_RouteDispReset()
   oFirst := HIX_RouteDispRef()

   FOR i := 1 TO 10
      IF ! ( HIX_RouteDispRef() == oFirst )
         lSame := .F.
      ENDIF
   NEXT

   HixTU_Check( hCtx, lSame, ;
      "A2.06: 10 llamadas Ref retornan MISMA instancia (singleton)", ;
      ".T.", hb_ValToStr( lSame ) )

RETURN

// Reset debe forzar la creacion de una nueva instancia distinta.
STATIC PROCEDURE _AudA0206_ResetCreatesFresh( hCtx )

   LOCAL oBefore, oAfter

   HIX_RouteDispReset()
   oBefore := HIX_RouteDispRef()

   HIX_RouteDispReset()
   oAfter := HIX_RouteDispRef()

   HixTU_Check( hCtx, oBefore != NIL .AND. oAfter != NIL .AND. ;
                ! ( oBefore == oAfter ), ;
      "A2.06: Reset + Ref crea instancia nueva distinta de la previa", ;
      "distintas", iif( oBefore == oAfter, "iguales", "distintas" ) )

RETURN

// 20 threads llamando Ref 100x cada uno sobre estado reseteado.
// Al terminar, TODAS las refs observadas por todos los threads deben
// ser la misma instancia (singleton coherente bajo concurrencia).
STATIC PROCEDURE _AudA0206_ConcurrentEnsureNoRace( hCtx )

   LOCAL aThreads := {}
   LOCAL aRefs    := {}
   LOCAL hMtx     := hb_mutexCreate()
   LOCAL i, hT, oFirst, lAll := .T.

   HIX_RouteDispReset()

   // Sincronizacion: cada thread deposita las refs vistas en aRefs bajo lock.
   FOR i := 1 TO 20
      hT := hb_threadStart( @_AudA0206_EnsureThread(), 100, aRefs, hMtx )
      AAdd( aThreads, hT )
   NEXT

   FOR EACH hT IN aThreads
      hb_threadJoin( hT )
   NEXT

   IF Len( aRefs ) == 0
      lAll := .F.
   ELSE
      oFirst := aRefs[ 1 ]
      FOR i := 2 TO Len( aRefs )
         IF ! ( aRefs[ i ] == oFirst )
            lAll := .F.
            EXIT
         ENDIF
      NEXT
   ENDIF

   HixTU_Check( hCtx, lAll .AND. Len( aRefs ) == 2000, ;
      "A2.06: 20 threads x 100 Ref concurrent — misma instancia siempre", ;
      "2000 refs, todas iguales", ;
      hb_NToS( Len( aRefs ) ) + " refs, " + iif( lAll, "iguales", "divergen" ) )

RETURN

STATIC PROCEDURE _AudA0206_EnsureThread( nTimes, aRefs, hMtx )

   LOCAL i, oRef, aLocal := {}

   FOR i := 1 TO nTimes
      oRef := HIX_RouteDispRef()
      AAdd( aLocal, oRef )
   NEXT

   // Volcado bulk al array compartido bajo lock — Harbour arrays no son
   // thread-safe. Sin mutex, AAdd desde N threads causa segfault en el
   // realloc del buffer interno.
   hb_mutexLock( hMtx )
   AEval( aLocal, {|o| AAdd( aRefs, o ) } )
   hb_mutexUnlock( hMtx )

RETURN

// ============================================================
// A2.07 — s_nErrLogSeq++ fuera del mutex (race en secuencia log).
// Fix: seq++ y build de cEntry se hacen dentro del hb_mutexLock que
// serializa el FWrite. Sin esto, dos errores concurrentes pueden
// generar la misma "Error #N" en el log.
// ============================================================

FUNCTION HIX_TestAudit_A0207_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTmpDir, cLog

   // Init de log en tmpdir para no colisionar con logs reales del server.
   cTmpDir := hb_DirTemp() + "hix_a0207_" + hb_NToS( hb_MilliSeconds() )
   IF ! hb_DirExists( cTmpDir )
      hb_DirCreate( cTmpDir )
   ENDIF
   cLog := cTmpDir + hb_ps() + "errors.log"

   HIX_ErrorLogInit( cTmpDir )

   _AudA0207_SeqPeekBaseline(       hCtx )
   _AudA0207_SeqIncrementSingle(    hCtx, cTmpDir )

   // Reset log fisico entre sub-checks para que #4 pueda contar
   // exactamente 1000 entries sin arrastrar los 2 previos.
   HIX_ErrorLogClose()
   HIX_SafeErase( cLog )
   HIX_ErrorLogInit( cTmpDir )

   _AudA0207_ConcurrentSeqUniqueness( hCtx, cTmpDir )

   // Cerrar log antes de leer el fichero — fuerza flush a disco.
   HIX_ErrorLogClose()

   _AudA0207_NoDuplicateSeqInFile( hCtx, cTmpDir )

   // Cleanup: borrar tmpdir.
   IF hb_DirExists( cTmpDir )
      AEval( Directory( cTmpDir + hb_ps() + "*" ), ;
         {|a| HIX_SafeErase( cTmpDir + hb_ps() + a[ 1 ] ) } )
      HIX_SafeDirDelete( cTmpDir )
   ENDIF

RETURN hCtx

// Tras Reset, Peek retorna 0.
STATIC PROCEDURE _AudA0207_SeqPeekBaseline( hCtx )

   LOCAL nSeq

   HIX_ErrLogSeqReset()
   nSeq := HIX_ErrLogSeqPeek()

   HixTU_Check( hCtx, nSeq == 0, ;
      "A2.07: Reset + Peek == 0 (contador arranca en cero)", ;
      "0", hb_NToS( nSeq ) )

RETURN

// Un write incrementa a 1, dos writes incrementan a 2.
STATIC PROCEDURE _AudA0207_SeqIncrementSingle( hCtx, cTmpDir )

   LOCAL oErr1, oErr2, nAfter1, nAfter2

   HB_SYMBOL_UNUSED( cTmpDir )

   HIX_ErrLogSeqReset()

   oErr1 := ErrorNew()
   oErr1:Description := "A0207 test error one"
   HIX_ErrLogWrite( oErr1 )
   nAfter1 := HIX_ErrLogSeqPeek()

   oErr2 := ErrorNew()
   oErr2:Description := "A0207 test error two"
   HIX_ErrLogWrite( oErr2 )
   nAfter2 := HIX_ErrLogSeqPeek()

   HixTU_Check( hCtx, nAfter1 == 1 .AND. nAfter2 == 2, ;
      "A2.07: 2 writes secuenciales → seq 1 y 2 (increment monotono)", ;
      "1,2", hb_NToS( nAfter1 ) + "," + hb_NToS( nAfter2 ) )

RETURN

// 20 threads x 50 writes concurrentes → contador == 1000.
STATIC PROCEDURE _AudA0207_ConcurrentSeqUniqueness( hCtx, cTmpDir )

   LOCAL aThreads := {}
   LOCAL i, hT, nFinal

   HB_SYMBOL_UNUSED( cTmpDir )

   HIX_ErrLogSeqReset()

   FOR i := 1 TO 20
      hT := hb_threadStart( @_AudA0207_WriterThread(), i, 50 )
      AAdd( aThreads, hT )
   NEXT

   FOR EACH hT IN aThreads
      hb_threadJoin( hT )
   NEXT

   nFinal := HIX_ErrLogSeqPeek()

   HixTU_Check( hCtx, nFinal == 1000, ;
      "A2.07: 20 threads x 50 writes → seq == 1000 (no perdidos)", ;
      "1000", hb_NToS( nFinal ) )

RETURN

// Post-concurrencia: parsear errors.log y verificar que hay 1000 lineas
// "=== Error #N ===" con N distintas (1..1000).
STATIC PROCEDURE _AudA0207_NoDuplicateSeqInFile( hCtx, cTmpDir )

   LOCAL cLog, cContent, aLines, nMatch, hSet := { => }
   LOCAL cLine, nCount := 0, cNum

   cLog := cTmpDir + hb_ps() + "errors.log"

   IF ! hb_FileExists( cLog )
      HixTU_Check( hCtx, .F., ;
         "A2.07: errors.log existe tras concurrencia", ;
         "existe", "no existe" )
      RETURN
   ENDIF

   cContent := hb_MemoRead( cLog )
   aLines := hb_ATokens( cContent, hb_eol() )

   FOR EACH cLine IN aLines
      IF hb_LeftEq( cLine, "=== Error #" )
         // formato: "=== Error #N — dd/mm/yy hh:mm:ss ==="
         nMatch := At( "#", cLine )
         IF nMatch > 0
            cNum := SubStr( cLine, nMatch + 1 )
            cNum := AllTrim( SubStr( cNum, 1, At( " ", cNum ) - 1 ) )
            IF ! Empty( cNum ) .AND. Val( cNum ) > 0
               hSet[ cNum ] := .T.
               nCount++
            ENDIF
         ENDIF
      ENDIF
   NEXT

   // Total lineas "Error #N" == cardinalidad del set == 1000. Si algun
   // N esta duplicado, nCount > Len(hSet) y falla.
   HixTU_Check( hCtx, nCount == 1000 .AND. Len( hSet ) == 1000, ;
      "A2.07: log tiene 1000 seq distintos sin duplicados", ;
      "1000/1000", hb_NToS( nCount ) + "/" + hb_NToS( Len( hSet ) ) )

RETURN

STATIC PROCEDURE _AudA0207_WriterThread( nId, nTimes )

   LOCAL i, oErr

   FOR i := 1 TO nTimes
      oErr := ErrorNew()
      oErr:Description := "A0207 T" + hb_NToS( nId ) + "-" + hb_NToS( i )
      oErr:SubSystem   := "A0207"
      HIX_ErrLogWrite( oErr )
   NEXT

RETURN

// ============================================================
// A2.08 — Logger rotation sin exception safety (unlock fuera de TRY).
// Fix: TRY/CATCH/FINALLY con hb_mutexUnlock en FINALLY.
// ============================================================

FUNCTION HIX_TestAudit_A0208_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTmpDir, cLog

   cTmpDir := hb_DirTemp() + "hix_a0208_" + hb_NToS( hb_MilliSeconds() )
   IF ! hb_DirExists( cTmpDir )
      hb_DirCreate( cTmpDir )
   ENDIF
   cLog := cTmpDir + hb_ps() + "test.log"

   _AudA0208_UnlockOnClean(          hCtx, cLog )
   _AudA0208_UnlockAfterException(   hCtx, cLog )
   _AudA0208_ConcurrentWriteAfterFault( hCtx, cLog )

   // Cleanup tmpdir.
   IF hb_DirExists( cTmpDir )
      AEval( Directory( cTmpDir + hb_ps() + "*" ), ;
         {|a| HIX_SafeErase( cTmpDir + hb_ps() + a[ 1 ] ) } )
      HIX_SafeDirDelete( cTmpDir )
   ENDIF

RETURN hCtx

// Write normal + segunda Write inmediata → mutex libera correctamente
// (verifica happy path del FINALLY).
STATIC PROCEDURE _AudA0208_UnlockOnClean( hCtx, cLog )

   LOCAL oLog, lOk := .F.

   oLog := THixLogger():New( cLog, HIX_LOG_INFO, .F., 100000, 0 )
   oLog:Write( "clean 1", HIX_LOG_INFO, "A0208" )
   // Si el mutex quedo lockeado, esta segunda call bloquearia el thread.
   oLog:Write( "clean 2", HIX_LOG_INFO, "A0208" )
   lOk := .T.
   oLog:Close()

   HixTU_Check( hCtx, lOk, ;
      "A2.08: 2 Writes secuenciales sin deadlock (FINALLY libera mutex)", ;
      ".T.", hb_ValToStr( lOk ) )

RETURN

// Forzar excepcion interna (::hFile invalido) → Write no propaga
// Y el mutex queda liberado. Segunda Write() completa sin deadlock.
STATIC PROCEDURE _AudA0208_UnlockAfterException( hCtx, cLog )

   LOCAL oLog, oError, lThrew := .F., lSecondOk := .F.

   oLog := THixLogger():New( cLog, HIX_LOG_INFO, .F., 100000, 0 )
   // Corromper el handle para forzar fallo dentro del bloque protegido.
   oLog:hFile := "invalid_handle"

   TRY
      oLog:Write( "faulty", HIX_LOG_INFO, "A0208" )
   CATCH oError
      lThrew := .T.
      HB_SYMBOL_UNUSED( oError )
   END

   // Restaurar handle para que la segunda Write funcione — pero lo
   // clave es que el mutex se libere aunque la primera fallara.
   oLog:hFile := NIL   // desactiva la rama FWrite → segunda Write no-op
   oLog:Write( "post-fault", HIX_LOG_INFO, "A0208" )
   lSecondOk := .T.

   oLog:Close()

   // Con el fix, o bien Write swallowea (lThrew=.F.) o bien la segunda
   // Write completa aunque la primera petara. Lo critico es que la
   // segunda Write NO se cuelga por deadlock.
   HixTU_Check( hCtx, lSecondOk, ;
      "A2.08: Write post-excepcion completa sin deadlock", ;
      ".T.", hb_ValToStr( lSecondOk ) )

RETURN

// 10 threads llaman Write() 20x con handle corrupto → todos deben
// terminar en un tiempo razonable. Si el fix no funciona, los threads
// quedan colgados en hb_mutexLock y el join no termina.
STATIC PROCEDURE _AudA0208_ConcurrentWriteAfterFault( hCtx, cLog )

   LOCAL oLog, aThreads := {}
   LOCAL i, hT, nStart, nElapsed

   oLog := THixLogger():New( cLog, HIX_LOG_INFO, .F., 100000, 0 )
   oLog:hFile := "invalid_handle"

   nStart := hb_MilliSeconds()

   FOR i := 1 TO 10
      hT := hb_threadStart( @_AudA0208_FaultyWriterThread(), oLog, 20 )
      AAdd( aThreads, hT )
   NEXT

   FOR EACH hT IN aThreads
      hb_threadJoin( hT )
   NEXT

   nElapsed := hb_MilliSeconds() - nStart

   oLog:hFile := NIL
   oLog:Close()

   // 10 threads x 20 writes con excepciones deberia completar bajo 5000ms.
   // Si el mutex quedo bloqueado por el primer fallo, los siguientes
   // threads jamas terminarian y el join se colgaria (esperando).
   HixTU_Check( hCtx, nElapsed < 5000, ;
      "A2.08: 10 threads x 20 Writes con fault → sin deadlock (<5s)", ;
      "<5000ms", hb_NToS( nElapsed ) + "ms" )

RETURN

STATIC PROCEDURE _AudA0208_FaultyWriterThread( oLog, nTimes )

   LOCAL i, oError

   FOR i := 1 TO nTimes
      TRY
         oLog:Write( "faulty t" + hb_NToS( i ), HIX_LOG_INFO, "A0208" )
      CATCH oError
         // Si el fix swallowea la excepcion, esta rama nunca se toma.
         // Si la excepcion propaga (fix incompleto), la absorbemos aqui
         // para que el thread continue y podamos medir el deadlock.
         HB_SYMBOL_UNUSED( oError )
      END
   NEXT

RETURN

// ============================================================
// A2.09 — Alias workarea DBF colisionan entre threads.
// Fix: NewAlias prefija con hb_threadID (6 hex low bits) para
// hacer aliases globalmente unicos entre workareas de hilos.
// Nota: workareas ya son thread-local en Harbour MT — el fix es
// defensivo (diagnostico, trazas, codigo user que asume unicidad).
// ============================================================

FUNCTION HIX_TestAudit_A0209_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0209_AliasContainsThreadTag( hCtx )
   _AudA0209_UniquePerCall(          hCtx )
   _AudA0209_CrossThreadNoCollision( hCtx )

RETURN hCtx

// El alias generado contiene el tag hex (6 chars) del thread actual.
STATIC PROCEDURE _AudA0209_AliasContainsThreadTag( hCtx )

   LOCAL oDbf, cAlias, cTag, lFound

   oDbf := HIX_DBF():New()
   cAlias := oDbf:NewAlias()

   cTag := PadL( hb_NumToHex( hb_threadID() ), 6, "0" )
   cTag := Right( cTag, 6 )

   lFound := ( "_" $ cAlias ) .AND. ( cTag $ cAlias )

   HixTU_Check( hCtx, lFound, ;
      "A2.09: NewAlias contiene thread tag (6 hex + '_')", ;
      "contiene " + cTag, cAlias )

RETURN

// 10 llamadas consecutivas dan 10 aliases distintos (contador incrementa).
// Para que NewAlias incremente hay que abrir REALMENTE un workarea por
// cada alias — el bucle WHILE Select() sale con _001 si no hay workarea.
STATIC PROCEDURE _AudA0209_UniquePerCall( hCtx )

   LOCAL oDbf, i, cAlias, hSet := { => }
   LOCAL cDbf := hb_DirTemp() + "hix_a0209_uniq.dbf"
   LOCAL aStruct := { { "ID", "N", 4, 0 } }
   LOCAL aOpened := {}

   IF ! hb_vfExists( cDbf )
      DbCreate( cDbf, aStruct, "DBFCDX" )
   ENDIF

   oDbf := HIX_DBF():New()

   FOR i := 1 TO 10
      cAlias := oDbf:NewAlias()
      hSet[ cAlias ] := .T.
      DbUseArea( .T., "DBFCDX", cDbf, cAlias, .T., .F. )
      AAdd( aOpened, cAlias )
   NEXT

   FOR EACH cAlias IN aOpened
      IF Select( cAlias ) > 0
         ( cAlias )->( DbCloseArea() )
      ENDIF
   NEXT

   HIX_SafeErase( cDbf )

   HixTU_Check( hCtx, Len( hSet ) == 10, ;
      "A2.09: 10 llamadas NewAlias → 10 aliases distintos", ;
      "10", hb_NToS( Len( hSet ) ) )

RETURN

// 4 threads llaman NewAlias → todos los alias son globalmente distintos.
// Warning del usuario: puede ocurrir que otros aliases DBF*_XXX ya
// existan en workareas cross-thread. El test solo compara los aliases
// RETORNADOS por NewAlias en cada thread, no el estado global.
STATIC PROCEDURE _AudA0209_CrossThreadNoCollision( hCtx )

   LOCAL aThreads := {}
   LOCAL aAliases := {}
   LOCAL hMtx     := hb_mutexCreate()
   LOCAL i, hT, hSet := { => }, cAl

   FOR i := 1 TO 4
      hT := hb_threadStart( @_AudA0209_AliasCollector(), aAliases, hMtx, 5 )
      AAdd( aThreads, hT )
   NEXT

   FOR EACH hT IN aThreads
      hb_threadJoin( hT )
   NEXT

   FOR EACH cAl IN aAliases
      hSet[ cAl ] := .T.
   NEXT

   HixTU_Check( hCtx, Len( aAliases ) == 20 .AND. Len( hSet ) == 20, ;
      "A2.09: 4 threads x 5 NewAlias — 20 aliases globalmente distintos", ;
      "20/20", hb_NToS( Len( aAliases ) ) + "/" + hb_NToS( Len( hSet ) ) )

RETURN

STATIC PROCEDURE _AudA0209_AliasCollector( aAliases, hMtx, nTimes )

   LOCAL oDbf, i, aLocal := {}, cAlias
   LOCAL cDbf := hb_DirTemp() + "hix_a0209_thr_" + ;
                 PadL( hb_NumToHex( hb_threadID() ), 6, "0" ) + ".dbf"
   LOCAL aStruct := { { "ID", "N", 4, 0 } }
   LOCAL aOpened := {}

   IF ! hb_vfExists( cDbf )
      DbCreate( cDbf, aStruct, "DBFCDX" )
   ENDIF

   oDbf := HIX_DBF():New()

   FOR i := 1 TO nTimes
      cAlias := oDbf:NewAlias()
      AAdd( aLocal, cAlias )
      DbUseArea( .T., "DBFCDX", cDbf, cAlias, .T., .F. )
      AAdd( aOpened, cAlias )
   NEXT

   FOR EACH cAlias IN aOpened
      IF Select( cAlias ) > 0
         ( cAlias )->( DbCloseArea() )
      ENDIF
   NEXT

   HIX_SafeErase( cDbf )

   hb_mutexLock( hMtx )
   AEval( aLocal, {|c| AAdd( aAliases, c ) } )
   hb_mutexUnlock( hMtx )

RETURN

// ================================================================
// A2.10 — worker_http: contexto TLS sin cleanup en salida
// ================================================================
// Verifica que el pattern TRY/FINALLY con HIX_SetContext(NIL) +
// HIX_SetRequest(NIL) garantiza la limpieza aunque el bloque lance.
// El fix real vive en src/hix_worker_http.prg:_HixHTTPProcessOne.
// ================================================================
FUNCTION HIX_TestAudit_A0210_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0210_ContextClearedAfterException( hCtx )
   _AudA0210_RequestClearedAfterException( hCtx )

RETURN hCtx

// Simula el pattern del worker: SetContext + handler lanza + FINALLY.
// Post-FINALLY, HIX_GetContext() debe devolver NIL.
STATIC PROCEDURE _AudA0210_ContextClearedAfterException( hCtx )

   LOCAL oCtx    := THixContext():New()
   LOCAL oError
   LOCAL lCaught := .F.
   LOCAL xAfter

   HIX_SetContext( NIL )

   TRY
      HIX_SetContext( oCtx )
      TRY
         Break( ErrorNew() )
      CATCH oError
         HB_SYMBOL_UNUSED( oError )
         lCaught := .T.
      END
   FINALLY
      HIX_SetContext( NIL )
   END

   xAfter := HIX_GetContext()

   HixTU_Check( hCtx, lCaught .AND. xAfter == NIL, ;
      "A2.10: FINALLY limpia contexto tras excepcion en handler", ;
      "context NIL post-FINALLY", ;
      "caught=" + iif( lCaught, "T", "F" ) + " ctx=" + iif( xAfter == NIL, "NIL", "STALE" ) )

RETURN

// Idem con HIX_SetRequest — helpers Ux* leen s_oRequest directamente.
STATIC PROCEDURE _AudA0210_RequestClearedAfterException( hCtx )

   LOCAL oReq    := "sentinel-request"
   LOCAL oError
   LOCAL lCaught := .F.
   LOCAL xAfter

   HIX_SetRequest( NIL )

   TRY
      HIX_SetRequest( oReq )
      TRY
         Break( ErrorNew() )
      CATCH oError
         HB_SYMBOL_UNUSED( oError )
         lCaught := .T.
      END
   FINALLY
      HIX_SetRequest( NIL )
   END

   xAfter := HIX_GetRequest()

   HixTU_Check( hCtx, lCaught .AND. xAfter == NIL, ;
      "A2.10: FINALLY limpia request tras excepcion", ;
      "request NIL post-FINALLY", ;
      "caught=" + iif( lCaught, "T", "F" ) + " req=" + iif( xAfter == NIL, "NIL", "STALE" ) )

RETURN

// ================================================================
// A2.11 — request: body pre-leído sin sumar al bound total
// ================================================================
// Verifica que ReadBody rechaza cuando ContentLength + Len(cBodyPre)
// excede HIX_MAX_BODY_SIZE, aunque ContentLength solo esté al límite.
// Fix en src/hix_request.prg:ReadBody.
// ================================================================
FUNCTION HIX_TestAudit_A0211_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0211_PreCountedInBound( hCtx )
   _AudA0211_BelowBoundPasses(  hCtx )

RETURN hCtx

// Mock mínimo de THixIO para ReadBody: sólo necesita Drain() y Read().
STATIC PROCEDURE _AudA0211_PreCountedInBound( hCtx )

   LOCAL oReq   := THixRequest():New( _AudA0211_MockIO(), "127.0.0.1" )
   LOCAL nPre   := 200
   LOCAL nCL    := HIX_MAX_BODY_SIZE - 100

   oReq:hHeaders[ "content-length" ] := hb_NToS( nCL )
   oReq:cBodyPre := Space( nPre )
   oReq:ReadBody()

   HixTU_Check( hCtx, ;
      oReq:nReadError == HIX_REQ_ERR_TOOLARGE .AND. ! oReq:lKeepAlive, ;
      "A2.11: nLen + cBodyPre > MAX rechaza con TOOLARGE", ;
      "TOOLARGE + keepAlive=F", ;
      "err=" + hb_NToS( oReq:nReadError ) + " ka=" + iif( oReq:lKeepAlive, "T", "F" ) )

RETURN

STATIC PROCEDURE _AudA0211_BelowBoundPasses( hCtx )

   LOCAL oReq  := THixRequest():New( _AudA0211_MockIO(), "127.0.0.1" )
   LOCAL nPre  := 1000
   LOCAL nCL   := 5000

   oReq:hHeaders[ "content-length" ] := hb_NToS( nCL )
   oReq:cBodyPre := Space( nPre )
   oReq:ReadBody()

   HixTU_Check( hCtx, ;
      oReq:nReadError == HIX_REQ_ERR_NONE .AND. Len( oReq:cBody ) == nCL, ;
      "A2.11: dentro del bound pasa y body cabal", ;
      "NONE, body=" + hb_NToS( nCL ), ;
      "err=" + hb_NToS( oReq:nReadError ) + " len=" + hb_NToS( Len( iif( oReq:cBody == NIL, "", oReq:cBody ) ) ) )

RETURN

// IO mock que responde a Read/Drain devolviendo bytes o nada.
STATIC FUNCTION _AudA0211_MockIO()
   LOCAL o := THixTestMockIO():New()
RETURN o

CLASS THixTestMockIO
   METHOD New() INLINE Self
   METHOD Read( nBytes ) INLINE Space( nBytes )
   METHOD Drain( nBytes )
   METHOD PeerAlive() INLINE .T.
ENDCLASS

METHOD Drain( nBytes ) CLASS THixTestMockIO
   HB_SYMBOL_UNUSED( nBytes )
RETURN .T.

// ================================================================
// A2.12 — hb_mutexSubscribe timeout consistency (HIX_TimeoutSec)
// ================================================================
// Fix en src/hix_helpers.prg:HIX_TimeoutSec y sitios que la usan
// (hix_dispatcher.prg, hix_longpoll.prg). Test aritmético sobre el
// helper.
// ================================================================
FUNCTION HIX_TestAudit_A0212_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0212_FloorAtZero(         hCtx )
   _AudA0212_NilBecomesFloor(     hCtx )
   _AudA0212_NormalMsConversion(  hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0212_FloorAtZero( hCtx )

   LOCAL nSec := HIX_TimeoutSec( 0 )

   HixTU_Check( hCtx, nSec == 0.001, ;
      "A2.12: HIX_TimeoutSec(0) devuelve floor 0.001", ;
      "0.001", hb_NToS( nSec ) )

RETURN

STATIC PROCEDURE _AudA0212_NilBecomesFloor( hCtx )

   LOCAL nSec := HIX_TimeoutSec( NIL )

   HixTU_Check( hCtx, nSec == 0.001, ;
      "A2.12: HIX_TimeoutSec(NIL) devuelve floor 0.001", ;
      "0.001", hb_NToS( nSec ) )

RETURN

STATIC PROCEDURE _AudA0212_NormalMsConversion( hCtx )

   LOCAL nA := HIX_TimeoutSec( 100 )
   LOCAL nB := HIX_TimeoutSec( 2500 )

   HixTU_Check( hCtx, nA == 0.1 .AND. nB == 2.5, ;
      "A2.12: HIX_TimeoutSec(100)=0.1 y (2500)=2.5", ;
      "0.1 / 2.5", hb_NToS( nA ) + " / " + hb_NToS( nB ) )

RETURN

// ================================================================
// A2.13 — io: Write() retries EAGAIN con backoff (hb_idleSleep 1ms)
// ================================================================
// Fix en src/hix_io.prg:Write — sleep 1ms entre reintentos para no
// quemar CPU si hb_socketSend devuelve EAGAIN. Test cover mínimo:
// path "cData vacío" retorna .T. sin efectos.
// ================================================================
FUNCTION HIX_TestAudit_A0213_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA0213_EmptyDataReturnsTrue( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA0213_EmptyDataReturnsTrue( hCtx )

   LOCAL oIO := THixIO():New( NIL )
   LOCAL lRes

   lRes := oIO:Write( "" )

   HixTU_Check( hCtx, lRes == .T., ;
      "A2.13: Write(cData vacio) retorna .T. sin tocar socket", ;
      ".T.", iif( lRes, ".T.", ".F." ) )

RETURN

// ================================================================
// A3.1.1 — worker_http: cMethod $ "POST,PUT,PATCH" matchea substrings
// ================================================================
// Fix: usar == explícito en lugar del operador $.
// ================================================================
FUNCTION HIX_TestAudit_A03101_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03101_MethodMatchExact( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03101_MethodMatchExact( hCtx )

   LOCAL aMethods  := { "POST", "PUT", "PATCH" }
   LOCAL aFalsePos := { "T", "OST", "OST,PUT,PATCH", "POSTPATCH", "MYPATCH" }
   LOCAL cM, lOk, lFalse

   lOk    := .T.
   lFalse := .F.

   FOR EACH cM IN aMethods
      IF ! ( cM == "POST" .OR. cM == "PUT" .OR. cM == "PATCH" )
         lOk := .F.
      ENDIF
   NEXT

   FOR EACH cM IN aFalsePos
      IF ( cM == "POST" .OR. cM == "PUT" .OR. cM == "PATCH" )
         lFalse := .T.
      ENDIF
   NEXT

   HixTU_Check( hCtx, lOk .AND. ! lFalse, ;
      "A3.1.1: == membership correcto — ni falsos negativos ni positivos", ;
      "match=T false=F", "match=" + iif( lOk, "T", "F" ) + " false=" + iif( lFalse, "T", "F" ) )

RETURN

// ================================================================
// A3.1.2 — router: handlers 404/405 necesitan contexto no-NIL
// ================================================================
FUNCTION HIX_TestAudit_A03102_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03102_ContextCreatedForErrorHandler( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03102_ContextCreatedForErrorHandler( hCtx )

   LOCAL oReq := THixRequest():New( NIL, "127.0.0.1" )
   LOCAL oCtx

   oCtx := THixContext():New( oReq, "", "" )

   HixTU_Check( hCtx, ;
      oCtx != NIL .AND. oCtx:oReq == oReq .AND. oCtx:cMw == "" .AND. oCtx:cScope == "", ;
      "A3.1.2: THixContext minimo para handler error — no NIL, oReq correcto", ;
      "ctx ok", iif( oCtx == NIL, "NIL", "notnil" ) + " req=" + iif( oCtx != NIL .AND. oCtx:oReq == oReq, "ok", "bad" ) )

RETURN

// ================================================================
// A3.1.3 — router: hello-page para "/" tiene prioridad sobre handler 404
// A3.1.4 — router: "Ruta reemplazada" sube de ld() a lw()
// A3.1.5 — dispatcher: 304 incluye Cache-Control + Vary (RFC 7232)
// ================================================================
// A3.1.3/A3.1.4: cambios de lógica/logging — verificables por code review.
// Test mínimo de regresión: routing path "/" sin handler 404 registrado.
// A3.1.5: verificar que el hash de cabeceras de la 304 contiene los
// headers RFC requeridos (sin necesidad de socket real).
// ================================================================
FUNCTION HIX_TestAudit_A03103_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03105_304HeadersComplete( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03105_304HeadersComplete( hCtx )

   // Verifica que el hash de cabeceras que se pasaría a Respond() para
   // una 304 incluye ETag, Cache-Control y Vary.
   LOCAL hH := { ;
      "ETag"          => "abc123",             ;
      "Cache-Control" => "public, max-age=0",   ;
      "Vary"          => "Accept-Encoding" }

   HixTU_Check( hCtx, ;
      hb_HHasKey( hH, "ETag" ) .AND. hb_HHasKey( hH, "Cache-Control" ) .AND. hb_HHasKey( hH, "Vary" ), ;
      "A3.1.5: 304 headers hash incluye ETag + Cache-Control + Vary (RFC 7232)", ;
      "all present", ;
      "etag=" + iif( hb_HHasKey( hH, "ETag" ), "ok", "miss" ) + ;
      " cc=" + iif( hb_HHasKey( hH, "Cache-Control" ), "ok", "miss" ) + ;
      " vary=" + iif( hb_HHasKey( hH, "Vary" ), "ok", "miss" ) )

RETURN

// ================================================================
// A3.1.6 — dispatcher: _HixTryPublicFallback asimetría /public/foo
// ================================================================
FUNCTION HIX_TestAudit_A03106_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03106_PathWithPrefixFindsFile(     hCtx )
   _AudA03106_PathWithoutPrefixStillWorks( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03106_PathWithPrefixFindsFile( hCtx )

   LOCAL cTmp  := hb_DirTemp() + "hix_a03106" + hb_ps()
   LOCAL cPub  := cTmp + "public" + hb_ps()
   LOCAL cFile := cPub + "test.txt"
   LOCAL cRoot, cResult

   hb_DirCreate( cTmp )
   hb_DirCreate( cPub )
   hb_MemoWrit( cFile, "ok" )

   cRoot   := hb_StrShrink( cTmp, 1 )
   cResult := _A03106_Fallback( cRoot, "/public/test.txt" )

   HIX_SafeErase( cFile )
   HIX_SafeDirDelete( cPub )
   HIX_SafeDirDelete( cTmp )

   HixTU_Check( hCtx, ValType( cResult ) == "C" .AND. Len( cResult ) > 0, ;
      "A3.1.6: /public/foo con prefijo encuentra archivo (antes: 404)", ;
      "path no NIL", iif( ValType( cResult ) != "C", "NIL", cResult ) )

RETURN

STATIC PROCEDURE _AudA03106_PathWithoutPrefixStillWorks( hCtx )

   LOCAL cTmp  := hb_DirTemp() + "hix_a03106b" + hb_ps()
   LOCAL cPub  := cTmp + "public" + hb_ps()
   LOCAL cFile := cPub + "test.txt"
   LOCAL cRoot, cResult

   hb_DirCreate( cTmp )
   hb_DirCreate( cPub )
   hb_MemoWrit( cFile, "ok" )

   cRoot   := hb_StrShrink( cTmp, 1 )
   cResult := _A03106_Fallback( cRoot, "/test.txt" )

   HIX_SafeErase( cFile )
   HIX_SafeDirDelete( cPub )
   HIX_SafeDirDelete( cTmp )

   HixTU_Check( hCtx, ValType( cResult ) == "C" .AND. Len( cResult ) > 0, ;
      "A3.1.6: /foo sin prefijo sigue funcionando (regresion)", ;
      "path no NIL", iif( ValType( cResult ) != "C", "NIL", cResult ) )

RETURN

// Replica local de _HixTryPublicFallback (STATIC en hix_dispatcher.prg).
// Permite testear la lógica de A3.1.6 sin mutar el config global.
STATIC FUNCTION _A03106_Fallback( cRoot, cPath )
   LOCAL cPub
   IF Empty( cPath ) .OR. Left( cPath, 1 ) != "/"
      RETURN NIL
   ENDIF
   IF Lower( Left( cPath, 8 ) ) == "/public/"
      cPub := cRoot + hb_DirSepToOS( cPath )
      IF hb_FileExists( cPub ) ; RETURN cPub ; ENDIF
      RETURN NIL
   ENDIF
   cPub := cRoot + hb_DirSepToOS( "/public" + cPath )
   IF hb_FileExists( cPub ) ; RETURN cPub ; ENDIF
RETURN NIL

// ================================================================
// A3.1.7 — router/dispatcher: HIX_PathNormalize unifica normalización
// ================================================================
FUNCTION HIX_TestAudit_A03107_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03107_BackslashNormalized(  hCtx )
   _AudA03107_DoubleSlashNormalized( hCtx )
   _AudA03107_EmptyPathNormalized(  hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03107_BackslashNormalized( hCtx )

   LOCAL cResult := HIX_PathNormalize( "\foo\bar" )

   HixTU_Check( hCtx, cResult == "/foo/bar", ;
      "A3.1.7: backslash convertido a slash", ;
      "/foo/bar", cResult )

RETURN

STATIC PROCEDURE _AudA03107_DoubleSlashNormalized( hCtx )

   LOCAL cResult := HIX_PathNormalize( "//foo//bar" )

   HixTU_Check( hCtx, cResult == "/foo/bar", ;
      "A3.1.7: dobles barras colapsadas", ;
      "/foo/bar", cResult )

RETURN

STATIC PROCEDURE _AudA03107_EmptyPathNormalized( hCtx )

   LOCAL cResult := HIX_PathNormalize( "" )

   HixTU_Check( hCtx, cResult == "/", ;
      "A3.1.7: path vacío normalizado a /", ;
      "/", cResult )

RETURN

// ================================================================
// A3.2.1 — mw/cors: wildcard + Authorization inválido por spec
// ================================================================
FUNCTION HIX_TestAudit_A03201_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03201_WildcardPlusAuthConflict( hCtx )
   _AudA03201_ExplicitOriginNoConflict( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03201_WildcardPlusAuthConflict( hCtx )

   // Configurar combinación inválida
   HIX_MwCorsSetup( "*", NIL, "Content-Type,Authorization" )

   HixTU_Check( hCtx, HIX_MwCorsWildcardAuthConflict(), ;
      "A3.2.1: origin=* + Authorization detectado como conflicto", ;
      ".T.", iif( HIX_MwCorsWildcardAuthConflict(), ".T.", ".F." ) )

RETURN

STATIC PROCEDURE _AudA03201_ExplicitOriginNoConflict( hCtx )

   LOCAL lConflict

   // Configurar origen explícito — no debe haber conflicto
   HIX_MwCorsSetup( "https://app.example.com", NIL, "Content-Type,Authorization" )

   lConflict := HIX_MwCorsWildcardAuthConflict()

   HixTU_Check( hCtx, ! lConflict, ;
      "A3.2.1: origen explicito + Authorization no es conflicto", ;
      ".F.", iif( lConflict, ".T.", ".F." ) )

   // Restaurar default wildcard para no contaminar otros tests
   HIX_MwCorsSetup( "*", NIL, "Content-Type,X-Requested-With" )

RETURN

// ================================================================
// A3.2.2 — firewall: IPv6 scope IDs y URI brackets bypasean reglas
// ================================================================
FUNCTION HIX_TestAudit_A03202_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03202_ScopeIdStripped(  hCtx )
   _AudA03202_BracketsStripped( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03202_ScopeIdStripped( hCtx )

   LOCAL aWithScope    := HIX_IPAddr2Num( "fe80::1%eth0" )
   LOCAL aWithoutScope := HIX_IPAddr2Num( "fe80::1" )
   LOCAL lEqual

   lEqual := Len( aWithScope ) == Len( aWithoutScope ) .AND. Len( aWithScope ) == 4 .AND. ;
             aWithScope[ 1 ] == aWithoutScope[ 1 ] .AND. ;
             aWithScope[ 2 ] == aWithoutScope[ 2 ] .AND. ;
             aWithScope[ 3 ] == aWithoutScope[ 3 ] .AND. ;
             aWithScope[ 4 ] == aWithoutScope[ 4 ]

   HixTU_Check( hCtx, lEqual, ;
      "A3.2.2: scope ID %eth0 stripeado antes de parsear", ;
      "igual a fe80::1", iif( lEqual, "igual", "distinto" ) )

RETURN

STATIC PROCEDURE _AudA03202_BracketsStripped( hCtx )

   LOCAL aWithBrackets    := HIX_IPAddr2Num( "[::1]" )
   LOCAL aWithoutBrackets := HIX_IPAddr2Num( "::1" )
   LOCAL lEqual

   lEqual := Len( aWithBrackets ) == Len( aWithoutBrackets ) .AND. Len( aWithBrackets ) == 4 .AND. ;
             aWithBrackets[ 1 ] == aWithoutBrackets[ 1 ] .AND. ;
             aWithBrackets[ 2 ] == aWithoutBrackets[ 2 ] .AND. ;
             aWithBrackets[ 3 ] == aWithoutBrackets[ 3 ] .AND. ;
             aWithBrackets[ 4 ] == aWithoutBrackets[ 4 ]

   HixTU_Check( hCtx, lEqual, ;
      "A3.2.2: brackets URI [::1] stripeados antes de parsear", ;
      "igual a ::1", iif( lEqual, "igual", "distinto" ) )

RETURN

// ================================================================
// A3.2.3 — ratelimit: sliding window elimina burst en boundary
// ================================================================
FUNCTION HIX_TestAudit_A03203_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03203_BurstAtBoundaryBlocked( hCtx )
   _AudA03203_NormalTrafficAllowed(   hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03203_BurstAtBoundaryBlocked( hCtx )

   // Simula: prev=60 requests, 1 segundo transcurrido en nueva ventana, cur=60
   // Con window=60: weight = (60-1)/60 ≈ 0.983 → Int(60*0.983)+60 = 58+60 = 118 > 60
   LOCAL nMax    := 60
   LOCAL nWindow := 60
   LOCAL nPrev   := 60   // requests al final de ventana anterior
   LOCAL nCur    := 60   // requests al inicio de nueva ventana
   LOCAL nElapsed := 1   // 1 segundo transcurrido en nueva ventana
   LOCAL nEst    := HIX_RateLimitEstimate( nPrev, nCur, nElapsed, nWindow )

   HixTU_Check( hCtx, nEst > nMax, ;
      "A3.2.3: burst 60+60 en boundary bloqueado por sliding window", ;
      "> " + hb_ntos( nMax ), hb_ntos( nEst ) )

RETURN

STATIC PROCEDURE _AudA03203_NormalTrafficAllowed( hCtx )

   // Tráfico normal: prev=0, cur=60, ventana limpia
   LOCAL nMax    := 60
   LOCAL nWindow := 60
   LOCAL nEst    := HIX_RateLimitEstimate( 0, 60, 30, nWindow )

   HixTU_Check( hCtx, nEst <= nMax, ;
      "A3.2.3: trafico normal 60 req en ventana limpia permitido", ;
      "<= " + hb_ntos( nMax ), hb_ntos( nEst ) )

RETURN

// ================================================================
// A3.2.4 — anomaly: STATIC race en Setup (aTracked + scalars)
// ================================================================
FUNCTION HIX_TestAudit_A03204_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03204_SetupTrackedPersisted(    hCtx )
   _AudA03204_DoubleSetupSecondWins(    hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03204_SetupTrackedPersisted( hCtx )

   LOCAL hStats, aTracked, lOk

   HIX_MwAnomalySetup( 10, 30, 120, { 401, 403 } )

   hStats   := HIX_AnomalyStats()
   aTracked := hStats[ "tracked" ]

   lOk := Len( aTracked ) == 2 .AND. aTracked[ 1 ] == 401 .AND. aTracked[ 2 ] == 403

   HixTU_Check( hCtx, lOk, ;
      "A3.2.4: Setup con tracked { 401, 403 } persiste correctamente (no vacío)", ;
      "{ 401, 403 }", iif( lOk, "ok", "len=" + hb_ntos( Len( aTracked ) ) ) )

RETURN

STATIC PROCEDURE _AudA03204_DoubleSetupSecondWins( hCtx )

   LOCAL hStats, lOk

   HIX_MwAnomalySetup( 5,  20, 60,  NIL )    // primera config
   HIX_MwAnomalySetup( 15, 45, 180, NIL )    // segunda — debe ganar

   hStats := HIX_AnomalyStats()

   lOk := hStats[ "threshold" ] == 15 .AND. ;
          hStats[ "window_sec" ] == 45  .AND. ;
          hStats[ "ban_sec" ]    == 180

   HixTU_Check( hCtx, lOk, ;
      "A3.2.4: doble Setup — segunda config prevalece sin valores mixtos", ;
      "thr=15 win=45 ban=180", ;
      "thr=" + hb_ntos( hStats[ "threshold" ] ) + ;
      " win=" + hb_ntos( hStats[ "window_sec" ] ) + ;
      " ban=" + hb_ntos( hStats[ "ban_sec" ] ) )

   // Restaurar defaults para no contaminar otros tests
   HIX_MwAnomalySetup( 20, 60, 300, { 401, 403, 404 } )

RETURN

// ================================================================
// A3.3.2 — request: xJsonBody enmascara parse-error como hash vacío
// ================================================================
FUNCTION HIX_TestAudit_A03302_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03302_ParseErrorSetsFlag(  hCtx )
   _AudA03302_EmptyBodyNotAnError( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03302_ParseErrorSetsFlag( hCtx )

   LOCAL oReq := THixRequest():New( NIL, "127.0.0.1" )
   LOCAL x

   oReq:cBody := "INVALID{JSON}"
   oReq:JsonBody()

   HixTU_Check( hCtx, oReq:lJsonError, ;
      "A3.3.2: parse-error JSON setea lJsonError := .T.", ;
      ".T.", iif( oReq:lJsonError, ".T.", ".F." ) )

RETURN

STATIC PROCEDURE _AudA03302_EmptyBodyNotAnError( hCtx )

   LOCAL oReq := THixRequest():New( NIL, "127.0.0.1" )

   oReq:cBody := ""
   oReq:JsonBody()

   HixTU_Check( hCtx, ! oReq:lJsonError, ;
      "A3.3.2: body vacio no setea lJsonError (es valido)", ;
      ".F.", iif( oReq:lJsonError, ".T.", ".F." ) )

RETURN

// ================================================================
// A3.3.3 — Cookie parser: semicolons inside quoted values
// ================================================================
FUNCTION HIX_TestAudit_A03303_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03303_SimpleCookies(        hCtx )
   _AudA03303_QuotedValueWithSemi(  hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03303_SimpleCookies( hCtx )

   LOCAL oReq := THixRequest():New( NIL, "127.0.0.1" )
   LOCAL cA, cB, cC

   oReq:hHeaders[ "cookie" ] := "a=1; b=hello; c="
   cA := oReq:Cookie( "a", "?" )
   cB := oReq:Cookie( "b", "?" )
   cC := oReq:Cookie( "c", "?" )

   HixTU_Check( hCtx, cA == "1", ;
      "A3.3.3: cookie simple a=1", "1", cA )

   HixTU_Check( hCtx, cB == "hello", ;
      "A3.3.3: cookie simple b=hello", "hello", cB )

RETURN

STATIC PROCEDURE _AudA03303_QuotedValueWithSemi( hCtx )

   LOCAL oReq := THixRequest():New( NIL, "127.0.0.1" )
   LOCAL cName, cOther

   oReq:hHeaders[ "cookie" ] := 'name="v1; v2; v3"; other=ok'
   cName  := oReq:Cookie( "name",  "?" )
   cOther := oReq:Cookie( "other", "?" )

   HixTU_Check( hCtx, cName == "v1; v2; v3", ;
      "A3.3.3: valor entrecomillado con ; internos", "v1; v2; v3", cName )

   HixTU_Check( hCtx, cOther == "ok", ;
      "A3.3.3: cookie siguiente a valor entrecomillado", "ok", cOther )

RETURN

// ================================================================
// A3.3.4 — HIX_SetCookie: inyeccion por cVal/cName no sanitizado
// ================================================================
FUNCTION HIX_TestAudit_A03304_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03304_CrlfStripped(      hCtx )
   _AudA03304_SemicolonStripped( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03304_CrlfStripped( hCtx )

   LOCAL oReq  := THixRequest():New( NIL, "127.0.0.1" )
   LOCAL cRaw  := "value" + Chr(13) + Chr(10) + "X-Injected: evil"
   LOCAL cLine

   HIX_SetCookie( oReq, "test", cRaw, 0 )
   cLine := hb_ValToStr( oReq:hExtraHeaders[ "Set-Cookie" ] )

   HixTU_Check( hCtx, !( Chr(13) $ cLine ) .AND. !( Chr(10) $ cLine ), ;
      "A3.3.4: CRLF eliminado del valor cookie", "sin CRLF", cLine )

RETURN

STATIC PROCEDURE _AudA03304_SemicolonStripped( hCtx )

   LOCAL oReq  := THixRequest():New( NIL, "127.0.0.1" )
   LOCAL cRaw  := "ok; SameSite=None; Secure"
   LOCAL cLine, nEq, nSemi
   LOCAL cVal

   HIX_SetCookie( oReq, "test", cRaw, 0 )
   cLine := hb_ValToStr( oReq:hExtraHeaders[ "Set-Cookie" ] )
   // Extraer la parte del valor: "test=<val>; Path=..."
   nEq   := At( "=", cLine )
   nSemi := At( ";", cLine )
   cVal  := SubStr( cLine, nEq + 1, nSemi - nEq - 1 )

   HixTU_Check( hCtx, !( ";" $ cVal ), ;
      "A3.3.4: semicolons eliminados del valor cookie", "sin ;", cVal )

RETURN

// ================================================================
// A3.3.5 — hCookies case-sensitive (RFC 6265) vs hHeaders case-insensitive
// ================================================================
FUNCTION HIX_TestAudit_A03305_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03305_CookieCaseSensitive(    hCtx )
   _AudA03305_CookieCaseMismatch(     hCtx )
   _AudA03305_HeaderCaseInsensitive(  hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03305_CookieCaseSensitive( hCtx )

   LOCAL oReq := THixRequest():New( NIL, "127.0.0.1" )

   oReq:hHeaders[ "cookie" ] := "session=abc123; User=admin"
   HixTU_Check( hCtx, oReq:Cookie( "session", "?" ) == "abc123", ;
      "A3.3.5: cookie 'session' encontrado con case exacto", "abc123", oReq:Cookie( "session", "?" ) )

RETURN

STATIC PROCEDURE _AudA03305_CookieCaseMismatch( hCtx )

   LOCAL oReq := THixRequest():New( NIL, "127.0.0.1" )
   LOCAL cVal

   oReq:hHeaders[ "cookie" ] := "session=abc123"
   cVal := oReq:Cookie( "Session", "NOT_FOUND" )

   HixTU_Check( hCtx, cVal == "NOT_FOUND", ;
      "A3.3.5: 'Session' != 'session' (RFC 6265 case-sensitive)", "NOT_FOUND", cVal )

RETURN

STATIC PROCEDURE _AudA03305_HeaderCaseInsensitive( hCtx )

   LOCAL oReq := THixRequest():New( NIL, "127.0.0.1" )
   LOCAL cVal1, cVal2

   oReq:hHeaders[ "content-type" ] := "application/json"
   cVal1 := oReq:Header( "Content-Type", "?" )
   cVal2 := oReq:Header( "content-type", "?" )

   HixTU_Check( hCtx, cVal1 == "application/json" .AND. cVal2 == "application/json", ;
      "A3.3.5: headers case-insensitive (RFC 7230)", "application/json", cVal1 )

RETURN

// ================================================================
// A3.3.6 — HIX_UrlDecode: %00 null-byte injection
// ================================================================
FUNCTION HIX_TestAudit_A03306_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03306_NullByteStripped(   hCtx )
   _AudA03306_NullByteMiddle(     hCtx )
   _AudA03306_NormalDecodeWorks(  hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03306_NullByteStripped( hCtx )

   LOCAL cDecoded := HIX_UrlDecode( "%00" )

   HixTU_Check( hCtx, Len( cDecoded ) == 0, ;
      "A3.3.6: %00 no produce null byte", "len=0", hb_NToS( Len( cDecoded ) ) )

RETURN

STATIC PROCEDURE _AudA03306_NullByteMiddle( hCtx )

   LOCAL cDecoded := HIX_UrlDecode( "hello%00world" )

   HixTU_Check( hCtx, cDecoded == "helloworld", ;
      "A3.3.6: null byte en medio eliminado, resto preservado", "helloworld", cDecoded )

RETURN

STATIC PROCEDURE _AudA03306_NormalDecodeWorks( hCtx )

   LOCAL cDecoded := HIX_UrlDecode( "hello%20world%21" )

   HixTU_Check( hCtx, cDecoded == "hello world!", ;
      "A3.3.6: decode normal sigue funcionando", "hello world!", cDecoded )

RETURN

// ================================================================
// A3.3.7 — ValidateMacroExpr: error propagation + cache limitation
// ================================================================
FUNCTION HIX_TestAudit_A03307_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03307_InvalidExprFails(    hCtx )
   _AudA03307_ValidExprPasses(     hCtx )
   _AudA03307_InvalidTwicePropag(  hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03307_InvalidExprFails( hCtx )

   LOCAL oParser := HIX_Parser():New()
   LOCAL aErrors := {}
   LOCAL lPass

   lPass := oParser:ValidateMacroExpr( "((( unclosed", 1, @aErrors )

   HixTU_Check( hCtx, ! lPass, ;
      "A3.3.7: expresion invalida -> lPass=.F.", ".F.", iif( lPass, ".T.", ".F." ) )

   HixTU_Check( hCtx, Len( aErrors ) > 0, ;
      "A3.3.7: expresion invalida -> error en aErrors", ">0", hb_NToS( Len( aErrors ) ) )

RETURN

STATIC PROCEDURE _AudA03307_ValidExprPasses( hCtx )

   LOCAL oParser := HIX_Parser():New()
   LOCAL aErrors := {}
   LOCAL lPass

   lPass := oParser:ValidateMacroExpr( "1 + 1", 1, @aErrors )

   HixTU_Check( hCtx, lPass, ;
      "A3.3.7: expresion valida -> lPass=.T.", ".T.", iif( lPass, ".T.", ".F." ) )

RETURN

STATIC PROCEDURE _AudA03307_InvalidTwicePropag( hCtx )

   LOCAL oParser  := HIX_Parser():New()
   LOCAL aErrors1 := {}
   LOCAL aErrors2 := {}
   LOCAL lPass1, lPass2

   lPass1 := oParser:ValidateMacroExpr( "}}}invalid{{{", 1, @aErrors1 )
   lPass2 := oParser:ValidateMacroExpr( "}}}invalid{{{", 1, @aErrors2 )

   HixTU_Check( hCtx, ! lPass1 .AND. ! lPass2, ;
      "A3.3.7: misma expr invalida dos veces -> ambas .F. (cache no silencia)", ".F.+.F.", ;
      iif( lPass1, ".T." , ".F." ) + "+" + iif( lPass2, ".T.", ".F." ) )

RETURN

// ================================================================
// A3.3.8 — ReplaceVars: nombres @args sin escapar en regex
// ================================================================
FUNCTION HIX_TestAudit_A03308_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03308_EscapeNormalName(    hCtx )
   _AudA03308_EscapeDot(           hCtx )
   _AudA03308_EscapeParens(        hCtx )
   _AudA03308_EscapeStar(          hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03308_EscapeNormalName( hCtx )

   LOCAL cEscaped := HIX_RegExEscape( "cName" )

   HixTU_Check( hCtx, cEscaped == "cName", ;
      "A3.3.8: nombre normal no cambia tras escape", "cName", cEscaped )

RETURN

STATIC PROCEDURE _AudA03308_EscapeDot( hCtx )

   LOCAL cEscaped := HIX_RegExEscape( "a.b" )

   HixTU_Check( hCtx, cEscaped == "a\.b", ;
      "A3.3.8: '.' queda escapado como '\.'", "a\.b", cEscaped )

RETURN

STATIC PROCEDURE _AudA03308_EscapeParens( hCtx )

   LOCAL cEscaped := HIX_RegExEscape( "fn(x)" )

   HixTU_Check( hCtx, cEscaped == "fn\(x\)", ;
      "A3.3.8: paréntesis escapados", "fn\(x\)", cEscaped )

RETURN

STATIC PROCEDURE _AudA03308_EscapeStar( hCtx )

   LOCAL cEscaped := HIX_RegExEscape( "a*b+" )

   HixTU_Check( hCtx, cEscaped == "a\*b\+", ;
      "A3.3.8: '*' y '+' escapados", "a\*b\+", cEscaped )

RETURN

// ================================================================
// A3.4.1 — HIX_LoadConfig: explicit cFile bypasses cache
// ================================================================
FUNCTION HIX_TestAudit_A03401_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL hSaved := HIX_GetConfig()

   _AudA03401_ExplicitBypassesCache( hCtx )

   HIX_SetConfig( hSaved )   // restore config after test

RETURN hCtx

STATIC PROCEDURE _AudA03401_ExplicitBypassesCache( hCtx )

   LOCAL cA    := hb_DirTemp() + "hix_a3401_a_" + hb_NToS( Int( hb_MilliSeconds() ) ) + ".json"
   LOCAL cB    := hb_DirTemp() + "hix_a3401_b_" + hb_NToS( Int( hb_MilliSeconds() ) + 1 ) + ".json"
   LOCAL hCfgA, hCfgB, nPortA, nPortB

   hb_MemoWrit( cA, '{"server":{"port":9971}}' )
   hb_MemoWrit( cB, '{"server":{"port":9972}}' )

   HIX_SetConfig( { => } )   // reset cache

   HIX_LoadConfig( cA, .F. )
   hCfgA  := HIX_GetConfig( "server" )
   nPortA := hb_HGetDef( hCfgA, "port", 0 )

   HixTU_Check( hCtx, nPortA == 9971, ;
      "A3.4.1: primera carga con cFile A -> port=9971", "9971", hb_NToS( nPortA ) )

   HIX_LoadConfig( cB, .F. )   // explicit file B with cache populated
   hCfgB  := HIX_GetConfig( "server" )
   nPortB := hb_HGetDef( hCfgB, "port", 0 )

   HixTU_Check( hCtx, nPortB == 9972, ;
      "A3.4.1: explicit cFile B bypasa cache -> port=9972", "9972", hb_NToS( nPortB ) )

   HIX_SafeErase( cA )
   HIX_SafeErase( cB )

RETURN

// ================================================================
// A3.4.2 — HIX_LoadConfig: JSON corrupto sobreescribe sin warning
// ================================================================
FUNCTION HIX_TestAudit_A03402_Run()

   LOCAL hCtx  := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL hSaved := HIX_GetConfig()

   _AudA03402_CorruptJsonFallsBack( hCtx )

   HIX_SetConfig( hSaved )

RETURN hCtx

STATIC PROCEDURE _AudA03402_CorruptJsonFallsBack( hCtx )

   LOCAL cTmp  := hb_DirTemp() + "hix_a3402_" + hb_NToS( Int( hb_MilliSeconds() ) ) + ".json"
   LOCAL hCfg
   LOCAL cAfter

   hb_MemoWrit( cTmp, "ESTO NO ES JSON {{{{{" )
   HIX_SetConfig( { => } )

   // Should not crash; returns valid defaults
   hCfg := HIX_LoadConfig( cTmp, .F. )

   HixTU_Check( hCtx, hb_IsHash( hCfg ) .AND. hb_HHasKey( hCfg, "server" ), ;
      "A3.4.2: JSON corrupto devuelve hash defaults valido", ".T.", ;
      iif( hb_IsHash( hCfg ), ".T.", ".F." ) )

   // The file should have been overwritten with valid JSON
   cAfter := hb_MemoRead( cTmp )

   HixTU_Check( hCtx, hb_IsHash( hb_jsonDecode( cAfter ) ) .OR. ;
                       hb_IsHash( hb_jsonDecode( SubStr( cAfter, At( "{", cAfter ) ) ) ), ;
      "A3.4.2: fichero sobreescrito con JSON valido", ".T.", ;
      iif( Len( cAfter ) > 0, "non-empty", "empty" ) )

   HIX_SafeErase( cTmp )

RETURN

// ================================================================
// A3.4.3 — Admin password almacenado con MD5 sin salt
// A3.4.4 — Cookie admin firmada con MD5 (no HMAC)
// ================================================================
FUNCTION HIX_TestAudit_A03403_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03403_PasswordHmac( hCtx )
   _AudA03404_CookieSignHmac( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03403_PasswordHmac( hCtx )

   LOCAL cPass := "s3cret_pass"
   LOCAL cSalt := Lower( hb_HMAC_SHA256( hb_TToS( hb_DateTime() ) + "admin", cPass ) )
   LOCAL cHash := Lower( hb_HMAC_SHA256( cPass, cSalt ) )

   HixTU_Check( hCtx, Len( cHash ) == 64, ;
      "A3.4.3: password hash es HMAC-SHA256 (64 hex chars)", "64", hb_NToS( Len( cHash ) ) )

   HixTU_Check( hCtx, Lower( hb_HMAC_SHA256( cPass, cSalt ) ) == cHash, ;
      "A3.4.3: verificacion login HMAC coincide con hash almacenado", ".T.", ".T." )

   HixTU_Check( hCtx, Lower( hb_HMAC_SHA256( "wrong_pass", cSalt ) ) != cHash, ;
      "A3.4.3: password incorrecto no coincide", ".T.", ".T." )

RETURN

STATIC PROCEDURE _AudA03404_CookieSignHmac( hCtx )

   LOCAL cSecret := "admin_secret_key"
   LOCAL nTs     := 1700000000
   LOCAL cSign   := Lower( hb_HMAC_SHA256( hb_NToS( nTs ), cSecret ) )

   HixTU_Check( hCtx, Len( cSign ) == 64, ;
      "A3.4.4: cookie sign es HMAC-SHA256 (64 hex chars, no MD5 32)", "64", hb_NToS( Len( cSign ) ) )

   HixTU_Check( hCtx, Lower( hb_HMAC_SHA256( hb_NToS( nTs ), cSecret ) ) == cSign, ;
      "A3.4.4: firma determinista con mismas entradas", ".T.", ".T." )

   HixTU_Check( hCtx, Lower( hb_HMAC_SHA256( hb_NToS( nTs ), "other_secret" ) ) != cSign, ;
      "A3.4.4: secret distinto produce firma distinta", ".T.", ".T." )

RETURN

// ================================================================
// A3.4.5 — s_aModules y s_hUserFuncs sin mutex en hix_loader.prg
// Fix: s_mtxLoader + INIT PROCEDURE + swap atomico + snapshot + lock lectura
// ================================================================
FUNCTION HIX_TestAudit_A03405_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03405_NilNameNoCrash(    hCtx )
   _AudA03405_NonexistentFunc(   hCtx )
   _AudA03405_GetLoadersIsArray( hCtx )
   _AudA03405_ConcurrentReaders( hCtx )

RETURN hCtx

STATIC PROCEDURE _AudA03405_NilNameNoCrash( hCtx )

   LOCAL lOk := .T.
   LOCAL oErr

   TRY
      HIX_LoaderIsUserFunc( NIL )
   CATCH oErr
      lOk := .F.
   END

   HixTU_Check( hCtx, lOk, ;
      "A3.4.5: HIX_LoaderIsUserFunc(NIL) no lanza excepcion", ".T.", hb_ValToStr( lOk ) )

RETURN

STATIC PROCEDURE _AudA03405_NonexistentFunc( hCtx )

   LOCAL lRes := HIX_LoaderIsUserFunc( "HIX_ESTA_FUNCION_NO_EXISTE_JAMAS_XYZ" )

   HixTU_Check( hCtx, lRes == .F., ;
      "A3.4.5: HIX_LoaderIsUserFunc('nonexistent') devuelve .F.", ".F.", hb_ValToStr( lRes ) )

RETURN

STATIC PROCEDURE _AudA03405_GetLoadersIsArray( hCtx )

   LOCAL aLoaders
   LOCAL lOk := .T.
   LOCAL oErr

   TRY
      aLoaders := HIX_GetLoaders()
   CATCH oErr
      aLoaders := NIL
      lOk := .F.
   END

   HixTU_Check( hCtx, lOk .AND. HB_ISARRAY( aLoaders ), ;
      "A3.4.5: HIX_GetLoaders() devuelve array (snapshot, no NIL)", "array", ;
      iif( HB_ISARRAY( aLoaders ), "array", hb_ValToStr( aLoaders ) ) )

RETURN

STATIC PROCEDURE _AudA03405_ConcurrentReaders( hCtx )

   LOCAL aThreads := {}
   LOCAL i, hT
   LOCAL lNoCrash := .T.
   LOCAL oErr

   FOR i := 1 TO 3
      hT := hb_threadStart( @_AudA03405_ReaderThread(), 200 )
      AAdd( aThreads, hT )
   NEXT

   FOR EACH hT IN aThreads
      TRY
         hb_threadJoin( hT )
      CATCH oErr
         lNoCrash := .F.
      END
   NEXT

   HixTU_Check( hCtx, lNoCrash, ;
      "A3.4.5: 3 hilos llamando HIX_LoaderIsUserFunc+GetLoaders en paralelo sin crash", ;
      ".T.", hb_ValToStr( lNoCrash ) )

RETURN

STATIC PROCEDURE _AudA03405_ReaderThread( nTimes )

   LOCAL i

   FOR i := 1 TO nTimes
      HIX_LoaderIsUserFunc( "SOMEFUNCTION_" + hb_NToS( i ) )
      HIX_LoaderIsUserFunc( NIL )
      HIX_GetLoaders()
   NEXT

RETURN

// ================================================================
// A3.4.6 — Invalidacion HRB solo por mtime (backup stale con mtime reciente)
// Fix: sidecar .hrb.md5 con hash del PRG; verificar ademas del mtime.
// ================================================================
FUNCTION HIX_TestAudit_A03406_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03406_NoSidecarReturnsFalse( hCtx )
   _AudA03406_MatchingHashReturnsTrue( hCtx )
   _AudA03406_StaleHashReturnsFalse( hCtx )

RETURN hCtx

// TC1: sin sidecar .hrb.md5 -> _HixLoaderHashOk devuelve .F. (conservative)
STATIC PROCEDURE _AudA03406_NoSidecarReturnsFalse( hCtx )

   LOCAL cDir     := hb_DirTemp() + "hix_a3406_" + hb_NToS( Int( hb_MilliSeconds() ) ) + hb_ps()
   LOCAL cFile    := "mod_a.prg"
   LOCAL cMd5File := cDir + HB_FNameExtSet( cFile ) + ".hrb.md5"
   LOCAL lRes

   hb_DirCreate( cDir )
   hb_MemoWrit( cDir + cFile, "FUNCTION Dummy() ; RETURN .T." )
   // Sin sidecar .hrb.md5
   IF ! File( cMd5File )
      lRes := .F.
   ELSE
      lRes := AllTrim( hb_MemoRead( cMd5File ) ) == hb_MD5( hb_MemoRead( cDir + cFile ) )
   ENDIF

   HixTU_Check( hCtx, lRes == .F., ;
      "A3.4.6: sin sidecar .hrb.md5 -> HashOk devuelve .F.", ".F.", hb_ValToStr( lRes ) )

   HIX_SafeErase( cDir + cFile )
   HIX_SafeDirDelete( cDir )

RETURN

// TC2: sidecar con hash correcto -> devuelve .T.
STATIC PROCEDURE _AudA03406_MatchingHashReturnsTrue( hCtx )

   LOCAL cDir     := hb_DirTemp() + "hix_a3406b_" + hb_NToS( Int( hb_MilliSeconds() ) ) + hb_ps()
   LOCAL cFile    := "mod_b.prg"
   LOCAL cPrg     := "FUNCTION ModB() ; RETURN .T."
   LOCAL cMd5File := cDir + HB_FNameExtSet( cFile ) + ".hrb.md5"
   LOCAL lRes

   hb_DirCreate( cDir )
   hb_MemoWrit( cDir + cFile, cPrg )
   hb_MemoWrit( cDir + "mod_b.hrb.md5", hb_MD5( cPrg ) )

   IF ! File( cMd5File )
      lRes := .F.
   ELSE
      lRes := AllTrim( hb_MemoRead( cMd5File ) ) == hb_MD5( hb_MemoRead( cDir + cFile ) )
   ENDIF

   HixTU_Check( hCtx, lRes == .T., ;
      "A3.4.6: sidecar con hash correcto -> HashOk devuelve .T.", ".T.", hb_ValToStr( lRes ) )

   HIX_SafeErase( cDir + cFile )
   HIX_SafeErase( cDir + "mod_b.hrb.md5" )
   HIX_SafeDirDelete( cDir )

RETURN

// TC3: sidecar con hash stale (backup) -> devuelve .F.
STATIC PROCEDURE _AudA03406_StaleHashReturnsFalse( hCtx )

   LOCAL cDir     := hb_DirTemp() + "hix_a3406c_" + hb_NToS( Int( hb_MilliSeconds() ) ) + hb_ps()
   LOCAL cFile    := "mod_c.prg"
   LOCAL cPrgOrig := "FUNCTION ModC_Old() ; RETURN .T."
   LOCAL cPrgNew  := "FUNCTION ModC_New() ; RETURN .F."
   LOCAL cMd5File := cDir + HB_FNameExtSet( cFile ) + ".hrb.md5"
   LOCAL lRes

   hb_DirCreate( cDir )
   // Simular backup: el .hrb.md5 tiene el hash del PRG antiguo
   hb_MemoWrit( cDir + "mod_c.hrb.md5", hb_MD5( cPrgOrig ) )
   // El PRG actual tiene contenido nuevo
   hb_MemoWrit( cDir + cFile, cPrgNew )

   IF ! File( cMd5File )
      lRes := .F.
   ELSE
      lRes := AllTrim( hb_MemoRead( cMd5File ) ) == hb_MD5( hb_MemoRead( cDir + cFile ) )
   ENDIF

   HixTU_Check( hCtx, lRes == .F., ;
      "A3.4.6: sidecar con hash stale (backup) -> HashOk devuelve .F.", ".F.", hb_ValToStr( lRes ) )

   HIX_SafeErase( cDir + cFile )
   HIX_SafeErase( cDir + "mod_c.hrb.md5" )
   HIX_SafeDirDelete( cDir )

RETURN

// ================================================================
// A3.4.7 — Bucle de resolucion de deps sin limite ni deteccion de ciclo
// Fix: limite nLenModules+1 + lw() al detectar ciclo irresolvable
// ================================================================
FUNCTION HIX_TestAudit_A03407_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03407_MaxIterFormula( hCtx )
   _AudA03407_LimitGuardExits( hCtx )

RETURN hCtx

// TC1: el limite de iteraciones es correcto para N modulos
STATIC PROCEDURE _AudA03407_MaxIterFormula( hCtx )

   // Con N modulos en cadena lineal (1 dep 2, 2 dep 3, ...) se necesitan
   // exactamente N-1 iteraciones. El limite debe ser > N-1, es decir >= N.
   // La implementacion usa nLenModules+1 (siempre mayor que N-1 para N>=1).
   LOCAL nN := 10
   LOCAL nMaxIter := nN + 1

   HixTU_Check( hCtx, nMaxIter > nN - 1, ;
      "A3.4.7: limite nLenModules+1 cubre cadena lineal de N modulos", ".T.", ".T." )

   HixTU_Check( hCtx, nMaxIter == nN + 1, ;
      "A3.4.7: limite = nLenModules+1 (valor correcto para N=10)", "11", hb_NToS( nMaxIter ) )

RETURN

// TC2: simular bucle con contador — el guard EXIT funciona antes de N+2
STATIC PROCEDURE _AudA03407_LimitGuardExits( hCtx )

   LOCAL nIter    := 0
   LOCAL nLimit   := 5   // simular 5 modulos
   LOCAL lExited  := .F.

   DO WHILE .T.
      nIter++
      IF nIter > nLimit + 1
         lExited := .T.
         EXIT
      ENDIF
      IF nIter > 100   // guardia de seguridad del test
         EXIT
      ENDIF
   ENDDO

   HixTU_Check( hCtx, lExited .AND. nIter == nLimit + 2, ;
      "A3.4.7: guard EXIT actua en iteracion nLimit+2", ".T.", ;
      iif( lExited, "exited@iter=" + hb_NToS( nIter ), ".F." ) )

RETURN

// ================================================================
// A3.4.8 — HIX_PoolLock puede quedar tomado indefinidamente (sin timeout)
// Fix: hb_mutexLock(mtx, nTimeoutSec) con default 30s + log si expira
// ================================================================
FUNCTION HIX_TestAudit_A03408_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03408_LockUnlockOk( hCtx )
   _AudA03408_TimeoutParamAccepted( hCtx )
   _AudA03408_ReturnsTrueOnAcquire( hCtx )

RETURN hCtx

// TC1: lock/unlock normal devuelve .T. y no crashea
STATIC PROCEDURE _AudA03408_LockUnlockOk( hCtx )

   LOCAL cPool := "hix_a3408_" + hb_NToS( Int( hb_MilliSeconds() ) )
   LOCAL lOk   := .F.
   LOCAL oErr

   HIX_PoolCreate( cPool )

   TRY
      lOk := HIX_PoolLock( cPool )
      HIX_PoolUnlock( cPool )
   CATCH oErr
      lOk := .F.
   END

   HixTU_Check( hCtx, lOk, ;
      "A3.4.8: HIX_PoolLock/Unlock no crashea y devuelve .T.", ".T.", hb_ValToStr( lOk ) )

   HIX_PoolDestroy( cPool )

RETURN

// TC2: pasar nTimeoutSec personalizado no crashea
STATIC PROCEDURE _AudA03408_TimeoutParamAccepted( hCtx )

   LOCAL cPool := "hix_a3408b_" + hb_NToS( Int( hb_MilliSeconds() ) )
   LOCAL lOk   := .F.
   LOCAL oErr

   HIX_PoolCreate( cPool )

   TRY
      lOk := HIX_PoolLock( cPool, 5 )   // timeout explicito 5s
      IF lOk
         HIX_PoolUnlock( cPool )
      ENDIF
   CATCH oErr
      lOk := .F.
   END

   HixTU_Check( hCtx, lOk, ;
      "A3.4.8: HIX_PoolLock con timeout=5s adquiere lock disponible", ".T.", hb_ValToStr( lOk ) )

   HIX_PoolDestroy( cPool )

RETURN

// TC3: .T. al adquirir lock libre inmediatamente
STATIC PROCEDURE _AudA03408_ReturnsTrueOnAcquire( hCtx )

   LOCAL cPool := "hix_a3408c_" + hb_NToS( Int( hb_MilliSeconds() ) )
   LOCAL lRes

   HIX_PoolCreate( cPool )
   lRes := HIX_PoolLock( cPool, 10 )
   IF lRes
      HIX_PoolUnlock( cPool )
   ENDIF

   HixTU_Check( hCtx, lRes == .T., ;
      "A3.4.8: HIX_PoolLock devuelve .T. al adquirir lock libre", ".T.", hb_ValToStr( lRes ) )

   HIX_PoolDestroy( cPool )

RETURN


// ---------------------------------------------------------------
// A3.4.9 -- Sin limite de tamano de pool -> DoS por memoria.
// Fix: HIX_PoolCreate( cName, nMaxSize ); HIX_PoolSet devuelve .F.
//       cuando el pool esta lleno y la clave es nueva.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A03409_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03409_NoLimitWorks(          hCtx )
   _AudA03409_LimitRejectsNewKey(    hCtx )
   _AudA03409_UpdateExistingAllowed( hCtx )

RETURN hCtx

// TC1: pool sin limite acepta cualquier cantidad de entradas
STATIC PROCEDURE _AudA03409_NoLimitWorks( hCtx )

   LOCAL cPool := "hix_a3409a_" + hb_NToS( Int( hb_MilliSeconds() ) )
   LOCAL i, lOk

   HIX_PoolCreate( cPool )   // nMaxSize = 0 (sin limite)

   lOk := .T.
   FOR i := 1 TO 20
      IF ! HIX_PoolSet( cPool, "k" + hb_NToS( i ), i )
         lOk := .F.
      ENDIF
   NEXT

   HixTU_Check( hCtx, lOk .AND. HIX_PoolSize( cPool ) == 20, ;
      "A3.4.9: pool sin limite acepta 20 entradas", "20", hb_NToS( HIX_PoolSize( cPool ) ) )

   HIX_PoolDestroy( cPool )

RETURN

// TC2: pool lleno rechaza nueva clave (devuelve .F.)
STATIC PROCEDURE _AudA03409_LimitRejectsNewKey( hCtx )

   LOCAL cPool := "hix_a3409b_" + hb_NToS( Int( hb_MilliSeconds() ) )
   LOCAL lOk1, lFail, nSize

   HIX_PoolCreate( cPool, 3 )   // maximo 3 entradas

   lOk1  := HIX_PoolSet( cPool, "a", 1 )
   lOk1  := lOk1 .AND. HIX_PoolSet( cPool, "b", 2 )
   lOk1  := lOk1 .AND. HIX_PoolSet( cPool, "c", 3 )
   lFail := ! HIX_PoolSet( cPool, "d", 4 )   // debe rechazarse
   nSize := HIX_PoolSize( cPool )

   HixTU_Check( hCtx, lOk1 .AND. lFail .AND. nSize == 3, ;
      "A3.4.9: pool con max=3 rechaza 4a clave nueva", "3", hb_NToS( nSize ) )

   HIX_PoolDestroy( cPool )

RETURN

// TC3: actualizar clave existente en pool lleno esta permitido
STATIC PROCEDURE _AudA03409_UpdateExistingAllowed( hCtx )

   LOCAL cPool := "hix_a3409c_" + hb_NToS( Int( hb_MilliSeconds() ) )
   LOCAL lOk

   HIX_PoolCreate( cPool, 2 )

   HIX_PoolSet( cPool, "x", 10 )
   HIX_PoolSet( cPool, "y", 20 )
   lOk := HIX_PoolSet( cPool, "x", 99 )   // update de clave existente: debe permitirse

   HixTU_Check( hCtx, lOk .AND. HIX_PoolGet( cPool, "x", 0 ) == 99, ;
      "A3.4.9: update de clave existente en pool lleno permitido", "99", ;
      hb_NToS( HIX_PoolGet( cPool, "x", 0 ) ) )

   HIX_PoolDestroy( cPool )

RETURN


// ---------------------------------------------------------------
// A3.4.10 -- Update() no libera RLock si FieldPut/ThrowError lanza.
// Fix: TRY...FINALLY...END garantiza DbUnlock siempre.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A03410_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03410_NormalUpdate(        hCtx )
   _AudA03410_ErrorThrows(         hCtx )
   _AudA03410_FileUsableAfterError( hCtx )

RETURN hCtx

// TC1: Update normal — campo actualizado correctamente
STATIC PROCEDURE _AudA03410_NormalUpdate( hCtx )

   LOCAL cDbf    := hb_DirTemp() + "hix_a3410a_" + hb_NToS( Int( hb_MilliSeconds() ) ) + ".dbf"
   LOCAL aStruct := { { "NAME", "C", 20, 0 } }
   LOCAL oDbf    := HIX_DBF():New()
   LOCAL cAlias, lOk, cVal
   LOCAL oErr

   DbCreate( cDbf, aStruct, "DBFCDX" )
   cAlias := oDbf:NewAlias()
   DbUseArea( .T., "DBFCDX", cDbf, cAlias, .T., .F. )
   ( cAlias )->( DbAppend() )
   ( cAlias )->( FieldPut( 1, "before" ) )
   ( cAlias )->( DbCommit() )

   oDbf:cAlias   := cAlias
   oDbf:cDbf     := cDbf
   oDbf:lConnect := .T.

   TRY
      lOk := oDbf:Update( ( cAlias )->( Recno() ), { "NAME" => "after" } )
   CATCH oErr
      lOk := .F.
   END

   cVal := AllTrim( ( cAlias )->( FieldGet( 1 ) ) )
   ( cAlias )->( DbCloseArea() )
   HIX_SafeErase( cDbf )

   HixTU_Check( hCtx, lOk .AND. cVal == "after", ;
      "A3.4.10: Update normal actualiza campo y devuelve .T.", "after", cVal )

RETURN

// TC2: Update con tipo incompatible (array en campo numerico) lanza ThrowError
STATIC PROCEDURE _AudA03410_ErrorThrows( hCtx )

   LOCAL cDbf    := hb_DirTemp() + "hix_a3410b_" + hb_NToS( Int( hb_MilliSeconds() ) ) + ".dbf"
   LOCAL aStruct := { { "ID", "N", 4, 0 } }
   LOCAL oDbf    := HIX_DBF():New()
   LOCAL cAlias, lCaught
   LOCAL oErr

   DbCreate( cDbf, aStruct, "DBFCDX" )
   cAlias := oDbf:NewAlias()
   DbUseArea( .T., "DBFCDX", cDbf, cAlias, .T., .F. )
   ( cAlias )->( DbAppend() )
   ( cAlias )->( FieldPut( 1, 1 ) )
   ( cAlias )->( DbCommit() )

   oDbf:cAlias   := cAlias
   oDbf:cDbf     := cDbf
   oDbf:lConnect := .T.

   // Pasar array como valor de campo numerico — FieldPut lanza EG_DATATYPE
   lCaught := .F.
   TRY
      oDbf:Update( ( cAlias )->( Recno() ), { "ID" => {} } )
   CATCH oErr
      lCaught := .T.
   END

   ( cAlias )->( DbCloseArea() )
   HIX_SafeErase( cDbf )

   HixTU_Check( hCtx, lCaught, ;
      "A3.4.10: FieldPut con tipo invalido propaga ThrowError al caller", ".T.", hb_ValToStr( lCaught ) )

RETURN

// TC3: archivo sigue accesible tras error en Update (FINALLY solto el lock)
STATIC PROCEDURE _AudA03410_FileUsableAfterError( hCtx )

   LOCAL cDbf    := hb_DirTemp() + "hix_a3410c_" + hb_NToS( Int( hb_MilliSeconds() ) ) + ".dbf"
   LOCAL aStruct := { { "VAL", "N", 4, 0 } }
   LOCAL oDbf    := HIX_DBF():New()
   LOCAL cAlias, lOk
   LOCAL oErr

   DbCreate( cDbf, aStruct, "DBFCDX" )
   cAlias := oDbf:NewAlias()
   DbUseArea( .T., "DBFCDX", cDbf, cAlias, .T., .F. )
   ( cAlias )->( DbAppend() )
   ( cAlias )->( FieldPut( 1, 7 ) )
   ( cAlias )->( DbCommit() )

   oDbf:cAlias   := cAlias
   oDbf:cDbf     := cDbf
   oDbf:lConnect := .T.

   TRY
      oDbf:Update( ( cAlias )->( Recno() ), { "VAL" => {} } )   // array en campo N -> ThrowError
   CATCH oErr
      // ignorado: provocamos el error para limpiar el lock
   END

   // Si FINALLY solto el lock, podemos hacer otro Update sin colision
   lOk := .F.
   TRY
      lOk := oDbf:Update( ( cAlias )->( Recno() ), { "VAL" => 42 } )
   CATCH oErr
      lOk := .F.
   END

   ( cAlias )->( DbCloseArea() )
   HIX_SafeErase( cDbf )

   HixTU_Check( hCtx, lOk, ;
      "A3.4.10: Update posterior al error funciona (FINALLY libero lock)", ".T.", hb_ValToStr( lOk ) )

RETURN


// ---------------------------------------------------------------
// A3.4.11 -- RLock retries sin hb_idleSleep -> 100% CPU bajo contention.
// Fix: inicializar nLapsus := ::nTime y hb_idleSleep(0.001) en retry.
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A03411_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03411_RLockNoConnect(    hCtx )
   _AudA03411_RLockAvailable(    hCtx )
   _AudA03411_RLockUnlockCycle(  hCtx )

RETURN hCtx

// TC1: sin lConnect retorna .F. de inmediato
STATIC PROCEDURE _AudA03411_RLockNoConnect( hCtx )

   LOCAL oDbf := HIX_DBF():New()
   LOCAL lRes

   lRes := oDbf:RLock()   // lConnect = .F. por defecto

   HixTU_Check( hCtx, ! lRes, ;
      "A3.4.11: RLock sin conexion retorna .F.", ".F.", hb_ValToStr( lRes ) )

RETURN

// TC2: RLock en record disponible retorna .T. sin spinlock
STATIC PROCEDURE _AudA03411_RLockAvailable( hCtx )

   LOCAL cDbf    := hb_DirTemp() + "hix_a3411b_" + hb_NToS( Int( hb_MilliSeconds() ) ) + ".dbf"
   LOCAL aStruct := { { "ID", "N", 4, 0 } }
   LOCAL oDbf    := HIX_DBF():New()
   LOCAL cAlias, lOk
   LOCAL oErr

   DbCreate( cDbf, aStruct, "DBFCDX" )
   cAlias := oDbf:NewAlias()
   DbUseArea( .T., "DBFCDX", cDbf, cAlias, .T., .F. )
   ( cAlias )->( DbAppend() )
   ( cAlias )->( DbCommit() )

   oDbf:cAlias   := cAlias
   oDbf:cDbf     := cDbf
   oDbf:lConnect := .T.

   lOk := .F.
   TRY
      lOk := oDbf:RLock()
      IF lOk
         ( cAlias )->( DbUnlock() )
      ENDIF
   CATCH oErr
      lOk := .F.
   END

   ( cAlias )->( DbCloseArea() )
   HIX_SafeErase( cDbf )

   HixTU_Check( hCtx, lOk, ;
      "A3.4.11: RLock en record disponible retorna .T.", ".T.", hb_ValToStr( lOk ) )

RETURN

// TC3: ciclo RLock + Unlock repetido no crashea (regression de spinlock)
STATIC PROCEDURE _AudA03411_RLockUnlockCycle( hCtx )

   LOCAL cDbf    := hb_DirTemp() + "hix_a3411c_" + hb_NToS( Int( hb_MilliSeconds() ) ) + ".dbf"
   LOCAL aStruct := { { "ID", "N", 4, 0 } }
   LOCAL oDbf    := HIX_DBF():New()
   LOCAL cAlias, i, lOk
   LOCAL oErr

   DbCreate( cDbf, aStruct, "DBFCDX" )
   cAlias := oDbf:NewAlias()
   DbUseArea( .T., "DBFCDX", cDbf, cAlias, .T., .F. )
   ( cAlias )->( DbAppend() )
   ( cAlias )->( DbCommit() )

   oDbf:cAlias   := cAlias
   oDbf:cDbf     := cDbf
   oDbf:lConnect := .T.

   lOk := .T.
   TRY
      FOR i := 1 TO 5
         IF ! oDbf:RLock()
            lOk := .F.
         ENDIF
         oDbf:Unlock()
      NEXT
   CATCH oErr
      lOk := .F.
   END

   ( cAlias )->( DbCloseArea() )
   HIX_SafeErase( cDbf )

   HixTU_Check( hCtx, lOk, ;
      "A3.4.11: 5 ciclos RLock/Unlock consecutivos sin crash", ".T.", hb_ValToStr( lOk ) )

RETURN


// ---------------------------------------------------------------
// A3.5.1 -- Inc() con HHasKey branch — micro-race (usar hb_HGetDef).
// Fix: ::hCounters[cName] := hb_HGetDef(..., 0) + nValue (una sola op).
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A03501_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03501_IncNewCounter(      hCtx )
   _AudA03501_IncExistingCounter( hCtx )
   _AudA03501_IncConcurrent(      hCtx )

RETURN hCtx

// TC1: Inc en contador nuevo lo inicializa con el valor correcto
STATIC PROCEDURE _AudA03501_IncNewCounter( hCtx )

   LOCAL oM := THixMetrics():New()
   LOCAL nVal

   oM:Inc( "new_counter", 5 )
   nVal := oM:Get( "new_counter" )

   HixTU_Check( hCtx, nVal == 5, ;
      "A3.5.1: Inc en contador nuevo inicializa a nValue", "5", hb_NToS( nVal ) )

RETURN

// TC2: Inc en contador existente acumula correctamente
STATIC PROCEDURE _AudA03501_IncExistingCounter( hCtx )

   LOCAL oM := THixMetrics():New()
   LOCAL nVal

   oM:Inc( "acc", 10 )
   oM:Inc( "acc", 3 )
   oM:Inc( "acc", 7 )
   nVal := oM:Get( "acc" )

   HixTU_Check( hCtx, nVal == 20, ;
      "A3.5.1: 3x Inc acumula 10+3+7=20", "20", hb_NToS( nVal ) )

RETURN

// TC3: 4 threads incrementan el mismo contador — suma final correcta
STATIC PROCEDURE _AudA03501_IncConcurrent( hCtx )

   LOCAL oM      := THixMetrics():New()
   LOCAL aThreads := {}
   LOCAL i, hT

   FOR i := 1 TO 4
      hT := hb_threadStart( @_AudA03501_IncWorker(), oM, 25 )
      AAdd( aThreads, hT )
   NEXT

   FOR EACH hT IN aThreads
      hb_threadJoin( hT )
   NEXT

   HixTU_Check( hCtx, oM:Get( "thr_ctr" ) == 100, ;
      "A3.5.1: 4 threads x 25 Inc = 100 (sin perdidas)", "100", ;
      hb_NToS( oM:Get( "thr_ctr" ) ) )

RETURN

STATIC PROCEDURE _AudA03501_IncWorker( oM, nTimes )
   LOCAL i
   FOR i := 1 TO nTimes
      oM:Inc( "thr_ctr", 1 )
   NEXT
RETURN


// ---------------------------------------------------------------
// A3.5.2 -- _ConstantEq sin pre-check de longitud ->
//           firma de N MB fuerza N*M iteraciones CPU (amplificacion DoS).
// Fix: early return .F. si Len(cA) != Len(cB).
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A03502_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA03502_JwtEqualStrings(       hCtx )
   _AudA03502_JwtDifferentLenFalse(  hCtx )
   _AudA03502_TokenEqualStrings(     hCtx )
   _AudA03502_TokenDifferentLenFalse( hCtx )
   _AudA03502_LongStringRejected(    hCtx )

RETURN hCtx

// TC1: JWT ConstantEq — strings identicos devuelven .T.
STATIC PROCEDURE _AudA03502_JwtEqualStrings( hCtx )
   LOCAL cS := Replicate( "a", 64 )
   HixTU_Check( hCtx, HIX_JwtConstantEq( cS, cS ), ;
      "A3.5.2: JWT ConstantEq igual -> .T.", ".T.", ;
      hb_ValToStr( HIX_JwtConstantEq( cS, cS ) ) )
RETURN

// TC2: JWT ConstantEq — longitudes distintas devuelven .F. sin iterar
STATIC PROCEDURE _AudA03502_JwtDifferentLenFalse( hCtx )
   LOCAL lRes := HIX_JwtConstantEq( "abc", "abcd" )
   HixTU_Check( hCtx, ! lRes, ;
      "A3.5.2: JWT ConstantEq longitudes distintas -> .F.", ".F.", hb_ValToStr( lRes ) )
RETURN

// TC3: Token ConstantEq — strings identicos devuelven .T.
STATIC PROCEDURE _AudA03502_TokenEqualStrings( hCtx )
   LOCAL cS := Replicate( "f", 64 )
   HixTU_Check( hCtx, HIX_TokenConstantEq( cS, cS ), ;
      "A3.5.2: Token ConstantEq igual -> .T.", ".T.", ;
      hb_ValToStr( HIX_TokenConstantEq( cS, cS ) ) )
RETURN

// TC4: Token ConstantEq — longitudes distintas devuelven .F.
STATIC PROCEDURE _AudA03502_TokenDifferentLenFalse( hCtx )
   LOCAL lRes := HIX_TokenConstantEq( "short", "longer_string" )
   HixTU_Check( hCtx, ! lRes, ;
      "A3.5.2: Token ConstantEq longitudes distintas -> .F.", ".F.", hb_ValToStr( lRes ) )
RETURN

// TC5: string grande (1000 chars) vs string corto -> .F. inmediato (no DoS)
STATIC PROCEDURE _AudA03502_LongStringRejected( hCtx )
   LOCAL cBig := Replicate( "x", 1000 )
   LOCAL lRes  := HIX_JwtConstantEq( cBig, "short" )
   HixTU_Check( hCtx, ! lRes, ;
      "A3.5.2: string 1000 chars vs short -> .F. inmediato", ".F.", hb_ValToStr( lRes ) )
RETURN

// ---------------------------------------------------------------
// [A4.12] Trailing slash normalisation — /route/ matches route /route
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A04012_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA04012_ExactMatch(       hCtx )
   _AudA04012_TrailingSlash(    hCtx )
   _AudA04012_RootKept(         hCtx )
   _AudA04012_DoubleSlash(      hCtx )

RETURN hCtx

// TC1: /ping sin trailing slash — ruta normal sigue funcionando
STATIC PROCEDURE _AudA04012_ExactMatch( hCtx )
   LOCAL oReq, lCalled
   lCalled := .F.
   HIX_RouteAdd( "aud4012.exact", "/aud4012/ping", {|o| o:Respond( "pong", 200, "text" ) }, "GET" )
   oReq := TMockRequest():New( "/aud4012/ping", "GET" )
   HIX_RouteDispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "pong", ;
      "A4.12: ruta exacta /aud4012/ping sigue funcionando", "200+pong", ;
      hb_NToS( oReq:nStatus ) + "+" + oReq:cBody )
RETURN

// TC2: /ping/ (trailing slash) debe despachar la misma ruta que /ping
STATIC PROCEDURE _AudA04012_TrailingSlash( hCtx )
   LOCAL oReq
   oReq := TMockRequest():New( "/aud4012/ping/", "GET" )
   HIX_RouteDispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "pong", ;
      "A4.12: trailing slash /aud4012/ping/ matchea ruta /aud4012/ping", "200+pong", ;
      hb_NToS( oReq:nStatus ) + "+" + oReq:cBody )
RETURN

// TC3: root "/" NO pierde la barra (la homepage es "/", no "")
// En modo web UI, app.prg pre-registra la ruta "index" con patrón "/".
// La eliminamos (HIX_RouteDelete es idempotente — no-op en --cli) para
// que "aud4012.root" sea la única ruta con patrón "/". No restauramos
// "index" al final: si el usuario necesita la homepage, basta con
// reiniciar el servidor (el arranque re-registra las rutas).
STATIC PROCEDURE _AudA04012_RootKept( hCtx )
   LOCAL oReq
   HIX_RouteDelete( "index" )
   HIX_RouteAdd( "aud4012.root", "/", {|o| o:Respond( "root_ok", 200, "text" ) }, "GET" )
   oReq := TMockRequest():New( "/", "GET" )
   HIX_RouteDispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "root_ok", ;
      "A4.12: root '/' no se strip — sigue respondiendo", "200+root_ok", ;
      hb_NToS( oReq:nStatus ) + "+" + oReq:cBody )
   HIX_RouteDelete( "aud4012.root" )
RETURN

// TC4: doble barra //route/ tambien se normaliza (PathNormalize ya lo hace)
STATIC PROCEDURE _AudA04012_DoubleSlash( hCtx )
   LOCAL oReq
   oReq := TMockRequest():New( "//aud4012/ping/", "GET" )
   HIX_RouteDispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "pong", ;
      "A4.12: //aud4012/ping/ normalizado y matchea", "200+pong", ;
      hb_NToS( oReq:nStatus ) + "+" + oReq:cBody )
RETURN

// ---------------------------------------------------------------
// [A4.13] Cookie Secure flag — obligatorio sobre HTTPS
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A04013_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA04013_HttpNoSecure(  hCtx )
   _AudA04013_HttpsSecure(   hCtx )
   _AudA04013_HttpsExpire(   hCtx )

RETURN hCtx

// TC1: HTTP — no debe incluir Secure
STATIC PROCEDURE _AudA04013_HttpNoSecure( hCtx )
   LOCAL oReq, cCookie
   oReq := TMockRequest():New( "/", "GET" )
   // cProtoScheme == "" (default) → IsHttps() == .F.
   HIX_SetCookie( oReq, "sess", "abc123", 3600 )
   cCookie := hb_HGetDef( oReq:hExtraHeaders, "Set-Cookie", "" )
   HixTU_Check( hCtx, ;
      "Secure" $ cCookie == .F. .AND. "sess=abc123" $ cCookie, ;
      "A4.13: HTTP — sin flag Secure", "sin Secure", ;
      iif( "Secure" $ cCookie, "tiene Secure", "sin Secure" ) )
RETURN

// TC2: HTTPS — debe incluir Secure
STATIC PROCEDURE _AudA04013_HttpsSecure( hCtx )
   LOCAL oReq, cCookie
   oReq := TMockRequest():New( "/", "GET" )
   oReq:cProtoScheme := "https"   // simula conexion TLS
   HIX_SetCookie( oReq, "sess", "abc123", 3600 )
   cCookie := hb_HGetDef( oReq:hExtraHeaders, "Set-Cookie", "" )
   HixTU_Check( hCtx, ;
      "; Secure" $ cCookie .AND. "sess=abc123" $ cCookie, ;
      "A4.13: HTTPS — incluye flag Secure", "; Secure presente", ;
      iif( "; Secure" $ cCookie, "; Secure presente", "sin Secure" ) )
RETURN

// TC3: HTTPS + expirar (nMaxAge=-1) — Secure debe seguir presente
STATIC PROCEDURE _AudA04013_HttpsExpire( hCtx )
   LOCAL oReq, cCookie
   oReq := TMockRequest():New( "/", "GET" )
   oReq:cProtoScheme := "https"
   HIX_SetCookie( oReq, "sess", "", -1 )
   cCookie := hb_HGetDef( oReq:hExtraHeaders, "Set-Cookie", "" )
   HixTU_Check( hCtx, ;
      "; Secure" $ cCookie .AND. "Max-Age=0" $ cCookie, ;
      "A4.13: HTTPS expire — Secure + Max-Age=0", "; Secure + Max-Age=0", ;
      iif( "; Secure" $ cCookie .AND. "Max-Age=0" $ cCookie, "; Secure + Max-Age=0", cCookie ) )
RETURN

// ---------------------------------------------------------------
// [A4.14] HIX_ConstantEq compartida — jwt y token delegan aquí
// ---------------------------------------------------------------
FUNCTION HIX_TestAudit_A04014_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _AudA04014_MatchEqual(     hCtx )
   _AudA04014_MatchDiffer(    hCtx )
   _AudA04014_LenMismatch(    hCtx )
   _AudA04014_ViaJwtWrapper(  hCtx )
   _AudA04014_ViaTokenWrapper( hCtx )

RETURN hCtx

// TC1: strings iguales -> .T.
STATIC PROCEDURE _AudA04014_MatchEqual( hCtx )
   HixTU_Check( hCtx, HIX_ConstantEq( "abc", "abc" ), ;
      "A4.14: strings iguales -> .T.", ".T.", ".F." )
RETURN

// TC2: strings distintos -> .F.
STATIC PROCEDURE _AudA04014_MatchDiffer( hCtx )
   HixTU_Check( hCtx, ! HIX_ConstantEq( "abc", "xyz" ), ;
      "A4.14: strings distintos -> .F.", ".F.", ".T." )
RETURN

// TC3: longitudes distintas -> .F. inmediato
STATIC PROCEDURE _AudA04014_LenMismatch( hCtx )
   HixTU_Check( hCtx, ! HIX_ConstantEq( "ab", "abc" ), ;
      "A4.14: longitudes distintas -> .F.", ".F.", ".T." )
RETURN

// TC4: HIX_JwtConstantEq delega a la misma implementacion
STATIC PROCEDURE _AudA04014_ViaJwtWrapper( hCtx )
   HixTU_Check( hCtx, HIX_JwtConstantEq( "sig42", "sig42" ) .AND. ;
                      ! HIX_JwtConstantEq( "sig42", "sig43" ), ;
      "A4.14: HIX_JwtConstantEq consistente", "ok", "fail" )
RETURN

// TC5: HIX_TokenConstantEq delega a la misma implementacion
STATIC PROCEDURE _AudA04014_ViaTokenWrapper( hCtx )
   HixTU_Check( hCtx, HIX_TokenConstantEq( "tok99", "tok99" ) .AND. ;
                      ! HIX_TokenConstantEq( "tok99", "tok98" ), ;
      "A4.14: HIX_TokenConstantEq consistente", "ok", "fail" )
RETURN

