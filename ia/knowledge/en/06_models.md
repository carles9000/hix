# Models

HIX has no ORM. Models are `.prg` files under `www/models/` that wrap DBF/CDX access with Harbour's RDD layer.

## Standard skeleton

    /*-----------------------------------------------------------
      File ......: users.prg
      Description: DBF CRUD for users
    -----------------------------------------------------------*/

    #include "hix_const.ch"

    STATIC scDbf   := "data/users"    // no extension
    STATIC scAlias := "USERS"

    FUNCTION UsersModelList()
       LOCAL aRows := {}
       _Open()
       SELECT ( scAlias )
       DBGOTOP()
       DO WHILE ! Eof()
          AAdd( aRows, _RowHash() )
          DBSKIP()
       ENDDO
       _Close()
    RETURN aRows

    FUNCTION UsersModelGet( nId )
       LOCAL hRow := NIL
       _Open()
       SELECT ( scAlias )
       DBSEEK( nId )
       IF Found()
          hRow := _RowHash()
       ENDIF
       _Close()
    RETURN hRow

    FUNCTION UsersModelCreate( cName, cEmail )
       LOCAL nId := 0
       _Open()
       SELECT ( scAlias )
       DBGOBOTTOM()
       nId := iif( Eof(), 1, USERS->id + 1 )
       DBAPPEND()
       USERS->id    := nId
       USERS->name  := cName
       USERS->email := cEmail
       USERS->cts   := hb_DateTime()
       DBCOMMIT()
       _Close()
    RETURN nId

    FUNCTION UsersModelUpdate( nId, hFields )
       LOCAL lOk := .F.
       _Open()
       SELECT ( scAlias )
       DBSEEK( nId )
       IF Found()
          hb_HEval( hFields, {|k, v| FieldPut( FieldPos(k), v ) } )
          DBCOMMIT()
          lOk := .T.
       ENDIF
       _Close()
    RETURN lOk

    FUNCTION UsersModelDelete( nId )
       LOCAL lOk := .F.
       _Open()
       SELECT ( scAlias )
       DBSEEK( nId )
       IF Found()
          DBDELETE()
          DBCOMMIT()
          lOk := .T.
       ENDIF
       _Close()
    RETURN lOk

    STATIC FUNCTION _Open()
       IF Select( scAlias ) == 0
          USE ( scDbf ) VIA "DBFCDX" NEW ALIAS ( scAlias ) SHARED
          SET INDEX TO ( scDbf )
       ENDIF
    RETURN NIL

    STATIC FUNCTION _Close()
       IF Select( scAlias ) > 0
          ( scAlias )->( DBCLOSEAREA() )
       ENDIF
    RETURN NIL

    STATIC FUNCTION _RowHash()
       LOCAL h := { => }
       LOCAL i
       FOR i := 1 TO FCount()
          hb_HSet( h, Lower( FieldName( i ) ), FieldGet( i ) )
       NEXT
    RETURN h

## Rules

- DBFCDX driver is preloaded (`REQUEST DBFCDX` in the HIX lib); no need to add `REQUEST` in your app.
- Open with `SHARED` — multiple workers hit the same file.
- Every write ends with `DBCOMMIT()`.
- Prefer opening/closing per operation (simple) unless you have profiling data showing a bottleneck.
- Alias must be UPPER (`USERS`, not `Users`).

## Locking

`DBRLOCK()` for row locks, `FLOCK()` for file locks. Always paired with `DBRUNLOCK()` / `DBUNLOCK()`. Wrap in `TRY/CATCH` to guarantee release.

    _Open()
    SELECT ( scAlias )
    IF DBRLOCK()
       TRY
          // ... modify ...
          DBCOMMIT()
       CATCH oError
          // ... log ...
       END
       DBRUNLOCK()
    ENDIF
    _Close()

## Indexes

Create with `INDEX ON expr TAG name TO cdxFile`. Use `ORDSCOPE()` for range filters, `DBSEEK(x, .T.)` for soft seek.

Structural indexes (same basename as DBF, `.cdx`) auto-open with the DBF.

## Migration / schema

No migration system. Create tables with a one-off script:

    DBCREATE( "data/users", { ;
       { "ID",    "N", 10, 0 }, ;
       { "NAME",  "C", 100, 0 }, ;
       { "EMAIL", "C", 200, 0 }, ;
       { "CTS",   "T",  0, 0 }  ;
    }, "DBFCDX" )

    USE "data/users" VIA "DBFCDX"
    INDEX ON id TO "data/users" TAG id
    CLOSE
