# 🧭 HixStyle - Roadmap

One of **HIX**'s characteristics is the ability for anyone to create
a personalized server, defining its routes, configurations, functions,
middlewares, processes,... essentially everything that a
web application has, all integrated.

Another way is to configure it in HixStyle mode, following its own pattern,
and one of the advantages it offers is being able to configure a standard
HIX server so that it adapts to an entire application via
**data-driven** configuration.

**HixStyle** allows different ways to shape your entire application.
As we've seen in previous chapters, it has its own architecture
and structure to offer a common system for everyone. One of these
features is the ability to define different functionalities from configuration
files.

## Config
At the root of your project you'll have a `config.json` file where you'll set
the main parameters that will configure your application: Harbour sets,
ddriver, database configurations, different keys (session, jwt, csrf,...).

## loaders

`loaders` are the functions that you want to preload in HIX to use them
from your application. Within the folder structure that you define
when using HixStyle, if you have a `/loaders` folder, HIX will load
all the `*.prg` files you have in it when you start the server. The server will compile and
add to its internal symbol map the functions you've defined.

If any module encounters an error during compilation and/or loading, HIX
will not start.

## middlewares

Middlewares, like loaders, will be located in their
`/middlewares` folder, and unlike the loaders folder, there will be a
`config.json` file that indicates which files in the folder will be loaded
and how each middleware will be configured. In the help section this is
well defined.

## routes

Routes can be defined in JSON files that will be located in
the `/routes` folder. You can have routes in a single file or
split into several. When HIX starts, it will read all the JSON files
from the /routes folder and initialize the server.


## Getting ready for AI

### What advantage does this configuration system offer?

One of the advantages it offers is that, starting from a server you have,
whether your own or from a third party, the server will already be prepared, tested, and
you'll only need to map how you want it to work without needing
to recompile the server.

On the other hand, and perhaps one of the most important, we're trying to design
a tool through which any AI can help us in the purpose
of designing our app using **HIX**.

The AI will be able to start the server, stop it, modify the different
configuration files, re-read and reload routes via API against the server,
remove some route, add some functionality, without the need to recompile
our server. This is the objective in the next revision of **HIX**.

The creation of different `/skills` and `/commands` that allow us to advance
in this direction is the main objective.

