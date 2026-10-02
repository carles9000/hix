/*	---------------------------------------------------------
	File.......: WDO.prg
	Description: Base WDO. Conexión a Bases de Datos. 
                Version for HIX
	Author.....: Carles Aubia Floresvi
	Date:......: 26/07/2019
	Updated:...: 25/09/2026
	--------------------------------------------------------- */
#include 'hix_const.ch'
#include 'hbclass.ch'
#include 'error.ch'

#define WDO_VERSION 		'2.0'

STATIC s_hWdoLoaded := {=>}
STATIC s_mtxWdoLoaded

//  Extended info registry — drivers register free-form key/value pairs
//  after a successful Open() (server version, client version, charset…).
//  Server banner iterates this hash in insertion order below "WDO Loaded".
STATIC s_hWdoInfo := {=>}
STATIC s_mtxWdoInfo

//	------------------------------------------------------- //

CLASS WDO

	DATA cError 								INIT ''
	
	CLASSDATA lShowError						INIT .t.
	CLASSDATA lLog								INIT .f.
	DATA bError
	
	METHOD New()		   
	METHOD Version()							INLINE WDO_VERSION
	METHOD VersionName()					INLINE 'WDO ' + WDO_VERSION
	
	METHOD SetError( cError )		
	METHOD GetError()						INLINE ::cError
   
	METHOD View( aRows, aHeaders, cTitle, lShow  )  
	
ENDCLASS

//	------------------------------------------------------- //

METHOD New( cDescription, cOperation ) CLASS WDO
   
   ::bError := nil 

RETU SELF 

//	------------------------------------------------------- //

METHOD SetError( cDescription, cOperation ) CLASS WDO

   LOCAL oErr

   hb_default( @cDescription, '' )
   hb_default( @cOperation,   '' )

   ::cError := cDescription

   oErr             := ErrorNew()
   oErr:subSystem   := 'WDO'
   oErr:subCode     := 500
   oErr:genCode     := EG_ARG
   oErr:severity    := ES_ERROR
   oErr:description := cDescription
   oErr:operation   := cOperation

   IF Valtype( ::bError ) == 'B'
      //  Pass Self as 2nd arg so pool-wide handlers can inspect the
      //  affected connection ({|oErr, oConn| ...}). Older single-arg
      //  handlers ({|oErr| ...}) still work -- Harbour ignores extras.
      RETU Eval( ::bError, oErr, Self )
   ENDIF

   IF ::lShowError
      Eval( ErrorBlock(), oErr )
      Break( oErr )
   ENDIF

RETU ::cError

//	------------------------------------------------------- //

