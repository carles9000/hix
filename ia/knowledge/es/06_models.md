# Modelos

HIX no tiene ORM. Los modelos son ficheros `.prg` bajo `www/models/` que envuelven el acceso DBF/CDX con la capa RDD de Harbour.

## Esqueleto estándar

    /*-----------------------------------------------------------
      File ......: users.prg
      Description: CRUD DBF para users
    -----------------------------------------------------------*/

    #include "hix_const.ch"

    STATIC scDbf   := "data/users"    // sin extensión
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

## Reglas

- El driver DBFCDX viene precargado (`REQUEST DBFCDX` en la librería HIX); no hace falta añadir `REQUEST` en tu app.
- Abre con `SHARED` — varios workers atacan el mismo fichero.
- Toda escritura termina con `DBCOMMIT()`.
- Prefiere abrir/cerrar por operación (simple) salvo que tengas datos de profiling que muestren un cuello de botella.
- El alias debe ir en MAYÚSCULAS (`USERS`, no `Users`).

## Bloqueos

`DBRLOCK()` para bloqueos de fila, `FLOCK()` para bloqueos de fichero. Siempre emparejados con `DBRUNLOCK()` / `DBUNLOCK()`. Envuelve en `TRY/CATCH` para garantizar el release.

    _Open()
    SELECT ( scAlias )
    IF DBRLOCK()
       TRY
          // ... modificar ...
          DBCOMMIT()
       CATCH oError
          // ... log ...
       END
       DBRUNLOCK()
    ENDIF
    _Close()

## Índices

Crea con `INDEX ON expr TAG name TO cdxFile`. Usa `ORDSCOPE()` para filtros por rango, `DBSEEK(x, .T.)` para soft seek.

Los índices estructurales (mismo basename que el DBF, `.cdx`) se abren automáticamente con el DBF.

## Migración / esquema

No hay sistema de migraciones. Crea las tablas con un script one-off:

    DBCREATE( "data/users", { ;
       { "ID",    "N", 10, 0 }, ;
       { "NAME",  "C", 100, 0 }, ;
       { "EMAIL", "C", 200, 0 }, ;
       { "CTS",   "T",  0, 0 }  ;
    }, "DBFCDX" )

    USE "data/users" VIA "DBFCDX"
    INDEX ON id TO "data/users" TAG id
    CLOSE
