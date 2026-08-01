# 📤 Middleware - Loader

## 📂 `<root>/middlewares`

**HIX** allows both static definition (based on your main source code) and
dynamic or hot loading (based on loading files at the moment the
server starts).

If we use **HixStyle** we have the option of placing middlewares in the
`/middlewares` folder. This means that the programmer only needs to copy the
necessary files, and when HIX starts up it will verify the PRG files, compile them,
and they will already be part of the application.

This means that it is not necessary to recompile each time we develop a
web application to include our middlewares.

To configure the middlewares we will create a `config.json` file
in the `/middlewares` directory.

The configuration is very simple:

`load` key which will have an array of all the PRG modules we have in the folder
`setup` key which will have a hash of configuration for the middlewares that need it

Example:
```json
{
  "load": [
    "myappauth.prg",
    "myapplogin.prg",
    "myappauthedit.prg"
  ],
  "setup": {
    "auth": {
      "session_user_key": "_auth_user",
      "roles_key":        "roles",
      "redirect_login":   "/login",
      "redirect_accept":  "/main"
    },
    "session": {
      "cookie":   "FENIXSID",
      "ttl":      3600,
      "max":      100,
      "storage":  "memory"
    },
    "csrf": {
      "redirect": "/login"
    }
  }
}	
```
	
The `load` key shows which files HIX will process when starting up

The `setup` key shows the configuration of each middleware.

Here we can see the nature of each middleware and how it is configured
according to its needs.

