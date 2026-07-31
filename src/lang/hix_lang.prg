STATIC s_hLang := NIL
STATIC s_cLang := ""

FUNCTION HIX_LangSelect( cLang )

   hb_default( @cLang, hb_langSelect() )

   s_cLang := Upper( cLang )

   DO CASE

      CASE s_cLang == "EN" ; s_hLang := LangStrings_EN()
      CASE s_cLang == "ES" ; s_hLang := LangStrings_ES()

      OTHERWISE
         s_hLang := LangStrings_EN()

   ENDCASE

   HB_HCaseMatch( s_hLang, .F. )

RETURN NIL


FUNCTION _( cKey, ... )

   LOCAL cResult
   LOCAL aParams  := hb_AParams()
   LOCAL nParam
   LOCAL xVal

   IF s_hLang == NIL

      HIX_LangSelect( "EN" )

   ENDIF

   IF ! hb_HHasKey( s_hLang, cKey )

      RETURN "[?" + cKey + "?]"

   ENDIF

   cResult := s_hLang[ cKey ]

   FOR nParam := 2 TO Len( aParams )

      xVal    := UStr( aParams[ nParam ] )
      cResult := StrTran( cResult, "{" + hb_ntos( nParam - 1 ) + "}", xVal )

   NEXT

RETURN cResult


