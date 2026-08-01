# 🧭 HIX Style - Hoja de ruta

Una de las características de **HIX** es la de poder crear quien desee 
un servidor personalizado, definiendo sus rutas, configuraciones, funciones, 
middlewares, procesos,... prácticamente todo lo que tiene una aplicación 
web, todo integrado. 

Otra de las maneras es configurarlo modo HIX Style siguiendo su propio patrón 
y una de las bondades que ofrece es la de poder configurar un servidor 
HIX estandard para que se adapte a toda una aplicación mediante 
configuración **data-driven**.

**HIX Style** permite diferentes maneras de moldear toda la aplicación. 
Como hemos visto en capítulos anteriores, tiene su propia arquitectura 
y estructura para ofrecer un sistema común para todos. Una de estas 
características es poder definir diferentes funcionalides desde ficheros 
de configuración.

## Config
Tendremos en la base de nuestro root un fichero `config.json` donde tendremos 
los principales parámetros que configurarán nuestra aplicación: sets de harbour, 
ddriver, configs de base de datos, diferentes claves (session, jwt, csrf,...).

## loaders

`loaders` son las funciones que deseamos pre-cargar en HIX par usarlas 
desde nuestra aplicación. Dentro de la estructura de carpetas que definimos 
cuando usemos HIX Style si tenemos una carpeta `/loaders` HIX cargará 
todos los ficheros *.prg que tengamos en ella cuando iniciemos el servidor. El servidor compilará y 
añadirá a su mapa de simbolos interno las funciones que hayamos definido. 

Si algun módulo ofrece algun error en la compilacion y/o carga HIX no 
se iniciará.

## middlewares

Los middlewares al igual que los loaders estaran ubicados en su carpeta 
`/middlewares` y a diferencia de la carpeta loaders, existirá un fichero 
config.json en el que se indicará que ficheros de la carpeta se cargaran 
y como se configurará cada middleware. En la sección de ayuda esta bien 
definido como se define.

## routes

Las rutas se pueden definir en ficheros json que estaran ubicados en 
la carpeta `/routes`. Podemos tener las rutas en un unico fichero o 
diversificar en varios. Cuando arranque HIX leerá todos los ficheros json 
de la carpeta /routes e inicializará el servidor 


## Preparándose para la IA

### Que ventaja aporta este sistema de configuración ?

Una de las ventajas que ofrece, es que a partir de un server que tengamos, 
sea propio o de un tercero, el servidor lo tendremos preparado, testeado y 
simplemente solo tengamos de mapear como queremos que funcione sin necesidad 
de recompilar el servidor.

Por otra parte y quizas una de las mas importantes, intentamos diseñar 
una herramienta mediante la cual cualquier IA puede ayudarnos en el proposito 
de diseñar nuestra app usando **HIX**. 

La IA podrá arrancar el server, pararlo, modificar los diferentes ficheros 
de configuracion, releer y recargar rutas via api contra el server, 
descargar alguna ruta, añadir alguna funcionalidad, sin la necesidad de recompilar 
nuestro servidor. Este es el objetivo en la próxima revisión de **HIX**. 

La creación de diferentes /skills y /commands que nos permita avanzar 
en este sentido, es el objetivo principal.


