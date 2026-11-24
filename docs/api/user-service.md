# User Service API contract

Status: APPROVED on 2026-11-23. Based on SRS v0.5, diagrams 05 v2 and 10, and the API conventions (docs/api/conventions.md).

Legend: [SRS] is a confirmed requirement. [REC] is a recommendation, not in the SRS. Decisions are in section 9.

## 1. Scope

User Service owns accounts, login, tokens and driver accounts [SRS FR-P1, FR-O9, FR-D1]. It uses two tables, `users` and `refresh_tokens` (diagram 05 section 5.1). It calls no other service. Trip Service calls it once, to check a driver (section 6).

Operator accounts are created by a seed script, not by an endpoint [SRS section 2].

## 2. Tokens

| Token | Form | Lifetime | Where it lives |
|---|---|---|---|
| Access token | JWT, RS256, claims as in the conventions (section 4) | 15 minutes | In the JavaScript memory of the app. Never in local storage. |
| Refresh token | 256 random bits, base64url, opaque | 7 days [REC] | In an `HttpOnly`, `Secure`, `SameSite=Strict` cookie named `refresh_token`, path `/api/v1/auth`. Stored in the database only as a SHA-256 hash. |

Rules:

- Refresh tokens rotate. Each refresh revokes the old one and issues a new one.
- If a revoked refresh token is presented again, it is treated as a theft. All refresh tokens of that user are revoked, and the caller gets 401.
- Logging out revokes that refresh token. Changing the password revokes all of them.
- Signing keys carry a `kid`. The JWKS endpoint can publish two keys at once, so a key can be replaced without logging everybody out.
- On localhost the browser sends the cookie across ports. In production the apps and the gateway need to share a site for `SameSite=Strict` to work.

## 3. Endpoints

All paths start with `/api/v1`. "Public" means no access token.

| Method and path | Who | Purpose | Success |
|---|---|---|---|
| `POST /auth/register` | Public | Create a passenger account [SRS FR-P1] | 201 |
| `POST /auth/login` | Public | Get an access token and a refresh cookie | 200 |
| `POST /auth/refresh` | Public, needs the cookie | Rotate the refresh token, get a new access token | 200 |
| `POST /auth/logout` | Public, needs the cookie | Revoke the refresh token | 204 |
| `GET /auth/jwks.json` | Public | The public keys that verify access tokens | 200 |
| `GET /users/me` | Any logged-in user | Own profile | 200 |
| `PATCH /users/me` | Any logged-in user | Change the name | 200 |
| `POST /users/me/password` | Any logged-in user | Change the password | 204 |
| `POST /users/drivers` | Operator | Create a driver account [SRS FR-O9] | 201 |
| `GET /users/drivers` | Operator | List own drivers | 200 |
| `PATCH /users/drivers/{id}` | Operator | Change a driver's name or status | 200 |

Internal, not reachable through the gateway: `GET /internal/v1/drivers/{id}/validate` (section 6).

## 4. Details

### POST /auth/register

Request:

```json
{
  "full_name": "Rahim Uddin",
  "phone": "01712345678",
  "email": "rahim@example.com",
  "password": "a long passphrase"
}
```

At least one of `phone` and `email` is required [SRS FR-P1]. The role is always PASSENGER. The caller cannot choose it.

Response 201:

```json
{
  "id": "2f6b1c0e-5a3d-4e0b-9c1a-7d8e4f1b2a33",
  "role": "PASSENGER",
  "full_name": "Rahim Uddin",
  "phone": "+8801712345678",
  "email": "rahim@example.com",
  "status": "ACTIVE",
  "created_at": "2026-11-23T10:15:30Z"
}
```

Errors: 422 `VALIDATION_FAILED`, 409 `ACCOUNT_EXISTS` (the phone or the email is already used). No tokens are returned. The app calls login next (UC-2).

### POST /auth/login

Request:

```json
{ "identifier": "01712345678", "password": "a long passphrase" }
```

`identifier` is a phone number or an email. Response 200, plus a `Set-Cookie` header for the refresh token:

```json
{
  "access_token": "eyJhbGciOi...",
  "token_type": "Bearer",
  "expires_in": 900,
  "user": { "id": "2f6b1c0e-5a3d-4e0b-9c1a-7d8e4f1b2a33", "role": "PASSENGER", "full_name": "Rahim Uddin" }
}
```

Errors: 401 `INVALID_CREDENTIALS`. It is the same answer for an unknown identifier, a wrong password and a disabled account, so the response does not tell anyone which accounts exist. 429 `RATE_LIMITED` from the gateway.

### POST /auth/refresh

No body. The cookie carries the token. Response 200 with a new `access_token` and `expires_in`, and a new cookie. Errors: 401 `REFRESH_INVALID` (missing, expired, revoked or reused).

### POST /auth/logout

No body. Response 204. It always succeeds, even if the cookie is missing, and it clears the cookie.

