# WDO MySQL — Instalación y requisitos previos

Antes de usar el driver MySQL en HIX necesitas dos cosas: la librería cliente y una base de datos de prueba.

## 1. Librería cliente MySQL

El driver WDO no incluye la librería cliente — necesitas proporcionarla tú.

=== "Opción A — junto al ejecutable (más simple)"
    Copia `libmysql64.dll` (MySQL) o `libmariadb64.dll` (MariaDB) al mismo directorio donde está el servidor HIX (`hb_DirBase()`).

=== "Opción B — campo `dll` en config.json"
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

=== "Opción C — variable de entorno"
    ```bash
    set WDO_LIB_MYSQL=C:\mysql\lib\libmysql64.dll
    ```

Consulta la [precedencia completa de resolución](config.md#dlls-driver-mysql-vs-mariadb) en la página de Configuración.

## 2. Base de datos de prueba — `employees`

Los ejemplos de WDO usan la base de datos de prueba oficial de MySQL/MariaDB.

### Instalación

```bash
# 1. Clonar el repositorio
git clone https://github.com/datacharmer/test_db.git
cd test_db

# 2. Importar (ajusta usuario y host si es necesario)
mysql -u root -p < employees.sql
```

La importación tarda unos segundos y crea estas tablas:

| Tabla | Filas aprox. | Descripción |
|-------|-------------|-------------|
| `employees` | 300.000 | Datos personales: emp_no, first_name, last_name, gender, hire_date |
| `departments` | 9 | dept_no, dept_name |
| `dept_emp` | 331.603 | Relación empleado ↔ departamento |
| `salaries` | 2.844.047 | Histórico de salarios |
| `titles` | 443.308 | Histórico de cargos |

### Verificar la instalación

```sql
USE employees;
SELECT COUNT(*) FROM employees;   -- debe retornar ~300.000
```

### Credenciales para los ejemplos

El `config.json` de los ejemplos usa estas credenciales por defecto:

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

Si usas credenciales distintas, edita `examples/wdo/www/config.json` antes de arrancar.

!!! info "Siguiente paso"
    Con la DLL y la base de datos listos, continúa con la [Configuración del pool](config.md).
