# libpq.dll para WDO_PG

Esta carpeta aloja la DLL cliente de PostgreSQL (`libpq.dll`) que usa el
driver `src/wdo/pg/`.

## Build actual

- **PostgreSQL 18.7** — compilada desde fuentes contra **OpenSSL 4.0.1**
  oficial (release Abril 2026). Toolchain: MSYS2/MinGW64 + Meson.
- Tamaño: ~1.8 MB.


## Dependencias runtime

La DLL depende únicamente de:

| DLL                    | Rol                              | Ubicación habitual |
|------------------------|----------------------------------|--------------------|
| `libcrypto-4-x64.dll`  | OpenSSL 4 — cripto base          | junto al `.exe`    |
| `libssl-4-x64.dll`     | OpenSSL 4 — SSL/TLS              | junto al `.exe`    |

Las DLLs de OpenSSL 4 **no viven en esta carpeta**: HIX ya las enlaza
junto al ejecutable para CSRF/JWT/HMAC/Password. El loader de Windows
las resuelve desde el directorio del `.exe`.

