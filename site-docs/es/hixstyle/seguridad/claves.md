# 🔑 Claves y secretos - almacén compartido

Cada engine de seguridad de HIX (JWT, sesiones, tokens firmados, CSRF,
resource IDs…) necesita una **clave secreta** para firmar. Para no
repetir setups por módulo, HIX ofrece un único almacén de claves:

- `HIX_KeySet( cName, cVal )` - guarda una clave con nombre.
- `HIX_KeyGet( cName, cDefault )` - la lee (o devuelve el default).
- `HIX_KeyExists( cName )` - comprueba si existe.

Los engines siempre leen a través de `HIX_KeyGet()`. **No les importa
de dónde salga la clave** - solo importa que esté cargada antes de
`oSrv:Start()`.

## Claves que usa HIX

| Nombre     | Consumido por                       | Default de fallback   |
|------------|-------------------------------------|-----------------------|
| `csrf`     | CSRF (`HIX_CsrfMakeToken/Valid`)    | `"H!x@CSRF@2026"`     |
| `resource` | Resource IDs (`HIX_ResourceHtml`)   | `"H!x@RES@2026"`      |
| `jwt`      | JWT (`HIX_JwtEncode/Validate`)      | `"H!x@JWT@2026"`      |
| `session`  | Sesiones (seed para encriptar SID)  | `"H!x@SESSION@2026"`  |
| `token`    | Tokens firmados genéricos           | `"H!x@TOKEN@2026"`    |

> Los defaults existen para que la lib arranque; **cámbialos siempre**
> en producción.

---

## Perfil hixstyle - carga automática desde `config.json`

En modo **hixstyle** (`config.json` presente en la raíz del proyecto), el
bootstrap del servidor lee la sección `keys` justo después de aplicar la
config de Harbour y publica cada entrada en el almacén.

```json
{
  "sets": { "language": "ES", "dateformat": "dd/mm/yyyy" },
  "dbf":  { "rddname": "DBFCDX" },
  "keys": {
    "csrf":     "T7$k9pM2!vX4qL8w",
    "resource": "res-2026-abc",
    "jwt":      "hix-jwt-prod-2026",
    "session":  "sess-seed-random",
    "token":    "tok-2026-xyz"
  }
}
```

En la primera ejecución, HIX genera `config.json` con esta sección ya
sembrada (con los defaults de fallback). El usuario solo tiene que
sustituir los valores por los suyos y reiniciar - sin recompilar.

## Perfil standalone - sin `config.json`

Si prefieres arrancar sin `config.json` (arranque totalmente programático),
publica las claves tú mismo antes de `oSrv:Start()`:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()

   // Cargar claves desde donde quieras: fichero .ini, variables de
   // entorno, KMS, hard-coded para desarrollo…
   HIX_KeySet( "csrf",    GetEnv( "HIX_CSRF_KEY" ) )
   HIX_KeySet( "jwt",     GetEnv( "HIX_JWT_KEY"  ) )
   HIX_KeySet( "session", GetEnv( "HIX_SESS_KEY" ) )

   oSrv:Start()
   IF oSrv:hThread != NIL ; hb_threadJoin( oSrv:hThread ) ; ENDIF
RETURN
```

Los engines ven exactamente lo mismo - la única diferencia es de dónde
sale el valor.

## Perfil legacy - setups por módulo

Los setups históricos (`HIX_MwJwtSetup`, `HixMwSessionSetup`,
`HIX_TokenSetSecret`, …) **siguen funcionando**. Internamente delegan en
`HIX_KeySet` con el nombre de clave adecuado.

```harbour
HIX_MwJwtSetup( "my-jwt-secret", 3600 )    // equivalente a HIX_KeySet("jwt", ...)
HIX_TokenSetSecret( "tok-2026" )           // equivalente a HIX_KeySet("token", ...)
```

Coexisten con las otras dos formas. Si mezclas orígenes, gana el último
que escribe.

---

## Precedencia

1. **Bootstrap hixstyle** - se ejecuta primero: `HIX_KeysLoadFromAppConfig()`
   copia la sección `keys` al almacén.
2. **Setup por módulo** - cualquier `HIX_*Setup()` que llames después.
3. **`HIX_KeySet()` manual** - la vía más directa; sobrescribe lo anterior.

Regla práctica: si un valor está en `config.json` **y** además llamas a
`HIX_MwJwtSetup("otra")` en `Main()`, la ejecución posterior gana.

## Inspección segura

Para depurar o exponer el estado del almacén sin filtrar secretos:

```harbour
? HIX_KeysAsHash()
// { "csrf" => "T7***4w", "jwt" => "hi***26", ... }
```

Cada valor se enmascara mostrando solo 2 caracteres iniciales y finales.
Es el mismo hash que puedes emitir por un endpoint interno de estado.
