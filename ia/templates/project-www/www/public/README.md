# public/

Static assets served without ACL restrictions.

Put CSS, JS, images, downloads, etc. here. Everything under `public/` is
reachable directly (e.g. `public/css/app.css` -> `http://host/css/app.css`
depending on your HIX version's public prefix policy).

The `public/` directory is the **only** subtree of `www/` that hixstyle
serves without an explicit whitelist entry. All other directories
(`controllers/`, `models/`, `routes/`, `middlewares/`, `loaders/`,
`views/`) are blocked from direct HTTP access by default.
