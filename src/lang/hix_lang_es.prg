FUNCTION LangStrings_ES()

   LOCAL hLang := HIX_InitLang()

   // ---- General messages ----
   hLang[ 'MSG_HELLO'       ] := "Hola Guapo !"
   hLang[ 'MSG_WELCOME'     ] := "Bienvenido/a {1} al sistema"
   hLang[ 'MSG_NOT_FOUND'   ] := "Registro no encontrado"
   hLang[ 'MSG_SAVE_OK'     ] := "Guardado correctamente"
   hLang[ 'MSG_CONFIRM_DEL' ] := "¿Confirma la eliminación de {1}?"
   hLang[ 'MSG_YES'         ] := "S"
   hLang[ 'MSG_NO'          ] := "N"
   hLang[ 'MSG_USER_INFO'   ] := "{1} tiene {2} cm y es mayor de edad: {3}"
   hLang[ 'MSG_ERROR'       ] := "Error en línea {1}: {2}"
   hLang[ 'MSG_PROGRESS'    ] := "Procesados {1} de {2} registros"

   // ---- Validator messages ----
   hLang[ 'VAL_REQUIRED'      ] := "El campo {1} es obligatorio"
   hLang[ 'VAL_NOT_DEFINED'   ] := "El campo {1} no esta definido en las reglas"
   hLang[ 'VAL_ISNUMERIC'     ] := "El campo {1} debe ser un numero"
   hLang[ 'VAL_INTEGER'       ] := "El campo {1} debe ser un numero entero"
   hLang[ 'VAL_POSITIVE'      ] := "El campo {1} debe ser un numero positivo"
   hLang[ 'VAL_MIN_NUM'       ] := "El campo {1} debe ser mayor o igual a {2}"
   hLang[ 'VAL_MIN_STR'       ] := "El campo {1} debe tener al menos {2} caracteres"
   hLang[ 'VAL_MAX_NUM'       ] := "El campo {1} debe ser menor o igual a {2}"
   hLang[ 'VAL_MAX_STR'       ] := "El campo {1} debe tener como maximo {2} caracteres"
   hLang[ 'VAL_BETWEEN'       ] := "El campo {1} debe estar entre {2} y {3}"
   hLang[ 'VAL_IN'            ] := "El campo {1} contiene un valor no permitido"
   hLang[ 'VAL_NOTIN'         ] := "El campo {1} contiene un valor no permitido"
   hLang[ 'VAL_ISMAIL'        ] := "El campo {1} debe ser un email valido"
   hLang[ 'VAL_ISURL'         ] := "El campo {1} debe ser una URL valida"
   hLang[ 'VAL_ISIP'          ] := "El campo {1} debe ser una direccion IP valida"
   hLang[ 'VAL_REGEX'         ] := "El campo {1} tiene un formato incorrecto"
   hLang[ 'VAL_MINDATE'       ] := "El campo {1} debe ser posterior a {2}"
   hLang[ 'VAL_MAXDATE'       ] := "El campo {1} debe ser anterior a {2}"
   hLang[ 'VAL_CONFIRMED'     ] := "El campo {1} no coincide con su confirmacion"
   hLang[ 'VAL_CODEBLOCK_ERR' ] := "El campo {1} no supero la validacion personalizada"

   // ---- HTTP / middleware error messages ----
   hLang[ 'ERR_CSRF_MSG' ] := "Peticion invalida, recarga la pagina"

   // ---- Boot log ----
   hLang[ 'BOOT_LOG_TITLE'            ] := "=== HIX Boot Log ==="
   hLang[ 'BOOT_LOG_END'              ] := "===================="
   hLang[ 'BOOT_ERR_NO_DESC'          ] := "error sin descripcion"
   hLang[ 'BOOT_ERR_UNKNOWN'          ] := "(error, sin descripcion)"
   hLang[ 'BOOT_LOADER_COMPILE_FAIL'  ] := "compilacion fallida"
   hLang[ 'BOOT_LOADER_HANDLE_NIL'    ] := "handle NIL"
   hLang[ 'BOOT_LOADER_LOAD_FAIL'     ] := "carga fallida"
   hLang[ 'BOOT_LOADER_LOAD_FAIL_NX'  ] := "carga fallida (sin excepcion)"
   hLang[ 'BOOT_LOADER_FALSE_POS'     ] := "falso positivo"

   // ---- Hixstyle dormant hint ----
   hLang[ 'HIXSTYLE_DORMANT_WARN' ] := ;
      "Layout hixstyle detectado ({1}) pero hixstyle.enabled=false. " + ;
      "Activa hixstyle.enabled=true en hix.json para usar el autostart data-driven."
   hLang[ 'HIXSTYLE_DORMANT_LOG'  ] := ;
      "config.json presente pero hixstyle.enabled=false"
   hLang[ 'HIXSTYLE_DORMANT_HINT' ] := ;
      "Aviso: parece un proyecto hixstyle. " + ;
      'Activalo con "hixstyle": { "enabled": true } en hix.json.'

   // ---- Server lifecycle ----
   hLang[ 'SRV_STARTING'        ] := "HIX iniciando..."
   hLang[ 'SRV_STARTING_SHARED' ] := "HIX iniciando (globals compartidos)..."
   hLang[ 'SRV_LISTENING'       ] := "Servidor escuchando"
   hLang[ 'SRV_STOPPING'        ] := "Servidor deteniendose..."
   hLang[ 'SRV_ACCEPT_ENDED'    ] := "AcceptLoop finalizado"
   hLang[ 'SRV_POOLS_DESTROY'   ] := "Destruyendo pools..."
   hLang[ 'SRV_POOLS_DESTROYED' ] := "Pools destruidos"
   hLang[ 'SRV_SHUTDOWN_WAIT'   ] := "Hix server apagandose, espera..."
   hLang[ 'SRV_SHUTDOWN_OK'     ] := "Hix server apagado correctamente !"

   // ---- Server errors ----
   hLang[ 'SRV_ERR_POOLS_INIT'   ] := "Error al inicializar pools"
   hLang[ 'SRV_ERR_BIND_PORT'    ] := "Error servidor. No se puede enlazar el puerto {1}"
   hLang[ 'SRV_LOG_BIND_PORT'    ] := "No se puede enlazar el puerto {1}"
   hLang[ 'SRV_ERR_SOCKET'       ] := "No se puede crear el socket"
   hLang[ 'SRV_ERR_RESOLVE'      ] := "No se puede resolver el host: {1}"
   hLang[ 'SRV_ERR_BIND'         ] := "No se puede enlazar: {1}"
   hLang[ 'SRV_ERR_LISTEN'       ] := "No se puede escuchar: {1}"
   hLang[ 'SRV_FW_BLOCKED'       ] := "Firewall: bloqueado {1}"
   hLang[ 'SRV_POOL_FULL_503'    ] := "AcceptLoop: pool lleno -- 503 a {1}"

   // ---- ACL display ----
   hLang[ 'SRV_ACL_TITLE'          ] := "=== Dispatcher ACL ==="
   hLang[ 'SRV_ACL_YES'            ] := "SI"
   hLang[ 'SRV_ACL_NO_BLOCKED'     ] := "NO (bloqueado)"
   hLang[ 'SRV_ACL_DENY_NONE'      ] := "  Deny dirs : (ninguno)"
   hLang[ 'SRV_ACL_ALLOW_ALL'      ] := "  Allow dirs: (all -- sin whitelist)"
   hLang[ 'SRV_ACL_NO_FILE_ROUTES' ] := "  (sin rutas de fichero registradas)"
   hLang[ 'SRV_ACL_FILE_ROUTES'    ] := "=== Rutas de fichero ==="

   // ---- Request errors ----
   hLang[ 'REQ_BODY_TOO_LARGE' ] := "Body demasiado grande: {1}"
   hLang[ 'REQ_JSON_INVALID'   ] := "JsonBody: JSON invalido -- {1}"

   // ---- Dispatcher ----
   hLang[ 'DISP_PATH_TRAVERSAL'  ] := "Path traversal bloqueado: {1}"
   hLang[ 'DISP_ZOMBIE_CRITICAL' ] := "CRITICAL: {1} zombies. Rechazando todo."

   // ---- Admin log ----
   hLang[ 'ADMIN_LOGIN_FAILED' ] := "Admin login fallido para usuario: {1}"

   // ---- WebSocket / SSE ----
   hLang[ 'WS_CONNECTED'    ] := "WS conectado: {1}"
   hLang[ 'WS_DISCONNECTED' ] := "WS desconectado: {1}"
   hLang[ 'SSE_OPENED'      ] := "SSE stream abierto: {1} channel={2}"
   hLang[ 'SSE_CLOSED'      ] := "SSE stream cerrado: {1}"

   // ---- Admin UI ----
   hLang[ 'ADMIN_PANEL_TITLE'            ] := "Panel de administracion"
   hLang[ 'ADMIN_SETUP_TITLE'            ] := "Configuracion inicial del panel admin"
   hLang[ 'ADMIN_LABEL_USER'             ] := "Usuario"
   hLang[ 'ADMIN_LABEL_PASSWORD'         ] := "Contrasena"
   hLang[ 'ADMIN_BTN_LOGIN'              ] := "Acceder"
   hLang[ 'ADMIN_LABEL_CONFIRM_PASSWORD' ] := "Confirmar contrasena"
   hLang[ 'ADMIN_BTN_CREATE'             ] := "Crear cuenta"
   hLang[ 'ADMIN_ERR_CREDENTIALS'        ] := "Credenciales incorrectas"
   hLang[ 'ADMIN_ERR_USER_EMPTY'         ] := "El usuario no puede estar vacio"
   hLang[ 'ADMIN_ERR_PASSWORD_SHORT'     ] := "La contrasena debe tener al menos 6 caracteres"
   hLang[ 'ADMIN_ERR_PASSWORD_MISMATCH'  ] := "Las contrasenas no coinciden"

RETURN hLang
