/*-----------------------------------------------------------
  File ......: {{ENTITY_LOWER}}.prg
  Author.....: {{AUTHOR}}
  Created....: {{DATE}}
  Version....: 1.0.0
  Description: {{ENTITY}} model -- DBF wrapper (no index, linear
               scan). Uses pure function-form Harbour so it
               compiles under the dispatcher's dynamic loader.
 -----------------------------------------------------------*/

STATIC scDbf   := "data/{{ENTITY_PLURAL_LOWER}}"
STATIC scAlias := "{{ENTITY_PLURAL_LOWER}}"

FUNCTION {{ENTITY}}ModelList()
   LOCAL aRows := {}
   _Open()
   dbSelectArea( scAlias )
   dbGoTop()
   DO WHILE ! Eof()
      IF ! Deleted()
         AAdd( aRows, _RowHash() )
      ENDIF
      dbSkip()
   ENDDO
   _Close()
RETURN aRows

FUNCTION {{ENTITY}}ModelGet( nId )
   LOCAL hRow := NIL
   _Open()
   IF _SeekId( nId )
      hRow := _RowHash()
   ENDIF
   _Close()
RETURN hRow

FUNCTION {{ENTITY}}ModelCreate( cName, cNotes )
   LOCAL nId := 0
   _Open()
   dbSelectArea( scAlias )
   dbGoTop()
   DO WHILE ! Eof()
      IF ! Deleted() .AND. FieldGet( FieldPos( "id" ) ) > nId
         nId := FieldGet( FieldPos( "id" ) )
      ENDIF
      dbSkip()
   ENDDO
   nId++
   dbAppend()
   FieldPut( FieldPos( "id" ),    nId )
   FieldPut( FieldPos( "name" ),  cName )
   FieldPut( FieldPos( "notes" ), cNotes )
   FieldPut( FieldPos( "cts" ),   hb_DateTime() )
   dbUnlock()
   dbCommit()
   _Close()
RETURN nId

FUNCTION {{ENTITY}}ModelUpdate( nId, hFields )
   LOCAL lOk := .F.
   LOCAL cKey
   _Open()
   IF _SeekId( nId )
      IF dbRLock()
         FOR EACH cKey IN hb_HKeys( hFields )
            FieldPut( FieldPos( cKey ), hFields[ cKey ] )
         NEXT
         dbRUnlock()
         dbCommit()
         lOk := .T.
      ENDIF
   ENDIF
   _Close()
RETURN lOk

FUNCTION {{ENTITY}}ModelDelete( nId )
   LOCAL lOk := .F.
   _Open()
   IF _SeekId( nId )
      IF dbRLock()
         dbDelete()
         dbRUnlock()
         dbCommit()
         lOk := .T.
      ENDIF
   ENDIF
   _Close()
RETURN lOk

STATIC FUNCTION _Open()
   IF Select( scAlias ) == 0
      IF ! hb_FileExists( scDbf + ".dbf" )
         IF ! hb_DirExists( "data" )
            hb_DirCreate( "data" )
         ENDIF
         dbCreate( scDbf, { ;
            { "ID",    "N", 10, 0 }, ;
            { "NAME",  "C", 100, 0 }, ;
            { "NOTES", "C", 200, 0 }, ;
            { "CTS",   "T",   0, 0 }  ;
         }, "DBFCDX" )
      ENDIF
      dbUseArea( .T., "DBFCDX", scDbf, scAlias, .T. )
   ENDIF
RETURN NIL

STATIC FUNCTION _Close()
   IF Select( scAlias ) > 0
      dbSelectArea( scAlias )
      dbCloseArea()
   ENDIF
RETURN NIL

STATIC FUNCTION _SeekId( nId )
   LOCAL lFound := .F.
   dbSelectArea( scAlias )
   dbGoTop()
   DO WHILE ! Eof()
      IF ! Deleted() .AND. FieldGet( FieldPos( "id" ) ) == nId
         lFound := .T.
         EXIT
      ENDIF
      dbSkip()
   ENDDO
RETURN lFound

STATIC FUNCTION _RowHash()
   LOCAL h := { => }
   LOCAL i
   FOR i := 1 TO FCount()
      hb_HSet( h, Lower( FieldName( i ) ), FieldGet( i ) )
   NEXT
RETURN h
