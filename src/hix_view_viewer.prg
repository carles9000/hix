/*-----------------------------------------------------------
  File ......: hix_view_viewer.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: HIX_View_Viewer — compiles and runs view templates via HRB
               dynamic loading.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#INCLUDE "hbclass.ch"
#INCLUDE "common.ch"
#INCLUDE "error.ch"
#INCLUDE "directry.ch"

#INCLUDE "hix_const.ch"
#INCLUDE "hix_hrb.ch"


CLASS Hix_View_Viewer

   DATA oParser
   DATA oTranspile
   DATA uRawCode   // Script original (limpio)
   DATA cFile
   DATA cFileName
   DATA lIsCode
   DATA cType
   DATA lTranspile     INIT .T.
   DATA lRawCode     INIT .F.
   DATA lCache      INIT .T.
   DATA aLines
   DATA aParams   // Parameters send to Render
   DATA oHrb

   DATA cPathView
   DATA cPathReal
   DATA cPathCached
   DATA cPathCachedFile
   DATA cFileCached
   DATA cFileNoExt
   DATA cPathViewRelative

   DATA lOutput     INIT .T.
   DATA lDebug      INIT .T.
   DATA lStrictMode    INIT .T.
   DATA llSaveTranspiled   INIT .F.

   DATA lError      INIT .F.
   DATA cHtmlView
   DATA cHtmlError

   DATA lThrow    // Nombres de variables de @args y @global

   METHOD New( cFile, cCode )    CONSTRUCTOR

   METHOD InitPaths()

   METHOD Render()

   METHOD SetPathView( cPathView )  INLINE ::cPathView  := cPathView

   METHOD SetCache( lCache )    INLINE ::lCache := if( valtype( lCache ) == 'L', lCache, .T. )
   METHOD SetPrg( cFilePrg )
   METHOD SetHrb( cFileHrb )

   METHOD SavePrg( cFile )
   METHOD SaveHrb( cFile )
   METHOD PrgToArray()
   METHOD IsPureHtml( cCode )

   METHOD Post_Compile()
   METHOD ExecuteHrb()

// METHOD Execute()

   METHOD _t( ... )       // Trace


   METHOD ShowError( oError )
   METHOD _ThrowParserErrors()

ENDCLASS

// ----------------------------------------------------------------//

METHOD New( cFile, cCode ) CLASS Hix_View_Viewer

   hb_Default( @cFile, '' )
   hb_Default( @cCode, '' )

// Init vars...

   ::cFile   := cFile
   ::cFileName  := ''
   ::uRawCode   := ''
   ::lRawCode   := .F.
   ::cType    := ''

   ::lCache   := .T.
   ::cPathView  := ''
   ::cPathReal  := ''
// ::cPathCached := hb_dirbase() + '.cached\views'
   ::cPathCached := hb_dirbase() + '.cached' + hb_ps() + 'views'
   ::cPathCachedFile := ''
   ::cFileCached := ''
   ::cFileNoExt := ''

   ::lOutput  := .T.
   ::lDebug  := .T.
   ::lStrictMode := .F.

   ::lError  := .F.
   ::cHtmlView  := ''
   ::cHtmlError := ''

   ::llSaveTranspiled := .F.

RETURN Self

// ----------------------------------------------------------------//

METHOD Render( ... ) CLASS Hix_View_Viewer

// LOCAL aResult

   LOCAL cHtml    := ''
   LOCAL cFileName, cFileCached, cPathReal, cPathCachedFile, nPos, aInfoFile, aInfoCached, oError
   LOCAL lUpdated   := .F.
   LOCAL nLapsus   := hb_milliseconds()

   ::_t( '-------------------------------' )
   ::_t( 'View:Render() -----------------' )
   ::_t( '-------------------------------' )

   ::lError   := .F.
   ::cHtmlView  := ''
   ::cHtmlError := ''


   ::oParser := HIX_Parser():New()


// Si es solo codigo html, no hace falta cargar todo el proceso para
// obtener el mismo resultado

   IF ::cType == 'prg' .AND. file( ::cFile )

      ::_t( 'Validating code style...' )

      IF ::IsPureHtml()

         ::_t( 'Render proc. 0' )
         ::_t( 'File es pure html' )
         RETU hb_memoread( ::cFile )

      ENDIF


      ::_t( 'Code is hixstyle, great !' )

   ENDIF

// --------------------------------------------------------


   ::aLines  := {}
   ::aParams  := hb_aParams()

// --------------------------------------------------------
// Podem carregar fitxer (prg/hrb) o codi directament
// El cache el farem sobre un ficher prg, que es compilarà
// i es caxejarà.
// El codi inyectat directament NO es caxejarà
// --------------------------------------------------------


   IF ::lIscode

      ::_t( 'Render proc. 1' )

      ::_t( 'Render direct code: ' + ::cType )

      DO CASE

         CASE ::cType == 'hrb'

            cHtml := ::ExecuteHrb()

         CASE ::cType == 'prg'

// ::oParser := HIX_Parser():New()
            ::oParser:lDebug       := ::lDebug
            ::oParser:lStrictMode  := ::lStrictMode    // ver TODOS los errores sin lanzar excepcion

            ::aLines := ::oParser:Parse( ::uRawCode )


         IF ! Empty( ::oParser:aErrors )

            ::_ThrowParserErrors()

            ENDIF


// Iniciaremos Transpile ...

            ::oTranspile    := Hix_Transpile():New( ::aLines, ::aParams, ::oParser:aBlocks )
            ::oTranspile:lDebug  := ::oParser:lDebug
            ::oTranspile:aRawSource := ::oParser:aSourceLines
            ::oHrb      := ::oTranspile:Run()

// ? 'Transpilat, pendent de compilar!!!'

            ::Post_Compile()

// RUN !!!

            cHtml := ::ExecuteHrb()


      ENDCASE

      ::_t( 'Time process: ' + ltrim( str( hb_milliseconds() - nLapsus ) ) + 'ms.' )

      RETU cHtml

   ENDIF


// --------------------------------------------------------

   IF ! ::lRawCode

      HIX_DoErrorView( NIL, 9001, "Error no rawcode", NIL, NIL, "hix_view_viewer" )
      RETU NIL

   ENDIF

// if ::lCache



// Init Paths --------------
   ::InitPaths()
// -------------------------

// Init Logic

   ::_t( 'Config Debug: ' + if( ::lDebug, 'Yes', 'No' ) )
   ::_t( 'Config Cache: ' + if( ::lCache, 'Yes', 'No' ) )

   IF ::lCache // .and. ! ::lIscode

      ::_t( 'Render proc. 2' )

      IF file( ::cFileCached )

         ::_t( 'Render proc. 2a' )

         ::_t( 'File is cached: '  + ::cFileCached )

         IF file( ::cFile )

            aInfoFile   := directory( ::cFile )[ 1 ]
            aInfoCached  := directory( ::cFileCached )[ 1 ]

            lUpdated   := dtos( aInfoCached[ F_DATE ] ) +  aInfoCached[ F_TIME ] < dtos( aInfoFile[ F_DATE ] ) +  aInfoFile[ F_TIME ]

            IF lUpdated

               ::_t( 'Original file is updated. Re-parsing... ' + ::cFile )

// ::oParser := HIX_Parser():New()
               ::oParser:lDebug       := ::lDebug
               ::oParser:lStrictMode  := ::lStrictMode    // ver TODOS los errores sin lanzar excepcion

     /*
     if ::IsPureHtml()
      ::_t( 'File es pure html' )
      retu hb_memoread( ::cFile )
     endif
     */


               ::aLines := ::oParser:Parse( ::uRawCode )


