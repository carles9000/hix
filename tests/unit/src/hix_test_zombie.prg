/*-----------------------------------------------------------
  File ......: hix_test_zombie.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Modified...: 2026-06-08
  Description: Integrated test — Zombie (HIX_Zombie*)
 -----------------------------------------------------------*/

FUNCTION HIX_TestZombie_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _ZombieBasics(   hCtx )
   _ZombieOverload( hCtx )
   _ZombieReport(   hCtx )
   _ZombiePurge(    hCtx )
RETURN hCtx

STATIC PROCEDURE _ZombieBasics( hCtx )
   LOCAL nId1, nId2
   HIX_ZombieInit()
   HixTU_Check( hCtx, HIX_ZombieCount() == 0, "Zombie: Count tras Init = 0", "0", hb_NToS( HIX_ZombieCount() ) )
   nId1 := HIX_ZombieAdd( "/req/1001", 5000 )
   HixTU_Check( hCtx, HIX_ZombieCount() == 1, "Zombie: Count tras Add 1 = 1", "1", hb_NToS( HIX_ZombieCount() ) )
   HixTU_Check( hCtx, nId1 > 0, "Zombie: ID > 0", "> 0", hb_NToS( nId1 ) )
   nId2 := HIX_ZombieAdd( "/req/1002", 5000 )
   HixTU_Check( hCtx, HIX_ZombieCount() == 2, "Zombie: Count tras Add 2 = 2", "2", hb_NToS( HIX_ZombieCount() ) )
   HixTU_Check( hCtx, nId2 > nId1, "Zombie: IDs son incrementales", "> " + hb_NToS( nId1 ), hb_NToS( nId2 ) )
   HIX_ZombieDead( nId1 )
   HixTU_Check( hCtx, HIX_ZombieCount() == 1, "Zombie: Count tras Dead 1 = 1", "1", hb_NToS( HIX_ZombieCount() ) )
   HIX_ZombieDead( nId2 )
   HixTU_Check( hCtx, HIX_ZombieCount() == 0, "Zombie: Count tras Dead 2 = 0", "0", hb_NToS( HIX_ZombieCount() ) )
   HIX_ZombieDead( NIL )
   HixTU_Check( hCtx, .T., "Zombie: Dead NIL no crash", "OK", "OK" )
RETURN

STATIC PROCEDURE _ZombieOverload( hCtx )
   LOCAL i
   HIX_ZombieInit()
   HixTU_Check( hCtx, ! HIX_ZombieOverload( 1 ), "Zombie: Overload(1) con 0 = .F.", ".F.", ".T." )
   FOR i := 1 TO 3
      HIX_ZombieAdd( "/req/" + hb_NToS( i ), 5000 )
   NEXT
   HixTU_Check( hCtx, HIX_ZombieCount() == 3,     "Zombie: 3 vivos",             "3",   hb_NToS( HIX_ZombieCount() ) )
   HixTU_Check( hCtx,   HIX_ZombieOverload( 3 ),  "Zombie: Overload(3) con 3 = .T.", ".T.", ".F." )
   HixTU_Check( hCtx,   HIX_ZombieOverload( 1 ),  "Zombie: Overload(1) con 3 = .T.", ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_ZombieOverload( 4 ),  "Zombie: Overload(4) con 3 = .F.", ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_ZombieOverload( 10 ), "Zombie: Overload(10) con 3 = .F.", ".F.", ".T." )
RETURN

