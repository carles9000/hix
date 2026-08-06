# Usuarios y perfiles

El ejemplo trae **tres usuarios hardcoded** en `www/models/modeluser.prg`. No hay base de datos de usuarios - es un stub deliberado para que el foco esté en el flujo de autenticación y autorización, no en cómo persistir credenciales.

Todos comparten password: **`1234`**.

Puedes reemplazar `ModelUser()` por una función que lea de DBF/SQL sin tocar nada más del ejemplo: el contrato de retorno es un hash `{ "id", "name", "roles" }` o `NIL` si la credencial no valida.

---

## Los tres usuarios

| Usuario | Password | Rol funcional | Uso típico en los tests |
|---------|----------|---------------|-------------------------|
| `demo`   | `1234` | Administrador - acceso total al módulo de clientes + `sales` + `purchases`. | Verificar que todas las operaciones CRUD pasan (tests 07-15). |
| `carles` | `1234` | Usuario restringido - solo puede listar y consultar clientes. | Verificar que `HasRole` bloquea con **403** las operaciones para las que no tiene permiso (tests 18-23). |
| `maria`  | `1234` | Usuario intermedio - listar, consultar, editar (sin crear ni borrar). | No cubierto por el test suite; útil para explorar manualmente en el navegador. |

---

## Formato de rol: `recurso: "accion1;accion2;..."`

El hash `roles` de cada usuario mapea **recurso → cadena separada por `;` con las acciones permitidas**. La cadena vacía `""` significa "acceso al recurso, sin acciones específicas" (útil para módulos como `sales` que no tienen sub-permisos definidos en este ejemplo).

Extracto de `modeluser.prg`:

```harbour
"demo"   => { "id" => "1", "name" => "Admin Demo", "pass" => "1234",
              "roles" => { "sales"     => "",
                           "purchases" => "",
                           "customers" => "search;show;edit;delete;recall;create" } },

"carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234",
              "roles" => { "customers" => "search;show",
                           "purchases" => "" } },

"maria"  => { "id" => "3", "name" => "Maria de la O", "pass" => "1234",
              "roles" => { "customers" => "search;show;edit",
                           "sales"   => "" } }
```

---

## Tabla de permisos por usuario y scope

Cruce entre los `scope` declarados en `web.json` y las acciones concedidas en `modeluser.prg`:

| Ruta                    | Scope requerido       | demo | carles | maria |
|-------------------------|-----------------------|:----:|:------:|:-----:|
| `GET  /customer/search` | `customers:search`    | 200  | 200    | 200   |
| `GET  /customer/:id`    | `customers:show`      | 200  | 200    | 200   |
| `GET  /customer/create` | `customers:create`    | 200  | **403**| **403** |
| `POST /customer/store`  | `customers:create`    | 302  | **403**| **403** |
| `GET  /customer/:id/edit` | `customers:edit`    | 200  | **403**| 200   |
| `POST /customer/:id/update` | `customers:edit`  | 302  | **403**| 302   |
| `POST /customer/:id/delete` | `customers:delete`| 302  | **403**| **403** |
| `GET  /main`            | - (solo autenticación) | 200  | 200    | 200   |
| `GET  /module_a` … `_c`  | - (solo autenticación) | 200  | 200    | 200   |

Nota sobre los códigos:
- **200** → `HasRole` acepta, el controlador renderiza HTML.
- **302** → operación POST OK; el controlador redirige tras `Append/Replace/Delete` (patrón PRG).
- **403** → `HasRole` rechaza con `HTTP 403 Forbidden` antes de ejecutar el controlador.

---

## Cómo se evalúa el permiso

En cada ruta con `middleware: "MyAppAuthRole"` o `"MyAppAuthRoleEdit"`, el MW `HIX_MwHasRole` recibe el `scope` declarado en la ruta y lo cruza contra `oCtx:hData["user"]["roles"]`:

1. Parte `scope` por el `:` → obtiene `cRecurso` y `cAccion` (`"customers:edit"` → `"customers"` / `"edit"`).
2. Busca `cRecurso` en el hash `roles` del usuario. Si no está → **403**.
3. Si `cAccion == ""` (solo se pidió el recurso) → OK.
4. Si `cAccion` está en la cadena `";"`-separada del recurso → OK. Si no → **403**.

Ejemplo: `carles` pide `GET /customer/1/edit` (scope `customers:edit`):
- `roles["customers"]` = `"search;show"` → `"edit"` no está → **403**.

---

## Cómo se materializa el usuario en la sesión

Al aceptar el login (`controllers/auth.prg`):

```harbour
oSess := USession()
oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )   // clave = "_auth_user"
oSess:Save()
URedirect( UMwConfig( "auth", "redirect_accept" ) )           // "/main"
```

La clave `_auth_user`, la ruta de aceptación y la de fallo (`/login`) están declaradas en `www/middlewares/config.json` (sección `setup.auth`) - no se hardcodean.

En cada request posterior:
- `HIX_MwSession` recupera el hash de sesión y lo mete en `oCtx:hData["session"]`.
- `HIX_MwIsAuth` lee `session["_auth_user"]`; si no existe redirige a `/login` (302).
- `HIX_MwHasRole` toma ese usuario y evalúa el scope.

Detalles en 4-middlewares.es.md

---

## Añadir o modificar usuarios

Edita `www/models/modeluser.prg`. Al ser un `.prg` cargado dinámicamente (compilado a HRB por el dispatcher), **no requiere recompilar `app.exe`** - basta con reiniciar el servidor o esperar al TTL de caché si lo tienes habilitado.

Añadir un usuario nuevo:

```harbour
"pepe" => { "id" => "4", "name" => "Pepe Test", "pass" => "abcd",
            "roles" => { "customers" => "search;show;edit;create" } },
```

Añadir un permiso al usuario `carles` sin tocar el resto:

```harbour
"carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234",
              "roles" => { "customers" => "search;show;edit",  // + edit
                           "purchases" => "" } },
```

Cambiar el nombre de la clave de sesión (`_auth_user` → otro): editar `www/middlewares/config.json`:

```json
"setup": {
  "auth": {
    "session_user_key": "_auth_user",
    "roles_key":        "roles",
    "redirect_login":   "/login",
    "redirect_accept":  "/main"
  }
}
```

---

## Producción vs demo

`ModelUser()` compara la password en claro. En producción **no**:

- Guarda hash bcrypt/argon2 en la fila DBF/SQL.
- Compara con la función de verificación de HIX o de tu librería crypto.
- Añade rate-limit por usuario además del rate-limit por IP que ya trae `MyAppLogin`.
- Rota la `keys.session` de `www/config.json` (por defecto `H!x@SESSION@2026`) - hay hooks en `loaders/init.prg` para rotarla automáticamente al primer arranque, ver comentario del fichero.