// No se si entra aqui. Si hi ha errors salta el error del Parse!!!

               IF ! Empty( ::oParser:aErrors )

                  ::_ThrowParserErrors()

               ENDIF

// ---------------------------------------------------------------

               ::_t( 'Tranpiling...' )

               ::oTranspile    := Hix_Transpile():New( ::aLines, ::aParams, ::oParser:aBlocks )
               ::oTranspile:lDebug  := ::oParser:lDebug
               ::oHrb      := ::oTranspile:Run()

               ::Post_Compile()

            ELSE

               ::_t( 'File cached is ready' )

               ::cType  := 'hrb'
               ::oHrb   := hb_memoread( ::cFileCached )

            ENDIF

         ELSE

            ::_t( 'Original file is updated. Re-parsing...' )

            ::cType  := 'hrb'
            ::oHrb   := hb_memoread( ::cFileCached )

         ENDIF

// RUN !!!

         cHtml := ::ExecuteHrb()

      ELSE

         ::_t( 'Render proc. 2b' )
         ::_t( 'Process: ' + if( ::lIscode, 'Code', 'File' ) )

// if file( ::cFile )

         IF ::lRawCode

            ::_t( 'Parsing...' )

// Iniciem  Parser...

// ::oParser := HIX_Parser():New()
            ::oParser:lDebug       := ::lDebug
            ::oParser:lStrictMode  := ::lStrictMode    // ver TODOS los errores sin lanzar excepcion

            ::aLines := ::oParser:Parse( ::uRawCode )

            IF ! Empty( ::oParser:aErrors )

               ::_ThrowParserErrors()

            ENDIF

