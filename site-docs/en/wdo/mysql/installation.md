# WDO MySQL — Installation and prerequisites

Before using the MySQL driver in HIX you need two things: the client library and a test database.

## 1. MySQL client library

The WDO driver does not include the client library — you need to provide it yourself.

=== "Option A — next to the executable (simplest)"
    Copy `libmysql64.dll` (MySQL) or `libmariadb64.dll` (MariaDB) to the same directory where the HIX server is located (`hb_DirBase()`).

=== "Option B — `dll` field in config.json"
    ```json
    {
      "databases": {
        "mysql": {
          "driver": "mysql",
          "dll":    "C:/mysql/lib/libmysql64.dll",
          ...
        }
      }
    }
    ```

=== "Option C — environment variable"
    ```bash
    set WDO_LIB_MYSQL=C:\mysql\lib\libmysql64.dll
    ```

See the [full resolution precedence](config.md#dlls-driver-mysql-vs-mariadb) on the Configuration page.

## 2. Test database — `employees`

The WDO examples use the official MySQL/MariaDB test database.

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/datacharmer/test_db.git
cd test_db

# 2. Import (adjust user and host if needed)
mysql -u root -p < employees.sql
```

The import takes a few seconds and creates these tables:

| Table | Approx. rows | Description |
|-------|-------------|-------------|
| `employees` | 300,000 | Personal data: emp_no, first_name, last_name, gender, hire_date |
| `departments` | 9 | dept_no, dept_name |
| `dept_emp` | 331,603 | Employee ↔ department relationship |
| `salaries` | 2,844,047 | Salary history |
| `titles` | 443,308 | Job title history |

### Verify the installation

```sql
USE employees;
SELECT COUNT(*) FROM employees;   -- should return ~300,000
```

### Credentials for the examples

The `config.json` for the examples uses these credentials by default:

```json
{
  "databases": {
    "mysql": {
      "driver": "mysql",
      "host":   "127.0.0.1",
      "user":   "harbour",
      "pwd":    "hb1234",
      "db":     "employees"
    }
  }
}
```

If you use different credentials, edit `examples/wdo/www/config.json` before starting.

!!! info "Next step"
    With the DLL and the database ready, continue with [Pool Configuration](config.md).
