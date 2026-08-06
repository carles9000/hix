# CRUD Web App - Descripción del proyecto

Aplicación web de ejemplo construida sobre **HIX Web Server** (Harbour). Sirve como referencia práctica para arrancar un proyecto real con autenticación por sesión, control de acceso por roles/scopes, protección CSRF y una tabla de datos (clientes) accesible en tabla DBF vía RDD **DBFCDX**.


## Objetivo 

- Autoarranque **hixstyle** - `THixServer():New():Start()` en 3 líneas de Harbour.
- Rutas configuradas en JSON (Data-Driven) (`www/routes/web.json`).
- Middlewares configurados en JSON  (Data-Driven) (`www/middlewares/*.prg`).
- Sesión en memoria con cookie `FENIXSID`.
- CSRF stateless (HMAC) con `@csrf` en los formularios.
- Control de acceso por scope `recurso:accion` (ej. `customers:edit`).
- Vistas HTML con motor de plantillas `{{ ... }}`.
- Acceso a datos DBF con driver DBFCDX (customers, states).

---

## Stack

| Capa | Tecnología |
|------|------------|
| Lenguaje | Harbour (dialecto xBase) |
| Servidor HTTP | HIX (librería propia, `hix_server.lib`) |
| Compilador | `hbmk2` + MSVC 64 (compila `app.exe`) |
| Persistencia | DBF + índices CDX (driver **DBFCDX**, enlazado por defecto en la lib) |
| Sesión | En memoria (cookie `FENIXSID`, TTL 3600 s) |
| Front | HTML + CSS + JS vanilla, sin frameworks |

---

## Estructura de carpetas

### Server 
```
examples/web/crud/
├── app.hbp                     # proyecto hbmk2
├── app.rc / app.res            # recursos Windows (icono, versión)
├── go.bat                      # compila y arranca (msvc64)
├── hix.json                    # configuración del servidor (puerto, pools, sesión, logs)
├── data/                       # tablas DBF: customers, states, products (+ CDX)
├── resources/                  # imágenes de recursos
├── docs/                       # documentación del ejemplo
│   ├── en/
│   └── es/
│
└── src/                        # código Harbour compilado en app.exe
     ├── app.prg                # PROCEDURE Main - 3 líneas
     ├── appconfig.prg          # helpers para leer JSON (legacy, opcional)
     └── appmiddleware.prg      # loader HRB (legacy, opcional)



```

### App Web 
```
examples/web/crud/
│
└── www/                        # raíz web servida por HIX
    ├── config.json             # sets Harbour + rddname + keys (csrf, jwt, session)
    ├── index.html              # portada pública
    ├── main.html               # dashboard (protegido)
    ├── public/                 # css / js / images (whitelist automática)
    ├── test/                   # test suite HTML (whitelist manual, ver test.es.md)
    │
    ├── routes/
    │   └── web.json            # 14 rutas declarativas
    │
    ├── middlewares/
    │   ├── config.json         # load list + setup (auth, session, csrf, ratelimit)
    │   ├── myappauth.prg       # grupo: Session + IsAuth
    │   ├── myappauthrole.prg   # grupo: Session + IsAuth + HasRole
    │   ├── myappauthedit.prg   # grupo: Session + IsAuth + HasRole + CsrfCheck
    │   └── myapplogin.prg      # grupo: Session + RateLimit + CsrfCheck
    │
    ├── controllers/            # una función Main() por endpoint
    │   ├── auth.prg            # POST /auth (login)
    │   ├── login.prg           # GET  /login
    │   ├── logout.prg          # GET  /logout
    │   ├── main.prg            # GET  /main (dashboard)
    │   └── masters/
    │       └── customer.prg    # CLASS Customer con 7 métodos (Search, Show, Edit, ...)
    │
    ├── models/
    │   ├── modeluser.prg       # usuarios y roles hardcoded (demo, carles, maria)
    │   ├── tcustomers.prg      # wrapper de customers.dbf
    │   └── tstates.prg         # wrapper de states.dbf
    │
    ├── loaders/                # ficheros .prg cargados al arrancar (hook UserInit)
    │   ├── init.prg
    │   └── test.prg
    │
    └── views/
        ├── index.html          # pública
        ├── main.html           # dashboard
        ├── common/             # header, navbar, sidebar (parciales)
        ├── sys/login.html      # formulario login
        └── masters/customer/   # search, show, edit, create, form.html
```
---

## Flujo de arranque (hixstyle)

`src/app.prg` es intencionadamente mínimo:

```harbour
#include "hbclass.ch"

FUNCTION Main()

   LOCAL oServer := THixServer():New()         
      
   // In HIXSTYLE mode, the root folder is protected.
   // Our application test is located within the /test folder, 
   // and we need to enable it to be run directly from our 
   // browser: http://localhost/test/index.html
   
      oServer:AllowDir( "test", .F. )  

   oServer:Start()

RETURN NIL
```

Con `hixstyle.enabled: true` en `hix.json`, `Start()` hace todo esto automáticamente:

1. Lee `www/config.json` → aplica `sets` Harbour (`SET DATE`, `SET LANGUAGE`, `SET DELETED`, …) + `rddSetDefault("DBFCDX")` + carga las `keys` (csrf, jwt, session, token, resource).
2. Lee `www/middlewares/config.json` → carga los 4 `.prg` listados en `load` (los compila a HRB y los mantiene residentes) + aplica los `setup` declarados (session, csrf con `ttl: 3600`, ratelimit `300/60`).
3. Lee `www/routes/web.json` → registra las 14 rutas con su método, action, middleware y scope.
4. Compila y carga `www/loaders/*.prg` → ejecuta `UserInit()` una sola vez.
5. Publica una whitelist ACL estricta: solo se sirve `www/public/*` y los directorios añadidos vía `AllowDir()`.

---

## Compilar y arrancar


Para compilar el ejemplo, revisa los paths del script de compilación

```bat
go.bat
```

Puerto por defecto (definido en `hix.json`): **80**. Ábrelo en el navegador:

```
http://localhost/
```

Verás la portada pública. Desde ahí `/login` con credenciales `demo/1234` (o `carles/1234`, `maria/1234`) te lleva a `/main`.

---

## Credenciales de prueba

| Usuario | Password | Perfil |
|---------|----------|--------|
| `demo`   | `1234` | Administrador - todos los permisos sobre clientes |
| `carles` | `1234` | Restringido - solo listado y consulta de clientes |
| `maria`  | `1234` | Intermedio - listado, consulta y edición (no crear/borrar) |

Detalle completo en 3-users.es.md

---

Los logs quedan en `.logs/hix.log` y `.logs/access.log` 
