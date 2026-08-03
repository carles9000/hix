/*-----------------------------------------------------------
  File ......: modeluser.prg
  Author.....: Charly 9000
  Created....: 2026-07-18
  Modified...: 2026-07-21
  Version....: 2.0.0
  Description: In-memory fake user model. No persistence — the
               store is hardcoded below so the example runs with
               zero setup (no DBF, no migrations, no seeding).

               Replace this file with a real backend (DBF, SQL,
               LDAP, external service) keeping the same public
               API and shape:

                 ModelUserAuthenticate( cUsername, cPassword )
                    -> hash { sub, name, scope } | NIL
                 ModelUserFindById( cId )
                    -> full user hash | NIL

               Shape returned by Authenticate matches the JWT
               payload consumed by MyWsBearer / UAuthUser.
  Usage      : hUser := ModelUserAuthenticate( "admin", "admin123" )
 -----------------------------------------------------------*/


// ============================================================
// _UserStore -- single source of truth for the fake backend.
// Passwords are cleartext on purpose: this is a teaching sample,
// not production. A real model would compare hashes.
// ============================================================
STATIC FUNCTION _UserStore()
RETURN { ;
   "admin" => { ;
      "id"    => "1", ;
      "name"  => "Admin Fenix", ;
      "pass"  => "admin123", ;
      "scope" => "me:read customers:read customers:write customers:delete" ;
   }, ;
   "demo"  => { ;
      "id"    => "2", ;
      "name"  => "Demo User", ;
      "pass"  => "demo123", ;
      "scope" => "me:read customers:read" ;
   }, ;
   "guest" => { ;
      "id"    => "3", ;
      "name"  => "Guest User", ;
      "pass"  => "guest123", ;
      "scope" => "customers:read" ;
   } ;
}


// ============================================================
// ModelUserAuthenticate -- verify credentials, return JWT
// payload hash { sub, name, scope } or NIL on failure.
// ============================================================
FUNCTION ModelUserAuthenticate( cUsername, cPassword )

   LOCAL hEntry

   cUsername := Lower( AllTrim( iif( ValType( cUsername ) == "C", cUsername, "" ) ) )
   cPassword := iif( ValType( cPassword ) == "C", cPassword, "" )

   hEntry := hb_HGetDef( _UserStore(), cUsername, NIL )

   IF hEntry == NIL .OR. ! ( hEntry[ "pass" ] == cPassword )
      RETURN NIL
   ENDIF

RETURN { ;
   "sub"   => hEntry[ "id"    ], ;
   "name"  => hEntry[ "name"  ], ;
   "scope" => hEntry[ "scope" ]  ;
}


// ============================================================
// ModelUserFindById -- look up a user by id (for /me endpoint).
// ============================================================
FUNCTION ModelUserFindById( cId )

   LOCAL hStore := _UserStore()
   LOCAL cKey, hEntry

   FOR EACH cKey IN hb_HKeys( hStore )

      hEntry := hStore[ cKey ]

      IF hEntry[ "id" ] == cId
         RETURN { ;
            "id"       => hEntry[ "id"    ], ;
            "username" => cKey, ;
            "name"     => hEntry[ "name"  ], ;
            "scope"    => hEntry[ "scope" ]  ;
         }
      ENDIF

   NEXT

RETURN NIL
