/*-----------------------------------------------------------
  File ......: hix_flash.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-26
  Description: Flash messages for form validation (per-tab, session-based).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

// ---------------------------------------------------------- //
// HELPER
FUNCTION UFlash( cFormId )
RETURN TFlash():New( cFormId )

#INCLUDE "hbclass.ch"

#DEFINE FLASH_SESSION_KEY  "_flash"

CLASS TFlash

   HIDDEN:
   DATA oSess
   DATA cFormId
   DATA hBag        // copia local del bag en memoria
   DATA lDirty      // indica si hay cambios pendientes de guardar

   EXPORTED:
   METHOD New( cFormId )
   METHOD Destroy()       // destructor automático

   METHOD GetId()
   METHOD Set( cKey, xVal )
   METHOD Get( cKey, xDefault )
   METHOD Has( cKey )
   METHOD Delete( cKey )
   METHOD Clear()
   METHOD Save()          // flush explícito a sesión

ENDCLASS

// ------------------------------------------------------------
// CONSTRUCTOR — carga el bag UNA sola vez
// ------------------------------------------------------------

METHOD New( cFormId ) CLASS TFlash

   LOCAL hFlash

   ::oSess   := USession()
   ::lDirty  := .F.
   ::cFormId := IF( ! Empty( cFormId ), cFormId, ;
      hb_MD5( hb_ntos( Int( hb_TToSec( hb_DateTime() ) ) ) + hb_ntos( hb_Random() ) ) )

   // Carga el bag completo de _flash una sola vez
   hFlash := ::oSess:Get( FLASH_SESSION_KEY )

   IF ValType( hFlash ) != "H"

      hFlash := { => }

   ENDIF

   // Extrae el bag de este formId en memoria local

   IF hb_HHasKey( hFlash, ::cFormId )

      ::hBag := hFlash[ ::cFormId ]
   ELSE
      ::hBag := { => }

   ENDIF

   HB_HCaseMatch( ::hBag, .F. )

RETURN Self

// ------------------------------------------------------------
// PÚBLICOS
// ------------------------------------------------------------

METHOD GetId() CLASS TFlash
RETURN ::cFormId

// Set( key, val ) — acumula sin guardar
// Set( hash )     — merge de todos los pares + auto-Save()
METHOD Set( cKey, xVal ) CLASS TFlash

   IF ValType( cKey ) == "H"

      hb_HMerge( ::hBag, cKey )
      ::lDirty := .T.
      ::Save()
   ELSE
      ::hBag[ cKey ] := xVal
      ::lDirty       := .T.

   ENDIF

RETURN Self

METHOD Get( cKey, xDefault ) CLASS TFlash

   LOCAL xVal

   __defaultNIL( @xDefault, "" )

   IF hb_HHasKey( ::hBag, cKey )

      xVal := ::hBag[ cKey ]
      hb_HDel( ::hBag, cKey )
      ::lDirty := .T.

   ENDIF


   IF Empty( xVal )

      xVal := xDefault

   ENDIF

RETURN xVal

METHOD Has( cKey ) CLASS TFlash


RETURN hb_HHasKey( ::hBag, cKey ) .AND. ! Empty( ::hBag[ cKey ] )

METHOD Delete( cKey ) CLASS TFlash

   IF hb_HHasKey( ::hBag, cKey )

      hb_HDel( ::hBag, cKey )
      ::lDirty := .T.

   ENDIF

RETURN Self

METHOD Clear() CLASS TFlash

   ::hBag   := { => }
   ::lDirty := .T.

RETURN Self

// Flush a sesión — llamar UNA vez al final
METHOD Save() CLASS TFlash

   LOCAL hFlash

   IF ! ::lDirty

      RETURN Self   // nada cambió, no tocamos la sesión

   ENDIF

   hFlash := ::oSess:Get( FLASH_SESSION_KEY )

   IF ValType( hFlash ) != "H"

      hFlash := { => }

   ENDIF

   IF Empty( ::hBag )

      // Bag vacío → eliminar el formId de _flash

      IF hb_HHasKey( hFlash, ::cFormId )

         hb_HDel( hFlash, ::cFormId )

      ENDIF

   ELSE
      hFlash[ ::cFormId ] := ::hBag

   ENDIF

   ::oSess:Set( FLASH_SESSION_KEY, hFlash )
   ::oSess:Save()

   ::lDirty := .F.

RETURN Self

METHOD Destroy() CLASS TFlash

   IF ::lDirty

      ::Save()

   ENDIF

RETURN Self
