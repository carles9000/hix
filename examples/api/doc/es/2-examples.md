# API HIX examples 

Disponemos de 2 ejemplos básicos de creación de apis con HIX: function y class. Las dos 
hacen exactamente lo mismo con la diferencia que una es en base a uso de funciones por 
cada tipo de petición y la otra se basa en encapsular toda la lógica en un solo fichero 
que sera una clase. 

Las 2 tienen sus ventajas e inconvenientes, pero quizás el uso de la clase y la encapsulación 
ofrece ventajas. Además, la clase tiene los métodos new() y destroy() que se ejecutan automáticamente 
y permiten la gestion encapsulada de opciones que via funcion seria muy repetitiva, por ejemplo:

- Inicializar base de datos
- Inicializar curl.
- Inicializar ...


