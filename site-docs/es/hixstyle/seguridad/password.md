# 🔑 Password storage — `HIX_Password*`

## ¿Qué es?

Primitiva del core HIX para **almacenar contraseñas** de forma segura.
Convierte una clave humana (`"admin1234"`) en un registro portable que
puede guardarse en DBF, SQL o JSON y volver a verificarse después.

Algoritmo: **PBKDF2-HMAC-SHA256** via OpenSSL `libcrypto` (la misma
librería que HIX ya carga para HMAC, JWT y CSRF — sin dependencias
nuevas en el enlazado). Mínimo **600 000 iteraciones** por defecto,
conforme a la recomendación OWASP 2026.

!!! tip "Dónde vive"
    Módulo core: `src/hix_password.prg`. Las tres funciones públicas
    (`HIX_PasswordHash`, `HIX_PasswordVerify`, `HIX_PasswordNeedsRehash`)
    están disponibles desde cualquier app HIX sin registrar middleware
    ni loader.

---

## ¿Por qué no un simple `SHA256(password)`?

Un hash rápido (SHA256, MD5) es **trivial de atacar por fuerza bruta**:
una GPU moderna calcula miles de millones de SHA256 por segundo. Un
diccionario de 10 M palabras cae en segundos.

PBKDF2 añade **coste artificial**:

| Iteraciones | Tiempo login legítimo | Intentos/seg del atacante |
|---|---|---|
| 1               | ~1 µs   | ~1 000 000 000 |
| 100 000         | ~100 ms | ~10             |
| **600 000**     | ~600 ms | ~1.6            |
| 1 000 000       | ~1 s    | ~1              |

600 ms son imperceptibles para el usuario; para un atacante con un
dump de la BD, cada clave candidata cuesta esos mismos 600 ms. Un
diccionario de 10 M palabras pasa de "resuelto en 10 s" a "resuelto
en 1–2 meses" — tiempo suficiente para detectar el breach y rotar.

Además, el **salt** aleatorio por usuario anula las *rainbow tables*:
dos usuarios con la misma clave producen hashes distintos.

---

## API pública

```clipper
HIX_PasswordHash( cPassword [, nRounds ] )  -> hash record | NIL
HIX_PasswordVerify( cPassword, hRecord )    -> .T. | .F.
HIX_PasswordNeedsRehash( hRecord )          -> .T. | .F.
```

| Parámetro | Rango válido | Comportamiento fuera de rango |
|---|---|---|
| `cPassword` | string, 1..1024 bytes | `NIL` / `.F.` |
| `nRounds`   | 600 000..2 000 000 (default 600 000) | `NIL` |
| `hRecord`   | hash con `PASSALG`, `PASSITER`, `SALT`, `PASSHASH` | `.F.` |

- El salt (16 bytes OS-seeded) se genera con `RAND_bytes` de libcrypto.
- La comparación en `Verify` usa `HIX_ConstantEq` → **timing-safe**:
  el atacante no puede inferir el hash por diferencias de latencia.

---

## Formato del hash record

```clipper
{ ;
   "PASSALG"  => "PBKDF2-SHA256",      ;   // tag de algoritmo
   "PASSITER" => 600000,               ;   // nº de iteraciones efectivo
   "SALT"     => "…32 hex chars…",     ;   // 16 bytes en hex (lowercase)
   "PASSHASH" => "…64 hex chars…"      ;   // 32 bytes en hex (lowercase)
}
```

Portable a cualquier backend:

| Campo | DBF | SQL | JSON |
|---|---|---|---|
| `PASSALG`  | `C(16)` | `VARCHAR(16)` | string |
| `PASSITER` | `N(9)`  | `INTEGER`     | number |
| `SALT`     | `C(32)` | `CHAR(32)`    | string |
| `PASSHASH` | `C(64)` | `CHAR(64)`    | string |

