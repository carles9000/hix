# What is (and what is not) a good web service

A web service is a communication interface between machines or applications,
typically exposed over HTTP, that allows a client to request data or actions
and receive a structured response, usually in JSON or XML.

The basic example that simply returns `{ "success" => .T. }` is technically
an endpoint that responds with data, but **it is not, by itself, a complete
or "good" web service**. It is only the most superficial layer: the final
response. A real web service needs all the scaffolding surrounding that line
of code: routing, middlewares, validation, authentication, error handling,
and traceability.

## The difference between "returning JSON" and "being a web service"

Returning JSON is the visible result, but a robust web service requires that
before reaching that line, several layers of responsibility have been resolved:

- **Routing**: deciding which code runs based on the HTTP method and the requested URL.
- **Middlewares**: intercepting the request before (or after) it reaches the controller,
  for auditing, CORS, logging, rate limiting, etc.
- **Authentication/authorization**: verifying identity and permissions before executing
  business logic.
- **Data validation**: ensuring that input parameters meet the expected contract
  (types, ranges, formats).
- **Error handling**: catching exceptions and returning consistent responses —
  not just happy paths ("success": true) but also structured failures.
- **Output serialization**: converting internal structures to JSON consistently,
  with correct HTTP status codes.

If any of these layers is missing, the service may "work" in simple tests
but will be fragile, insecure, or unpredictable in production.

## Why the routing and middleware system matters so much

A middleware is a function that runs before (and sometimes after) the request
reaches the business logic, acting as a filter or interceptor.

This "chain of responsibility" pattern is what separates a simple script that
returns JSON from a real server framework, because it allows:

- Reusing cross-cutting logic (logging, security, rate limiting) without
  repeating it in every endpoint.
- Applying different rules per route or group of routes (public vs. protected).
- Keeping business code clean, separated from infrastructure concerns.

## Data validation: the first line of defense

Input data validation is critical because a web service that blindly trusts
what it receives is vulnerable to injections, data corruption, or unexpected
behavior. Before executing any logic, the system must verify types, formats,
lengths, and business rules, returning clear errors and appropriate HTTP codes
(400, 422) when something does not meet the contract.

## Comparison table: simple endpoint vs. robust web service

| Aspect           | Simple function          | Robust web service (HIX style)                    |
|------------------|--------------------------|---------------------------------------------------|
| Routing          | None, fixed response     | Route system with methods, parameters and groups  |
| Middlewares      | Absent                   | Configurable chain (auth, logging, CORS)          |
| Validation       | None                     | Schema validation before executing logic          |
| Security         | None                     | Tokens, CSRF, roles per route                     |
| Error handling   | Undefined                | Structured and consistent responses               |
| Scalability      | Not applicable           | Worker pools, concurrency, connection pooling     |

## How this translates to HIX

A "good" web service is not defined by the simplicity of its response, but by
the discipline of all the layers that precede it. HIX, by implementing its own
routing, middleware, and validation system on top of Harbour, does not just
"return JSON" as in the initial example — it builds the infrastructure that
guarantees that response is secure, predictable, and maintainable under real
load. The combination of strict contract validation with a decoupled middleware
architecture is precisely what allows a server to be both rigorous (rejecting
invalid input early) and powerful (efficiently processing valid input), without
sacrificing reliability.
