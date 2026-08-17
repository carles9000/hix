/*-----------------------------------------------------------
  File ......: hix_test_new_overrides.prg
  Author.....: Charly 9000
  Created....: 2026-07-08
  Modified...: 2026-07-08
  Version....: 1.0.0
  Description: Test HIX_ConfigMerge + THixServer:New( hOverrides ).
               Verifica que el hash de overrides muta la config
               global sin borrar claves ajenas, respeta la firma
               retrocompatible New() y que sub-servers ignoran el
               argumento (no contaminan al server dueno).
  Usage      : llamado desde app.prg _TestGroups() como HIX_TestNewOverrides_Run
  Notes      : el proceso ya tiene snServerCount >= 1, por lo que
               las llamadas a New() en este test son sub-servers.
 -----------------------------------------------------------*/
#include "hbclass.ch"
#include "hix_logger.ch"

FUNCTION HIX_TestNewOverrides_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   //	Baseline: garantizar config cargada antes de mutar
   HIX_LoadConfig( , .T. )

   _TestNoArgs(         hCtx )
   _TestMergeSimple(    hCtx )
   _TestMergeMulti(     hCtx )
   _TestNewSection(     hCtx )
   _TestEmptyIgnored(   hCtx )
   _TestSubServerIgnores( hCtx )

   //	Restore para no contaminar tests siguientes
   HIX_LoadConfig( , .T. )

RETURN hCtx

// -------------------------------------------------------
// Retrocompatibilidad: New() sin args devuelve Self valido.
// -------------------------------------------------------
STATIC PROCEDURE _TestNoArgs( hCtx )
   LOCAL oSrv := THixServer():New()
   HixTU_Check( hCtx, oSrv != NIL,                                  ;
      "NewOverrides: New() sin args -> Self", "!=NIL",              ;
      iif( oSrv == NIL, "NIL", "obj" ) )
   HixTU_Check( hCtx, oSrv:ClassName() == "THIXSERVER",             ;
      "NewOverrides: New() clase correcta", "THIXSERVER",           ;
      hb_CStr( oSrv:ClassName() ) )
RETURN

// -------------------------------------------------------
// Merge de una sola clave sobre seccion existente.
// -------------------------------------------------------
STATIC PROCEDURE _TestMergeSimple( hCtx )
   LOCAL cPrev := UConfig( "app", "env", "" )
   LOCAL cOtherPrev := UConfig( "app", "default_page", "" )

   HIX_ConfigMerge( { "app" => { "env" => "prod" } } )

   HixTU_Check( hCtx, UConfig( "app", "env", "" ) == "prod",        ;
      "NewOverrides: merge simple app.env=prod", "prod",            ;
      UConfig( "app", "env", "" ) )

   //	Claves ajenas de la misma seccion no se tocan
   HixTU_Check( hCtx, UConfig( "app", "default_page", "" ) == cOtherPrev, ;
      "NewOverrides: claves ajenas intactas", cOtherPrev,           ;
      UConfig( "app", "default_page", "" ) )

   //	Restore
   HIX_ConfigMerge( { "app" => { "env" => cPrev } } )
RETURN

// -------------------------------------------------------
// Merge multi-seccion con varias claves por seccion.
// -------------------------------------------------------
STATIC PROCEDURE _TestMergeMulti( hCtx )
   LOCAL cEnvPrev  := UConfig( "app",    "env", "" )
   LOCAL nPortPrev := UConfig( "server", "port", 0 )

   HIX_ConfigMerge( { ;
      "app"    => { "env" => "prod" }, ;
      "server" => { "port" => 9999 } ;
   } )

   HixTU_Check( hCtx, UConfig( "app", "env", "" ) == "prod",        ;
      "NewOverrides: multi-seccion app.env=prod", "prod",           ;
      UConfig( "app", "env", "" ) )

   HixTU_Check( hCtx, UConfig( "server", "port", 0 ) == 9999,       ;
      "NewOverrides: multi-seccion server.port=9999", "9999",       ;
      hb_NToS( UConfig( "server", "port", 0 ) ) )

   //	Restore
   HIX_ConfigMerge( { ;
      "app"    => { "env"  => cEnvPrev  }, ;
      "server" => { "port" => nPortPrev } ;
   } )
