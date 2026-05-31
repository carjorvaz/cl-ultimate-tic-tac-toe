# Product

Last reviewed: 2026-05-30

## App Contract

The scaffold app renders a small, useful home page that proves the server,
stylesheets, static assets, and validation harness are connected.

## User Experience

- `/` shows the app title, summary, and links to health/version endpoints.
- `/health` returns a plain `ok` readiness response.
- `/version` returns the configured version string.
- The footer links to the configured source URL.