// Iniciaremos Transpile ...

            ::_t( 'Transpiling...' )

            ::oTranspile    := Hix_Transpile():New( ::aLines, ::aParams, ::oParser:aBlocks )
            ::oTranspile:lDebug  := ::oParser:lDebug
            ::oTranspile:aRawSource := ::oParser:aSourceLines
            ::oHrb      := ::oTranspile:Run()

            ::Post_Compile()

// RUN !!!

            ::_t( 'Execute...' )

            cHtml := ::ExecuteHrb()

         ELSE
            ::_t( 'Render proc. Error 222' )

         ENDIF

      ENDIF

   ELSE

      ::_t( 'Render proc. 3' )
      ::_t( 'Is Code: ' + if( ::lIsCode, 'Yes', 'No'  ) )
      ::_t( 'File type: ' + ::cType )

      IF ::cType == 'prg'

         IF ::lRawCode

            ::_t( 'Render proc. 3a' )

// ? 'Existeix !'

            ::_t( 'Parsing...' )

// ::oParser := HIX_Parser():New()
            ::oParser:lDebug      := ::lDebug
            ::oParser:lStrictMode := ::lStrictMode    // ver TODOS los errores sin lanzar excepcion


            ::aLines := ::oParser:Parse( ::uRawCode )

            IF ! Empty( ::oParser:aErrors )

               ::_ThrowParserErrors()

            ENDIF

            ::_t( 'Tranpiling...' )

            ::oTranspile    := Hix_Transpile():New( ::aLines, ::aParams, ::oParser:aBlocks )
            ::oTranspile:lDebug  := ::oParser:lDebug
            ::oTranspile:aRawSource := ::oParser:aSourceLines
            ::oHrb      := ::oTranspile:Run()

            ::Post_Compile()

// RUN !!!

            cHtml := ::ExecuteHrb()

         ELSE

            ::_t( 'Render proc. Error 223' )

         ENDIF

      ELSE

         ::_t( 'Render proc. 3b' )

         ::_t( 'Execute: ' + ::cFile )

         cHtml := ::ExecuteHrb()

      ENDIF

   ENDIF

   ::_t( 'Time process: ' + ltrim( str( hb_milliseconds() - nLapsus ) ) + 'ms.' )

 /*
 if ::lOutput
  ?? cHtml
 endif
 */

   ::_t( 'Render proc. 4' )


   RETU cHtml

