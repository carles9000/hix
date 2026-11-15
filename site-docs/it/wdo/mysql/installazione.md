# WDO MySQL — Installazione e prerequisiti

Prima di usare il driver MySQL in HIX hai bisogno di due cose: la libreria client e un database di test.

## 1. Libreria client MySQL

Il driver WDO non include la libreria client — devi fornirla tu.

=== "Opzione A — accanto all'eseguibile (più semplice)"
    Copia `libmysql64.dll` (MySQL) o `libmariadb64.dll` (MariaDB) nella stessa directory dove si trova il server HIX (`hb_DirBase()`).

=== "Opzione B — campo `dll` in config.json"
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

=== "Opzione C — variabile d'ambiente"
    ```bash
    set WDO_LIB_MYSQL=C:\mysql\lib\libmysql64.dll
    ```

Consulta la [precedenza completa di risoluzione](config.md#dlls-driver-mysql-vs-mariadb) nella pagina di Configurazione.

## 2. Database di test — `employees`

Gli esempi WDO usano il database di test ufficiale di MySQL/MariaDB.

### Installazione

```bash
# 1. Clonare il repository
git clone https://github.com/datacharmer/test_db.git
cd test_db

# 2. Importare (adatta utente e host se necessario)
mysql -u root -p < employees.sql
```

L'importazione richiede alcuni secondi e crea queste tabelle:

| Tabella | Righe appross. | Descrizione |
|---------|----------------|-------------|
| `employees` | 300.000 | Dati personali: emp_no, first_name, last_name, gender, hire_date |
| `departments` | 9 | dept_no, dept_name |
| `dept_emp` | 331.603 | Relazione dipendente ↔ dipartimento |
| `salaries` | 2.844.047 | Storico degli stipendi |
| `titles` | 443.308 | Storico delle qualifiche |

### Verificare l'installazione

```sql
USE employees;
SELECT COUNT(*) FROM employees;   -- deve restituire ~300.000
```

### Credenziali per gli esempi

Il `config.json` degli esempi usa queste credenziali di default:

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

Se usi credenziali diverse, modifica `examples/wdo/www/config.json` prima di avviare.

!!! info "Passo successivo"
    Con la DLL e il database pronti, continua con la [Configurazione del pool](config.md).
