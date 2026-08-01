# 📤 Middleware - Loader

## 📂 `<root>/middlewares`

**HIX** permite la definición estática (basada en el código fuente principal) y 
la carga dinámica o en caliente (basada en la carga de ficheros en el momento 
de iniciar el servidor).

Si usamos **HIXStyle** tenemos la opcion de poner los middlewares en la carpeta 
`/middlewares`. Esto significa que el programador solo necesita copiar los 
ficheros necesarios y cuando HIX se arranque verificará los prg, compilará y 
ya formaran parte de la aplicación.

Esto significa que no es necesario recompilar cada vez que hagamos una aplicacion 
web para incluir nuestros Mw.

Para poder configrar los Mw crearemos en el directorio /middlewares el fichero 
`config.json`.

La configuración es muy sencilla: 

clave `load` que tendra un array de todos los modulos prg que tengamos en la carpeta 
clave `setup` que tendrá un hash de configuracion de los Mw que lo necesiten

Ejemplo:
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
	
La clave `load` muestra que ficheros procesará HIX al iniciar 

La clave `setup` muestra la configuracion de cada Mw.

Aqui podemos observar la naturaleza de cada middleware como se configura 
segun sus necesidades.


	

