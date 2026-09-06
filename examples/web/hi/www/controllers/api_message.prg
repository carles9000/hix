/*-----------------------------------------------------------
  File ......: api_message.prg
  Author.....: Charly 9000
  Created....: 2026-08-20
  Modified...: 2026-08-20
  Version....: 2.0.0
  Description: Stores one message posted from the /message screen
               into data/messages.dbf, together with the client IP
               and the current timestamp. Creates the table on the
               fly when it is missing, so the module is self
               contained: no boot code needed.
  Usage      : POST /api/message   { "alias": "...", "message": "..." }
  Notes      : ID is a DBFCDX autoincrement field ("+"), filled by the
               RDD inside dbAppend() and readable right after it.
               The one-message-per-minute limit is NOT handled here --
               route web.json wires MyMsgGuard (CSRF + throttle) in
               front of this controller, so a second call inside the
               window never reaches this code.
               The work area is closed by the server when
               app.auto_close_dbf is on (hix.json).
 -----------------------------------------------------------*/

#define MSG_TABLE   'data/messages.dbf'

FUNCTION Main()

   LOCAL oVal, cAlias, cMessage, nId

   oVal := UValidateOrFail( { 'alias'   => 'required|string|max:10' ,  ;
                              'message' => 'required|string|max:150' }, ;
                            { 'alias'   => 'trim',                     ;
                              'message' => 'trim'                    } )

   IF oVal == NIL       // already answered 422 with the field errors
      RETURN NIL
   ENDIF

   cAlias   := oVal:Get( 'alias'   )
   cMessage := oVal:Get( 'message' )

   IF ! _EnsureTable()
      RETURN USendJson( { 'ok' => .F., 'error' => 'Cannot create messages table' }, 500 )
   ENDIF

   USE ( MSG_TABLE ) SHARED NEW

   IF NetErr() .OR. Empty( Alias() )
      RETURN USendJson( { 'ok' => .F., 'error' => 'Cannot open messages table' }, 500 )
   ENDIF

   dbAppend()

   IF NetErr()
      RETURN USendJson( { 'ok' => .F., 'error' => 'Table busy, please retry' }, 503 )
   ENDIF

   field->alias   := cAlias
   field->message := cMessage
   field->ip      := UIP()
   field->stamp   := hb_DateTime()

   nId := field->id      // autoincrement, already assigned by dbAppend()

   dbCommit()

RETURN USendJson( { 'ok'   => .T.,   ;
                    'id'   => nId,   ;
                    'time' => Time() } )

/*-----------------------------------------------------------
  Creates data/messages.dbf when it is not there. Returns .T. if
  the table is ready to be opened.

  ID is type "+" (autoincrement, 4 bytes) and STAMP type "T"
  (timestamp, 8 bytes): both turn the file into a VFP flavoured
  DBF, which DBFCDX handles natively.
 -----------------------------------------------------------*/

STATIC FUNCTION _EnsureTable()

   LOCAL oError

   IF hb_FileExists( MSG_TABLE )
      RETURN .T.
   ENDIF

   TRY

      dbCreate( MSG_TABLE, { { 'ID'     , '+',   4, 0 },   ;
                             { 'ALIAS'  , 'C',  10, 0 },   ;
                             { 'MESSAGE', 'C', 150, 0 },   ;
                             { 'IP'     , 'C',  45, 0 },   ;
                             { 'STAMP'  , 'T',   8, 0 } }, ;
                'DBFCDX' )

   CATCH oError

      RETURN .F.

   END

RETURN hb_FileExists( MSG_TABLE )
