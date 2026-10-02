# WDO - Web Database Objects

WDO is the data access layer of HIX. Its full name is **W**eb **D**ata **O**bjects: it wraps native database drivers (C libraries) and exposes a coherent, thread-safe, production-ready Harbour API.

## Why WDO exists

In a multi-threaded web server like HIX, each HTTP request runs in its own thread. Without WDO, the "natural" way to connect to the database would be to open and close a TCP connection per request. This works in development, but under real load it collapses within minutes:

- Each `connect()` leaves the socket in **TIME_WAIT** state for 60–240 seconds.
- The operating system has a limited range of ephemeral ports (~16,000 on Windows).
- After a few thousand fast requests, the OS can no longer assign ports → error 10048 / `WSAEADDRINUSE`.

WDO solves this with a **connection pool**: it opens N sockets at app startup, keeps them alive and lends them to threads that need them. Each "close" returns the connection to the pool, never to the operating system.

This problem is not exclusive to Harbour. PHP, Node.js, Python and Java all use pooling for exactly the same reason.

## Available drivers

| Driver | Status | JSON key |
|--------|--------|----------|
| **MySQL / MariaDB** | Production-ready | `"driver": "mysql"` or `"driver": "mariadb"` |
