# ✨ HixStyle Mode

**HixStyle** is the structured face of HIX. Where [Basic Mode](modo-basico.md)
lets you serve any `.html`, `.prg`, or `.hrb` with complete freedom, **HixStyle**
imposes a way of working: a fixed architecture, predictable names, a clear
flow, and conventions shared by the entire community.

It's not more powerful because it has more features - HIX has those in both modes.
It's more powerful because **all developers work the same way**. That's real
maintainability, real collaboration, and interchangeable modules between projects.

Config HixStyle ➡ hix.json ➡ hixstyle.enabled = **true**

---

## 🎯 One single way to work

**HixStyle** implements the **MVC (Model-View-Controller)** pattern, a standard
widely proven in the software industry (Laravel, Rails, Django,
Spring, ASP.NET MVC, Phoenix...). We didn't reinvent anything: we adopted what already
works and adapted it to the Harbour ecosystem.

The practical consequence:

- A programmer entering a HixStyle project **immediately knows where
  everything is** without needing explanations.
- Routes are declared in one place. Controllers live in another. Views
  in another. Models in another. Middlewares in another.
- There are no "loose scripts lying around". There's no "that .prg that does everything".
  There are no files hanging in random folders.

> 💡 Rigidity is not a cost - it's the guarantee that a project remains
> readable over the years, even if several hands pass through it.

---

## 📁 Folder structure from `<root>`