// ----------------------------------------------------------------//

METHOD SetPrg( cFilePrg, cCode ) CLASS Hix_View_Viewer

   LOCAL oError, cFile

   hb_default( @cFilePrg, '' )
   hb_default( @cCode, '' )

   ::_t( '-------------------------------' )
   ::_t( 'View:SetPrg() -----------------' )
   ::_t( '-------------------------------' )

   ::cType   := ''
// ::cFilePrg  := ''
   ::cFile     := ''
   ::uRawCode   := ''
   ::lTranspile  := .T.
   ::lRawCode   := .F.

   ::_t( 'SetPrg: ' + cFilePrg )

   IF empty( cFilePrg ) .AND. empty( cCode )

      HIX_DoErrorView( NIL, 9011, "SetPrg: No file or code", NIL, NIL, "hix_view_viewer" )
      RETU NIL

   ENDIF

   IF ! empty( cFilePrg )

      ::lIscode := .F.

      cFile :=  UOsFileName( ::cPathView + cFilePrg )

      ::_t( 'File view: ' + cFile )

      IF !file( cFile )

         ::_t( 'Original file not exist: ' + cFile )

// Si no existeix file, hem de xequejar abans  que potser existeix
// el fitxer catxejat

// ::cFile    := cFilePrg
         ::cFile    := cFile
         ::InitPaths()

         IF file( ::cFileCached )

            ::_t( 'File catched was found: ' + ::cFileCached )

            ::oHrb   := hb_memoread( ::cFileCached )
            ::cType  := 'hrb'
            ::lIsCode  := .T.

            RETU NIL

         ELSE

  /*
    oError := ErrorView()
    oError:subsystem   :=  "HIX Style"
    oError:description  :=  "Set prg"
    oError:operation   :=  "File not found: " + cFilePrg

    Throw( oError )
  */
            HIX_DoErrorView( NIL, 9010, "File not found: " + cFilePrg, NIL, NIL, "hix_view_viewer" )


            RETU NIL

         ENDIF

      ELSE

         ::_t( 'Found: yes' )


         ::uRawCode    := hb_MemoRead( cFile )

         ::cFile    := cFile // cFilePrg
         ::cFileName      := hb_FNameNameExt( ::cFile  )

      ENDIF

   ELSE

      ::lIscode := .T.
      ::uRawCode := cCode

   ENDIF

// ::_t( 'Is fileType: ' + if( ::lIscode, 'Code', 'File' ) )

   ::cType   := 'prg'
   ::lRawCode   := .T.
   ::lTranspile  := .T.

   RETU NIL

// ----------------------------------------------------------------//

METHOD SetHrb( cFileHrb, cCode  ) CLASS Hix_View_Viewer

   LOCAL oError

   hb_default( @cFileHrb, '' )
   hb_default( @cCode, '' )

   ::_t( '-------------------------------' )
   ::_t( 'View:SetHrb() -----------------' )
   ::_t( '-------------------------------' )

   ::cType   := ''
// ::cFileHrb   := ''
   ::cFile     := ''
   ::uRawCode   := ''
   ::lTranspile  := .T.
   ::lRawCode   := .F.
   ::lIscode  := ''

   ::_t( 'SetHrb: ' + cFileHrb )
   ::_t( 'Is file: ' + if( empty( cFileHrb ), 'si', 'no' ) )
   ::_t( 'Is code: ' + if( empty( cCode ), 'si', 'no' ) )

   IF empty( cFileHrb ) .AND. empty( cCode )

      HIX_DoErrorView( NIL, 9011, "SetHrb: No file or code", NIL, NIL, "hix_view_viewer" )
      RETU NIL

   ENDIF

   IF ! empty( cFileHrb )

      ::lIscode := .F.

      IF !file( cFileHrb )

         HIX_DoErrorView( NIL, 9010, "SetHrb: File not found: " + cFileHrb, NIL, NIL, "hix_view_viewer" )
         RETU NIL
      ELSE

         ::_t( 'Found hrb !' )

