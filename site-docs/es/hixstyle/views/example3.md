## 📖 Example 3 - XSS Control

This example shows how the {{ }} macro escapes any HTML values, preventing 
malicious code from being injected. We don't have to worry about anything. 
The {!! !!} macro can be used to display raw HTML data.

We also use the @prg directive to use Harbour functions that can support our 
views.

### Controller: example3.prg

```clipper 
function main()	

	local aData := {;
		{ "Harbour", "Open-source language derived from Clipper, focused on business applications and databases with classic syntax.", .T. },;
		{ "PHP", "Server-side scripting language designed specifically for web development and building dynamic applications.", .F. },;
		{ "Python", "High-level language with clean, readable syntax, widely used in data science, backend, and automation.", .F. },;
		{ "Rust", "Systems language focused on safety, performance, and concurrency without the need for a garbage collector.", .F. },;
		{ "Kotlin", "Modern JVM language that combines functional and object-oriented programming with concise, safe syntax.", .F. };
	}
	
	local hUrls := {=>}
		hUrls[ 'Harbour' ] := 'https://harbour.github.io/' 
		hUrls[ 'PHP' ] := 'https://www.php.net/' 
		hUrls[ 'Python' ] := 'https://www.python.org/' 
		hUrls[ 'Rust' ] := 'https://rust-lang.org/es/' 
		hUrls[ 'Kotlin' ] := 'https://kotlinlang.org/' 					

return UView( 'example3.html', aData, hUrls )
```

### View: example3.html

```html 
@args mydata, urls

<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Example 3</title>

  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css" rel="stylesheet">

</head>
<body>


<div class="container"> 
	<h1 class="text-secondary">XSS control</h1>
	<hr>
	
	@for n := 1  to len( myData )
	
		<br>
		
		@if myData[n][3] 
		
		
			<div class="alert alert-success" role="alert">
				<b>⭐ {{ myData[n][1]}}</b><hr>
				<br>
				{{ myData[n][2] }}
				
				<br>
				<div class="text-end">
					<a href="{!! GetUrl( myData[n][1] ) !!}" class="btn btn-outline-success btn-sm rounded-pill px-3 mt-2">
						{{ GetUrl( myData[n][1] ) }}
					</a>												
				</div>
			</div>
			
		@else 
		
			<div class="alert alert-dark" role="alert">
				<b>{{ myData[n][1]}}</b><hr>
				<br>
				{{ myData[n][2] }}
				
				
				<br>
				<div class="text-end">
					<a href="{!! GetUrl( myData[n][1] ) !!}" class="btn btn-outline-dark btn-sm rounded-pill px-3 mt-2">
						{{ GetUrl( myData[n][1] ) }}
					</a>			
				</div>
			</div>		
			
		@endif 
	
	
	@next
	
@prg 

function GetUrl( uKey )

	local cUrl := HB_HGetDef( urls, uKey, '' )

return cUrl


@endprg 	

</div>	

</body>
</html>
```

### Result

![image](../../../../assets/images/manual/mambo/img4.jpg)