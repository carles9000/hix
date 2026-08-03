/*-----------------------------------------------------------
  File ......: apphelpers.prg
  Author.....: Charly 9000
  Created....: 2026-07-18
  Modified...: 2026-07-18
  Version....: 1.0.0
  Description: Uniform API response helpers. All controllers
               must go through USendApi / USendApiError to
               keep the { data | error, meta } contract stable.

               meta always contains:
                 req_id  : mirrored X-Request-Id or generated
                 took_ms : elapsed since URequest():nT0 if set
  Usage      : USendApi( { "id" => 42 } )
               USendApi( aList, 201 )
               USendApiError( "AUTH_INVALID", "Bad token", 401 )
 -----------------------------------------------------------*/


// ============================================================
// USendApi — success envelope { data, meta }.
// xData: any value (H, A, C, N, L). Wrapped as-is under "data".
// ============================================================
FUNCTION USendApi( xData, nStatus, hExtraHeaders )

   LOCAL hOut, cReqId

   hb_default( @nStatus, 200 )

   cReqId := _AppReqId()

   hOut := { ;
      "data" => xData, ;
      "meta" => { ;
         "req_id"  => cReqId, ;
         "took_ms" => _AppElapsed() ;
      } ;
   }

   USetHeader( "X-Request-Id",     cReqId )
   USetHeader( "Content-Type",     "application/json; charset=utf-8" )

   IF ValType( hExtraHeaders ) == "H"
      _AppEmitExtraHeaders( hExtraHeaders )
   ENDIF

   USendJson( hOut, nStatus )

RETURN NIL


// ============================================================
// USendApiError — error envelope { error, meta }.
// cCode    : stable SCREAMING_SNAKE_CASE, part of contract.
// cMessage : human hint, not part of contract.
// nStatus  : HTTP status (400/401/403/404/409/415/422/429/500).
// hExtra   : optional { hint, fields } merged into error.
// ============================================================
FUNCTION USendApiError( cCode, cMessage, nStatus, hExtra )

   LOCAL hError, hOut, cReqId

   hb_default( @cCode,    "INTERNAL_ERROR" )
   hb_default( @cMessage, "An error occurred" )
   hb_default( @nStatus,  500 )

   cReqId := _AppReqId()

   hError := { ;
      "code"    => cCode, ;
      "message" => cMessage ;
   }

   IF ValType( hExtra ) == "H"
      IF hb_HHasKey( hExtra, "hint"   ) ; hError[ "hint"   ] := hExtra[ "hint"   ] ; ENDIF
      IF hb_HHasKey( hExtra, "fields" ) ; hError[ "fields" ] := hExtra[ "fields" ] ; ENDIF
   ENDIF

   hOut := { ;
      "error" => hError, ;
      "meta"  => { ;
         "req_id"  => cReqId, ;
         "took_ms" => _AppElapsed() ;
      } ;
   }

   USetHeader( "X-Request-Id", cReqId )
   USendJson( hOut, nStatus )

RETURN NIL



// ============================================================
// UWho — payload of the currently authenticated JWT (or NIL).
// Populated by MyWsBearer middleware in oReq:hData["user"].
// ============================================================
FUNCTION UWho()

   LOCAL o := URequest()

   IF o == NIL
      RETURN NIL
   ENDIF

   IF ! hb_HHasKey( o:hData, "user" )
      RETURN NIL
   ENDIF

RETURN o:hData[ "user" ]


// UHasScope is provided by hix_server.lib (reads JWT claim
// "scope" — space-separated OAuth2-style tokens). Do not
// redefine it here.

// -------------------------------------------------------------- //
// Private helpers
// -------------------------------------------------------------- //


STATIC FUNCTION _AppReqId()

   LOCAL cReqId, o

   cReqId := UHeader( "X-Request-Id", "" )

   IF Empty( cReqId ) .OR. Len( cReqId ) > 64 .OR. ! _AppValidReqId( cReqId )
      cReqId := _AppNewReqId()
   ENDIF

   // Cache on request so both success/error paths return the same id.
   o := URequest()
   IF o != NIL
      o:hData[ "_req_id" ] := cReqId
   ENDIF

RETURN cReqId


STATIC FUNCTION _AppValidReqId( cId )

   LOCAL nI, c

   FOR nI := 1 TO Len( cId )
      c := SubStr( cId, nI, 1 )
      IF !( IsAlpha( c ) .OR. IsDigit( c ) .OR. c == "-" .OR. c == "_" )
         RETURN .F.
      ENDIF
   NEXT

RETURN .T.


STATIC FUNCTION _AppNewReqId()

   LOCAL cRaw := hb_MD5( hb_TToS( hb_DateTime() ) + hb_NToS( hb_RandomInt( 1, 999999999 ) ) )

RETURN Left( cRaw, 24 )


STATIC FUNCTION _AppElapsed()

   LOCAL o := URequest()

   IF o == NIL .OR. ! hb_HHasKey( o:hData, "_t0" )
      RETURN 0
   ENDIF

RETURN Int( hb_MilliSeconds() - o:hData[ "_t0" ] )


STATIC PROCEDURE _AppEmitExtraHeaders( hHeaders )

   LOCAL cKey

   FOR EACH cKey IN hb_HKeys( hHeaders )
      USetHeader( cKey, hHeaders[ cKey ] )
   NEXT

RETURN