// ::uRawCode    := hb_MemoRead( cFileHrb )
         ::oHrb     := hb_MemoRead( cFileHrb )

         ::cFile    := cFileHrb
         ::cFileName      := hb_FNameNameExt( ::cFile  )

      ENDIF


   ELSE

      ::lIscode := .T.
      ::oHrb   := cCode

   ENDIF

   ::_t( 'Type: ' + if( ::lIscode, 'Code', 'File' ) )

   ::cType   := 'hrb'
   ::lRawCode   := .T.
   ::lTranspile  := .F.

   RETU NIL

// ----------------------------------------------------------------//

METHOD SavePrg( cFile ) CLASS Hix_View_Viewer

   IF !Empty( ::oTranspile ) .AND. !Empty( ::oTranspile:cTranspiledPRG )

      hb_MemoWrit( cFile, ::oTranspile:cTranspiledPRG )
      RETURN .T.

   ENDIF

RETURN .F.

// ----------------------------------------------------------------//

METHOD SaveHrb( cFile ) CLASS Hix_View_Viewer

   IF !Empty( ::oHrb )

      hb_MemoWrit( cFile, ::oHrb )
      RETURN .T.

   ENDIF

RETURN .F.

// ----------------------------------------------------------------//

METHOD PrgToArray() CLASS Hix_View_Viewer

   LOCAL aCode := {}

   IF file( ::cFile ) .AND. ::cType == 'prg'

// aCode := hb_atokens( hb_memoread( ::cFile ), Chr(10) )
      aCode := hb_atokens( hb_memoread( ::cFile ), Chr( 13 ) + Chr( 10 ) )

   ENDIF

   RETU aCode
// ----------------------------------------------------------------//

METHOD Post_Compile() CLASS Hix_View_Viewer

   LOCAL cFile

   ::_t( 'Post compiling' )

   IF empty( ::oHrb )

      RETU NIL

   ENDIF

// TEMPORAL. SOLS PER TRACE --------------------------------

   IF !empty( ::cFileNoExt ) .AND. ::llSaveTranspiled

      cFile := ::cPathCachedFile + '__' + ::cFileNoExt + '.prg'

      ::_t( 'Writed file transpiled: ' + cFile )

      hb_memowrit( cFile, ::oTranspile:cTranspiledPRG ) // Per veure, log

   ENDIF

// ---------------------------------------------------------

   IF ::lCache

      hb_memowrit( ::cFileCached, ::oHrb )
      ::_t( 'Transpiled was cached to ' + ::cFileCached )

   ENDIF

   RETU NIL

// ----------------------------------------------------------------//

METHOD ExecuteHrb() CLASS Hix_View_Viewer

   LOCAL pHandle
   LOCAL cHtml      := ''
   LOCAL nLine      := 0
   LOCAL oLastError := NIL
   LOCAL oPar, oSubError, pFunc, cCode, aCode, oErrorView, oError

// Stack levels capturados en el WITH handler (antes de que el stack se deshaga)
   LOCAL cPN0, cPN1, cPN2, cPN3
   LOCAL nPL0, nPL1, nPL2, nPL3

   IF empty( ::oHrb )

      RETU cHtml

   ENDIF

// Capturamos hb_procLine(N) ANTES de que el stack del HRB se deshaga:
// el Error object runtime no expone PROCLINE como DATA en esta version.

   BEGIN SEQUENCE WITH {| e |

      nPL0 := ProcLine( 0 ) ; cPN0 := ProcName( 0 )
      nPL1 := ProcLine( 1 ) ; cPN1 := ProcName( 1 )
      nPL2 := ProcLine( 2 ) ; cPN2 := ProcName( 2 )
      nPL3 := ProcLine( 3 ) ; cPN3 := ProcName( 3 )
      nLine := iif( nPL1 > 0, nPL1, iif( nPL2 > 0, nPL2, iif( nPL3 > 0, nPL3, 0 ) ) )
      Break( e )
      RETURN NIL
      }

      ::_t( 'Loading hrb..' )


