/*-----------------------------------------------------------
  File ......: hix_zombie.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-06
  Description: Zombie thread registry — tracks timed-out HRB threads for
               monitoring and cleanup.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_DISPATCHER

#INCLUDE "hix_logger.ch"

STATIC s_hZombies := NIL   // hash { nID => aRec }
STATIC s_hMutex   := NIL
STATIC s_nNextID  := 1

// Índices del registro
#DEFINE ZB_PATH      1
#DEFINE ZB_START     2
#DEFINE ZB_TIMEOUT   3
#DEFINE ZB_BORN      4
#DEFINE ZB_DEAD      5
#DEFINE ZB_STATUS    6

// ------------------------------------------------------------
FUNCTION HIX_ZombieInit()

   s_hMutex   := hb_mutexCreate()
   s_hZombies := hb_Hash()
   s_nNextID  := 1

RETURN NIL

// ------------------------------------------------------------
// Añadir zombie → retorna nID para pasarlo al hilo
// ------------------------------------------------------------
FUNCTION HIX_ZombieAdd( cPath, nTimeoutMs, tStart )

   LOCAL nID

   hb_default( @tStart, hb_DateTime() )

   hb_mutexLock( s_hMutex )
   nID := s_nNextID++
   s_hZombies[ nID ] := { ;
      cPath,          ;  // ZB_PATH
      tStart,         ;  // ZB_START
      nTimeoutMs,     ;  // ZB_TIMEOUT
      hb_DateTime(),  ;  // ZB_BORN
      NIL,            ;  // ZB_DEAD
      "ZOMBIE"        ;  // ZB_STATUS
      }
   hb_mutexUnlock( s_hMutex )

   lw( "ZOMBIE #" + hb_NToS( nID ) + ;
      " | " + cPath + ;
      " | timeout: " + hb_NToS( nTimeoutMs ) + "ms" )

RETURN nID

// ------------------------------------------------------------
// El zombie terminó → actualizar su entrada en el hash
// ------------------------------------------------------------
FUNCTION HIX_ZombieDead( nID )

   LOCAL aRec, nElapsed

   IF nID == NIL ; RETURN NIL ; ENDIF

   hb_mutexLock( s_hMutex )

   IF hb_HHasKey( s_hZombies, nID )

      aRec                := s_hZombies[ nID ]
      aRec[ ZB_DEAD   ]   := hb_DateTime()
      aRec[ ZB_STATUS ]   := "DEAD"
      nElapsed := ( aRec[ ZB_DEAD ] - aRec[ ZB_START ] ) * 86400000

   ENDIF

   hb_mutexUnlock( s_hMutex )

   IF aRec != NIL

      lw( "ZOMBIE #" + hb_NToS( nID ) + " MUERTO" + ;
         " | " + aRec[ ZB_PATH ] + ;
         " | total: " + hb_NToS( Int( nElapsed ) ) + "ms" )

   ENDIF

RETURN NIL

// ------------------------------------------------------------
// Contar zombies vivos
// ------------------------------------------------------------
FUNCTION HIX_ZombieCount()

   LOCAL n := 0

   hb_mutexLock( s_hMutex )
   hb_HEval( s_hZombies, {| k, v | iif( v[ ZB_STATUS ] == "ZOMBIE", n++, NIL ) } )
   hb_mutexUnlock( s_hMutex )

RETURN n

// ------------------------------------------------------------
FUNCTION HIX_ZombieOverload( nMax )

   hb_default( @nMax, 10 )

RETURN HIX_ZombieCount() >= nMax

// ------------------------------------------------------------
// Reporte completo para /hix/status
// ------------------------------------------------------------
FUNCTION HIX_ZombieReport()

   LOCAL aReport := {}
   LOCAL nElapsed

   hb_mutexLock( s_hMutex )
   hb_HEval( s_hZombies, {| nID, aRec |
   nElapsed := ( hb_DateTime() - aRec[ ZB_START ] ) * 86400000
   AAdd( aReport, { ;
      "id"         => nID, ;
      "path"       => aRec[ ZB_PATH    ], ;
      "status"     => aRec[ ZB_STATUS  ], ;
      "timeout_ms" => aRec[ ZB_TIMEOUT ], ;
      "start"      => hb_TToS( aRec[ ZB_START ] ), ;
      "born"       => hb_TToS( aRec[ ZB_BORN  ] ), ;
      "dead"       => iif( aRec[ ZB_DEAD ] != NIL, ;
      hb_TToS( aRec[ ZB_DEAD ] ), "alive" ), ;
      "elapsed_ms" => Int( nElapsed ) ;
      } )

RETURN NIL
} )
hb_mutexUnlock( s_hMutex )

RETURN aReport

// ------------------------------------------------------------
// Purgar entradas DEAD antiguas (housekeeping)
// ------------------------------------------------------------
FUNCTION HIX_ZombiePurge( nMaxAgeSecs )

   LOCAL aKeys := {}, i, nPurged := 0
   LOCAL tLimit

   hb_default( @nMaxAgeSecs, 300 )
   tLimit := hb_DateTime() - ( nMaxAgeSecs / 86400 )

   hb_mutexLock( s_hMutex )
   // Recopilar keys a borrar (no modificar el hash mientras se itera)
   hb_HEval( s_hZombies, {| nID, aRec |

   IF aRec[ ZB_STATUS ] == "DEAD" .AND. aRec[ ZB_DEAD ] <= tLimit

      AAdd( aKeys, nID )

   ENDIF

RETURN NIL
} )

FOR i := 1 TO Len( aKeys )

hb_HDel( s_hZombies, aKeys[ i ] )
nPurged++

NEXT

hb_mutexUnlock( s_hMutex )

IF nPurged > 0

ld( "ZombiePurge: " + hb_NToS( nPurged ) + " entradas eliminadas" )

ENDIF

RETURN nPurged