FUNCTION HIX_InitLang()    // English is default value

   LOCAL hLang := { => }

   // ---- General messages ----
   hLang[ 'MSG_HELLO'       ] := "Hi guy !"
   hLang[ 'MSG_WELCOME'     ] := "Welcome {1} to the system"
   hLang[ 'MSG_NOT_FOUND'   ] := "Record not found"
   hLang[ 'MSG_SAVE_OK'     ] := "Saved successfully"
   hLang[ 'MSG_CONFIRM_DEL' ] := "Confirm deletion of {1}?"
   hLang[ 'MSG_YES'         ] := "Y"
   hLang[ 'MSG_NO'          ] := "N"
   hLang[ 'MSG_USER_INFO'   ] := "{1} is {2} cm tall and is adult: {3}"
   hLang[ 'MSG_ERROR'       ] := "Error at line {1}: {2}"
   hLang[ 'MSG_PROGRESS'    ] := "Processed {1} of {2} records"

   // ---- Validator messages ----
   hLang[ 'VAL_REQUIRED'      ] := "The field {1} is required"
   hLang[ 'VAL_NOT_DEFINED'   ] := "The field {1} is not defined in the rules"
   hLang[ 'VAL_ISNUMERIC'     ] := "The field {1} must be a number"
   hLang[ 'VAL_INTEGER'       ] := "The field {1} must be an integer"
   hLang[ 'VAL_POSITIVE'      ] := "The field {1} must be a positive number"
   hLang[ 'VAL_MIN_NUM'       ] := "The field {1} must be greater than or equal to {2}"
   hLang[ 'VAL_MIN_STR'       ] := "The field {1} must have at least {2} characters"
   hLang[ 'VAL_MAX_NUM'       ] := "The field {1} must be less than or equal to {2}"
   hLang[ 'VAL_MAX_STR'       ] := "The field {1} must have at most {2} characters"
   hLang[ 'VAL_BETWEEN'       ] := "The field {1} must be between {2} and {3}"
   hLang[ 'VAL_IN'            ] := "The field {1} contains a value that is not allowed"
   hLang[ 'VAL_NOTIN'         ] := "The field {1} contains a value that is not allowed"
   hLang[ 'VAL_ISMAIL'        ] := "The field {1} must be a valid email"
   hLang[ 'VAL_ISURL'         ] := "The field {1} must be a valid URL"
   hLang[ 'VAL_ISIP'          ] := "The field {1} must be a valid IP address"
   hLang[ 'VAL_REGEX'         ] := "The field {1} has an incorrect format"
   hLang[ 'VAL_MINDATE'       ] := "The field {1} must be after {2}"
   hLang[ 'VAL_MAXDATE'       ] := "The field {1} must be before {2}"
   hLang[ 'VAL_CONFIRMED'     ] := "The field {1} does not match its confirmation"
   hLang[ 'VAL_CODEBLOCK_ERR' ] := "The field {1} did not pass the custom validation"

   // ---- HTTP / middleware error messages ----
   hLang[ 'ERR_BAD_REQUEST'           ] := "Bad Request"
   hLang[ 'ERR_INTERNAL_SERVER_ERROR' ] := "Internal Server Error"
   hLang[ 'ERR_FILE_NOT_FOUND'        ] := "File not found"
   hLang[ 'ERR_TOO_MANY_PENDING'      ] := "Too many pending executions"
   hLang[ 'ERR_PAYLOAD_TOO_LARGE'     ] := "payload_too_large"
   hLang[ 'ERR_MAINTENANCE'           ] := "maintenance"
   hLang[ 'ERR_CSRF_INVALID'          ] := "csrf_invalid"
   hLang[ 'ERR_CSRF_REQUIRES_SESSION' ] := "csrf_requires_session"
   hLang[ 'ERR_CSRF_MSG'              ] := "Invalid request, please reload the page"
   hLang[ 'ERR_PARAM_NOT_FOUND'       ] := "Parameter '{1}' not found"

   // ---- Admin UI ----
   hLang[ 'ADMIN_PANEL_TITLE'            ] := "Administration panel"
   hLang[ 'ADMIN_SETUP_TITLE'            ] := "Initial admin panel setup"
   hLang[ 'ADMIN_LABEL_USER'             ] := "Username"
   hLang[ 'ADMIN_LABEL_PASSWORD'         ] := "Password"
   hLang[ 'ADMIN_BTN_LOGIN'              ] := "Sign in"
   hLang[ 'ADMIN_LABEL_CONFIRM_PASSWORD' ] := "Confirm password"
   hLang[ 'ADMIN_BTN_CREATE'             ] := "Create account"
   hLang[ 'ADMIN_ERR_CREDENTIALS'        ] := "Invalid credentials"
   hLang[ 'ADMIN_ERR_USER_EMPTY'         ] := "Username cannot be empty"
   hLang[ 'ADMIN_ERR_PASSWORD_SHORT'     ] := "Password must be at least 6 characters"
   hLang[ 'ADMIN_ERR_PASSWORD_MISMATCH'  ] := "Passwords do not match"

   // ---- Boot log ----
   hLang[ 'BOOT_LOG_TITLE'            ] := "=== HIX Boot Log ==="
   hLang[ 'BOOT_LOG_END'              ] := "===================="
   hLang[ 'BOOT_ERR_NO_DESC'          ] := "error without description"
   hLang[ 'BOOT_ERR_UNKNOWN'          ] := "(error, no description)"
   hLang[ 'BOOT_LOADER_COMPILE_FAIL'  ] := "compile failed"
   hLang[ 'BOOT_LOADER_HANDLE_NIL'    ] := "handle NIL"
   hLang[ 'BOOT_LOADER_LOAD_FAIL'     ] := "load failed"
   hLang[ 'BOOT_LOADER_LOAD_FAIL_NX'  ] := "load failed (no exception)"
   hLang[ 'BOOT_LOADER_FALSE_POS'     ] := "false positive"

   // ---- Hixstyle dormant hint ----
   hLang[ 'HIXSTYLE_DORMANT_WARN' ] := ;
      "Hixstyle layout detected ({1}) but hixstyle.enabled=false. " + ;
      "Set hixstyle.enabled=true in hix.json to use data-driven autostart."
   hLang[ 'HIXSTYLE_DORMANT_LOG'  ] := ;
      "config.json present but hixstyle.enabled=false"
   hLang[ 'HIXSTYLE_DORMANT_HINT' ] := ;
      "Hint: this looks like a hixstyle project. " + ;
      'Enable it with "hixstyle": { "enabled": true } in hix.json.'

   // ---- Server lifecycle ----
   hLang[ 'SRV_STARTING'        ] := "HIX starting..."
   hLang[ 'SRV_STARTING_SHARED' ] := "HIX starting (shared globals)..."
   hLang[ 'SRV_LISTENING'       ] := "Server listening"
   hLang[ 'SRV_STOPPING'        ] := "Server stopping..."
   hLang[ 'SRV_ACCEPT_ENDED'    ] := "AcceptLoop ended"
   hLang[ 'SRV_POOLS_DESTROY'   ] := "Destroying pools..."
   hLang[ 'SRV_POOLS_DESTROYED' ] := "Pools destroyed"
   hLang[ 'SRV_SHUTDOWN_WAIT'   ] := "Hix server shutting down, waiting..."
   hLang[ 'SRV_SHUTDOWN_OK'     ] := "Hix server shutdown completed successfully !"

   // ---- Server errors ----
   hLang[ 'SRV_ERR_POOLS_INIT'   ] := "Failed to init pools"
   hLang[ 'SRV_ERR_BIND_PORT'    ] := "Error server. Cannot bind port {1}"
   hLang[ 'SRV_LOG_BIND_PORT'    ] := "Failed to bind port {1}"
   hLang[ 'SRV_ERR_SOCKET'       ] := "Cannot create socket"
   hLang[ 'SRV_ERR_RESOLVE'      ] := "Cannot resolve host: {1}"
   hLang[ 'SRV_ERR_BIND'         ] := "Cannot bind: {1}"
   hLang[ 'SRV_ERR_LISTEN'       ] := "Cannot listen: {1}"
   hLang[ 'SRV_FW_BLOCKED'       ] := "Firewall: blocked {1}"
   hLang[ 'SRV_POOL_FULL_503'    ] := "AcceptLoop: pool full -- 503 to {1}"

   // ---- ACL display ----
   hLang[ 'SRV_ACL_TITLE'          ] := "=== Dispatcher ACL ==="
   hLang[ 'SRV_ACL_YES'            ] := "YES"
   hLang[ 'SRV_ACL_NO_BLOCKED'     ] := "NO (blocked)"
   hLang[ 'SRV_ACL_DENY_NONE'      ] := "  Deny dirs : (none)"
   hLang[ 'SRV_ACL_ALLOW_ALL'      ] := "  Allow dirs: (all -- no whitelist)"
   hLang[ 'SRV_ACL_NO_FILE_ROUTES' ] := "  (no file routes registered)"
   hLang[ 'SRV_ACL_FILE_ROUTES'    ] := "=== File Routes ==="

   // ---- Request errors ----
   hLang[ 'REQ_BODY_TOO_LARGE' ] := "Body too large: {1}"
   hLang[ 'REQ_JSON_INVALID'   ] := "JsonBody: invalid JSON -- {1}"

   // ---- Dispatcher ----
   hLang[ 'DISP_PATH_TRAVERSAL'  ] := "Path traversal blocked: {1}"
   hLang[ 'DISP_ZOMBIE_CRITICAL' ] := "CRITICAL: {1} zombies. Rejecting all."

   // ---- Admin log ----
   hLang[ 'ADMIN_LOGIN_FAILED' ] := "Admin login failed for user: {1}"

   // ---- WebSocket / SSE ----
   hLang[ 'WS_CONNECTED'    ] := "WS connected: {1}"
   hLang[ 'WS_DISCONNECTED' ] := "WS disconnected: {1}"
   hLang[ 'SSE_OPENED'      ] := "SSE stream opened: {1} channel={2}"
   hLang[ 'SSE_CLOSED'      ] := "SSE stream closed: {1}"

   // ---- DBF errors ----
   hLang[ 'DBF_ERR_NO_FILE'       ] := "No dbf file"
   hLang[ 'DBF_ERR_NO_FIELDS'     ] := "No fields selected"
   hLang[ 'DBF_ERR_TAG_NOT_FOUND' ] := "Tag doesn't exist: {1}"
   hLang[ 'DBF_ERR_CDX_NOT_FOUND' ] := "Cdx doesn't exist: {1}"
   hLang[ 'DBF_ERR_LOCK'          ] := "Lock error"

RETURN hLang
