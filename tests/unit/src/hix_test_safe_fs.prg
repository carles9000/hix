/*-----------------------------------------------------------
  File ......: hix_test_safe_fs.prg
  Author.....: Charly 9000
  Created....: 2026-09-18
  Description: Safe-Delete Root Guard tests. Verifies that
               HIX_SafeErase / HIX_SafeDirDelete refuse any path
               outside HIX_AppRoot() or matching the hardcoded
               system-path blacklist, and only accept paths
               strictly under the app root.
  Usage      : Registered in app.prg -> HIX_TestSafeFs_Run()
 -----------------------------------------------------------*/

FUNCTION HIX_TestSafeFs_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _TestSafeFs_Reject_Empty(         hCtx )
   _TestSafeFs_Reject_Nil(           hCtx )
   _TestSafeFs_Reject_DriveRoot(     hCtx )
   _TestSafeFs_Reject_SystemPath(    hCtx )
   _TestSafeFs_Reject_UnixSystem(    hCtx )
   _TestSafeFs_Reject_Traversal(     hCtx )
   _TestSafeFs_Reject_TraversalDeep( hCtx )
   _TestSafeFs_Reject_NullByte(      hCtx )
   _TestSafeFs_Reject_RootItself(    hCtx )
   _TestSafeFs_Reject_SiblingEscape( hCtx )

   _TestSafeFs_Accept_UnderRoot(     hCtx )
   _TestSafeFs_Accept_UnderSubdir(   hCtx )
   _TestSafeFs_Accept_DotResolves(   hCtx )

RETURN hCtx

// ---------------------------------------------------------------
// TC1: empty string -> .F.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_Empty( hCtx )
   HixTU_Check( hCtx, ! HIX_SafeErase( "" ), ;
      "SafeFs T01: HIX_SafeErase('') rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC2: NIL -> .F. (no crash)
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_Nil( hCtx )
   HixTU_Check( hCtx, ! HIX_SafeErase( NIL ), ;
      "SafeFs T02: HIX_SafeErase(NIL) rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC3: raiz de unidad (Windows) o "/" (Linux) -> .F.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_DriveRoot( hCtx )
   LOCAL cPath := iif( hb_ps() == "\", "c:\", "/" )
   HixTU_Check( hCtx, ! HIX_SafeErase( cPath ), ;
      "SafeFs T03: HIX_SafeErase(drive root) rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC4: fichero de sistema (kernel32.dll / passwd) -> .F.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_SystemPath( hCtx )
   LOCAL cPath := iif( hb_ps() == "\", ;
                       "c:\windows\system32\kernel32.dll", ;
                       "/usr/bin/ls" )
   HixTU_Check( hCtx, ! HIX_SafeErase( cPath ), ;
      "SafeFs T04: HIX_SafeErase(system path) rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC5: /etc/passwd (o equivalente Windows) -> .F. via blacklist
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_UnixSystem( hCtx )
   LOCAL cPath := iif( hb_ps() == "\", ;
                       "c:\programdata\test.txt", ;
                       "/etc/passwd" )
   HixTU_Check( hCtx, ! HIX_SafeErase( cPath ), ;
      "SafeFs T05: HIX_SafeErase(blacklist recursive) rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC6: traversal relativa "../../pepito.txt" -> .F.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_Traversal( hCtx )
   HixTU_Check( hCtx, ! HIX_SafeErase( ".." + hb_ps() + ".." + hb_ps() + "pepito.txt" ), ;
      "SafeFs T06: HIX_SafeErase('../../pepito') rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC7: traversal absoluta con .. dentro -> .F.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_TraversalDeep( hCtx )
   LOCAL cRoot := HIX_AppRoot()
   LOCAL cPath := cRoot + ".." + hb_ps() + ".." + hb_ps() + "pepito.txt"
   HixTU_Check( hCtx, ! HIX_SafeErase( cPath ), ;
      "SafeFs T07: HIX_SafeErase(root+../../pepito) rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC8: null byte injection -> .F.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_NullByte( hCtx )
   LOCAL cPath := HIX_AppRoot() + "file" + Chr( 0 ) + ".safe"
   HixTU_Check( hCtx, ! HIX_SafeErase( cPath ), ;
      "SafeFs T08: HIX_SafeErase(null byte) rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC9: HIX_SafeDirDelete(HIX_AppRoot()) -> .F. (no borrar la raiz)
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_RootItself( hCtx )
   HixTU_Check( hCtx, ! HIX_SafeDirDelete( HIX_AppRoot() ), ;
      "SafeFs T09: HIX_SafeDirDelete(AppRoot) rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC10: sibling escape via .. -> .F.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Reject_SiblingEscape( hCtx )
   LOCAL cPath := HIX_AppRoot() + ".." + hb_ps() + "hix.other"
   HixTU_Check( hCtx, ! HIX_SafeDirDelete( cPath ), ;
      "SafeFs T10: HIX_SafeDirDelete(../sibling) rechaza", ".F.", ".T." )
RETURN

// ---------------------------------------------------------------
// TC11: fichero real bajo root -> .T. (creado y borrado)
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Accept_UnderRoot( hCtx )

   LOCAL cPath := HIX_AppRoot() + "safe_fs_test.tmp"
   LOCAL lOk

   hb_MemoWrit( cPath, "probe" )

   lOk := HIX_SafeErase( cPath )
   HixTU_Check( hCtx, lOk .AND. ! hb_FileExists( cPath ), ;
      "SafeFs T11: HIX_SafeErase(file bajo root) borra OK", ".T.", ;
      hb_CStr( lOk ) )

RETURN

// ---------------------------------------------------------------
// TC12: fichero en subdirectorio bajo root -> .T.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Accept_UnderSubdir( hCtx )

   LOCAL cDir  := HIX_AppRoot() + "safe_fs_sub"
   LOCAL cPath := cDir + hb_ps() + "probe.tmp"
   LOCAL lOk

   IF ! hb_DirExists( cDir ) ; hb_DirCreate( cDir ) ; ENDIF
   hb_MemoWrit( cPath, "probe" )

   lOk := HIX_SafeErase( cPath )
   HixTU_Check( hCtx, lOk .AND. ! hb_FileExists( cPath ), ;
      "SafeFs T12: HIX_SafeErase(subdir/probe) borra OK", ".T.", ;
      hb_CStr( lOk ) )

   HIX_SafeDirDelete( cDir )

RETURN

// ---------------------------------------------------------------
// TC13: path con '.' intermedio pero dentro de root -> .T.
// ---------------------------------------------------------------
STATIC PROCEDURE _TestSafeFs_Accept_DotResolves( hCtx )

   LOCAL cPath := HIX_AppRoot() + "." + hb_ps() + "safe_fs_dot.tmp"
   LOCAL lOk

   hb_MemoWrit( HIX_AppRoot() + "safe_fs_dot.tmp", "probe" )

   lOk := HIX_SafeErase( cPath )
   HixTU_Check( hCtx, lOk .AND. ! hb_FileExists( HIX_AppRoot() + "safe_fs_dot.tmp" ), ;
      "SafeFs T13: HIX_SafeErase(./file) resuelve y borra", ".T.", ;
      hb_CStr( lOk ) )

RETURN
