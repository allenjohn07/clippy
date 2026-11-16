# Security

Clippy reads everything you copy, so security matters.

## Reporting a problem

Please **don't open a public issue** for security problems. Report them privately instead:
**Security tab → Report a vulnerability** on https://github.com/allenjohn07/clippy.

## What's checked automatically

- **CodeQL** scans the Swift app, the JavaScript test code and the GitHub workflows on every push, on pull requests, and weekly.
- **Secret scanning with push protection** stops passwords, tokens and keys from being pushed to the repo.
- **Dependabot** watches dependencies and the GitHub Actions used in the workflows.

## How Clippy protects your data

- History is stored only on your Mac (`~/Library/Application Support/clippy/`), readable only by your user account.
- Copies that look like passwords or keys, copies marked private by password managers, and anything copied in a password manager app are never saved.
- The only network use: when you copy a YouTube link, Clippy fetches that video's thumbnail and title from YouTube (no cookies, nothing else sent).
