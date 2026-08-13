# 🎺️ Mambo - View Engine

## Introduzione

**Mambo** è il motore di template web integrato in **HIX** e combina codice web
(HTML, JS, CSS, ecc.) con Harbour, facilitando la creazione di pagine web.
Questo semplifica notevolmente la costruzione di qualsiasi pagina, poiché permette di
incorporare logica basata sui parametri che la view riceve, il tutto con l'aiuto di
Harbour.

Questi tipi di motori si concentrano sulla semplificazione del lavoro dello sviluppatore quando
progetta pagine web. Permettono di creare rapidamente pagine dinamiche e potenti
attraverso semplici direttive per controllare il flusso delle informazioni.

Attualmente, ci sono alcuni motori di template molto popolari (come Blade, Twig,
Smarter, ecc.), che fondamentalmente hanno due obiettivi principali:

* Semplificare la progettazione delle pagine.

* Fornire alla community un modo comune di progettare. Tutti lavorano allo stesso modo.

## Impatto sulla produttività

Quando si usano questi motori, non stiamo solo cercando di rendere le cose più belle; è
una scelta ingegneristica legittima. Usando l'ereditarietà dei template (layouts), si
evita di copiare e incollare header e footer in ogni file. Hai bisogno di cambiare un
link nel menu? Lo fai una volta e si aggiorna in tutto il sito.
Inoltre, la sintassi semplificata per i cicli e i condizionali riduce notevolmente
la complessità.

|Vantaggi|Descrizione|
|---|---|
|Sintassi pulita|Capacità di eseguire macro-sostituzioni con eleganti `{{ var }}` o, ad esempio, l'uso di funzioni `{{ time() }}`.|
|Ereditarietà dei template|Permette di creare layout "master" da cui ereditano tutte le altre view.|
|Sicurezza integrata|Esegue automaticamente l'escape dei dati per prevenire attacchi XSS di default.|
|Separazione delle responsabilià|Richiede di mantenere la logica di business separata dal livello di presentazione (HTML).|
|Direttive di controllo|Fornisce strutture come `@foreach` o `@if`, molto più leggibili del codice nativo.|
|Componenti riutilizzabili|Semplifica la creazione di elementi (bottoni, alert) che puoi usare in tutto il sito.|
|Gestione degli errori|Offre messaggi di errore più chiari e specifici, focalizzati sulla progettazione delle view.|
|Performance (Caching)|Compila in codice nativo solo una volta e lo serve dalla cache per la massima velocità.|
|Ecosistema e filtri|Numerose estensioni per formattare automaticamente date o testo.|
|Manutenibilità|È molto più facile riprendere un progetto mesi dopo e capire cosa sta succedendo.|

## Confronto

Linguaggi come `php` si sono evoluti da scrivere qualcosa del genere:

```php
<ul>

<?php if (count($usuarios) > 0): ?>

  <?php foreach ($usuarios as $usuario): ?>

    <li><?php echo htmlspecialchars($usuario->nombre, ENT_QUOTES, 'UTF-8'); ?></li>

  <?php endforeach; ?>

<?php else: ?>

  <li>No hay usuarios registrados.</li>

<?php endif; ?>
</ul>
```

All'uso di motori come questo, che offrono una chiarezza e funzionalità molto maggiori.

```clipper
<ul>

   @foreach oUser IN oItem[ 'Users' ]
   
      <li>Name: {{ oUser[ 'Name' ] }} </li>
   
   @endforeach

</ul>
```

Differenze chiave in questo esempio:

* **Sicurezza:** In PHP puro, se dimentichi `htmlspecialchars`, lasci la
porta aperta ad attacchi XSS. Con *Mambo*, la macro-sostituzione `{{ }}` lo gestisce
automaticamente.

Nel caso volessimo iniettare codice HTML, useremmo semplicemente `{!! !!}`

* **Concisione:** Usa direttive diverse adattate ai comandi classici: `@if`,
`@foreach`, `@for`, ecc.

* **Leggibilità:** Non c'è "rumore" visivo dai tag di apertura/chiusura lato
server, il che permette ai web designer di lavorare più velocemente.

Usando un sistema di ereditarietà, il tuo flusso di lavoro passa da "modifica 20 file" a
"modifica 1 file base e vedi le modifiche in 20 pagine". Se aggiungiamo che non devi
"sanitizzare manualmente ogni variabile", puoi consegnare i progetti in una
frazione del tempo.

## UView() - Il nostro helper magico

`UView( cView, ... )` è la funzione che chiami da qualsiasi controller. Il primo
parametro è il nome della view, e il resto sono i parametri che vuoi
passare.

Nel caso tu abbia HixStyle attivato, le view verranno caricate direttamente dalla
cartella `<cRoot>/views/`.

Come spiegato in precedenza, il flusso base è router->controller->view.

Questo significa che un controller elabora e raccoglie tutte le informazioni necessarie
che invierà alla view, il cui unico scopo è "dipingere" una schermata usando questi
dati.

Esempio di controller, raccolta dati e chiamata a Mambo:

```clipper  
function main()

  local aData := { "Harbour", "PHP", "Python", "Rust", "Kotlin" }

  local cInfo := DToC(Date()) + ' ' + time()

return UView( 'welcome.html', aData, cInfo )
```

Non resta che avere una view definita `welcome.html`

```html 
@args hMydata = {=>}, cInfo := ''
<html>

<h2>Ciao Mambo!</h2>

<hr>
  <small>Test alle {{ cInfo }} </small>
<hr>

   <ul>
      @foreach cItem in hMyData
         <li> {{ cItem }}
      @endforeach
   </ul>
   
<hr>

</html>
```

Fondamentalmente, il codice inizia raccogliendo i parametri inviati dal controller
e se non vengono inviati, li inizializza -> facile.

Poi possiamo vedere un semplice uso di una direttiva, in questo caso @foreach ... @endforeach
e come usiamo le variabili con `{{ ... }}`

![image](../../../assets/images/manual/mambo/img1.png)


## Cache delle view

Il sistema funziona in due modalità:

`live`: analizza, compila ed esegue la view in tempo reale.

`cached`: esegue direttamente una versione cached della view e la ri-analizza
e ricompila solo se il file sorgente originale è cambiato.

Di default, il sistema usa la cache delle view.

Quando usi `UView()`, il motore memorizza tutte le view compilate nella cartella `.cached/views`.
Se rileva che il file sorgente originale è stato modificato, lo analizzerà, ricompilerà
ed eseguirà la view. Se la view non è cambiata, esegue semplicemente
la versione cached.

## Creazione di pagine

Di default, una pagina sarà HTML, ma puoi inserire ed elaborare codice Harbour
al suo interno. Ciò che fa HixStyle è unire due ambienti in uno, in modo efficiente
e facile.

## Codice HTML

Questo è puro codice web, dove puoi inserire macro Harbour. Il codice va dentro
`{{ }}` e deve contenere solo codice Harbour.

```clipper
Ciao alle {{ time() }}
```

Tutto ciò che scrivi dentro una macro `{{ }}` viene automaticamente sanificato. Non
devi preoccuparti di fare l'escape del codice HTML.
