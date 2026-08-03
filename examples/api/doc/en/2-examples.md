# HIX API examples

Two basic examples of building APIs with HIX are available: **function** and **class**.
Both do exactly the same thing, the difference being that one is based on using
individual functions per request type, while the other encapsulates all the logic
in a single file as a class.

Both approaches have their advantages and disadvantages, but perhaps the class-based
approach and its encapsulation offer a clear edge. In addition, the class has the
`new()` and `destroy()` methods that run automatically and allow encapsulated
management of setup tasks that would be very repetitive with plain functions, for
example:

- Initializing the database
- Initializing curl
- Initializing other shared resources
