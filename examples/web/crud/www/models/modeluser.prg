// --------------------------------------------------------------------------------
// This is a fake object of a data model. You can obviously replace this model with 
// another one you prefer.
// --------------------------------------------------------------------------------

FUNCTION ModelUser( cUser, cPass )

   LOCAL hStore, hEntry

   hStore := {                                                                          ;
      "demo"   => { "id" => "1", "name" => "Admin Demo",   "pass" => "1234",          ;
                    "roles" => { "sales"     => "",                                    ;
                                 "purchases" => "",                                    ;
                                 "customers" => "search;show;edit;delete;recall;create" }    ;
                  },;
      "carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234",          ;
                    "roles" => { "customers" => "search;show",                        ;
                                 "purchases" => "" }                               ;
                  },;
      "maria"  => { "id" => "3", "name" => "Maria de la O", "pass" => "1234",          ;
                    "roles" => { "customers" => "search;show;edit",                   ;
                                 "sales"   => "" }                               ;
                  };
   }

   hEntry := hb_HGetDef( hStore, Lower( cUser ), NIL )

   IF hEntry == NIL .OR. ! ( hEntry["pass"] == cPass )
      RETURN NIL
   ENDIF

RETURN { "id"    => hEntry["id"],    ;
         "name"  => hEntry["name"],  ;
         "roles" => hEntry["roles"]  }
