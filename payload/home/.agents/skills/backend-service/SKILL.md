---
name: backend-service
description: "Design and harden Node/Python APIs, persistence, databases, and external-service failure handling. Use for endpoints, retries, OAuth, pools, MySQL/SQLite/Redis, or error contracts."
when-to-use: "Use when adding or modifying API endpoints, handling timeout/cancellation/idempotency, designing error responses, accessing MySQL/SQLite/Redis, integrating external services, or investigating service behavior on failure paths. Do not use when the task is frontend UI, pure CLI tool, TUI, or only running an existing service."
---

# Backend Service

Backend defects concentrate on failure paths, not happy paths. This skill provides criteria for interface contracts, persistence, and external calls; implementation details follow the project's existing conventions.

## Confirm the Landscape First

Before making changes, read three things; do not introduce frameworks the project doesn't use:

1. **What is the HTTP layer.** A local project using `node:http`'s `createServer` + manual routing is not Express. Add endpoints following the same dispatch structure.
2. **What is the persistence.** mysql2 connection pools, SQLite, JSON files, or in-memory Maps each have different consistency costs.
3. **Where is auth decided.** Find the actual auth function before modifying it; don't invent a new one.

## Interface Contracts

- Each endpoint specifies: method, path, required/optional parameters, success response shape, and status codes for each failure class.
- Input validation happens before business logic: type, range, enum, length caps. Distinguish missing from invalid (400 vs 422 per project convention).
- Error responses maintain a consistent shape so callers can process them programmatically. Do not return internal exception messages, stack traces, SQL, or file paths directly to clients.
- Breaking changes need migration consideration: new fields are optional, old parameters are kept through a transition period, response fields only add, never change semantics.

## Auth and Exposure Surface

Services that open a listening port must explicitly state their auth status, even if the user doesn't ask.

Anti-pattern:

```js
if (!APP_AUTH_USER || !APP_AUTH_PASSWORD) return true;  // missing env = wide open
```

When environment variables are missing, defaulting to open access means a deployment oversight becomes an unauthenticated service. The correct approach is to validate required configuration at startup, refusing to start or explicitly entering a restricted local-only mode; never silently permit all access.

Other points:

- Default to binding only `127.0.0.1`; external access requires explicit configuration.
- Use timing-safe comparison (`timingSafeEqual`) for passwords and tokens; compare length first, then content.
- Credentials are only read from environment variables or key files; never written into code, logs, or error responses.

## State and Persistence

- Always use parameterized queries for SQL; never concatenate strings.
- Create connection pools once and reuse (mysql2 `createPool` at module-level lazy init); do not create a new connection per request.
- File state writes must be atomic: write to temp file then `rename`. Direct `fs.writeFileSync` overwrites leave truncated JSON on process crash or concurrent writes — a real risk of data loss.
- When multiple parties modify the same resource, choose a strategy explicitly: serialization, optimistic locking (version numbers), or database transactions. In-memory Map + async disk writes is not safe by default.
- Startup must tolerate corrupted state files: parse failures must take a recoverable path, not prevent the service from starting.

## External Calls

When integrating third-party APIs (axios, IMAP, OAuth endpoints), address each item:

- **Timeout**: Set for every request; no default infinite wait.
- **Cancellation**: Long-running tasks accept `AbortController`; stop background work when the client disconnects.
- **Retry**: Only retry idempotent operations on retryable errors (timeout, 5xx, connection reset) with exponential backoff and jitter; 4xx are not retried.
- **Idempotency**: Creation operations carry an idempotency key to prevent duplicate side effects from retries.
- **Resource release**: IMAP/database connections are closed in `finally`; failure paths must also reach cleanup.
- **Rate limiting and quotas**: Track and respect upstream 429 and `Retry-After`.

Treat external responses as untrusted input: validate structure before use; do not spread directly into business objects.

## Observability

- Log levels; error logs include enough location info (request id, endpoint, failure reason) but never credentials, tokens, cookies, or full request bodies.
- Logs have caps or rotation; no unbounded arrays resident in memory.
- Failures are either handled or logged; empty `catch` blocks that swallow errors are not allowed.

## Verification

After changes, select based on risk and state what was actually run:

- Endpoint changes: normal request + missing params + invalid params + unauthorized; confirm status codes and response shape for each.
- Persistence changes: write-then-restart-read, concurrent writes, corrupted file recovery.
- External integration: timeout, upstream 5xx, connection drop — at least one of each (use fake implementations to inject).
- After dependency changes, run `npm audit`; report findings without self-downgrading versions.

For how to organize tests and ensure they can fail, use `testing-strategy`.