STATIC PROCEDURE _ZombieReport( hCtx )
   LOCAL nId, aRep, hRec
   HIX_ZombieInit()
   nId := HIX_ZombieAdd( "/app/report.prg", 8000 )
   aRep := HIX_ZombieReport()
   HixTU_Check( hCtx, Len( aRep ) == 1, "Zombie: Report 1 entrada", "1", hb_NToS( Len( aRep ) ) )
   hRec := aRep[1]
   HixTU_Check( hCtx, hb_HHasKey( hRec, "id"         ), "Zombie: Report campo 'id'",         "si", "no" )
   HixTU_Check( hCtx, hb_HHasKey( hRec, "path"       ), "Zombie: Report campo 'path'",       "si", "no" )
   HixTU_Check( hCtx, hb_HHasKey( hRec, "status"     ), "Zombie: Report campo 'status'",     "si", "no" )
   HixTU_Check( hCtx, hb_HHasKey( hRec, "timeout_ms" ), "Zombie: Report campo 'timeout_ms'", "si", "no" )
   HixTU_Check( hCtx, hb_HHasKey( hRec, "elapsed_ms" ), "Zombie: Report campo 'elapsed_ms'", "si", "no" )
   HixTU_Check( hCtx, hb_HHasKey( hRec, "born"       ), "Zombie: Report campo 'born'",       "si", "no" )
   HixTU_Check( hCtx, hb_HHasKey( hRec, "dead"       ), "Zombie: Report campo 'dead'",       "si", "no" )
   HixTU_Check( hCtx, hRec["path"]       == "/app/report.prg", "Zombie: Report path correcto",     "/app/report.prg", hRec["path"] )
   HixTU_Check( hCtx, hRec["status"]     == "ZOMBIE",          "Zombie: Report status = ZOMBIE",    "ZOMBIE",          hRec["status"] )
   HixTU_Check( hCtx, hRec["timeout_ms"] == 8000,              "Zombie: Report timeout_ms = 8000",  "8000",            hb_NToS( hRec["timeout_ms"] ) )
   HixTU_Check( hCtx, hRec["elapsed_ms"] >= 0,                 "Zombie: Report elapsed_ms >= 0",    ">= 0",            hb_NToS( hRec["elapsed_ms"] ) )
   HixTU_Check( hCtx, hRec["dead"] == "alive",                 "Zombie: Report dead = 'alive'",     "alive",           hRec["dead"] )
   HIX_ZombieDead( nId )
   aRep := HIX_ZombieReport()
   HixTU_Check( hCtx, aRep[1]["status"] == "DEAD",  "Zombie: Report tras Dead status = DEAD", "DEAD", aRep[1]["status"] )
   HixTU_Check( hCtx, aRep[1]["dead"]   != "alive", "Zombie: Report tras Dead dead = ts",     "ts",   aRep[1]["dead"] )
RETURN

STATIC PROCEDURE _ZombiePurge( hCtx )
   LOCAL nId, nPurged
   HIX_ZombieInit()
   nPurged := HIX_ZombiePurge()
   HixTU_Check( hCtx, nPurged == 0, "Zombie: Purge tabla vacia = 0", "0", hb_NToS( nPurged ) )
   nId := HIX_ZombieAdd( "/app/purge.prg", 1000 )
   HIX_ZombieDead( nId )
   nPurged := HIX_ZombiePurge( 300 )
   HixTU_Check( hCtx, nPurged == 0, "Zombie: Purge DEAD reciente (maxAge=300) = 0", "0", hb_NToS( nPurged ) )
   HIX_ZombieInit()
   nId := HIX_ZombieAdd( "/app/purge2.prg", 1000 )
   HIX_ZombieDead( nId )
   nPurged := HIX_ZombiePurge( 0 )
   HixTU_Check( hCtx, nPurged == 1, "Zombie: Purge(0) DEAD inmediato = 1", "1", hb_NToS( nPurged ) )
   HIX_ZombieInit()
   HIX_ZombieAdd( "/app/alive.prg", 5000 )
   nPurged := HIX_ZombiePurge( 0 )
   HixTU_Check( hCtx, nPurged == 0,            "Zombie: Purge no toca vivo",       "0", hb_NToS( nPurged ) )
   HixTU_Check( hCtx, HIX_ZombieCount() == 1,  "Zombie: vivo permanece tras purge", "1", hb_NToS( HIX_ZombieCount() ) )
RETURN
