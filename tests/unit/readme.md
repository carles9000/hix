# HIX - Unit test

This is a suite for testing the various functionalities of the HIX server. 
This test was built 100% by CC.

- **Linux:**
  - Run `./make_test_cert.sh` to generate self-signed test SSL certificates.
  - Run `./go_linux.sh --server` to start the interactive test dashboard at http://localhost:8900/
  - Run `./go_linux.sh --cli` to run all test suites in headless CLI mode.
- **Windows:**
  - Run `make_test_cert.bat` to generate test certificates.
  - Run `go_msvc64.bat` or `go_mingw64.bat`.
  - Copy DLLs from `/dll` folder if necessary.

--- 

<img width="1385" height="833" alt="test_master" src="https://github.com/user-attachments/assets/55d367f8-45cf-405a-a451-9987afa58d59" />


