/*-----------------------------------------------------------
  File ......: hix_test_permissions.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Modified...: 2026-06-09
  Version....: 2.0.0
  Description: Integrated test — unified roles model (HIX_MwHasRole, UHasRole)
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[Perm] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

STATIC FUNCTION _MakeCtxPerm( oReq, hUser, cScope )
   LOCAL oCtx
   hb_default( @cScope, "" )
   oCtx                  := THixContext():New( oReq, "", cScope )
   oCtx:hData["session"] := { => }
   IF ValType( hUser ) == "H"
      oCtx:hData["user"] := hUser
      oReq:hData["user"] := hUser
   ENDIF
RETURN oCtx

FUNCTION HIX_TestPermissions_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   UAuthLogout()
   _TLog( "=== Permissions Test Start ===" )
   _TestRolesLogic(         hCtx )
   _TestRolesGranularLogic( hCtx )
   _TestUHasRole(           hCtx )
   _TestUHasRoleOps(        hCtx )
   _TestMwHasRole(          hCtx )
   _TestMwHasRoleOps(       hCtx )
   _TestPipeline(           hCtx )
   _TLog( "=== Permissions Test End ===" )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestRolesLogic( hCtx )
   LOCAL hAdmin  := { "roles" => { "admin" => "", "masters" => "" } }
   LOCAL hEditor := { "roles" => { "editor" => "" } }
   LOCAL hNoRole := { "roles" => { => } }
   LOCAL hNoKey  := { => }
   _TLog( "--- RolesLogic ---" )

   HixTU_Check( hCtx, HB_HHasKey( hAdmin["roles"],  "admin"   ), "Perm: admin tiene rol admin",    ".T.", ".F." )
   HixTU_Check( hCtx, HB_HHasKey( hAdmin["roles"],  "masters" ), "Perm: admin tiene rol masters",  ".T.", ".F." )
   HixTU_Check( hCtx, ! HB_HHasKey( hAdmin["roles"], "editor" ), "Perm: admin no tiene editor",    ".F.", ".T." )
   HixTU_Check( hCtx, ! HB_HHasKey( hAdmin["roles"], "ghost"  ), "Perm: admin no tiene ghost",     ".F.", ".T." )
   HixTU_Check( hCtx, HB_HHasKey( hEditor["roles"],  "editor" ), "Perm: editor tiene editor",      ".T.", ".F." )
   HixTU_Check( hCtx, ! HB_HHasKey( hEditor["roles"], "admin" ), "Perm: editor no tiene admin",    ".F.", ".T." )
   HixTU_Check( hCtx, Empty( hNoRole["roles"] ),                  "Perm: hash roles vacio",         ".T.", ".F." )
   HixTU_Check( hCtx, ! HB_HHasKey( hb_HGetDef( hNoKey, "roles", {=>} ), "admin" ), "Perm: sin clave roles", ".F.", ".T." )
RETURN

STATIC PROCEDURE _TestRolesGranularLogic( hCtx )
   LOCAL hAdmin := { "roles" => { "compras" => "", "ventas" => "", "masters" => "" } }
   LOCAL hUser  := { "roles" => { "compras" => "show;create", "masters" => "" } }
   LOCAL cOps, cOp
   _TLog( "--- RolesGranularLogic ---" )

   cOps := hb_HGetDef( hAdmin["roles"], "compras", NIL )
   HixTU_Check( hCtx, cOps != NIL,   "Perm: admin tiene modulo compras",   "not NIL", "NIL" )
   HixTU_Check( hCtx, Empty( cOps ), "Perm: admin acceso total a compras", "''",      cOps )

   cOps := hb_HGetDef( hAdmin["roles"], "ventas", NIL )
   HixTU_Check( hCtx, cOps != NIL .AND. Empty( cOps ),                      "Perm: admin acceso total ventas",  ".T.", ".F." )
   HixTU_Check( hCtx, hb_HGetDef( hAdmin["roles"], "rrhh", NIL ) == NIL,    "Perm: admin no tiene rrhh",        "NIL", "not NIL" )

   cOps := hb_HGetDef( hUser["roles"], "compras", NIL )
   cOp  := "show"
   HixTU_Check( hCtx, ";" + cOp + ";" $ ";" + cOps + ";",    "Perm: user puede show en compras",      ".T.", ".F." )
   cOp  := "create"
   HixTU_Check( hCtx, ";" + cOp + ";" $ ";" + cOps + ";",    "Perm: user puede create en compras",    ".T.", ".F." )
   cOp  := "delete"
   HixTU_Check( hCtx, ! (";" + cOp + ";" $ ";" + cOps + ";"), "Perm: user NO puede delete compras",   ".F.", ".T." )
   cOp  := "admin"
   HixTU_Check( hCtx, ! (";" + cOp + ";" $ ";" + cOps + ";"), "Perm: user NO puede admin compras",    ".F.", ".T." )

   cOps := hb_HGetDef( hUser["roles"], "masters", NIL )
   HixTU_Check( hCtx, cOps != NIL .AND. Empty( cOps ),                    "Perm: user acceso total masters",  ".T.", ".F." )
   HixTU_Check( hCtx, hb_HGetDef( hUser["roles"], "ventas", NIL ) == NIL, "Perm: user NO tiene ventas",       "NIL", "not NIL" )
RETURN

STATIC PROCEDURE _TestUHasRole( hCtx )
   LOCAL oReq, oCtx
   LOCAL hAdmin  := { "id" => "1", "name" => "Admin",  "roles" => { "admin" => "", "masters" => "" } }
   LOCAL hEditor := { "id" => "2", "name" => "Editor", "roles" => { "editor" => "" } }
   _TLog( "--- UHasRole ---" )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin )
   HIX_SetContext( oCtx )
   HIX_SetRequest( oReq )
   HixTU_Check( hCtx, UHasRole( "admin"   ),   "Perm U: admin tiene admin",     ".T.", ".F." )
   HixTU_Check( hCtx, UHasRole( "masters" ),   "Perm U: admin tiene masters",   ".T.", ".F." )
   HixTU_Check( hCtx, ! UHasRole( "editor" ),  "Perm U: admin no tiene editor", ".F.", ".T." )
   HixTU_Check( hCtx, ! UHasRole( "ghost"  ),  "Perm U: admin no tiene ghost",  ".F.", ".T." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hEditor )
   HIX_SetContext( oCtx )
   HIX_SetRequest( oReq )
   HixTU_Check( hCtx, UHasRole( "editor" ),    "Perm U: editor tiene editor",   ".T.", ".F." )
   HixTU_Check( hCtx, ! UHasRole( "admin" ),   "Perm U: editor no tiene admin", ".F.", ".T." )

   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq, "", "" )
   HIX_SetContext( oCtx )
   HIX_SetRequest( oReq )
   HixTU_Check( hCtx, ! UHasRole( "admin" ), "Perm U: sin user -> .F.", ".F.", ".T." )
RETURN

STATIC PROCEDURE _TestUHasRoleOps( hCtx )
   LOCAL oReq, oCtx
   LOCAL hAdmin := { "id" => "1", "roles" => { "admin" => "", "compras" => "", "ventas" => "", "masters" => "" } }
   LOCAL hUser  := { "id" => "2", "roles" => { "editor" => "", "compras" => "show;create", "masters" => "" } }
   _TLog( "--- UHasRoleOps ---" )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin )
   HIX_SetContext( oCtx )
   HIX_SetRequest( oReq )
   HixTU_Check( hCtx, UHasRole( "compras" ),             "Perm U: admin accede compras",        ".T.", ".F." )
   HixTU_Check( hCtx, UHasRole( "compras", "delete" ),   "Perm U: admin puede delete compras",  ".T.", ".F." )
   HixTU_Check( hCtx, UHasRole( "compras", "admin"  ),   "Perm U: admin puede admin compras",   ".T.", ".F." )
   HixTU_Check( hCtx, UHasRole( "ventas",  "show"   ),   "Perm U: admin puede show ventas",     ".T.", ".F." )
   HixTU_Check( hCtx, ! UHasRole( "rrhh" ),              "Perm U: admin no tiene rrhh",         ".F.", ".T." )
   HixTU_Check( hCtx, ! UHasRole( "rrhh", "show"    ),   "Perm U: admin rrhh:show -> .F.",      ".F.", ".T." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hUser )
   HIX_SetContext( oCtx )
   HIX_SetRequest( oReq )
   HixTU_Check( hCtx, UHasRole( "compras"              ), "Perm U: user accede compras",           ".T.", ".F." )
   HixTU_Check( hCtx, UHasRole( "compras", "show"   ),    "Perm U: user puede show compras",       ".T.", ".F." )
   HixTU_Check( hCtx, UHasRole( "compras", "create" ),    "Perm U: user puede create compras",     ".T.", ".F." )
   HixTU_Check( hCtx, ! UHasRole( "compras", "delete" ),  "Perm U: user NO puede delete compras",  ".F.", ".T." )
   HixTU_Check( hCtx, ! UHasRole( "compras", "admin"  ),  "Perm U: user NO puede admin compras",   ".F.", ".T." )
   HixTU_Check( hCtx, UHasRole( "masters" ),              "Perm U: user accede masters (full)",    ".T.", ".F." )
   HixTU_Check( hCtx, UHasRole( "masters", "delete"  ),   "Perm U: user masters:delete (full)",    ".T.", ".F." )
   HixTU_Check( hCtx, UHasRole( "masters", "admin"   ),   "Perm U: user masters:admin (full)",     ".T.", ".F." )
   HixTU_Check( hCtx, ! UHasRole( "ventas" ),             "Perm U: user NO tiene ventas",          ".F.", ".T." )
   HixTU_Check( hCtx, ! UHasRole( "ventas", "show"   ),   "Perm U: user ventas:show -> .F.",       ".F.", ".T." )

   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq, "", "" )
   HIX_SetContext( oCtx )
   HIX_SetRequest( oReq )
   HixTU_Check( hCtx, ! UHasRole( "compras" ),           "Perm U: sin user -> .F.",     ".F.", ".T." )
   HixTU_Check( hCtx, ! UHasRole( "compras", "show" ),   "Perm U: sin user op -> .F.",  ".F.", ".T." )
RETURN

STATIC PROCEDURE _TestMwHasRole( hCtx )
   LOCAL oReq, oCtx, lOk
   LOCAL hAdmin := { "roles" => { "admin" => "", "masters" => "" } }
   LOCAL hUser  := { "roles" => { "editor" => "" } }
   _TLog( "--- MwHasRole ---" )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin, "" )
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Perm Mw: scope vacio pasa siempre",      ".T.", ".F." )
   HixTU_Check( hCtx, ! oCtx:lHandled,       "Perm Mw: scope vacio lHandled .F.",       ".F.", ".T." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin, "admin" )
   lOk  := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, lOk,             "Perm Mw: admin scope admin pasa",        ".T.", ".F." )
   HixTU_Check( hCtx, ! oCtx:lHandled, "Perm Mw: admin scope admin handled .F.", ".F.", ".T." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin, "masters" )
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Perm Mw: admin scope masters pasa",   ".T.", ".F." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hUser, "admin" )
   lOk  := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lOk,               "Perm Mw: user scope admin denegado",    ".F.", ".T." )
   HixTU_Check( hCtx, oCtx:lHandled,       "Perm Mw: user scope admin handled .T.", ".T.", ".F." )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Perm Mw: user scope admin 403",         "403", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hUser, "editor" )
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Perm Mw: user scope editor pasa", ".T.", ".F." )

   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq, "", "admin" )
   lOk  := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lOk,               "Perm Mw: sin user denegado", ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Perm Mw: sin user 403",      "403", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestMwHasRoleOps( hCtx )
   LOCAL oReq, oCtx, lOk
   LOCAL hAdmin := { "roles" => { "compras" => "", "ventas" => "", "masters" => "" } }
   LOCAL hUser  := { "roles" => { "compras" => "show;create", "masters" => "" } }
   _TLog( "--- MwHasRoleOps ---" )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin, "" )
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Perm Mp: scope vacio pasa siempre",        ".T.", ".F." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin, "compras" )
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Perm Mp: admin scope compras pasa",         ".T.", ".F." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin, "compras:delete" )
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Perm Mp: admin scope compras:delete pasa",  ".T.", ".F." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hAdmin, "rrhh" )
   lOk  := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lOk,               "Perm Mp: admin scope rrhh denegado",          ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Perm Mp: admin scope rrhh 403",               "403", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hUser, "compras:show" )
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Perm Mp: user scope compras:show pasa",    ".T.", ".F." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hUser, "compras:delete" )
   lOk  := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lOk,               "Perm Mp: user scope compras:delete denegado", ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Perm Mp: user scope compras:delete 403",      "403", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hUser, "masters:delete" )
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Perm Mp: user scope masters:delete pasa",  ".T.", ".F." )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hUser, "ventas" )
   lOk  := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lOk,               "Perm Mp: user scope ventas denegado",         ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Perm Mp: user scope ventas 403",              "403", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq, "", "compras" )
   lOk  := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lOk,               "Perm Mp: sin user denegado",                 ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Perm Mp: sin user 403",                       "403", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestPipeline( hCtx )
   LOCAL oReq, oCtx, lRole
   LOCAL hAdmin := { "id" => "1", "name" => "Admin", "roles" => { "admin" => "", "compras" => "", "ventas" => "", "masters" => "" } }
   LOCAL hUser  := { "id" => "2", "name" => "User",  "roles" => { "editor" => "", "compras" => "show;create", "masters" => "" } }
   _TLog( "--- Pipeline ---" )

   oReq  := TMockRequest():New( "/customer/delete", "POST" )
   oCtx  := _MakeCtxPerm( oReq, hAdmin, "admin" )
   lRole := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, lRole, "Perm Pipe: admin role admin OK",           ".T.", ".F." )

   oCtx:cScope := "compras:delete"
   lRole := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, lRole, "Perm Pipe: admin compras:delete OK",       ".T.", ".F." )

   oReq  := TMockRequest():New( "/customer/delete", "POST" )
   oCtx  := _MakeCtxPerm( oReq, hUser, "editor" )
   lRole := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, lRole,   "Perm Pipe: user rol editor OK",              ".T.", ".F." )

   oCtx:cScope := "compras:delete"
   lRole := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lRole, "Perm Pipe: user compras:delete denegado",   ".F.", ".T." )

   oReq  := TMockRequest():New( "/admin", "GET" )
   oCtx  := _MakeCtxPerm( oReq, hUser, "admin" )
   lRole := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lRole,             "Perm Pipe: user rol admin denegado",  ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Perm Pipe: rol admin -> 403",         "403", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New()
   oCtx := _MakeCtxPerm( oReq, hUser )
   HIX_SetContext( oCtx )
   HIX_SetRequest( oReq )
   HixTU_Check( hCtx, UHasRole( "editor" ),               "Perm Pipe: UHasRole editor OK",          ".T.", ".F." )
   HixTU_Check( hCtx, ! UHasRole( "admin" ),              "Perm Pipe: UHasRole admin denegado",     ".F.", ".T." )
   HixTU_Check( hCtx, UHasRole( "compras", "show"   ),    "Perm Pipe: UHasRole compras:show OK",    ".T.", ".F." )
   HixTU_Check( hCtx, ! UHasRole( "compras", "delete" ),  "Perm Pipe: UHasRole compras:delete KO",  ".F.", ".T." )
   HixTU_Check( hCtx, UHasRole( "masters", "delete" ),    "Perm Pipe: UHasRole masters:delete OK",  ".T.", ".F." )
   HixTU_Check( hCtx, ! UHasRole( "ventas" ),             "Perm Pipe: UHasRole ventas KO",          ".F.", ".T." )
RETURN
