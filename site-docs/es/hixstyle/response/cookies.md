# 🍪 Cookies


Una **cookie** es un pequeño par `nombre=valor` que el servidor manda al
navegador con `Set-Cookie`, y que el navegador devuelve en cada request
subsiguiente vía `Cookie`. Es el mecanismo básico para mantener estado
(sesiones, preferencias, autenticación) entre requests HTTP, que por sí
solos no tienen memoria.

```
Browser  ─── GET /login ───────────────▶ HIX
                                          │  valida user/pass
                                          │  USetCookie( "HIXSID", cSid, 3600 )
         <── 200 + Set-Cookie  ───────────┤
            HIXSID=abc...; Max-Age=3600;
            Path=/; HttpOnly; SameSite=Lax

Browser  ─── GET /dashboard ───────────▶ HIX
            Cookie: HIXSID=abc...         │  UCookie( "HIXSID" )  → "abc..."
                                          │  identifica al user
         <── 200 + datos  ────────────────┤
```

---

## Leer una cookie

```clipper
UCookie( cNombre, xDef )
```

```clipper
cSid   := UCookie( "HIXSID",     "" )
cTheme := UCookie( "ui_theme",   "light" )
cLang  := UCookie( "lang",       "es" )
```

Internamente parsea el header `Cookie` una sola vez por request (lazy).

---

## Escribir una cookie

```clipper
USetCookie( cNombre, cValor, nMaxAge )
```

```clipper
USetCookie( "ui_theme", "dark", 86400 * 30 )    // 30 días
USetCookie( "HIXSID",   cSid,   3600 )          // 1 hora
USetCookie( "pref",     "x",    0 )             // cookie de sesión
USetCookie( "old",      "",     -1 )            // expirar
```

### Significado de `nMaxAge`

| Valor | Comportamiento |
|---|---|
| `> 0` | Duración en segundos — el navegador la guarda hasta que expire |
| `0` | **Cookie de sesión** — el navegador la borra al cerrar |
| `-1` | **Expirar inmediatamente** — manda `Max-Age=0` para borrarla |

```clipper
// Logout
USetCookie( "HIXSID", "", -1 )    // el navegador olvida la cookie
URedirect( "/login" )
```

---

## Flags automáticos

HIX **siempre** añade tres flags por defecto:

```
Set-Cookie: nombre=valor; Path=/; HttpOnly; SameSite=Lax
```

| Flag | Qué hace |
|---|---|
| `Path=/` | La cookie se manda en toda la app, no solo en `/login` |
| `HttpOnly` | JavaScript **no puede** leerla (`document.cookie` la ignora) — anti-XSS |
| `SameSite=Lax` | El navegador no la envía en requests cross-site POST/PUT — defensa CSRF básica |

