# Security rules

Hooks and permissions block `.env` files, credential directories (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config/op`, `~/.config/gh`) and `curl | sh`. These rules cover what hooks cannot.

- API keys, tokens, passwords and connection strings come from environment variables. Never hard-code them in code, tests or docs.
- Shared variable names go in `.env.example` without values; the PO creates and updates it.
- Never print secrets in logs or the conversation. If an error message contains one, redact it in the report.
- Do not send source code, specs or user data to third-party services. Allowed outbound traffic: package registries, GitHub, official documentation. Any other external API needs the PO's approval after explaining what is sent and why.
- Every new dependency is presented to the PO with one line each on purpose, license and maintenance status. Install only from official registries. Only lockfile-preserving installs run automatically; anything that changes the lockfile goes to the PO.
