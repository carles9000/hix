# ⚙️ Compilare il progetto HIX

### Libreria HIX_Server.lib

**HIX** è una libreria basata su **Harbour** e in questa versione usiamo il compilatore **Visual Studio** (MSVC64).

Puoi scaricare **Harbour** dal suo repository ufficiale
[https://harbour.github.io/doc/](https://harbour.github.io/doc/)

**Visual Studio** può essere scaricato da
[https://visualstudio.microsoft.com/es/vs/community/](https://visualstudio.microsoft.com/es/vs/community/)


Per compilare la libreria puoi usare lo script `go_lib_msvc.bat`. Rivedi prima i percorsi della tua installazione di Harbour.


Questo script genera `hix_server.lib` e `hix_server.hbx` (tabella dei simboli esportati).


### Applicazione di esempio

Se preferisci non usare il server precompilato, puoi creare il tuo.
Il file `/examples/server/app.prg` contiene un esempio molto basico di come creare il tuo server **HIX**.

```clipper
FUNCTION Main()

   LOCAL oServer := THixServer():New()   

   oServer:Start()
   
RETURN NIL
```

Per compilarlo e linkarlo, ti basi sugli script di supporto `go_msvc.bat` e `hix.hbp` che possono servire come punto di partenza per incorporare i tuoi file e librerie esterne per creare il tuo server.

La prima volta che avvii il server mostra la configurazione del server.

<img alt="image" src="../../assets/images/manual/primeros-pasos/start.png" />

Compila il tuo server `hix.exe` linkando contro `hix_server.lib`.
Usa questo progetto come punto di partenza: aggiungi le tue route, middleware e librerie aggiuntive in `examples/server/src/app.prg` e `hix.hbp`.

Ricorda che in tutti i tuoi progetti devi copiare le DLL dalla cartella `/dll`
nella directory in cui hai il tuo server.
