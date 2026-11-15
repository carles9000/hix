/*-----------------------------------------------------------
  File ......: wdo_sqlite3_pool.prg
  Author.....: Charly 9000
  Created....: 2026-10-05
  Modified...: 2026-10-05
  Version....: 1.0.0
  Description: Bootstrap for SQLite3 standalone connections.
               Not a pool -- SQLite3 serializes concurrent access
               internally and the HIX worker threads share one
               singleton via the WDO_RegisterConn registry. Name
               mirrors wdo_mysql_pool.prg for callsite symmetry.
  Usage      : WDO_InitSqlite3( cFile [, lCreate [, bError]] )
               -- OR, hash variant used by HIX_InitPoolsFromConfig --
               WDO_InitSqlite3Ex( cKey, hParams )
               ...
               WDO_EndSqlite3( cKey )
  Notes      : hParams keys recognized by WDO_InitSqlite3Ex:
                 file           (string, required unless :memory:)
                 create         (bool, default .T.)
                 journal_mode   (string, default "WAL")
                 synchronous    (string, default "NORMAL")
                 foreign_keys   (bool, default .T.)
                 to_utf8        (bool, default .T.)
                 berror         (string: function name)
                 berror_block   (block shortcut, used by positional)
                 table          (default cTable passed to new Stmts)
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'

#define WDO_SQLITE3_KEY   "SQLITE"


//	=======================================================  //
//  Positional convenience wrapper.
//	=======================================================  //

FUNCTION WDO_InitSqlite3( cFile, lCreate, bError )

   LOCAL hParams := { => }

   hb_default( @cFile,   ":memory:" )
   hb_default( @lCreate, .T. )

   hParams[ "file"   ] := cFile
   hParams[ "create" ] := lCreate

   IF bError != NIL
      hParams[ "berror_block" ] := bError
   ENDIF

RETU WDO_InitSqlite3Ex( WDO_SQLITE3_KEY, hParams )


//	=======================================================  //
//  Hash-based API. Consumed by HIX_InitPoolsFromConfig().
//	=======================================================  //

FUNCTION WDO_InitSqlite3Ex( cKey, hParams )

   LOCAL oConn
   LOCAL cFile, cJournal, cSync, cBErrorName
   LOCAL lCreate, lForeignKeys, lToUtf8
   LOCAL bError

   IF Empty( cKey )
      cKey := WDO_SQLITE3_KEY
   ENDIF

   IF ! HB_ISHASH( hParams )
      hParams := { => }
   ENDIF

   cFile        := hb_HGetDef( hParams, "file",         ":memory:" )
   lCreate      := hb_HGetDef( hParams, "create",       .T. )
   cJournal     := hb_HGetDef( hParams, "journal_mode", "WAL" )
   cSync        := hb_HGetDef( hParams, "synchronous",  "NORMAL" )
   lForeignKeys := hb_HGetDef( hParams, "foreign_keys", .T. )
   lToUtf8      := hb_HGetDef( hParams, "to_utf8",      .T. )
   cBErrorName  := hb_HGetDef( hParams, "berror",       "" )

   IF hb_HHasKey( hParams, "berror_block" )
      bError := hParams[ "berror_block" ]
   ELSEIF ! Empty( cBErrorName )
      bError := _WdoResolveBErrorFromName( cBErrorName )
   ENDIF

   //  Resolve a relative "file" against the app's current working directory
   //  so values coming from www/config.json ("www/sqlite3/data/demo.db")
   //  behave the same regardless of how the exe was launched.
   IF ! ( cFile == ":memory:" ) .AND. ! _IsAbsolutePath( cFile )
      cFile := hb_cwd() + cFile
   ENDIF

   //  Make sure the parent directory exists when the DB file lives in a
   //  nested path. SQLite doesn't create directories; a missing one causes
   //  SQLITE_CANTOPEN with no useful hint.
   IF ! ( cFile == ":memory:" )
      _EnsureParentDir( cFile )
   ENDIF

   HIX_Dbg( "[WDO_Sqlite3Pool] InitSqlite3Ex[" + cKey + "]: file=" + cFile + ;
            " create=" + iif( lCreate, "T", "F" ) + ;
            " journal=" + cJournal + " sync=" + cSync + ;
            " fk=" + iif( lForeignKeys, "T", "F" ) )

   oConn := WDO_Sqlite3():New( cFile, lCreate )

   oConn:cJournalMode  := cJournal
   oConn:cSynchronous  := cSync
   oConn:lForeignKeys  := lForeignKeys
   oConn:lToUtf8       := lToUtf8
   oConn:cPoolKey      := Lower( cKey )

   IF bError != NIL
      oConn:bError := bError
   ENDIF

   oConn:Open()

   IF ! oConn:lConnect
      le( _( 'WDO_LOG_SQLITE_INIT_FAIL', cKey, cFile ) )
      HIX_Dbg( "[WDO_Sqlite3Pool] InitSqlite3Ex[" + cKey + "]: FAILED to open " + cFile )
      RETU .F.
   ENDIF

   WDO_RegisterConn( cKey, oConn )

   l( _( 'WDO_LOG_SQLITE_INIT', cKey, cFile ) )
   HIX_Dbg( "[WDO_Sqlite3Pool] InitSqlite3Ex[" + cKey + "]: END OK" )

RETU .T.


//	=======================================================  //
//  Shutdown single conn under a given key.
//	=======================================================  //

FUNCTION WDO_EndSqlite3( cKey )

   hb_default( @cKey, WDO_SQLITE3_KEY )

   HIX_Dbg( "[WDO_Sqlite3Pool] EndSqlite3[" + cKey + "]: BEGIN" )

   WDO_UnregisterConn( cKey )

   HIX_Dbg( "[WDO_Sqlite3Pool] EndSqlite3[" + cKey + "]: END" )

RETU NIL


//	=======================================================  //
//  Convenience accessor (parity with WDO_GetMySql).
//	=======================================================  //

FUNCTION WDO_GetSqlite3( cKey )
   hb_default( @cKey, WDO_SQLITE3_KEY )
RETU WDO_Get( cKey )


//	=======================================================  //
//  Helpers
//	=======================================================  //

STATIC FUNCTION _IsAbsolutePath( cPath )

   LOCAL cCh1, cCh2

   IF Empty( cPath )
      RETU .F.
   ENDIF

   cCh1 := SubStr( cPath, 1, 1 )
   cCh2 := SubStr( cPath, 2, 1 )

   IF "Windows" $ OS()
      //  "C:\foo" or "C:/foo"
      IF Len( cPath ) >= 3 .AND. cCh2 == ":"
         RETU .T.
      ENDIF
   ENDIF

   //  "/foo" or "\foo"
   IF cCh1 == "/" .OR. cCh1 == "\"
      RETU .T.
   ENDIF

RETU .F.


STATIC FUNCTION _EnsureParentDir( cFile )

   LOCAL cDir, nPos

   //  Walk back to the last path separator (either / or \).
   nPos := RAt( "/", cFile )
   IF RAt( "\", cFile ) > nPos
      nPos := RAt( "\", cFile )
   ENDIF

   IF nPos == 0
      RETU NIL
   ENDIF

   cDir := Left( cFile, nPos - 1 )

   IF ! Empty( cDir ) .AND. ! hb_DirExists( cDir )
      hb_DirBuild( cDir )
   ENDIF

RETU NIL
