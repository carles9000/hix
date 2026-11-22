# Run the PostgreSQL modules:

1.- Install the `libpq.dll` client next to `app.exe` or set its path
    in `www/config.json` (option `dllpath`, under `databases.pg`).

    The reference DLL ships at:

        C:\HIX.PROJECT\hix.pro\resources\wdo\pg\dll\libpq.dll

2.- Have a running PostgreSQL 14+ server reachable from the box:

    - default user: `postgres` / password: `postgres`
    - default database: `postgres`
    - default port: `5432`

    Edit `www/config.json > databases.pg` to point at a different
    host/role/DB if needed.

3.- Browse http://127.0.0.1:8081/ to run the demo pages. Every page
    creates and drops its own `hix_demo_*` table, so no additional
    dataset has to be loaded.

4.- (Optional) To run the pages against the official `employees`
    sample dataset instead, replace the self-bootstrap blocks in
    `pg2.html` / `pg3.html` / `pg4.html` with your own `SELECT`
    statements. The schema expected is the typical `emp_no`,
    `first_name`, `last_name`, `gender`, `hire_date` layout.
