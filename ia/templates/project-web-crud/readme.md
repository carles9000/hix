# {{PROJECT_NAME}}

Web-CRUD application built with [HIX](https://github.com/carles9000/hix).

- Author: {{AUTHOR}}
- Created: {{DATE}}

## Structure

```
{{PROJECT_NAME_LOWER}}/
    app.hbp             hbmk2 project file
    go.bat              compile + run
    hix.json            server config (port, pools, session, log)
    data/               DBFs live here
    src/
        app.prg         Main() -- server bootstrap
    www/
        config.json     Harbour sets, DBF driver, keys
        index.html      landing page
        public/         static assets (whitelisted automatically)
        controllers/    action code
        models/         DBF wrappers
        views/          .view.html templates
        routes/         route JSON files
        middlewares/    middleware config + custom .prg
        loaders/        boot .prg (e.g. create DBFs on first run)
```

## Run

```
go.bat
```

Serves on the port set in `hix.json` (default 80).

## Add a CRUD module

Use the skill `/hix-add-crud <entity> [field:type ...]`.

## License

Choose one. Placeholder — replace this section.
