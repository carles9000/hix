/*-----------------------------------------------------------
  File ......: hix_test_ip.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — IP utilities (ValidIP, IsPublicIP, GetClientIP)
 -----------------------------------------------------------*/

// Unique name to avoid conflict with other test files
#include "hbclass.ch"
CLASS TMockReqIP
   DATA cIP          INIT "127.0.0.1"
   DATA hHeaders     INIT {=>}
   DATA lProxied     INIT .F.
   METHOD New( cIP ) INLINE ( ::cIP := hb_defaultValue( cIP, "127.0.0.1" ), Self )
   METHOD Header( cKey, xDef ) INLINE hb_HGetDef( ::hHeaders, Lower( cKey ), hb_defaultValue( xDef, "" ) )
ENDCLASS

FUNCTION HIX_TestIP_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _IPValidIPv4(  hCtx )
   _IPValidIPv6(  hCtx )
   _IPPublicIPv4( hCtx )
   _IPPublicIPv6( hCtx )
   _IPGetClient(  hCtx )
RETURN hCtx

STATIC PROCEDURE _IPValidIPv4( hCtx )
   HixTU_Check( hCtx, HIX_ValidIP( "1.2.3.4"         ), "IP: valid 1.2.3.4",         ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "0.0.0.0"         ), "IP: valid 0.0.0.0",         ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "255.255.255.255"  ), "IP: valid 255.255.255.255", ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "192.168.1.1"      ), "IP: valid 192.168.1.1",     ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "10.0.0.1"         ), "IP: valid 10.0.0.1",        ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_ValidIP( "256.1.1.1"      ), "IP: invalid 256.x",         ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_ValidIP( "1.2.3"          ), "IP: invalid 3 octetos",     ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_ValidIP( "1.2.3.4.5"      ), "IP: invalid 5 octetos",     ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_ValidIP( "abc.def.ghi.jkl"), "IP: invalid letras",        ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_ValidIP( ""               ), "IP: invalid empty",         ".F.", ".T." )
RETURN

STATIC PROCEDURE _IPValidIPv6( hCtx )
   HixTU_Check( hCtx, HIX_ValidIP( "::1"                    ), "IP: valid ::1",                ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "::"                     ), "IP: valid :: unspec",          ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "fe80::1"                ), "IP: valid fe80::1 link-local", ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "2001:db8::1"            ), "IP: valid 2001:db8::1",        ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "::ffff:192.168.1.1"     ), "IP: valid IPv4-mapped",        ".T.", ".F." )
   HixTU_Check( hCtx, HIX_ValidIP( "2800:810:46d:10::1"     ), "IP: valid comprimida",         ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_ValidIP( "gggg::1"              ), "IP: invalid hex gggg::1",      ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_ValidIP( "1:2:3:4:5:6:7:8:9"   ), "IP: invalid 9 grupos",         ".F.", ".T." )
RETURN

STATIC PROCEDURE _IPPublicIPv4( hCtx )
   HixTU_Check( hCtx, HIX_IsPublicIP( "8.8.8.8"        ), "IP: 8.8.8.8 publica",        ".T.", ".F." )
   HixTU_Check( hCtx, HIX_IsPublicIP( "1.1.1.1"        ), "IP: 1.1.1.1 publica",        ".T.", ".F." )
   HixTU_Check( hCtx, HIX_IsPublicIP( "203.0.1.1"      ), "IP: 203.0.1.1 publica",      ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "10.0.0.1"     ), "IP: 10.x privada",           ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "172.16.0.1"   ), "IP: 172.16 privada",         ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "172.31.255.255"), "IP: 172.31 privada",        ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "192.168.1.1"  ), "IP: 192.168 privada",        ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "127.0.0.1"    ), "IP: 127.x loopback",         ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "169.254.1.1"  ), "IP: 169.254 link-local",     ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "100.64.0.1"   ), "IP: 100.64 CGNAT",           ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "100.127.255.1"), "IP: 100.127 CGNAT",          ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "224.0.0.1"    ), "IP: 224.x multicast",        ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "0.0.0.0"      ), "IP: 0.0.0.0 red 0",         ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "198.18.0.1"   ), "IP: 198.18 benchmark",       ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "198.51.100.1" ), "IP: 198.51.100 TEST-NET",    ".F.", ".T." )
RETURN

STATIC PROCEDURE _IPPublicIPv6( hCtx )
   HixTU_Check( hCtx, HIX_IsPublicIP( "2001:db8:1::1"     ), "IP: 2001:db8 global unicast", ".T.", ".F." )
   HixTU_Check( hCtx, HIX_IsPublicIP( "2800:810:46d::1"   ), "IP: 2800: IP publica",        ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "::1"             ), "IP: ::1 loopback",            ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "::"              ), "IP: :: unspecified",          ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "fe80::1"         ), "IP: fe80 link-local",         ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "fc00::1"         ), "IP: fc00 ULA",                ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "fd00::1"         ), "IP: fd00 ULA",                ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "ff02::1"         ), "IP: ff02 multicast",          ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_IsPublicIP( "::ffff:192.168.1.1"), "IP: mapped privada",        ".F.", ".T." )
   HixTU_Check( hCtx, HIX_IsPublicIP( "::ffff:8.8.8.8"   ), "IP: mapped publica",          ".T.", ".F." )
RETURN

STATIC PROCEDURE _IPGetClient( hCtx )
   LOCAL oReq, cIP

   oReq := TMockReqIP():New( "10.0.0.1" )
   oReq:hHeaders[ "cf-connecting-ip" ] := "8.8.8.8"
   oReq:hHeaders[ "x-forwarded-for"  ] := "1.1.1.1"
   cIP := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cIP == "8.8.8.8", "IP: CF-Connecting-IP prioritario", "8.8.8.8", cIP )

   oReq := TMockReqIP():New( "10.0.0.1" )
   oReq:hHeaders[ "x-forwarded-for" ] := "10.0.0.5, 172.16.1.1, 8.8.8.8"
   cIP := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cIP == "8.8.8.8", "IP: XFF primera publica en cadena", "8.8.8.8", cIP )

   oReq := TMockReqIP():New( "10.0.0.1" )
   oReq:hHeaders[ "x-real-ip" ] := "1.2.3.4"
   cIP := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cIP == "1.2.3.4", "IP: X-Real-IP detectado", "1.2.3.4", cIP )

   oReq := TMockReqIP():New( "10.0.0.9" )
   cIP := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cIP == "10.0.0.9", "IP: fallback a oReq:cIP", "10.0.0.9", cIP )

   oReq := TMockReqIP():New( "127.0.0.1" )
   oReq:hHeaders[ "x-forwarded-for" ] := "10.0.0.1, 192.168.1.1"
   oReq:hHeaders[ "x-real-ip"       ] := "5.5.5.5"
   cIP := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cIP == "5.5.5.5", "IP: XFF privadas -> X-Real-IP", "5.5.5.5", cIP )

   oReq := TMockReqIP():New( "127.0.0.1" )
   oReq:hHeaders[ "x-forwarded-for" ] := "  9.9.9.9  ,  10.0.0.1"
   cIP := HIX_GetClientIP( oReq )
   HixTU_Check( hCtx, cIP == "9.9.9.9", "IP: XFF AllTrim espacios", "9.9.9.9", cIP )
RETURN