!!! warning "Los 4 campos son obligatorios"
    Si colapsas el registro en un solo campo `password_encriptado`,
    pierdes la posibilidad de **subir el coste** (`PASSITER`) o
    **migrar algoritmo** (`PASSALG`) sin forzar reset de todas las
    claves. Los 4 campos juntos son el contrato de PBKDF2.

---

## Flujo típico

### Alta de usuario

```clipper
FUNCTION UserCreate()

   LOCAL hRec, oVal

   oVal := UValidateOrFail( { ;
      "user" => "required|string|max:40", ;
      "pass" => "required|string|min:8"   ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   hRec := HIX_PasswordHash( oVal:Get( "pass" ) )
   IF hRec == NIL
      RETURN USendError( 400, "clave fuera de rango" )
   ENDIF

   // Persiste los 4 campos en tu backend (DBF, SQL, etc.)
   oRow := UserRepoNew( oVal:Get( "user" ) )
   oRow:PASSALG  := hRec[ "PASSALG" ]
   oRow:PASSITER := hRec[ "PASSITER" ]
   oRow:SALT     := hRec[ "SALT" ]
   oRow:PASSHASH := hRec[ "PASSHASH" ]
   oRow:Save()

   USendJson( { "ok" => .T., "user" => oRow:USUARIO }, 201 )
RETURN NIL
```

### Login — verificar + rehash transparente

```clipper
FUNCTION UserLogin()

   LOCAL oRow, hStored, hRec

   oRow := UserRepoFind( UParam( "user" ) )
   IF oRow == NIL
      // Dummy hash para que el tiempo sea indistinguible entre
      // "usuario no existe" y "clave incorrecta" (anti-enumeration).
      HIX_PasswordVerify( UParam( "pass" ), _DummyRecord() )
      RETURN USendError( 401, "credenciales incorrectas" )
   ENDIF

   hStored := { "PASSALG"  => oRow:PASSALG,  ;
                "PASSITER" => oRow:PASSITER, ;
                "SALT"     => oRow:SALT,     ;
                "PASSHASH" => oRow:PASSHASH }

   IF ! HIX_PasswordVerify( UParam( "pass" ), hStored )
      RETURN USendError( 401, "credenciales incorrectas" )
   ENDIF

   // Rehash transparente: si los parámetros guardados son obsoletos
   // (iteraciones por debajo del mínimo o algoritmo antiguo), se
   // re-deriva la clave con los parámetros vigentes y se actualiza.
   IF HIX_PasswordNeedsRehash( hStored )
      hRec := HIX_PasswordHash( UParam( "pass" ) )
      IF hRec != NIL
         oRow:PASSALG  := hRec[ "PASSALG" ]
         oRow:PASSITER := hRec[ "PASSITER" ]
         oRow:SALT     := hRec[ "SALT" ]
         oRow:PASSHASH := hRec[ "PASSHASH" ]
         oRow:Save()
      ENDIF
   ENDIF

   USession():Set( "user", { "id" => oRow:ID, "name" => oRow:NOMBRE } )
   USession():Save()
   URedirect( "/main" )
RETURN NIL
```

---

## `HIX_PasswordNeedsRehash` — subir el coste en caliente

El coste recomendado por OWASP **sube cada ~2 años** para mantener
constante el coste de ataque. Con `PASSITER` por usuario puedes:

1. Cambiar el valor interno mínimo (`HIX_PASSWORD_MIN_ROUNDS`).
2. Al próximo login de cada usuario, `NeedsRehash` devuelve `.T.` si
   su registro está por debajo del nuevo mínimo.
3. Re-derivas con `HIX_PasswordHash` (coste nuevo) y guardas.

Así subes la seguridad **transparente para el usuario**, sin forzar
reset de claves.

El helper devuelve `.T.` en estos casos:

| Caso | Motivo |
|---|---|
| `hRecord` no es un hash | `.T.` — invalid record |
| `PASSALG != "PBKDF2-SHA256"` | algoritmo antiguo, migrar |
| `PASSITER < 600 000` | coste por debajo del mínimo |
| `SALT` o `PASSHASH` con longitud/formato incorrecto | record corrupto |