// pHandle := hb_hrbLoad( HB_HRB_BIND_LAZY, ::oHrb )
      pHandle := hb_hrbLoad( HB_HRB_BIND_LOCAL, ::oHrb )

      oPar := Hix_View_Params():New( ::aParams )

      ::_t( 'Execute hrb..' )

      cHtml := hb_HrBDo( pHandle, oPar )

      ::_t( 'Executed Ok!' )

   RECOVER USING oError

      IF valtype( oError:filename ) == 'U' .OR. empty( oError:filename )

         oError:filename := HB_FNameNameExt( ::cFileName )

      ENDIF

// Error ya envuelto (cargo hash) → propagar sin re-envolver

      IF ValType( oError ) == "O" .AND. ValType( oError:cargo ) == "H"

         ::ShowError( oError )
         oLastError := oError
      ELSE

         oErrorView := HIX_ErrorView( oError, 9004, oError:description, NIL, NIL, "hix_view_viewer" )

// nLine fue capturado en el WITH handler: nivel de stack del HRB
// Es el indice en aLineMap (no la linea del template original).

         TRY

            IF nLine > 0

               pFunc := hb_hrbGetFunSym( pHandle, "__trace" )
               cCode := hb_base64Decode( hb_ExecFromArray( pFunc ) )
               aCode := hb_jsondecode( cCode )

               IF Len( aCode ) > 0 .AND. nLine <= Len( aCode )

                  oErrorView:cargo[ "line"       ] := aCode[ nLine ][ 1 ]  // n linea visible (template)
                  oErrorView:cargo[ "line_code"  ] := aCode[ nLine ][ 2 ]
                  oErrorView:cargo[ "line_index" ] := nLine               // indice en aLineMap
                  oErrorView:cargo[ "aCode"      ] := aCode

               ENDIF

            ENDIF

         CATCH oSubError

         END

         oLastError := oErrorView

      ENDIF

   ALWAYS

      IF !Empty( pHandle )

         TRY

            hb_hrbUnload( pHandle )
         CATCH oSubError

         END

         pHandle := nil

      ENDIF

   END

   IF ValType( oLastError ) == "O"

      HIX_Throw( oLastError )

   ENDIF

   RETU cHtml

// ----------------------------------------------------------------//

METHOD _t( ... ) CLASS Hix_View_Viewer

   IF ::lDebug

      _t( ... )

   ENDIF

   RETU NIL

// ----------------------------------------------------------------//

METHOD IsPureHtml( cCode ) CLASS Hix_View_Viewer

   LOCAL cUpperCode
   LOCAL oParser, cDir

   IF hb_IsNil( cCode )

      cCode := ::uRawCode

   ENDIF



   IF Empty( cCode )

      RETURN .T.

   ENDIF

// Verificamos presencia de macros


   IF hb_at( "{{", cCode ) > 0 .OR. hb_at( "{!!", cCode ) > 0

      RETURN .F.

   ENDIF

// Verificamos presencia de directivas (solo si hay al menos un '@' para optimizar)


   IF hb_at( "@", cCode ) > 0

// De momento no chequeamos si es un directiva, aunque esto implica que si
// en el fichero hay algun main (test@gmail.com) dira que NO es html puro.
// Valoraremos...

      cUpperCode := Upper( cCode )

      FOR EACH cDir IN ::oParser:aDirectives

         IF hb_at( cDir, cUpperCode ) > 0

            RETURN .F. // Hemos encontrado una directiva de Harbour

         ENDIF

      NEXT

   ENDIF

RETURN .T.

// ----------------------------------------------------------------//