> Los tres flags juntos cubren el 80% de los ataques típicos contra
> cookies. Si necesitas comportamiento distinto, ver
> [HIX_SetCookie directo](#hix_setcookie-bajo-nivel).

### Flag `Secure` — pendiente

El flag `Secure` indicaría que la cookie solo viaja por HTTPS. La
versión actual de HIX **no lo emite automáticamente** — si terminas TLS
en un proxy delante, normalmente el proxy lo añade. Si HIX termina TLS
directamente, escribe el `Set-Cookie` manual con `USetHeader` para incluir
`Secure`.

---

## Cookies múltiples

Cada `USetCookie` genera un header `Set-Cookie` independiente — los
navegadores aceptan varios en la misma respuesta:

```clipper
USetCookie( "HIXSID",   cSid,    3600 )
USetCookie( "ui_theme", "dark",  86400 * 30 )
USetCookie( "lang",     "es",    86400 * 30 )

// En la respuesta:
// Set-Cookie: HIXSID=...; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600
// Set-Cookie: ui_theme=dark; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000
// Set-Cookie: lang=es; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000
```

`HIX_SetCookie` detecta cookies con el mismo nombre y las **sustituye**
en vez de duplicarlas — no terminas con dos `HIXSID` distintos.

---

## `HIX_SetCookie` — bajo nivel

Cuando no estás en una acción de ruta (por ejemplo, dentro de un
middleware con `oCtx`), usa la función con `oReq` explícito:

```clipper
FUNCTION MyAppRememberMeMw( oCtx )
   LOCAL cToken := _GenerateRememberToken( oCtx )

   HIX_SetCookie( oCtx:oReq, "remember", cToken, 86400 * 30 )
RETURN .T.
```

Es exactamente lo mismo que `USetCookie`, pero recibe `oReq` como primer
parámetro. `USetCookie` lo llama por debajo con el request del hilo
actual.

---

## Patrones útiles

### Login con sesión + remember-me

```clipper
FUNCTION _LoginAction()
   LOCAL hUser := _CheckCredentials( UPost("user"), UPost("pass") )

   IF hUser == NIL
      RETURN USendError( 401, "Credenciales inválidas" )
   ENDIF

   USession():Set( "user_id", hUser["id"] )
   USession():Save()

   IF UPost( "remember", "" ) == "1"
      USetCookie( "remember", _MakeRememberToken( hUser ), 86400 * 30 )
   ENDIF

   URedirect( "/dashboard" )
RETURN NIL
```

### Logout — limpiar cookies

```clipper
FUNCTION _LogoutAction()
   USession():Destroy()              // expira HIXSID
   USetCookie( "remember", "", -1 )  // borra el remember-me

   URedirect( "/" )
RETURN NIL
```

### Preferencias de UI (light/dark)

```clipper
oSrv:AddRoutePost( "ui.theme.set", "/ui/theme", {||
   LOCAL cTheme := UPost( "theme", "light" )

   IF AScan( { "light", "dark", "auto" }, cTheme ) == 0
      RETURN USendError( 400, "Tema no válido" )
   ENDIF

   USetCookie( "ui_theme", cTheme, 86400 * 365 )
   USendJson( { "ok" => .T., "theme" => cTheme } )
} )
```

### Idioma persistente

```clipper
FUNCTION MyAppLangMw( oCtx )
   LOCAL cLang := UCookie( "lang", "" )

   IF Empty( cLang )
      cLang := Left( UHeader( "accept-language", "es" ), 2 )
      USetCookie( "lang", cLang, 86400 * 365 )
   ENDIF

   oCtx:hData[ "lang" ] := cLang
RETURN .T.
```

---

## Errores típicos

| Síntoma | Causa |
|---|---|
| Cookie no llega al cliente | `USetCookie` después de enviar la respuesta (`USendJson`/`URedirect`) |
| Cookie llega pero `UCookie` la lee vacía | Nombre con mayúsculas/minúsculas distintas — comparación es case-sensitive |
| Cookie llega solo a veces | `Path` distinto o cliente bloqueando cookies cross-site |
| `document.cookie` no la ve en JS | `HttpOnly` lo impide — diseño correcto |
| POST de form externo no manda la cookie | `SameSite=Lax` lo impide — diseño correcto |
| La cookie expira al refrescar | Pasaste `nMaxAge=0` (cookie de sesión) en vez de un valor en segundos |

---

## Buenas prácticas

1. **Nunca guardes datos sensibles en cookies.** Solo identificadores
   opacos (`HIXSID=abc...`). Los datos reales van en sesión server-side.
2. **`HttpOnly` y `SameSite` siempre.** HIX ya los pone — no los desactives
   sin un motivo claro.
3. **Tamaño bajo control.** Las cookies son enviadas en **cada** request.
   Una cookie de 4KB × 30 requests/segundo = mucho ancho de banda
   desperdiciado.
4. **Cookies firmadas si son sensibles.** Si necesitas guardar algo "real"
   (un user-id, un rol), firma el valor con HMAC + `app_key`. Si el
   cliente lo manipula, la firma deja de cuadrar.
5. **Expira al hacer logout.** No basta destruir la sesión server-side —
   también hay que mandar la cookie con `Max-Age=0` para que el navegador
   la olvide.
6. **Cuidado con `SameSite=Strict`.** Lax es el sweet-spot habitual. Strict
   bloquea cookies en navegaciones desde sitios externos (incluyendo
   enlaces) y rompe muchos flujos.

