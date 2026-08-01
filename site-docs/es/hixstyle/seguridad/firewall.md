# 🧱 Firewall - Filtrado por IP

## ¿Qué es?

El **firewall** de HIX decide, **antes** de aceptar una conexión TCP,
si la IP del cliente puede entrar. Es la **primera línea de defensa**:
si la IP está bloqueada, ni siquiera se llega a hablar HTTP - el socket
se cierra inmediatamente.

```
TCP accept()    ┌───────────────────┐
   ↓            │   Firewall check  │
  cIP ------->  │  ¿IP permitida?   │
                └─────────┬─────────┘
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
        ✅ continúa pipeline    ❌ socket close
        (HTTP/WS/SSE)
```

---

## Cuándo usarlo

| Caso | Firewall |
|---|---|
| Bloquear IPs concretas que abusan | ✅ Sí - blacklist |
| Limitar el panel admin a la red interna | ✅ Sí - whitelist con CIDR |
| API solo accesible desde ciertos partners | ✅ Sí - whitelist |
| Bloquear países enteros | ⚠️ Sí, pero con cuidado - usa DBs GeoIP fuera |
| Sustituir auth | ❌ No - IP cambia, no autentica |
| Sustituir rate limit | ❌ No - IPs nuevas se cuelan |

---

## Setup

### Desde `hix.json`

```json
{
  "firewall": {
    "mode":   "blacklist",
    "filter": "1.2.3.4 10.0.0.0/8 192.168.1.10-192.168.1.50"
  }
}
```

### Desde código

```clipper
HIX_FirewallSetup( ;
   "1.2.3.4 10.0.0.0/8 !10.0.1.0/24",   ;   // cFilter
   "blacklist" )                            // cMode: blacklist | whitelist
```

Llamar **antes** de `oSrv:Start()`. Si `cFilter` está vacío, el firewall
queda desactivado y deja pasar todo.

### Apagarlo en runtime

```clipper
HIX_FirewallClear()        // permite cualquier IP
```

---

## Modos

| Mode | Significado |
|---|---|
| **`blacklist`** | Las IPs del filtro se **bloquean**. Todas las demás pasan. |
| **`whitelist`** | Solo las IPs del filtro **pasan**. El resto se bloquea. |

```clipper
// Blacklist - bloquea atacantes conocidos
HIX_FirewallSetup( "1.2.3.4 5.6.7.8 198.51.100.0/24", "blacklist" )

// Whitelist - solo la oficina + VPN
HIX_FirewallSetup( "10.0.0.0/8 203.0.113.42", "whitelist" )
```

---

## Sintaxis del filtro

Lista de expresiones separadas por **espacios o comas** (ambos válidos -
usa el que quede más legible en tu `hix.json`). Cada expresión es una
de estas formas:

| Forma | Ejemplo | Qué representa |
|---|---|---|
| IP individual | `1.2.3.4` | Solo esa IP |
| CIDR | `192.168.1.0/24` | Bloque `/24` |
| Netmask dotted | `192.168.1.0/255.255.255.0` | Equivalente a `/24` |
| Rango | `192.168.1.10-192.168.1.50` | Todas las IPs del rango |
| Exclusión | `!10.0.1.0/24` | Excluye un sub-bloque |
| IPv6 | `::1` `2001:db8::/32` | También soportado |

### Combinar inclusión + exclusión

```json
{
  "firewall": {
    "filter": "10.0.0.0/8 !10.0.1.0/24 !10.0.2.5"
  }
}
```

Equivale a: "todo `10.0.0.0/8` **excepto** `10.0.1.0/24` y la IP
`10.0.2.5`".

```clipper
HIX_FirewallSetup( "10.0.0.0/8 !10.0.1.0/24 !10.0.2.5", "whitelist" )
```

Las exclusiones (`!`) se aplican después de mergear inclusiones - el
parser deja un conjunto final ordenado y compacto.

---

## Ejemplos completos

### Panel admin solo para LAN

```json
{
  "firewall": {
    "mode":   "whitelist",
    "filter": "127.0.0.1 ::1 192.168.0.0/16 10.0.0.0/8"
  }
}
```

Solo localhost y redes privadas alcanzan al servidor. Internet → drop.

### Bloquear atacantes detectados

```json
{
  "firewall": {
    "mode":   "blacklist",
    "filter": "1.2.3.4 5.6.7.8 91.0.0.0/8"
  }
}
```

Cada IP/bloque añadido cae al silencio (sin respuesta HTTP). Útil para
echar a scrappers que ya identificaste.

### Whitelist con excepciones internas

```json
{
  "firewall": {
    "mode":   "whitelist",
    "filter": "203.0.113.0/24 !203.0.113.99"
  }
}
```

Pasan IPs del bloque `/24` **excepto** la `203.0.113.99` (servidor en
mantenimiento, por ejemplo).

---

## Detrás de proxies

Si HIX está detrás de un balanceador (Apache, Nginx, AWS ALB), la IP que
ve el firewall es la **del proxy**, no la del cliente real. El filtro
por IP **no funciona** si no lo configuras.

```json
{
  "server": {
    "mode": "proxied"
  }
}
```

Con `server.mode = "proxied"`, HIX lee `X-Forwarded-For` / `X-Real-IP` para identificar
al cliente real. Pero **el firewall actúa al `accept()`**, antes de
parsear headers - la IP que filtra es la del socket TCP.

> Por eso el firewall solo es útil cuando HIX está **expuesto
> directamente**. Detrás de proxy, configura el firewall **en el proxy**
> (mod_authz_host en Apache, deny en Nginx).

---

## Verificación manual

Útil para tests o para chequear si una IP está permitida:

```clipper
IF HIX_FirewallCheck( "1.2.3.4" )
   ? "IP permitida"
ELSE
   ? "IP bloqueada"
ENDIF
```

---

## Comparación con otras capas

| Capa | Qué bloquea | Cuándo actúa |
|---|---|---|
| **Firewall** | IPs concretas / rangos | Al `accept()` - antes de HTTP |
| **[Rate Limit](ratelimit.md)** | Demasiados requests de la misma IP | Por request HTTP |
| **[CORS](cors.md)** | Cross-origin desde navegador | Por request HTTP |
| **[Auth](autenticacion.md)** | Usuario no autenticado | Por request HTTP |

Las cuatro suelen ir **stackadas**: firewall corta IPs malas, rate limit
frena abusos, CORS valida origen y auth identifica al user.

---

## Buenas prácticas

1. **Whitelist para servicios internos.** El panel admin, métricas o un
   endpoint de webhook deberían ser whitelist por IP.
2. **Blacklist para fuegos puntuales.** Bloquear IPs concretas tras
   detectar abuso. No te apoyes en blacklist como única defensa - las
   IPs cambian.
3. **No bloquees país enteros con listas manuales.** Imposible mantener.
   Si necesitas geo-blocking serio, usa servicios GeoIP fuera del firewall.
4. **Combina con rate limit.** El firewall corta IPs **conocidas**;
   el rate limit corta IPs **abusivas no conocidas todavía**.
5. **Cuidado con whitelist + IPv6.** Si publicas IPv6, recuerda añadir
   tanto el v4 como el v6 de tus ubicaciones permitidas.
6. **Testea antes de aplicar whitelist en prod.** Una whitelist mal
   escrita te deja fuera del servidor - incluida tu propia IP.