/*
HB_FNameDir   Extract Folder name from file specification
HB_FNameName  Extract File name from file specification
HB_FNameNameExt Extract File name and extention from file specification
HB_FNameExt   Extract File extention from full file specification
HB_FNameExtSet  Returns changed file extension from file specification
HB_FNameMerge  Composes a full file specification from individual components
HB_FNameSplit  Extract folder, file, extension from full file specification

File : c:\ut-hix.dev\web\loader\script1.prg
HB_FNameName  script1
HB_FNameNameExt script1.prg
HB_FNameExt  .prg
HB_FNameExtSet  c:\ut-hix.dev\web\loader\script1
HB_FNameMerge  c:\ut-hix.dev\web\loader\script1.prg
*/

METHOD InitPaths() CLASS Hix_View_Viewer

   LOCAL cConfiguredViewPath

   ::_t( 'Init Paths & Vars' )
   ::_t( '-----------------' )

   ::cFileNoExt        := HB_FNameName( ::cFile )
   ::cPathReal         := hb_dirbase()

// Guardar el view root configurado por SetPathView() antes de sobreescribir
   cConfiguredViewPath := ::cPathView

   ::cPathView         := HB_FNameDir( ::cFile )

// cPathViewRelative = subdirectorio del archivo relativo al view root configurado
   ::cPathViewRelative := ''

   IF ! Empty( cConfiguredViewPath )

      IF Upper( Left( ::cPathView, Len( cConfiguredViewPath ) ) ) == Upper( cConfiguredViewPath )

         ::cPathViewRelative := SubStr( ::cPathView, Len( cConfiguredViewPath ) + 1 )

      ENDIF

   ELSE

      IF Upper( Left( ::cPathView, Len( ::cPathReal ) ) ) == Upper( ::cPathReal )

         ::cPathViewRelative := SubStr( ::cPathView, Len( ::cPathReal ) + 1 )

      ENDIF

   ENDIF

   IF !empty( ::cPathViewRelative )

      ::cPathCachedFile  := ::cPathCached + hb_ps() + ::cPathViewRelative
   ELSE
      ::cPathCachedFile  := ::cPathCached + hb_ps()

   ENDIF

   ::cFileCached   := ::cPathCachedFile + ::cFileNoExt + '.hrb'


   ::_t( 'Root: ' + HIX_GetRoot() )
   ::_t( 'Root Absolute: ' + HIX_GetRootAbsolute() )
   ::_t( 'cFile: ' + ::cFile )
   ::_t( 'cFileName: ' + ::cFileName )
   ::_t( 'cFileNoExt: ' + ::cFileNoExt )
   ::_t( 'cPathViewRelative: ' + ::cPathViewRelative )
   ::_t( 'cPathCached: ' + ::cPathCached )
   ::_t( 'cPathReal: ' + ::cPathReal )
   ::_t( 'cPathView: ' + ::cPathView )
   ::_t( 'cPathCachedFile for view: ' + ::cPathCachedFile )
   ::_t( 'cFileCached for view: ' + ::cFileCached )
   ::_t( '--------------------------------' )

// Check directories

   IF ! IsDirectory( ::cPathCached )   // Default cached folder

      hb_DirBuild( ::cPathCached )
      ::_t( 'Init cached folder ' + ::cPathCached  )

   ENDIF

   IF ! IsDirectory( hb_StrShrink( ::cPathCachedFile, 1 ) ) // strip trailing sep: GetFileAttributes fails with it

      hb_DirBuild( hb_StrShrink( ::cPathCachedFile, 1 ) )
      ::_t( 'Init cached file folder ' + ::cPathCachedFile  )

   ENDIF

   RETU NIL

// ----------------------------------------------------------------//

METHOD ShowError( oError ) CLASS Hix_View_Viewer

   // Enriquecer aCode si el error de vista no lo tiene aun

   IF ValType( oError ) == "O" .AND. ValType( oError:cargo ) == "H"

      IF ValType( oError:cargo[ "aCode" ] ) != "A" .OR. Empty( oError:cargo[ "aCode" ] )

         IF ! Empty( ::cFile ) .AND. File( ::cFile )

            oError:filename          := HB_FNameNameExt( ::cFile )
            oError:cargo[ "aCode" ]  := ::PrgToArray()

         ENDIF

      ENDIF

   ENDIF

