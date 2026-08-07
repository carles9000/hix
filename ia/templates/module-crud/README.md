# module-crud template

Drop-in CRUD module. Adds one entity (routes + controller + model + views + a
first-boot DBF creator) to an existing hixstyle project.

## What gets copied

Into `www/` of the target project:

```
controllers/{{ENTITY_LOWER}}.prg     -- List/Show/Create/Store/Edit/Update/Delete
models/{{ENTITY_LOWER}}.prg          -- DBF wrapper (open/close per operation)
views/{{ENTITY_LOWER}}/list.view.html
views/{{ENTITY_LOWER}}/show.view.html
views/{{ENTITY_LOWER}}/edit.view.html
routes/{{ENTITY_LOWER}}.json         -- 7 routes prefixed with /{{ENTITY_PLURAL_LOWER}}
loaders/init_{{ENTITY_LOWER}}.prg    -- Creates data/{{ENTITY_PLURAL_LOWER}}.dbf on first boot
```

## Tokens

See `../README.md` for the full list. This template uses:

- `{{ENTITY}}`               -- e.g. `Product`
- `{{ENTITY_LOWER}}`         -- e.g. `product`
- `{{ENTITY_PLURAL_LOWER}}`  -- e.g. `products` (URL segment + DBF basename)
- `{{DATE}}`, `{{AUTHOR}}`

## Fields

The out-of-the-box schema is:

    id     N 10 0    (auto-incremented)
    name   C 100 0
    notes  C 200 0
    cts    T  0 0    (created timestamp)

Edit the loader `.prg` after scaffolding to add / change fields; then delete
`data/{{ENTITY_PLURAL_LOWER}}.dbf` so the loader recreates it. (Or use a
proper migration when you have production data.)

## Usage

```
/hix-add-crud <Entity>
```

Example: `/hix-add-crud Product`