When you activate HixStyle, HIX expects to find (and creates if they don't exist) a
fixed structure from the root directory (`<root>`, usually `www/`):

```
www/
 ├── public/         ← the only directory served directly to the browser
 ├── routes/         ← route definitions in JSON
 ├── controllers/    ← endpoint logic (.prg)
 ├── views/          ← templates .view.html
 ├── models/         ← data access (UDbf, SQL, external APIs)
 ├── middlewares/    ← interceptors (auth, csrf, rate-limit, ...)
 ├── errors/         ← error pages
 └── loaders/        ← auto-load on startup (routes, MW, helpers)
```

Each folder has **a unique purpose** and **clear semantics**.
This is not a suggestion: HixStyle actively looks in these
directories and rejects any attempt to execute code outside the established flow.

---

## 🔒 Folder privacy

In HixStyle the browser **can only access `public/`**. Period.

- `public/` contains static assets: CSS, JS, images, fonts, downloadable PDFs,
  robots.txt, favicon, etc.
- Everything else (`controllers/`, `views/`, `models/`, `routes/`...) is
  **private by default**. An attempt to request `/controllers/auth.prg`
  directly from the browser receives a **403/404**, never the code.

This policy is enforced at the dispatcher level, not by convention. There's no
way to accidentally leak a `.prg` file: if it's not mounted as a route
in `routes/*.json`, it doesn't run.

> 🛡️ In [Basic Mode](modo-basico.md) any `.prg` or `.hrb` placed
> under `<root>/` can be executed by requesting its URL. In HixStyle that's
> **completely blocked** - it's one of the first visible differences
> when you activate `hixstyle.enabled = true` in `hix.json`.

---

## 🚦 The flow: route → controller → view

Every HTTP request in HixStyle follows the same journey:

```
    Request
       │
       ▼
┌─────────────┐
│  routes/    │  Which controller handles this URL?
│  *.json     │  Which middlewares apply before?
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  middlewares/   │  auth, csrf, rate-limit, cors, ...
│  (chain)        │  can cut the request here
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  controllers/   │  business logic
│  *.prg          │  requests data from models/
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  models/        │  data access (UDbf, SQL, API)
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  views/         │  final HTML render
│  *.view.html    │  (or JSON for APIs)
└──────┬──────────┘
       │
       ▼
   Response
```

This flow is **always the same**, whether the response is an
HTML page for a human or JSON for a mobile app.

---

## 🎨 The view engine (Mambo)

**HixStyle** pushes you to use the [view engine](../hixstyle/views/mambo.md)
of HIX to render HTML - not to concatenate strings inside the controller.
Our view engine that we call Mambo (it gives us great rhythm) offers us
some advantages (detailed in its dedicated chapter):

- **Clear separation** between logic and presentation: designers touch
  the views without needing to understand Harbour.
- **Declarative syntax** with interpolation `{{ }}`, conditionals `@if`,
  loops `@for`, template inheritance...
- **Automatic cache**: views are compiled to HRB the first
  time and reused. Fast rendering even with complex pages.
- **Explicit `@args`**: each view declares what variables it expects to receive.
  There are no "magical" variables injected blindly, they are the classic parameters
  used when calling a function. the controller processes the data
  and sends it in the form of arguments to the view.
- **Automatic escaping**: protection against XSS without thinking about it.

> 📚 The [view engine](../hixstyle/views/mambo.md) has its
> own chapter. Here you just need to know that **it exists** and that in
> HixStyle it is the recommended way to return HTML.

---

## 💾 Models

Models live in `models/` and encapsulate data access:

- **DBF** via [UDbf](../hixstyle/models/udbf.md), a wrapper that adds
  validation, casting, and ActiveRecord-like operations.
- **SQL** (MariaDB, PostgreSQL, SQLite) via the project drivers, Harbour
  libraries,...
- **External APIs** via `hb_curl`.
- **Files, caches, queues...** any data source can live here.

The rule is simple: **controllers don't access tables directly**.
They go through a **model**. This gives you:

- One single place to touch if the database schema changes.
- Possible unit tests: the model can be mocked.
- Reusability: the same model serves multiple controllers.

---

## 🌐 Web + API in the same ecosystem

With HixStyle **the same application simultaneously serves** a
traditional web (HTML) and a REST API (JSON), sharing:

- The same models.
- The same middleware for auth, validation, and rate-limit.
- The same route structure (`routes/web.json` and `routes/api.json`,
  or a single file with `/api/v1/...` prefixes).
- The same user session, or JWT tokens if the API is stateless.

You don't need to maintain two parallel projects. The back-office web and
the API consumed by the mobile app **live in the same HIX**, with the same
business logic behind. You change the output format (view vs JSON)
in one line of the controller.

---

## 🛡️ Middlewares: the real superpower

Middlewares are interceptors that execute **before** the controller
in the chain of each request. In HixStyle they are **first-class citizens**
and most cross-cutting concerns are solved here:

- **Authentication** (session, JWT, API keys).
- **CSRF** (protection against forged requests).
- **CORS** (cross-origin policies for APIs).
- **Rate-limit** (anti-brute-force, anti-DoS).
- **Firewall** (whitelist/blacklist by IP/CIDR).
- **Validation** of input.
- **Logging and metrics** of each request.
- **Translation** (i18n) and locale selection.
- **GZIP compression** of responses.

They are declared in `routes/*.json` per route or per route group, and
combined with commas. The controller **only runs if the entire chain
passes**. If a middleware cuts the request (401, 403, 429...), your
controller doesn't know about it.

> 🧩 All security and orchestration logic lives **outside** the
> controller. The controller only does its thing: orchestrate models
> and render the response. That's clean code.

---

## 📌 Summary of benefits

**HixStyle** gives you, at a stroke:

| Benefit                    | What it gives you                           |
|----------------------------|---------------------------------------------|
| Fixed structure            | Anyone understands any project              |
| Private folders            | Impossible to accidentally leak code        |
| MVC flow                   | Logic, data, and presentation separated    |
| View engine (Mambo)        | Maintainable, fast, and secure HTML        |
| Declarative middlewares    | Security and orchestration outside code    |
| Web + API in one project   | One code, two output channels               |
| Shared conventions         | Onboarding in hours, not weeks              |
| Interchangeable modules    | Import a module from another project and go |

Each of these points has its **own chapter** in the documentation.
This page is just the big picture; from here on, each
section of the manual develops a specific aspect.