### GET /auth/jwks.json

Standard JWKS with `kid`, `kty`, `alg`, `use`, `n`, `e` for each active key. The gateway and the services cache it and re-fetch it when they meet an unknown `kid`.

### GET /users/me and PATCH /users/me

Response is the same shape as the register response. `PATCH` accepts `{ "full_name": "..." }`. Phone and email cannot be changed in v1, because there is no way to verify a new one (UC-5).

### POST /users/me/password

```json
{ "current_password": "...", "new_password": "..." }
```

Response 204. Revokes all refresh tokens of the user. The current access token keeps working until it expires. Errors: 401 `INVALID_CREDENTIALS` if the current password is wrong, 422 for a weak new one.

### POST /users/drivers (operator)

```json
{ "full_name": "Karim Mia", "phone": "01812345678", "password": "initial password" }
```

Creates a DRIVER account with `created_by_user_id` set to the calling operator. Response 201 with the driver (id, role, full_name, phone, status, created_at). The operator gives the initial password to the driver. Errors: 403 `FORBIDDEN` for non-operators, 409 `ACCOUNT_EXISTS`, 422.

### GET /users/drivers (operator)

A page of the operator's own drivers, as in the conventions. Query: `page`, `size`, optional `status`.

### PATCH /users/drivers/{id} (operator)

```json
{ "full_name": "Karim Mia", "status": "DISABLED" }
```

Both fields are optional. Disabling a driver also revokes that driver's refresh tokens. A driver that does not belong to the caller gives 404.

## 5. Validation rules

| Field | Rule |
|---|---|
| `full_name` | 2 to 100 characters, trimmed. |
| `phone` | A Bangladesh mobile number: `01XXXXXXXXX` (11 digits, second part 3 to 9), or `+8801XXXXXXXXX`, or `8801XXXXXXXXX`. Stored as `+8801XXXXXXXXX`. |
| `email` | A valid address, lower-cased, at most 254 characters. |
| `password` | 8 to 72 characters. No composition rules, but it must not be the phone, the email or a very common password (UC-4). The limit of 72 is a BCrypt limit. |
| `status` | `ACTIVE` or `DISABLED`. |

## 6. Internal endpoint for Trip Service

`GET /internal/v1/drivers/{driver_id}/validate?operator_user_id={operator_user_id}`

Called by Trip Service when an operator assigns a driver to a trip (diagram 10, Q6 from diagram 05). The call has a 1 second timeout and no retry.

```json
{ "valid": true }
```

`valid` is true only if the user exists, has the role DRIVER, is ACTIVE, and was created by that operator. Otherwise `{ "valid": false }`. It never returns a name or any personal data.

## 7. Security notes

- Passwords are hashed with BCrypt at cost 12 (UC-1). The password is never logged and never returned.
- Login answers take about the same time for an unknown account as for a wrong password, so timing does not reveal which accounts exist.
- A user who is DISABLED cannot log in or refresh. Existing access tokens work until they expire, at most 15 minutes.
- Register and login are rate limited at the gateway [conventions section 8].
- The seed script creates operator accounts with a generated password that is printed once and must be changed.

## 8. Errors specific to this service

| Code | Status | When |
|---|---|---|
| `ACCOUNT_EXISTS` | 409 | The phone or the email is already registered. |
| `INVALID_CREDENTIALS` | 401 | Login failed, or the current password is wrong. |
| `REFRESH_INVALID` | 401 | The refresh token is missing, expired, revoked or reused. |

Registering shows that an account exists. That is a known trade-off, because a passenger needs to be told why registration failed (UC-3).

## 9. Decisions taken on 2026-11-23, all accepted as recommended

| ID | Question | Decision |
|---|---|---|
| UC-1 | Password hashing: BCrypt or Argon2id? | BCrypt cost 12. It is in Spring Security with no extra library. Argon2id needs a Bouncy Castle dependency. |
| UC-2 | Does register log the user in? | No. Register returns the user, then the app calls login. It keeps each endpoint simple. |
| UC-3 | Tell a registering user that the phone or email exists (409)? | Yes. The alternative hides it but leaves the user confused. Login stays generic. |
| UC-4 | Check new passwords against a list of common passwords? | Yes, a small built-in list of the most common few thousand. |
| UC-5 | Can phone or email be changed? | Not in v1. There is no verification by SMS or email. |
| UC-6 | Refresh token in a cookie, or in the response body? | Cookie, `HttpOnly`, so a script cannot steal it. |
| UC-7 | Refresh token lifetime. | 7 days, rotating, with theft detection as in section 2. |
| UC-8 | Does a driver have to change the initial password? | Not enforced in v1. Mention it in the driver app later. |
| UC-9 | Lock an account after repeated failed logins? | No lock in v1. The gateway rate limit slows guessing. A lock would let someone block a victim's account on purpose. |
