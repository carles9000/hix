# WDO — Web Database Objects

WDO es la capa de acceso a datos de HIX. Su nombre completo es **W**rapped **D**ata **O**bjects: envuelve los drivers de base de datos nativos (librerías C) y expone una API Harbour coherente, thread-safe y lista para producción.

## Por qué existe WDO

En un servidor web multihilo como HIX, cada petición HTTP corre en su propio hilo. Sin WDO, la forma "natural" de conectarse a la base de datos sería abrir y cerrar una conexión TCP por petición. Esto funciona en desarrollo, pero bajo carga real colapsa en minutos:

- Cada `connect()` deja el socket en estado **TIME_WAIT** durante 60–240 segundos.
- El sistema operativo tiene un rango limitado de puertos efímeros (~16.000 en Windows).
- Tras unos miles de peticiones rápidas, el SO ya no puede asignar más puertos → error 10048 / `WSAEADDRINUSE`.

WDO resuelve esto con un **pool de conexiones**: abre N sockets al arrancar la app, los mantiene vivos y los presta a los hilos que los necesitan. Cada "cierre" devuelve la conexión al pool, nunca al sistema operativo.

Este problema no es exclusivo de Harbour. PHP, Node.js, Python y Java todos usan pooling por exactamente la misma razón.

## Drivers disponibles

| Driver | Estado | Clave JSON |
|--------|--------|------------|
| **MySQL / MariaDB** | Production-ready | `"driver": "mysql"` o `"driver": "mariadb"` |
| PostgreSQL | Reservado | — |
| SQLite | Reservado | — |
| MSSQL | Reservado | — |

## Estructura de ficheros fuente

```
src/wdo/
  wdo_pool.prg              Pool genérico thread-safe
  wdo_config.prg            Bootstrap declarativo desde config.json
  wdo.prg                   Registro global y helpers U*
  mysql/
    wdo_mysql.prg           Driver MySQL/MariaDB (New/Open/Query/Close)
    wdo_mysql_pool.prg      Factory del pool MySQL
    wdo_mysql_stmt.prg      Prepared statements — Alt B (texto)
    wdo_mysql_stmt_bin.prg  Prepared statements — Alt A (binario nativo)
    include/
      wdo_mysql_bind.ch     Constantes de tipos para Alt A
```

## Primeros pasos

Si es tu primera vez con WDO, empieza aquí:

1. **[MySQL — Concepto y Pool](mysql/index.md)** — entiende el modelo antes de escribir código.
2. **[Configuración](mysql/config.md)** — cómo declarar el pool en `config.json`.
3. **[Uso del pool](mysql/uso.md)** — cómo usar `WDO_Get` en tus handlers.