METHOD View( aRows, aHeaders, cTitle ) CLASS WDO

   local n, j, nRows, cType, nFields, hRow, aRow
   local cHtml := '' 

   __defaultNIL( @aHeaders, {} )
   __defaultNIL( @cTitle, '' )   

   if valtype( aRows ) != 'A' .or. ( nRows := len(aRows) ) == 0
      retu ''
   endif    
   
   cType := valtype( aRows[1] )
   
   if cType != 'A' .and. cType != 'H'
      retu ''
   endif 

   
   // HEADERS 
   
      IF cType == 'H' 
      
            hRow     := aRows[1]
            nFields  := len( hRow )
            
         IF empty( aHeaders ) .or. len( aHeaders ) != nFields       
            
            aHeaders := {}
            
            FOR n := 1 to nFields 
               Aadd( aHeaders, HB_HKeyAt( hRow, n ) )
            NEXT 
         
         ENDIF 
         
      ELSE 
      
         aRow     := aRows[1]
         nFields  := len( aRow )   
         
         if len( aHeaders ) != nFields
            aHeaders := {}
         endif 
      
      ENDIF 
   
   
   // ---------------------------------------------
   
      BLOCK TO cHtml 
      <style>
         #wdo_table_title { text-align:center;font-size:18px;font-weight: bold; }
         #wdo_table thead { background-color: #425ecf;color: white;font-weight: bold;}
      </style>   
      ENDTEXT 
      
      cHtml += '<div>'
      
      if !empty( cTitle )
         cHtml += '<div id="wdo_table_title">' + cTitle + '</div>'
      endif 
      
      
      cHtml += '<table id="wdo_table" class="table table-hover ">'
      
      if !empty( aHeaders )
      
         cHtml += '<thead><tr>'
         
         FOR n := 1 TO nFields
         
            cHtml += '<td>' + aHeaders[n] + '</td>'
            
         NEXT
         
         cHtml += '</tr></thead>'   
      
      endif   
   
   
   // DATA...
   
      cHtml += '<tbody>'      
      
      IF cType == 'H' 
      
         FOR n := 1 to nRows 
         
            cHtml += '<tr>'
            
            FOR j := 1 to nFields

               cHtml += '<td>' + hb_CStr( HB_HValueAt( aRows[n], j ) ) + '</td>'
            
            NEXT
            
            cHtml += '</tr>'   
         
         NEXT            
      
      ELSE 
      
         FOR n := 1 to nRows 
         
            cHtml += '<tr>'
            
            FOR j := 1 to nFields

               cHtml += '<td>' + hb_CStr( aRows[n,j] ) + '</td>'
            
            NEXT
            
            cHtml += '</tr>'   
         
         NEXT         
      
      ENDIF 
      
   // ---------------------------------------------      
   
   cHtml += '</tbody>'   
   cHtml += '</table>'   
   cHtml += '</div>'   

RETU cHtml
//	------------------------------------------------------- //

function WDO_Version() ; retu WDO_VERSION

//	------------------------------------------------------- //
//  WDO loaded-drivers registry — driver name registers itself on
//  first successful Open(). Server banner reads this to show
//  "WDO Loaded" line after "RDD Default".
//	------------------------------------------------------- //

INIT PROCEDURE _WdoLoadedInit()
   s_mtxWdoLoaded := hb_mutexCreate()
   s_mtxWdoInfo   := hb_mutexCreate()
RETU

FUNCTION WDO_LoadedRegister( cDriver, cVersion )
   LOCAL cName := iif( Empty( cVersion ), cDriver, cDriver + ' ' + cVersion )
   hb_mutexLock( s_mtxWdoLoaded )
   s_hWdoLoaded[ Upper( cDriver ) ] := cName
   hb_mutexUnlock( s_mtxWdoLoaded )
RETU NIL

FUNCTION WDO_Loaded()
   LOCAL cResult := ""
   LOCAL cKey
   hb_mutexLock( s_mtxWdoLoaded )
   FOR EACH cKey IN hb_HKeys( s_hWdoLoaded )
      cResult += iif( Empty( cResult ), "", ", " ) + s_hWdoLoaded[ cKey ]
   NEXT
   hb_mutexUnlock( s_mtxWdoLoaded )
RETU cResult

//  ------------------------------------------------------- //
//  Extended info registry: free-form label -> value map.
//  WDO_InfoRegister is idempotent (same label overwrites). WDO_InfoList
//  returns a shallow copy so callers can iterate without holding the lock.
//  ------------------------------------------------------- //

FUNCTION WDO_InfoRegister( cLabel, cValue )
   IF Empty( cLabel )
      RETU NIL
   ENDIF
   hb_mutexLock( s_mtxWdoInfo )
   s_hWdoInfo[ cLabel ] := iif( cValue == NIL, "", hb_CStr( cValue ) )
   hb_mutexUnlock( s_mtxWdoInfo )
RETU NIL

FUNCTION WDO_InfoList()
   LOCAL hCopy := {=>}
   LOCAL cKey
   hb_mutexLock( s_mtxWdoInfo )
   FOR EACH cKey IN hb_HKeys( s_hWdoInfo )
      hCopy[ cKey ] := s_hWdoInfo[ cKey ]
   NEXT
   hb_mutexUnlock( s_mtxWdoInfo )
RETU hCopy

//	------------------------------------------------------- //
