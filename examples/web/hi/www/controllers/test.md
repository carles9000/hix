# First module

## Create Route 

`/routes/web.json`
```
{ "name": "hello", "url": "/hello", "action": "controllers/hello.prg", "method": "GET" }
```

## Create Controller 

`/controllers/hello.prg`
```
FUNCTION Main()

   LOCAL hMyData := { 'name' => 'Hal', ;
                      'now' => dtoc(date()) + ' ' + time() }
   
RETURN UView( 'hello.html', hMyData )
```

## Create View

`/views/hello.html`
```
@args hData := {=>}

<html>   
   <h1>Hi {{ hData[ 'name' ] }}...</h1>
   <hr>
   <small>Request at {{ hData[ 'now' ] }}</small>
</html>
```
 