<h1 style="display: flex; align-items: center;">
  <img src="https://raw.githubusercontent.com/carles9000/hix/refs/heads/main/resources/images/hix.png" height="50" style="margin-right: 10px;">            
  Web Server 
</h1>

**HIX** is a lightweight, versatile web server built to fit the way you work. Whether you're 
after total freedom or a structured, rock-solid architecture, HIX gives you the tools you need 
to build modern apps efficiently.

## ⚙️ Two philosophies, one engine

**HIX** is designed to let you code in two different ways:

* **HIX Style:** "The playbook" A predefined, optimized app structure 
that follows industry best practices, so you can scale and maintain your code without the headache.

* **Standard:** For coders who go their own way no trends, no set patterns, 
just pure freedom.



**HIX Style** is all about helping developers get on the same page. By using HIX Style, 
sharing code, contributing to other projects, and building scalable solutions becomes second nature 
no more friction from learning a new structure with every repo. The main goal here is to offer a 
common path that works for everyone.

--- 

## 📘 Documentation

Full documentation is available at: https://carles9000.github.io/hix/ 

---

### ✏️ Notes 


- The first version of HIX is completely incompatible with the current version because everything 
has been refactored. If you wish to download it, you can find it in this repository 
https://github.com/carles9000/hix.legacy 

- You can download Harbour binaries from here 
https://github.com/carles9000/hix.harbour 

- The examples include scripts for building them on: 

   - GCC (Linux)
   - MSVC64 (Windows)  
   - MINGW64 (Windows)  

---

## 🐧 Linux Quick Start & Considerations

### 1. Build the HIX Server Library
```bash
./go_lib_linux.sh
```

### 2. Build and Run Examples
Each example in `examples/` includes a dedicated `go_linux.sh` script:
```bash
cd examples/web/hi
./go_linux.sh --run
```

### 3. Unit Test Master
To build and start the interactive web test runner:
```bash
cd tests/unit
# Generate local SSL test certificates (first time only)
./make_test_cert.sh

# Run test dashboard (http://localhost:8900/)
./go_linux.sh --server

# Or run tests in headless CLI mode
./go_linux.sh --cli
```

### ⚠️ Important Considerations for Desktop / Domestic Users
* **Port Selection (`hix.json`):** In Linux, ports `< 1024` (such as default HTTP port `80`) require administrative (`root`/`sudo`) privileges and frequently conflict with pre-installed web servers (Apache, Nginx). It is recommended to use non-privileged ports such as `8080`, `8081`, `8082`, etc.
* **Execution Permissions:** Ensure build scripts have execution permissions with `chmod +x *.sh`.
* **Harbour Path:** If Harbour is not installed globally in `/usr/local/bin`, the scripts automatically look in `$HOME/harbour-core` or the `$HB_DIR` environment variable.