---

## Seguridad — detalles importantes

### `libcrypto` se resuelve en runtime

HIX no enlaza libcrypto estáticamente; la carga con `LoadLibraryA`
(Windows: `libcrypto-4-x64.dll`) o `dlopen` (Linux:
`libcrypto.so.{4,3,1.1}`) **en el primer uso**.

Si la librería no está disponible:

- `HIX_PasswordHash` devuelve `NIL` → nunca cae a un hash débil.
- `HIX_PasswordVerify` devuelve `.F.` → el login falla, no se abre.

Esta política ("fallar en vez de debilitar") evita el caso clásico de
una app que empieza a aceptar hashes MD5 porque alguien desplegó sin
las DLLs.

### Timing attacks

`HIX_PasswordVerify` compara con `HIX_ConstantEq` — recorre siempre
los 32 bytes y acumula diferencias con XOR. Dos hashes que difieren
en el primer byte tardan lo mismo que dos iguales. El atacante no
puede explotar latencia para adivinar el hash byte a byte.

### Nunca enviar el record al cliente

Los 4 campos juntos son **material sensible**. Nunca los emitas en
una respuesta JSON, en una vista o en un log. Si tu endpoint
`GET /users/:id` devuelve datos del usuario, filtra explícitamente
estos campos antes de serializar.

### Longitud máxima de clave

El límite de 1024 bytes protege contra **denial-of-service** por
password ultra-larga: sin este cap, un cliente podría enviar 100 MB
y forzar al servidor a derivar 600 k veces esa cadena.

---

## Comparativa con otros algoritmos

| Algoritmo | CPU-hard | Memory-hard | Estado |
|---|---|---|---|
| MD5 / SHA1 / SHA256 directo | ❌ | ❌ | **Inseguro** — nunca usar |
| bcrypt      | ✅ | Débil (4 KB) | Aceptable |
| **PBKDF2**  | ✅ | ❌            | **Estándar HIX** (NIST/FIPS) |
| scrypt      | ✅ | ✅            | Bueno |
| Argon2id    | ✅ | ✅ (configurable) | Recomendación OWASP 2026 |

PBKDF2 sigue siendo válido porque:

- Está en todas las librerías estándar.
- Lo exige **FIPS 140** (software en entornos gubernamentales/bancarios).
- Con 600 k+ iteraciones el coste de ataque sigue siendo prohibitivo
  para la mayoría de atacantes.

Si en el futuro HIX añade Argon2id, el campo `PASSALG` permite
**migración gradual**: nuevas claves con `"argon2id"`, las antiguas
con `"PBKDF2-SHA256"` siguen verificándose con su parámetro guardado.

---

## Qué **no** hace esta primitiva

`HIX_Password*` es **crypto input/output puro**. No cubre:

| Fuera de alcance | Capa que lo cubre |
|---|---|
| Rate-limit de intentos de login | Middleware (`HIX_MwRateLimit` o repo del usuario) |
| Persistencia del record | Tu `model/userrepo.prg` (DBF, WDO, etc.) |
| Sesión post-login | `HIX_MwSession` + `USession()` |
| Revocación de sesiones al cambiar clave | Campo `AUTHVER` en tabla + `MyAppReloadUser` |
| Flujo de reset de contraseña por email | Tu app (HIX provee token con `HIX_TokenMake`) |
| Políticas de contraseña (mayúsculas, dígitos...) | `UValidator` con regla `regex:` |

El diseño es deliberado: una primitiva pequeña y auditable, no un
"auth framework" monolítico.

---

## Referencias

- **RFC 2898** / **RFC 8018** — especificación formal PBKDF2
- **NIST SP 800-63B** — Digital Identity Guidelines
- **OWASP Password Storage Cheat Sheet** — iteraciones recomendadas por año
- **Password Hashing Competition 2015** — contexto Argon2
