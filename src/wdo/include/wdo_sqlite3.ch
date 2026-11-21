/*-----------------------------------------------------------
  File ......: wdo_sqlite3.ch
  Author.....: Charly 9000
  Created....: 2026-11-20
  Modified...: 2026-11-20
  Version....: 1.0.0
  Description: Constants shared by WDO_Sqlite3 driver files.
               Mirrors sqlite3.h result/type codes and SQLCipher
               PRAGMA defaults so .prg files don't carry magic
               numbers.
  Usage      : #include "wdo_sqlite3.ch"
  Notes      : Values match sqlite3.h — stable across SQLite 3.x
               and SQLCipher 4.x.
 -----------------------------------------------------------*/

#ifndef _WDO_SQLITE3_CH
#define _WDO_SQLITE3_CH

//  Pool registry key (default).
#define WDO_SQLITE3_POOL_KEY           "SQLITE"

//  Driver tag reported in the "WDO Loaded" banner.
#define WDO_SQLITE3_DLL_TYPE           "SQLite3"

//  Default busy timeout (ms). Keeps concurrent writers from failing
//  immediately with SQLITE_BUSY while the first one completes.
#define WDO_SQLITE3_DEFAULT_BUSY_MS    5000

//  SQLCipher defaults (apply only when the DB is opened with a key).
#define WDO_SQLCIPHER_DEFAULT_KDF_ITER 256000
#define WDO_SQLCIPHER_DEFAULT_PAGE     4096
#define WDO_SQLCIPHER_DEFAULT_HMAC     "HMAC_SHA512"
#define WDO_SQLCIPHER_DEFAULT_KDF      "PBKDF2_HMAC_SHA512"

//  Result codes (sqlite3.h — stable primary codes).
#define SQLITE_OK                      0
#define SQLITE_ERROR                   1
#define SQLITE_BUSY                    5
#define SQLITE_LOCKED                  6
#define SQLITE_NOMEM                   7
#define SQLITE_READONLY                8
#define SQLITE_CORRUPT                 11
#define SQLITE_NOTFOUND                12
#define SQLITE_CANTOPEN                14
#define SQLITE_CONSTRAINT              19
#define SQLITE_MISMATCH                20
#define SQLITE_MISUSE                  21
#define SQLITE_NOTADB                  26
#define SQLITE_ROW                     100
#define SQLITE_DONE                    101

//  Fundamental column datatypes.
#define SQLITE_INTEGER                 1
#define SQLITE_FLOAT                   2
#define SQLITE_TEXT                    3
#define SQLITE_BLOB                    4
#define SQLITE_NULL                    5

//  sqlite3_open_v2 flags (used for future expansion — current driver
//  uses the simpler sqlite3_open() which assumes RW+Create).
#define SQLITE_OPEN_READONLY           0x00000001
#define SQLITE_OPEN_READWRITE          0x00000002
#define SQLITE_OPEN_CREATE             0x00000004
#define SQLITE_OPEN_FULLMUTEX          0x00010000
#define SQLITE_OPEN_SHAREDCACHE        0x00020000
#define SQLITE_OPEN_PRIVATECACHE       0x00040000

//  sqlite3_bind_* destructor sentinels (passed as the last arg to
//  sqlite3_bind_text/blob).
//    SQLITE_STATIC:    (void(*)(void*))0
//    SQLITE_TRANSIENT: (void(*)(void*))-1  →  cast of the integer -1
//  We pass SQLITE_TRANSIENT to force SQLite to copy the buffer, since
//  the Harbour string's lifetime is not guaranteed past the call.
#define SQLITE_STATIC                  0
#define SQLITE_TRANSIENT               -1

#endif
