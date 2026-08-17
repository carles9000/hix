# Model

HIX non ha un ORM. I model sono file `.prg` sotto `www/models/` che incapsulano l'accesso DBF/CDX con il layer RDD di Harbour.

## Scheletro standard

    /*-----------------------------------------------------------
      File ......: users.prg
      Description: CRUD DBF per users
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

## Regole

- Il driver DBFCDX è precaricato (`REQUEST DBFCDX` nella lib HIX); non serve aggiungere `REQUEST` nella tua app.
- Apri con `SHARED` — più worker accedono allo stesso file.
- Ogni scrittura termina con `DBCOMMIT()`.
- Preferisci apri/chiudi per operazione (semplice) a meno che tu non abbia dati di profiling che mostrino un collo di bottiglia.
- L'alias deve essere UPPER (`USERS`, non `Users`).

## Locking

`DBRLOCK()` per lock di riga, `FLOCK()` per lock di file. Sempre accoppiati con `DBRUNLOCK()` / `DBUNLOCK()`. Wrappali in `TRY/CATCH` per garantire il rilascio.

    _Open()
    SELECT ( scAlias )
    IF DBRLOCK()
       TRY
          // ... modifica ...
          DBCOMMIT()
       CATCH oError
          // ... log ...
       END
       DBRUNLOCK()
    ENDIF
    _Close()

## Indici

Crea con `INDEX ON expr TAG name TO cdxFile`. Usa `ORDSCOPE()` per filtri di range, `DBSEEK(x, .T.)` per il soft seek.

Gli indici strutturali (stesso basename del DBF, `.cdx`) si aprono automaticamente con il DBF.

## Migrazione / schema

Nessun sistema di migrazione. Crea le tabelle con uno script one-off:

    DBCREATE( "data/users", { ;
       { "ID",    "N", 10, 0 }, ;
       { "NAME",  "C", 100, 0 }, ;
       { "EMAIL", "C", 200, 0 }, ;
       { "CTS",   "T",  0, 0 }  ;
    }, "DBFCDX" )

    USE "data/users" VIA "DBFCDX"
    INDEX ON id TO "data/users" TAG id
    CLOSE
