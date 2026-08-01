# Middleware - Practical example

This final chapter shows a practical example of how a simple application could look, 
in which we will have an authentication screen (login), a CRUD, and 3 fake modules.

For the schema of this application "my conditions" (because everyone has their own) 
are:

- main screen Hello splash without security, open access
- login screen -> middleware "MyAppLogin"
- module_x screen -> middleware "MyAppAuth", if only authenticated -> ok
- CRUD screen -> middleware "MyAppAuthRole" with granular role validation. Authenticated + role
- CRUD screen (edit) -> middleware "MyAppAuthEdit" with granular role validation + CSRF

We can observe how I use 3 types of Mw. A structure that validates simply if you are 
authenticated (MyAppAuth) to if I am validated and have a specific role (MyAppRole)

The route definitions could look as follows:

```json
[
  { "name": "index",          "url": "/",                            "action": "views/index.html",                         "method": "GET" },
  { "name": "main",           "url": "/main",                        "action": "controllers/main.prg",                     "method": "GET",  "middleware": "MyAppAuth" },
  { "name": "sys.login" ,     "url": "/login",                       "action": "controllers/login.prg",                    "method": "GET" },
  { "name": "sys.logout",     "url": "/logout",                      "action": "controllers/logout.prg",                   "method": "GET",  "middleware": "MyAppAuth" },
  { "name": "sys.auth",       "url": "/auth",                        "action": "controllers/auth.prg" ,                    "method": "POST", "middleware": "MyAppLogin" },
  { "name": "module_a",       "url": "/module_a",                    "action": "views/masters/modules/module_a.view.html", "method": "GET",  "middleware": "MyAppAuth" },
  { "name": "module_b",       "url": "/module_b",                    "action": "views/masters/modules/module_b.view.html", "method": "GET",  "middleware": "MyAppAuth" },
  { "name": "module_c",       "url": "/module_c",                    "action": "views/masters/modules/module_c.view.html", "method": "GET",  "middleware": "MyAppAuth" },
  { "name": "customer.search","url": "/customer/search",             "action": "controllers/masters/search@customer.prg",  "method": "GET",  "middleware": "MyAppAuthRole", "scope": "customers" },
  { "name": "customer.create","url": "/customer/create",             "action": "controllers/masters/create@customer.prg",  "method": "GET",  "middleware": "MyAppAuthRole", "scope": "customers:create" },
  { "name": "customer.store", "url": "/customer/store",              "action": "controllers/masters/store@customer.prg",   "method": "POST", "middleware": "MyAppAuthEdit", "scope": "customers:create" },
  { "name": "customer.show",  "url": "/customer/:id",                "action": "controllers/masters/show@customer.prg",    "method": "GET",  "middleware": "MyAppAuthRole", "scope": "customers" },
  { "name": "customer.edit",  "url": "/customer/:id([0-9]+)/edit",   "action": "controllers/masters/edit@customer.prg",    "method": "GET",  "middleware": "MyAppAuthRole", "scope": "customers:edit" },
  { "name": "customer.update","url": "/customer/:id([0-9]+)/edit",   "action": "controllers/masters/update@customer.prg",  "method": "POST", "middleware": "MyAppAuthEdit", "scope": "customers:edit" },
  { "name": "customer.delete","url": "/customer/:id([0-9]+)/delete", "action": "controllers/masters/delete@customer.prg",  "method": "POST", "middleware": "MyAppAuthEdit", "scope": "customers:delete" }

]	
```
