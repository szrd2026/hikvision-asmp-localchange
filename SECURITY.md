# Security Policy

## Reporting a vulnerability

Please open a private security advisory on GitHub instead of creating a public
issue. Include the affected version, reproduction steps and the potential
impact. Do not include real `accesstoken` values, serial numbers, customer
records or production logs in the report.

## Credential handling

- `accesstoken` is a short-lived ASMP session credential. Treat it like a
  password.
- This tool keeps the token in memory only. It is never written to
  `localchange_config.json`, and only a masked value appears in logs.
- Do not commit `localchange_config.json`, `hik_token.txt`, `logs/` or
  `*_records.csv`. They are excluded by `.gitignore`.
- If a token is exposed, sign out of ASMP (or wait for expiry) to invalidate
  the session, then copy a new token.

## Local data

Runtime logs contain full API requests and responses, including serial
numbers and customer information. Store them securely and delete them when
they are no longer needed.