RETURN

// -------------------------------------------------------
// Seccion inexistente se crea en el hash global.
// -------------------------------------------------------
STATIC PROCEDURE _TestNewSection( hCtx )
   LOCAL hCfg

   HIX_ConfigMerge( { "custom_test" => { "flag" => .T., "id" => 42 } } )

   hCfg := HIX_GetConfig()
   HixTU_Check( hCtx, hb_HHasKey( hCfg, "custom_test" ),            ;
      "NewOverrides: seccion nueva creada", ".T.",                  ;
      hb_CStr( hb_HHasKey( hCfg, "custom_test" ) ) )

   HixTU_Check( hCtx, UConfig( "custom_test", "flag", .F. ) == .T., ;
      "NewOverrides: clave nueva flag=.T.", ".T.",                  ;
      hb_CStr( UConfig( "custom_test", "flag", .F. ) ) )

   HixTU_Check( hCtx, UConfig( "custom_test", "id", 0 ) == 42,      ;
      "NewOverrides: clave nueva id=42", "42",                      ;
      hb_NToS( UConfig( "custom_test", "id", 0 ) ) )

   //	Cleanup: eliminar seccion sintetica
   hb_HDel( hCfg, "custom_test" )
   HIX_SetConfig( hCfg )
RETURN

// -------------------------------------------------------
// Overrides vacio / NIL / no-hash son no-op.
// -------------------------------------------------------
STATIC PROCEDURE _TestEmptyIgnored( hCtx )
   LOCAL cEnvPrev := UConfig( "app", "env", "" )

   HIX_ConfigMerge( NIL )
   HixTU_Check( hCtx, UConfig( "app", "env", "" ) == cEnvPrev,      ;
      "NewOverrides: NIL ignorado", cEnvPrev,                       ;
      UConfig( "app", "env", "" ) )

   HIX_ConfigMerge( {=>} )
   HixTU_Check( hCtx, UConfig( "app", "env", "" ) == cEnvPrev,      ;
      "NewOverrides: hash vacio ignorado", cEnvPrev,                ;
      UConfig( "app", "env", "" ) )

   HIX_ConfigMerge( "not-a-hash" )
   HixTU_Check( hCtx, UConfig( "app", "env", "" ) == cEnvPrev,      ;
      "NewOverrides: no-hash ignorado", cEnvPrev,                   ;
      UConfig( "app", "env", "" ) )
RETURN

// -------------------------------------------------------
// New(hOverrides) en sub-server ignora el hash (lOwnsGlobals=.F.).
// El proceso ya tiene 1 server dueno, asi que este New() es sub.
// -------------------------------------------------------
STATIC PROCEDURE _TestSubServerIgnores( hCtx )
   LOCAL cPrev := UConfig( "app", "env", "" )
   LOCAL oSrv

   oSrv := THixServer():New( { "app" => { "env" => "should_not_apply" } } )

   HixTU_Check( hCtx, oSrv != NIL,                                  ;
      "NewOverrides: New(hOverrides) sub-server -> Self", "!=NIL",  ;
      iif( oSrv == NIL, "NIL", "obj" ) )

   HixTU_Check( hCtx, ! oSrv:lOwnsGlobals,                          ;
      "NewOverrides: sub-server lOwnsGlobals=.F.", ".F.",           ;
      hb_CStr( oSrv:lOwnsGlobals ) )

   HixTU_Check( hCtx, UConfig( "app", "env", "" ) == cPrev,         ;
      "NewOverrides: sub-server no muta config", cPrev,             ;
      UConfig( "app", "env", "" ) )
RETURN
