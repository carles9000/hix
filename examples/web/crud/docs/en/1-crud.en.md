# CRUD Web App - Project Overview

A sample web application built on **HIX Web Server** (Harbour). It serves as a practical reference for starting a real project with session-based authentication, role/scope access control, CSRF protection, and a data table (customers) accessed through a DBF file via the **DBFCDX** RDD driver.


## Goal

- **hixstyle** auto-start — `THixServer():New():Start()` in 3 lines of Harbour.
- Routes configured in JSON (Data-Driven) (`www/routes/web.json`).
- Middlewares configured in JSON (Data-Driven) (`www/middlewares/*.prg`).
- In-memory session with `FENIXSID` cookie.
- Stateless CSRF (HMAC) with `@csrf` in forms.
- Scope-based access control `resource:action` (e.g. `customers:edit`).
- HTML views with `{{ ... }}` template engine.
- DBF data access with DBFCDX driver (customers, states).

---

## Stack

| Layer | Technology |
|-------|------------|
| Language | Harbour (xBase dialect) |
| HTTP Server | HIX (own library, `hix_server.lib`) |
| Compiler | `hbmk2` + MSVC 64 (compiles `app.exe`) |
| Persistence | DBF + CDX indexes (**DBFCDX** driver, linked by default in the lib) |
| Session | In-memory (cookie `FENIXSID`, TTL 3600 s) |
| Front-end | HTML + CSS + vanilla JS, no frameworks |

---

## Folder Structure

### Server
```
examples/web/crud/
├── app.hbp                     # hbmk2 project file
├── app.rc / app.res            # Windows resources (icon, version)
├── go.bat                      # compile and start (msvc64)
├── hix.json                    # server config (port, pools, session, logs)
├── data/                       # DBF tables: customers, states, products (+ CDX)
├── resources/                  # resource images
├── docs/                       # example documentation
│   ├── en/
│   └── es/
│
└── src/                        # Harbour code compiled into app.exe
     ├── app.prg                # PROCEDURE Main - 3 lines
     ├── appconfig.prg          # helpers for reading JSON (legacy, optional)
     └── appmiddleware.prg      # HRB loader (legacy, optional)
```

### Web App
```
examples/web/crud/
│
└── www/                        # web root served by HIX
    ├── config.json             # Harbour sets + rddname + keys (csrf, jwt, session)
    ├── index.html              # public home page
    ├── main.html               # dashboard (protected)
    ├── public/                 # css / js / images (automatic whitelist)
    ├── test/                   # HTML test suite (manual whitelist, see 5-test.en.md)
    │
    ├── routes/
    │   └── web.json            # 14 declarative routes
    │
    ├── middlewares/
    │   ├── config.json         # load list + setup (auth, session, csrf, ratelimit)
    │   ├── myappauth.prg       # group: Session + IsAuth
    │   ├── myappauthrole.prg   # group: Session + IsAuth + HasRole
    │   ├── myappauthedit.prg   # group: Session + IsAuth + HasRole + CsrfCheck
    │   └── myapplogin.prg      # group: Session + RateLimit + CsrfCheck
    │
    ├── controllers/            # one Main() function per endpoint
    │   ├── auth.prg            # POST /auth (login)
    │   ├── login.prg           # GET  /login
    │   ├── logout.prg          # GET  /logout
    │   ├── main.prg            # GET  /main (dashboard)
    │   └── masters/
    │       └── customer.prg    # CLASS Customer with 7 methods (Search, Show, Edit, ...)
    │
    ├── models/
    │   ├── modeluser.prg       # hardcoded users and roles (demo, carles, maria)
    │   ├── tcustomers.prg      # customers.dbf wrapper
    │   └── tstates.prg         # states.dbf wrapper
    │
    ├── loaders/                # .prg files loaded at startup (UserInit hook)
    │   ├── init.prg
    │   └── test.prg
    │
    └── views/
        ├── index.html          # public
        ├── main.html           # dashboard
        ├── common/             # header, navbar, sidebar (partials)
        ├── sys/login.html      # login form
        └── masters/customer/   # search, show, edit, create, form.html
```
---

## Startup Flow (hixstyle)

`src/app.prg` is intentionally minimal:

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

With `hixstyle.enabled: true` in `hix.json`, `Start()` does all of this automatically:

1. Reads `www/config.json` → applies Harbour `sets` (`SET DATE`, `SET LANGUAGE`, `SET DELETED`, …) + `rddSetDefault("DBFCDX")` + loads the `keys` (csrf, jwt, session, token, resource).
2. Reads `www/middlewares/config.json` → loads the 4 `.prg` files listed in `load` (compiles them to HRB and keeps them resident) + applies the declared `setup` sections (session, csrf with `ttl: 3600`, ratelimit `300/60`).
3. Reads `www/routes/web.json` → registers the 14 routes with their method, action, middleware and scope.
4. Compiles and loads `www/loaders/*.prg` → runs `UserInit()` once.
5. Publishes a strict ACL whitelist: only `www/public/*` and directories added via `AllowDir()` are served.

---

## Compile and Start

To compile the example, review the paths in the build script:

```bat
go.bat
```

Default port (defined in `hix.json`): **80**. Open it in the browser:

```
http://localhost/
```

You will see the public home page. From there, `/login` with credentials `demo/1234` (or `carles/1234`, `maria/1234`) takes you to `/main`.

---

## Test Credentials

| User | Password | Profile |
|------|----------|---------|
| `demo`   | `1234` | Administrator — full permissions on the customers module |
| `carles` | `1234` | Restricted — list and view customers only |
| `maria`  | `1234` | Intermediate — list, view and edit (no create/delete) |

Full details in 3-users.en.md

---

Logs are written to `.logs/hix.log` and `.logs/access.log`
