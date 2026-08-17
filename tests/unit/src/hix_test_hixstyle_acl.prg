/*-----------------------------------------------------------
  File ......: hix_test_hixstyle_acl.prg
  Author.....: Charly 9000
  Created....: 2026-07-13
  Version....: 1.0.0
  Description: Integrated test - hixstyle whitelist ACL
               Verifies AllowDir(cDir, lAllowExec) semantics and
               Dispatch() enforcement of aAllowDirs. Uses
               THixDispatcher directly (no HTTP layer) via
               TMockRequest from hix_test_utils.prg.
  Usage      : called from app.prg _TestGroups() as HIX_TestHixstyleAcl_Run
  Notes      : Also covers HIX_FileRoute bypass (lSkipDeny=.T.)
               and per-folder exec override for dispatch_mode=static.
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"
#include "fileio.ch"

// -------------------------------------------------------
// Helpers
// -------------------------------------------------------
STATIC FUNCTION _Dispatch( oDisp, cPath )
   LOCAL oReq := TMockRequest():New( cPath, "GET" )
   LOCAL oErr
   TRY
      oDisp:Dispatch( oReq )
   CATCH oErr
      IF ! oReq:lResponded
         oReq:nStatus    := iif( ValType( oErr:subCode ) == "N" .AND. oErr:subCode > 0, oErr:subCode, 500 )
         oReq:lResponded := .T.
         oReq:cBody      := oErr:description
      ENDIF
   END
RETURN oReq

// Prepara un root con estructura HixStyle: public/img/logo.png, controllers/foo.prg,
// views/x.html y una carpeta custom "micarpeta/bar.prg + bar.html".
STATIC FUNCTION _TmpRoot()
   LOCAL cRoot := hb_DirTemp() + "hix_tm_acl" + hb_ps()
   IF ! hb_DirExists( cRoot ) ; hb_DirCreate( cRoot ) ; ENDIF
   IF ! hb_DirExists( cRoot + "public" ) ; hb_DirCreate( cRoot + "public" ) ; ENDIF
   IF ! hb_DirExists( cRoot + "public" + hb_ps() + "img" )
      hb_DirCreate( cRoot + "public" + hb_ps() + "img" )
   ENDIF
   IF ! hb_DirExists( cRoot + "controllers" ) ; hb_DirCreate( cRoot + "controllers" ) ; ENDIF
   IF ! hb_DirExists( cRoot + "views" )       ; hb_DirCreate( cRoot + "views" )       ; ENDIF
   IF ! hb_DirExists( cRoot + "micarpeta" )   ; hb_DirCreate( cRoot + "micarpeta" )   ; ENDIF

   hb_MemoWrit( cRoot + "public" + hb_ps() + "img" + hb_ps() + "logo.png", "PNG" )
   hb_MemoWrit( cRoot + "controllers" + hb_ps() + "foo.prg", ;
                "FUNCTION Main()" + hb_eol() + "RETURN '<h1>ctrl</h1>'" )
   hb_MemoWrit( cRoot + "views" + hb_ps() + "x.html", "<html/>" )
   hb_MemoWrit( cRoot + "micarpeta" + hb_ps() + "bar.html", "<html>bar</html>" )
   hb_MemoWrit( cRoot + "micarpeta" + hb_ps() + "bar.prg", ;
                "FUNCTION Main()" + hb_eol() + "RETURN '<h1>bar</h1>'" )
RETURN cRoot

STATIC PROCEDURE _CleanTmpRoot( cRoot )
   LOCAL aFiles, aEntry
   IF ! hb_DirExists( cRoot ) ; RETURN ; ENDIF
   aFiles := Directory( cRoot + "*.*", "D" )
   FOR EACH aEntry IN aFiles
      IF aEntry[1] != "." .AND. aEntry[1] != ".."
         IF "D" $ aEntry[5]
            _CleanTmpRoot( cRoot + aEntry[1] + hb_ps() )
            DirRemove( cRoot + aEntry[1] )
         ELSE
            FErase( cRoot + aEntry[1] )
         ENDIF
      ENDIF
   NEXT
RETURN

// -------------------------------------------------------
// Root
// -------------------------------------------------------
FUNCTION HIX_TestHixstyleAcl_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cRoot := _TmpRoot()

   _AllowDirStruct(    hCtx )
   _WhitelistBlocks(   hCtx, cRoot )
   _WhitelistAllows(   hCtx, cRoot )
   _DenyOverWhitelist( hCtx, cRoot )
   _ExecPerFolder(     hCtx, cRoot )
   _FileRouteBypass(   hCtx, cRoot )
   _GetAclShape(       hCtx )

   _CleanTmpRoot( cRoot )
   DirRemove( cRoot )

   //	DEBUG: dump failures to traces/info.txt for triage
   _DumpFailures( hCtx )
RETURN hCtx

STATIC PROCEDURE _DumpFailures( hCtx )
   LOCAL hRes, nH, cOut := "=== HixstyleAcl failures ===" + hb_eol()
   FOR EACH hRes IN hCtx["results"]
      IF hRes["status"] == "fail"
         cOut += hRes["name"] + " | expected=" + hRes["exp"] + " got=" + hRes["got"] + hb_eol()
      ENDIF
   NEXT
   // Anexar, nunca hb_MemoWrit(): info.txt es el log compartido de todos
   // los tests y truncarlo borra las trazas de los que ya han corrido.
   nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, cOut )
      hb_vfClose( nH )
   ENDIF
RETURN

// -------------------------------------------------------
// 1. Estructura de aAllowDirs: hash {dir, exec}
// -------------------------------------------------------
STATIC PROCEDURE _AllowDirStruct( hCtx )
   LOCAL oDisp := THixDispatcher():New( "www" )

   oDisp:AllowDir( "public" )
   HixTU_Check( hCtx, ValType( oDisp:aAllowDirs ) == "A" .AND. Len( oDisp:aAllowDirs ) == 1, ;
      "ACL: AllowDir crea entrada", "A[1]", ;
      iif( oDisp:aAllowDirs == NIL, "NIL", "A" + hb_NToS( Len( oDisp:aAllowDirs ) ) ) )
   HixTU_Check( hCtx, oDisp:aAllowDirs[1]["dir"] == "public", ;
      "ACL: campo dir normalizado", "public", oDisp:aAllowDirs[1]["dir"] )
   HixTU_Check( hCtx, oDisp:aAllowDirs[1]["exec"] == .F., ;
      "ACL: exec default .F.", ".F.", iif( oDisp:aAllowDirs[1]["exec"], ".T.", ".F." ) )

   //	Upgrade: segunda llamada con exec=.T. lo activa
   oDisp:AllowDir( "public", .T. )
   HixTU_Check( hCtx, Len( oDisp:aAllowDirs ) == 1, ;
      "ACL: no duplica entrada existente", "1", hb_NToS( Len( oDisp:aAllowDirs ) ) )
   HixTU_Check( hCtx, oDisp:aAllowDirs[1]["exec"] == .T., ;
      "ACL: upgrade a exec=.T.", ".T.", iif( oDisp:aAllowDirs[1]["exec"], ".T.", ".F." ) )

   //	No downgrade: llamada posterior con exec=.F. no baja el flag
   oDisp:AllowDir( "public", .F. )
   HixTU_Check( hCtx, oDisp:aAllowDirs[1]["exec"] == .T., ;
      "ACL: no downgrade a exec=.F.", ".T.", iif( oDisp:aAllowDirs[1]["exec"], ".T.", ".F." ) )
RETURN

// -------------------------------------------------------
// 2. Whitelist bloquea carpetas no listadas (403)
// -------------------------------------------------------
STATIC PROCEDURE _WhitelistBlocks( hCtx, cRoot )
   LOCAL oDisp := THixDispatcher():New( cRoot )
   LOCAL oReq

   oDisp:AllowDir( "public" )

   oReq := _Dispatch( oDisp, "/views/x.html" )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "ACL: /views/x.html bloqueado", "403", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( oDisp, "/controllers/foo.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "ACL: /controllers/foo.prg bloqueado", "403", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( oDisp, "/micarpeta/bar.html" )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "ACL: /micarpeta sin AllowDir bloqueado", "403", hb_NToS( oReq:nStatus ) )
RETURN

// -------------------------------------------------------
// 3. Whitelist permite carpetas listadas
// -------------------------------------------------------
STATIC PROCEDURE _WhitelistAllows( hCtx, cRoot )
   LOCAL oDisp := THixDispatcher():New( cRoot )
   LOCAL oReq

   oDisp:AllowDir( "public" )
   oDisp:AllowDir( "micarpeta" )

   oReq := _Dispatch( oDisp, "/public/img/logo.png" )
   HixTU_Check( hCtx, oReq:nStatus == 200, ;
      "ACL: /public/img/logo.png sirve", "200", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( oDisp, "/micarpeta/bar.html" )
   HixTU_Check( hCtx, oReq:nStatus == 200, ;
      "ACL: /micarpeta/bar.html sirve tras AllowDir", "200", hb_NToS( oReq:nStatus ) )
RETURN

// -------------------------------------------------------
// 4. Deny gana sobre allow para el mismo path
// -------------------------------------------------------
STATIC PROCEDURE _DenyOverWhitelist( hCtx, cRoot )
   LOCAL oDisp := THixDispatcher():New( cRoot )
   LOCAL oReq

   oDisp:AllowDir( "micarpeta" )
   oDisp:DenyDir(  "micarpeta" )

   oReq := _Dispatch( oDisp, "/micarpeta/bar.html" )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "ACL: Deny gana sobre Allow", "403", hb_NToS( oReq:nStatus ) )
RETURN

// -------------------------------------------------------
// 5. Exec per-folder: lAllowExec=.T. permite PRG aunque lExecPrg=.F.
// -------------------------------------------------------
STATIC PROCEDURE _ExecPerFolder( hCtx, cRoot )
   LOCAL oDisp, oReq

   //	5a. dispatch_mode=static + AllowDir sin exec -> PRG bloqueado
   oDisp := THixDispatcher():New( cRoot )
   oDisp:lExecPrg := .F.
   oDisp:AllowDir( "micarpeta", .F. )
   oReq := _Dispatch( oDisp, "/micarpeta/bar.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "ACL: static + allow sin exec -> PRG 403", "403", hb_NToS( oReq:nStatus ) )

   //	5b. dispatch_mode=static + AllowDir con exec=.T. -> PRG ejecuta
   oDisp := THixDispatcher():New( cRoot )
   oDisp:lExecPrg := .F.
   oDisp:AllowDir( "micarpeta", .T. )
   oReq := _Dispatch( oDisp, "/micarpeta/bar.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 200, ;
      "ACL: static + allow(exec) -> PRG 200", "200", hb_NToS( oReq:nStatus ) )

   //	5c. dispatch_mode=full (default) + AllowDir sin exec -> sigue funcionando
   oDisp := THixDispatcher():New( cRoot )
   oDisp:AllowDir( "micarpeta", .F. )
   oReq := _Dispatch( oDisp, "/micarpeta/bar.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 200, ;
      "ACL: full + allow(no exec) -> PRG 200", "200", hb_NToS( oReq:nStatus ) )
RETURN

// -------------------------------------------------------
// 6. HIX_FileRoute bypasea whitelist (lSkipDeny=.T. en el codeblock generado)
// -------------------------------------------------------
STATIC PROCEDURE _FileRouteBypass( hCtx, cRoot )
   LOCAL oDisp := THixDispatcher():New( cRoot )
   LOCAL bAction, oReq

   //	Solo public en whitelist -> "controllers" bloqueado por URL directa
   oDisp:AllowDir( "public" )

   //	Ruta registrada apuntando a controllers/foo.prg debe ejecutar
   //	aunque controllers no este en la whitelist (bypass por lSkipDeny=.T.)
   bAction := HIX_FileRoute( oDisp, "controllers/foo.prg" )
   HixTU_Check( hCtx, ValType( bAction ) == "B", ;
      "ACL: HIX_FileRoute retorna codeblock", "B", ValType( bAction ) )

   oReq := TMockRequest():New( "/anything", "GET" )
   Eval( bAction, oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200, ;
      "ACL: ruta registrada a controllers/ ejecuta (bypass)", "200", hb_NToS( oReq:nStatus ) )
RETURN

// -------------------------------------------------------
// 7. GetACL expone la estructura enriquecida
// -------------------------------------------------------
STATIC PROCEDURE _GetAclShape( hCtx )
   LOCAL oDisp := THixDispatcher():New( "www" )
   LOCAL hAcl, aAllow

   oDisp:AllowDir( "public", .F. )
   oDisp:AllowDir( "admin",  .T. )
   hAcl := oDisp:GetACL()

   HixTU_Check( hCtx, ValType( hAcl["allow_dirs"] ) == "A", ;
      "ACL: GetACL.allow_dirs es array", "A", ValType( hAcl["allow_dirs"] ) )

   aAllow := hAcl["allow_dirs"]
   HixTU_Check( hCtx, Len( aAllow ) == 2, ;
      "ACL: GetACL.allow_dirs Len=2", "2", hb_NToS( Len( aAllow ) ) )
   HixTU_Check( hCtx, aAllow[1]["dir"] == "public" .AND. aAllow[1]["exec"] == .F., ;
      "ACL: GetACL[1] public sin exec", "public/.F.", ;
      aAllow[1]["dir"] + "/" + iif( aAllow[1]["exec"], ".T.", ".F." ) )
   HixTU_Check( hCtx, aAllow[2]["dir"] == "admin" .AND. aAllow[2]["exec"] == .T., ;
      "ACL: GetACL[2] admin con exec", "admin/.T.", ;
      aAllow[2]["dir"] + "/" + iif( aAllow[2]["exec"], ".T.", ".F." ) )
RETURN
