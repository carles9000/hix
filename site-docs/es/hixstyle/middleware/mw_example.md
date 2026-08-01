# Middleware - Ejemplo práctico 

Este capitulo final muestra un ejemplo práctico de como podria quedar una simple 
aplicación, en el que tendremos una pantalla de autenticacion (login), un crud 
y 3 modulos fake. 

Para el esquema de esta aplicación "mis condiciones" (porque cada uno tiene las suyas) 
son: 

- pantalla principal Hello splash sin seguridad, libre acceso 
- pantalla login -> middleware "MyAppLogin" 
- pantalla module_x -> middleware "MyAppAuth" , si esta solo autenticado -> ok
- pantalla crud -> middleware "MyAppAuthRole" con validacion de role granular. Autenticado + role
- pantalla crud (edit) -> middleware "MyAppAuthEdit" con validacion de role granular + CSRF

Podemos observar como uso 3 tipos de Mw. Una estructura que valida simplemente si estas 
autenticado (MyAppAuth) hasta si estoy validado y tendo un role específico (MyAppRole) 

La definicion de rutas podrian quedar de la siguiente manera:

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