RETURN oError

// ----------------------------------------------------------------//

METHOD _ThrowParserErrors() CLASS Hix_View_Viewer

   LOCAL oErr

   oErr := HIX_ErrorView( NIL, 9001, ;
      ::oParser:aErrors[ 1 ][ 3 ], ;
      ::oParser:aErrors[ 1 ][ 1 ], ;
      ::oParser:aErrors[ 1 ][ 2 ] )

   IF ! Empty( ::cFile ) .AND. File( ::cFile ) .AND. ::cType == "prg"

      oErr:filename           := HB_FNameNameExt( ::cFile )
      oErr:cargo[ "aCode" ]   := ::PrgToArray()

   ENDIF

   ::lError := .T.
   break oErr

RETURN NIL

// ----------------------------------------------------------------//

FUNCTION HIX_DbgError( o )

   LOCAL cLog := ''
   LOCAL n

   IF valtype( o ) != 'O' .OR. ( o:classname != 'ERRORVIEW' .AND. o:classname != 'ERROR' )

      _t( 'Error DbgError', o )
      RETU NIL

   ENDIF

   cLog += '-------------------' + HIX_CRLF
   cLog += '--- Trace Error ---' + HIX_CRLF
   cLog += '-------------------' + HIX_CRLF
   cLog += 'Hora: ' + time() + HIX_CRLF
   cLog += 'Classname: ' + o:classname + HIX_CRLF

   IF o:classname == 'ERRORVIEW'

      cLog += 'System: ' + hb_CStr( o:system ) + HIX_CRLF
      cLog += 'Process: ' + hb_CStr( o:process ) + HIX_CRLF
      cLog += 'Line: ' + hb_CStr( o:line ) + HIX_CRLF
      cLog += 'Line Code: ' + hb_CStr( o:line_code ) + HIX_CRLF
      cLog += 'Code: ' + hb_CStr( o:aCode ) + HIX_CRLF

   ENDIF

   cLog += 'Subsystem: ' + hb_CStr( o:subsystem ) + HIX_CRLF
   cLog += 'Subcode: ' + hb_CStr( o:subcode ) + HIX_CRLF


   cLog += 'Description: ' + o:description + HIX_CRLF
   cLog += 'Operation: ' + hb_CStr( o:operation ) + HIX_CRLF
   cLog += 'Procline: ' + hb_CStr( o:procline ) + HIX_CRLF
   cLog += 'Filename: ' + hb_CStr( o:filename ) + HIX_CRLF
   cLog += 'Cargo: ' + hb_CStr( o:cargo ) + HIX_CRLF

   IF valtype( o:args ) == 'A'

      cLog += 'Args: ' +  HIX_CRLF

      cLog += '       [' + ltrim( str( 1 ) ) + '] => ' + hb_Cstr( o:args[ 1 ] ) + HIX_CRLF

      FOR n := 2 TO len( o:args )

         cLog += '       [' + ltrim( str( n ) ) + '] => ' + hb_Cstr( o:args[ n ] ) + HIX_CRLF

      NEXT

   ENDIF

   cLog += 'Stack: '

   cLog +=        '[' + ltrim( str( 1 ) ) + '] => ' + ProcName( 1 ) + ':' + ltrim( str( Procline( 1 ) ) ) + HIX_CRLF

   FOR n := 2 TO 4

      cLog += '       [' + ltrim( str( n ) ) + '] => ' + ProcName( n ) + ':' + ltrim( str( Procline( n ) ) ) + HIX_CRLF

   NEXT

   cLog += '-------------------' + HIX_CRLF

   _t( cLog )

   RETU NIL

// ------------------------------------------------------------------- //
