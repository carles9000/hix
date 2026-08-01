# ⚙️ Compile HIX Project

### HIX_Server.lib Library

**HIX** is a library based on **Harbour** and in this version we use the **Visual Studio** compiler (MSVC64).

You can download **Harbour** from its official repository
[https://harbour.github.io/doc/](https://harbour.github.io/doc/)

**Visual Studio** can be downloaded from
[https://visualstudio.microsoft.com/es/vs/community/](https://visualstudio.microsoft.com/es/vs/community/)


To compile the library you can use the `go_lib_msvc.bat` script. Review the paths to your Harbour installation first.


This script generates `hix_server.lib` and `hix_server.hbx` (exported symbols table).


### Example Application

If you prefer not to use the pre-built server, you can create your own.
The file `/src.app/app.prg` contains a very basic example of how to create your **HIX** server.

```clipper
// Force to link all functions ---------------------
   #define __HBEXTERN__HIX_SERVER__REQUEST
   #include "../hix_server.hbx"

   #define __HBEXTERN__HARBOUR__REQUEST
   #include "harbour.hbx"
// ------------------------------------------------

FUNCTION Main()

   LOCAL oServer := THixServer():New()

   oServer:Start()
   
RETURN NIL
```

To compile and link it, you rely on the support script `go_app_msvc.bat` and `hix_app.hbp` which can serve as a starting point for incorporating your files and external libraries to create your own server.

The first time you start the server it displays the server configuration.

<img alt="image" src="../../../assets/images/manual/primeros-pasos/start.png" />

Compile your server `hix_app.exe` by linking against `hix_server.lib`.
Use this project as a starting point: add your routes, middlewares, and additional libraries in `src.app/app.prg` and `hix_app.hbp`.
