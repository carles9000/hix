/*-----------------------------------------------------------
  File ......: hix_test_firewall.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — Firewall (HIX_Firewall*)
 -----------------------------------------------------------*/

FUNCTION HIX_TestFirewall_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _FwIPAddr2Num(      hCtx )
   _FwParseFilter(     hCtx )
   _FwBlacklist(       hCtx )
   _FwWhitelist(       hCtx )
   _FwDenySubRange(    hCtx )
   _FwCommaSeparator(  hCtx )
RETURN hCtx

STATIC PROCEDURE _FwIPAddr2Num( hCtx )
   HixTU_Check( hCtx, HIX_IPAddr2Num( "0.0.0.0" )[1]        == 0,          "FW: 0.0.0.0=0",          "0",          hb_NToS( HIX_IPAddr2Num( "0.0.0.0" )[1] ) )
   HixTU_Check( hCtx, HIX_IPAddr2Num( "255.255.255.255" )[1] == 4294967295, "FW: 255.255.255.255=max", "4294967295", hb_NToS( HIX_IPAddr2Num( "255.255.255.255" )[1] ) )
   HixTU_Check( hCtx, HIX_IPAddr2Num( "192.168.1.1" )[1]  > 0, "FW: 192.168.1.1 > 0", ">0", hb_NToS( HIX_IPAddr2Num( "192.168.1.1" )[1] ) )
RETURN

STATIC PROCEDURE _FwParseFilter( hCtx )
   LOCAL aR
   HIX_ParseFirewallFilter( "192.168.0.0/24", @aR )
   HixTU_Check( hCtx, ValType( aR ) == "A" .AND. Len( aR ) == 1, "FW: Parse CIDR -> array[1]", "A[1]", iif( ValType(aR)=="A", "A"+hb_NToS(Len(aR)), ValType(aR) ) )
   HIX_ParseFirewallFilter( "10.0.0.5", @aR )
   HixTU_Check( hCtx, ValType( aR ) == "A" .AND. Len( aR ) == 1, "FW: Parse IP sola -> array[1]", "A[1]", iif( ValType(aR)=="A", "A"+hb_NToS(Len(aR)), ValType(aR) ) )
   HIX_ParseFirewallFilter( "10.0.0.1-10.0.0.99", @aR )
   HixTU_Check( hCtx, ValType( aR ) == "A" .AND. Len( aR ) == 1, "FW: Parse rango -> array[1]", "A[1]", iif( ValType(aR)=="A", "A"+hb_NToS(Len(aR)), ValType(aR) ) )
RETURN

STATIC PROCEDURE _FwBlacklist( hCtx )
   HIX_FirewallSetup( "", "blacklist" )
   HIX_FirewallClear()
   HIX_FirewallSetup( "10.0.0.0/8", "blacklist" )
   HixTU_Check( hCtx, ! HIX_FirewallCheck( "10.1.2.3" ),  "FW: blacklist bloquea 10.1.2.3",   ".F.", ".T." )
   HixTU_Check( hCtx, HIX_FirewallCheck( "192.168.1.1" ), "FW: blacklist permite 192.168.1.1", ".T.", ".F." )
   HIX_FirewallClear()
RETURN

STATIC PROCEDURE _FwWhitelist( hCtx )
   HIX_FirewallSetup( "", "whitelist" )
   HIX_FirewallClear()
   HIX_FirewallSetup( "127.0.0.1", "whitelist" )
   HixTU_Check( hCtx, HIX_FirewallCheck( "127.0.0.1" ),  "FW: whitelist permite 127.0.0.1",  ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_FirewallCheck( "8.8.8.8" ),  "FW: whitelist bloquea 8.8.8.8",    ".F.", ".T." )
   HIX_FirewallClear()
RETURN

STATIC PROCEDURE _FwDenySubRange( hCtx )
   HIX_FirewallSetup( "", "blacklist" )
   HIX_FirewallClear()
   HIX_FirewallSetup( "172.16.0.0/12", "blacklist" )
   HixTU_Check( hCtx, ! HIX_FirewallCheck( "172.20.5.5" ), "FW: blacklist sub-rango 172.20.5.5 bloqueado", ".F.", ".T." )
   HixTU_Check( hCtx, HIX_FirewallCheck( "172.15.255.255" ), "FW: 172.15.x fuera del rango permitido", ".T.", ".F." )
   HIX_FirewallClear()
RETURN

// Verifica que el parser acepta comas como separador (equivalente a espacios).
STATIC PROCEDURE _FwCommaSeparator( hCtx )
   LOCAL aR

   // Parseo: comas producen el mismo array que espacios
   HIX_ParseFirewallFilter( "1.2.3.4, 5.6.7.8, 9.10.11.12", @aR )
   HixTU_Check( hCtx, ValType( aR ) == "A" .AND. Len( aR ) == 3, ;
                "FW: Parse 3 IPs con coma -> array[3]", "A[3]", ;
                iif( ValType(aR)=="A", "A"+hb_NToS(Len(aR)), ValType(aR) ) )

   // Mezcla de comas y espacios
   HIX_ParseFirewallFilter( "1.2.3.4,5.6.7.8 9.10.11.12", @aR )
   HixTU_Check( hCtx, ValType( aR ) == "A" .AND. Len( aR ) == 3, ;
                "FW: Parse coma+espacio mezclados -> array[3]", "A[3]", ;
                iif( ValType(aR)=="A", "A"+hb_NToS(Len(aR)), ValType(aR) ) )

   // Blacklist con comas: se bloquean las tres
   HIX_FirewallClear()
   HIX_FirewallSetup( "1.2.3.4, 5.6.7.8, 9.10.11.12", "blacklist" )
   HixTU_Check( hCtx, ! HIX_FirewallCheck( "1.2.3.4" ),      "FW: coma-blacklist bloquea 1.2.3.4",      ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_FirewallCheck( "5.6.7.8" ),      "FW: coma-blacklist bloquea 5.6.7.8",      ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_FirewallCheck( "9.10.11.12" ),   "FW: coma-blacklist bloquea 9.10.11.12",   ".F.", ".T." )
   HixTU_Check( hCtx, HIX_FirewallCheck( "8.8.8.8" ),        "FW: coma-blacklist permite 8.8.8.8",      ".T.", ".F." )
   HIX_FirewallClear()

   // Whitelist con comas + CIDR + exclusion + rango
   HIX_FirewallSetup( "127.0.0.1, 192.168.1.0/24, 10.0.0.1-10.0.0.50, !10.0.0.5", "whitelist" )
   HixTU_Check( hCtx, HIX_FirewallCheck( "127.0.0.1" ),      "FW: coma-whitelist permite 127.0.0.1",    ".T.", ".F." )
   HixTU_Check( hCtx, HIX_FirewallCheck( "192.168.1.99" ),   "FW: coma-whitelist permite 192.168.1.99", ".T.", ".F." )
   HixTU_Check( hCtx, HIX_FirewallCheck( "10.0.0.10" ),      "FW: coma-whitelist permite rango 10.0.0.10", ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_FirewallCheck( "10.0.0.5" ),     "FW: coma-whitelist excluye 10.0.0.5",     ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_FirewallCheck( "8.8.8.8" ),      "FW: coma-whitelist bloquea 8.8.8.8",      ".F.", ".T." )
   HIX_FirewallClear()
RETURN
