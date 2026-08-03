# Qué es (y qué no es) un buen webservice

Un webservice es una interfaz de comunicación entre máquinas o aplicaciones, 
expuesta normalmente sobre HTTP, que permite a un cliente solicitar datos o 
acciones y recibir una respuesta estructurada, típicamente en JSON o XML. 

El ejemplo básico que simplemente devuelve un json `{ "success" => .T. }` 
es técnicamente un endpoint que responde con datos, pero **no es, por sí solo, 
un webservice completo ni "bueno"**. Es solo la capa más superficial: 
la respuesta final. Un webservice real necesita todo el andamiaje que rodea 
esa línea de código: enrutamiento, middlewares, validación, autenticación, 
control de errores y trazabilidad.

## La diferencia entre "responder JSON" y "ser un webservice"

Devolver JSON es el resultado visible, pero un servicio web robusto exige 
que antes de llegar a esa línea se hayan resuelto varias capas de responsabilidad: 

- Enrutamiento: decidir qué código se ejecuta según el método HTTP y la URL solicitada.
- Middlewares: interceptar la petición antes (o después) de llegar al controlador, 
para auditoría, CORS, logging, límites de tasa, etc.
- Autenticación/autorización: verificar identidad y permisos antes de ejecutar 
la lógica de negocio. 
- Validación de datos: asegurar que los parámetros de entrada cumplen el contrato 
esperado (tipos, rangos, formatos).
- Manejo de errores: capturar excepciones y devolver respuestas coherentes, 
no solo felices ("success": true) sino también fallos estructurados.
- Serialización de salida: convertir estructuras internas a JSON de forma consistente, 
con códigos de estado HTTP correctos.

Si cualquiera de estas capas falta, el servicio puede "funcionar" en pruebas simples, 
pero será frágil, inseguro o impredecible en producción.

## Por qué el sistema de rutas y middlewares importa tanto

Un middleware es una función que se ejecuta antes (y a veces después) de que la petición 
llegue a la lógica de negocio, actuando como filtro o interceptor. 

Este patrón de "cadena de responsabilidad" es lo que separa un simple script que responde 
JSON de un framework de servidor real, porque permite:

- Reutilizar lógica transversal (logging, seguridad, rate limiting) sin repetirla en cada endpoint.
- Aplicar reglas distintas por ruta o grupo de rutas (públicas vs. protegidas).
- Mantener el código de negocio limpio, separado de las preocupaciones de infraestructura.

## Validación de datos: la primera línea de defensa

La validación de datos de entrada es crítica porque un webservice que confía ciegamente en lo 
que recibe es vulnerable a inyecciones, corrupción de datos o comportamientos inesperados. 
Antes de ejecutar cualquier lógica, el sistema debe verificar tipos, formatos, longitudes y 
reglas de negocio, devolviendo errores claros y códigos HTTP apropiados (400, 422) 
cuando algo no cumple el contrato.

## Tabla comparativa: endpoint simple vs. webservice robusto

| Aspecto | Función simple | Webservice robusto (estilo HIX) |
|---|---|---|
| Enrutamiento | Ninguno, respuesta fija | Sistema de rutas con métodos, parámetros y grupos |
| Middlewares | Ausentes | Cadena configurable (auth, logging, CORS) |
| Validación | Ninguna | Validación de esquema antes de ejecutar lógica |
| Seguridad | Ninguna | Tokens, CSRF, roles por ruta |
| Manejo de errores | No definido | Respuestas estructuradas y consistentes |
| Escalabilidad | No aplica | Worker pools, concurrencia, pooling de conexiones |

## Cómo esto se traduce en HIX

Un webservice "bueno" no se define por la simplicidad de su respuesta, sino por la disciplina 
de todas las capas que la preceden. HIX, al implementar un sistema propio de rutas, middlewares 
y validaciones sobre Harbour, no solo "responde JSON" como en el ejemplo inicial, sino que 
construye la infraestructura que garantiza que esa respuesta sea segura, predecible y 
mantenible bajo carga real. La combinación de estricta validación de contratos con arquitectura 
de middlewares desacoplada es precisamente lo que permite que un servidor sea a la vez riguroso 
(rechaza lo inválido temprano) y potente (procesa con eficiencia lo válido), sin sacrificar 
fiabilidad.

