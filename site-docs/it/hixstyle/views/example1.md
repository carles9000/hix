## 📖 Esempio 1 - Parametri

Questo esempio mostra come definire i parametri inviati dal controller
e come usarli in un semplice ciclo.

### Controller: example1.prg
```clipper
function main()	

	local cTicket := 'ABC-' + ltrim( Str( hb_RandomInt(100000, 999999) ) )
	local aData   := {;
		{ "Harbour", "Linguaggio open-source derivato da Clipper, focalizzato su applicazioni business e database con sintassi classica.", .T. },;
		{ "PHP", "Linguaggio di scripting server-side progettato specificamente per lo sviluppo web e la creazione di applicazioni dinamiche.", .F. },;
		{ "Python", "Linguaggio di alto livello con sintassi pulita e leggibile, molto usato in data science, backend e automazione.", .F. },;
		{ "Rust", "Linguaggio di sistema focalizzato su sicurezza, performance e concorrenza senza bisogno di un garbage collector.", .F. },;
		{ "Kotlin", "Linguaggio JVM moderno che combina programmazione funzionale e object-oriented con sintassi concisa e sicura.", .F. };
	}

return UView( 'example1.html', aData, cTicket )
```

### View: example1.html

```html 
@args mydata, cId

<h1>Esempio base</h1>
<hr>

<b>Ticket: </b>{{ cId }}

<ul>
	
	@foreach oItem IN myData 
	
		<li>{{ oItem[1] }} => {{ oItem[2] }} </li>
		
		<hr>		
		
	@endforeach			
	
</ul>
<hr>
L'ora attuale è {{ time() }}
```

### Risultato

![image](../../../assets/images/manual/mambo/img2.jpg)
