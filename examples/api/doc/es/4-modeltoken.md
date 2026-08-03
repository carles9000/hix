# modeltoken.prg — Almacén de refresh tokens

## ¿Qué es?

Es el **almacén en memoria de refresh tokens**. Complementa al JWT: el JWT es
de vida corta (minutos), y el refresh token es de vida larga (días) para
renovarlo sin re-login.

---

## El problema que resuelve

En una API con JWT puro tienes este dilema:

- **JWT de vida larga** → si alguien lo roba, tiene acceso durante días
- **JWT de vida corta** → el usuario debe re-loguearse cada 15 min

La solución estándar es **dos tokens**:

| Token                    | Vida    | Dónde viaja          | Propósito                   |
|--------------------------|---------|----------------------|-----------------------------|
| **JWT** (access token)   | 15 min  | cada request         | autorizar operaciones       |
| **Refresh token**        | 1-N días| solo en `/auth/refresh` | renovar el JWT sin re-login |

---

## La estrategia: rotación con detección de reutilización

Este es el núcleo del modelo. Cuando el cliente llama a `/auth/refresh`:

```
Cliente:    "Aquí tienes mi refresh token A"
Servidor:   - Marca A como revocado
            - Emite B nuevo (rot_from = A)
            - Devuelve JWT nuevo + token B
Cliente:    Guarda B, descarta A
```

**¿Qué pasa si alguien roba el token A y lo usa después?**

```
Atacante:   "Aquí tienes A"
Servidor:   - A existe PERO está revocado
            - Llama a _TokenRevokeChain(A)
            - Revoca también B, C, D... (toda la cadena de hijos)
            - Responde 401 → el usuario legítimo también pierde acceso
            - Debe re-loguearse (detecta que hubo robo)
```

Esto se llama **Refresh Token Rotation** — es el patrón de OAuth 2.0 moderno.

---

## Las 4 funciones públicas

```
ModelTokenInit()               → crea el pool al arrancar (una vez)
ModelTokenIssue(userId, ip)    → mint un token nuevo, devuelve { token, exp }
ModelTokenRotate(token, ip)    → valida + revoca viejo + emite nuevo
ModelTokenRevoke(token)        → logout: marca como revocado
```

---

## Detalles de implementación

- **Almacén**: `HIX_DataPool("token")` — hash en memoria, protegido con mutex propio
- **Limpieza**: `_TokenPurge()` se llama en cada `Issue` — borra expirados sin
  worker background
- **TTL**: configurable vía `UMwConfig("token", "ttl_days", 1)` — default 1 día
- **Token**: 48 caracteres alfanuméricos aleatorios (≈ 285 bits de entropía)
