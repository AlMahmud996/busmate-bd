# API conventions

Status: APPROVED on 2026-11-23. Applies to every service. Based on SRS v0.5 and diagrams 03, 04, 07, 10 and 11.

Legend: [SRS] is a confirmed requirement. [REC] is a recommendation, not in the SRS. Decisions are in section 11.

## 1. Basics

- Base path `/api/v1/...` for everything the gateway exposes (SC-7). Internal endpoints use `/internal/v1/...` and are never routed by the gateway (diagram 10).
- JSON only, UTF-8, `Content-Type: application/json`.
- Field names are `snake_case`, the same as database columns and Kafka payloads.
- Paths are nouns in plural form. Actions that are not plain create, read, update or delete use a verb sub-path, for example `POST /bookings/{id}/pay`.
- Contracts are written here first. The OpenAPI document generated from the code by springdoc is compared against them, and any difference is a bug in one of the two.

## 2. Value formats

| Kind | Format | Example |
|---|---|---|
| Identifier | UUID string | `"2f6b1c0e-5a3d-4e0b-9c1a-7d8e4f1b2a33"` |
| Timestamp | ISO 8601, UTC, with `Z` | `"2026-11-23T10:15:30Z"` |
| Money amount | Decimal string, two places, plus a currency field | `"1250.00"` and `"BDT"` |
| Enum | UPPER_SNAKE_CASE string | `"PENDING_PAYMENT"` |
| Phone number | E.164, Bangladesh mobile | `"+8801712345678"` |
| Boolean | `true` or `false` | |

Money is a string so that no client turns it into a floating point number [REC, AC-1]. A client may send a local number such as `01712345678`. The server stores and returns the E.164 form.

## 3. Headers

| Header | Direction | Meaning |
|---|---|---|
| `Authorization: Bearer <jwt>` | request | The access token on every call except the public paths. |
| `X-Correlation-Id` | request, response | The gateway creates it if absent. Every service returns it and logs it [SRS NFR-15]. |
| `Retry-After` | response | Seconds to wait, on 429 and 503. |
| `Cache-Control: no-store` | response | On every response with tokens or personal data. |

## 4. Authentication

- The access token is a JWT signed with RS256. Only User Service holds the private key. The gateway and every service verify it with the public key from `GET /api/v1/auth/jwks.json`.
- It lasts 15 minutes. Claims: `iss` (`busmate-bd`), `sub` (user id), `role` (`PASSENGER`, `OPERATOR` or `DRIVER`), `name`, `iat`, `exp`, `jti`. The `kid` header names the signing key.
- No phone number, email or gender goes into the token.
- The gateway checks signature, expiry and role for the path. The service checks the rest, such as "this booking belongs to this passenger" (diagram 04).
- The refresh token is an opaque value held in a cookie, never in JavaScript (details in the User Service contract).
- Public paths, with no token: register, login, refresh, JWKS, and `/api/v1/tracking/public/**`, which uses a tracking token instead.

## 5. Errors

Every error uses the problem details format (RFC 9457), `Content-Type: application/problem+json`:

```json
{
  "type": "about:blank",
  "title": "Validation failed",
  "status": 422,
  "detail": "One or more fields are invalid.",
  "code": "VALIDATION_FAILED",
  "correlation_id": "6c1e2f40-8b53-4a77-b1d2-0a9e6f3c11aa",
  "errors": [
    { "field": "phone", "message": "must be a Bangladesh mobile number" }
  ]
}
```

`code` is for programs and never changes once published. `title` and `detail` are for people and may change. `errors` appears only for validation. Messages never contain stack traces, SQL, or personal data.

| Status | Use |
|---|---|
| 200, 201, 204 | Success. 201 for a created resource, with the resource in the body. 204 for no body. |
| 202 | Accepted, the result comes later (for example paying). |
| 400 | The request cannot be read: broken JSON, wrong type. |
| 401 | No token, a bad token, or an expired token. |
| 403 | A valid token with the wrong role. |
| 404 | Not found, and also "exists but is not yours", so nothing leaks. |
| 409 | A conflict with the current state: duplicate, seat unavailable, wrong status. |
| 422 | The request is readable but breaks a rule (see `errors`). |
| 429 | Rate limit. Always with `Retry-After`. |
| 503 | A dependency is down. Always with `Retry-After`. |

Codes used by more than one service: `VALIDATION_FAILED`, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `RATE_LIMITED`, `DEPENDENCY_UNAVAILABLE`, `INTERNAL_ERROR`. Each service adds its own, listed in its contract.

## 6. Lists and pagination

Lists use `?page=0&size=20`. `size` is at most 100.

```json
{
  "items": [ ],
  "page": 0,
  "size": 20,
  "total_items": 53,
  "total_pages": 3
}
```

An empty list is a 200 with `"items": []`, not a 404.

## 7. Retries and idempotency

- GET, PUT and DELETE are safe to repeat. Clients may retry GET automatically.
- POST is not retried automatically. Where a repeat must be harmless, the request carries a client-chosen id in the body: `client_request_id` on creating a hold (diagram 07).
- Results that arrive later, such as payment, are read by polling `GET /bookings/{id}` (diagram 07, SQ-1).

## 8. Rate limits

The gateway returns 429 with `Retry-After` when a limit is hit. Starting values (SC-4): login 5 per minute per IP, creating a hold 10 per minute per user, everything else 120 per minute per user.

## 9. CORS

The gateway allows only the origins in an environment variable (the three frontends), with credentials, because the refresh token is a cookie. Methods GET, POST, PUT, PATCH, DELETE. Allowed headers `Authorization`, `Content-Type`, `X-Correlation-Id`. Exposed header `X-Correlation-Id`.

## 10. Privacy rules for every response

- Never include another user's name, phone number, email or gender. The seat map shows only an icon on confirmed seats [SRS BR-13].
- A request for a resource that is not yours returns 404, not 403.
- Logs never contain passwords, tokens, tracking tokens, phone numbers or passenger names [SRS NFR-6].

## 11. Decisions taken on 2026-11-23, all accepted as recommended

| ID | Question | Decision |
|---|---|---|
| AC-1 | Money as a string or a JSON number? | String, with a separate currency field. |
| AC-2 | Error format: RFC 9457 problem details or a custom shape? | RFC 9457. Spring Boot supports it natively. |
| AC-3 | 422 or 400 for a validation failure? | 422 for readable requests that break a rule, 400 only for unreadable ones. |
| AC-4 | Page-and-size pagination, or cursors? | Page and size. Simple, and the lists here are small. |
| AC-5 | `snake_case` or `camelCase` in JSON? | `snake_case`, to match the database and the Kafka events. Spring needs one setting for it. |
| AC-6 | Contracts in Markdown first, or OpenAPI YAML first? | Markdown first. It is easier to review, and OpenAPI is generated from code and compared. |
