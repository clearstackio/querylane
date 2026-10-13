# Security policy

## Reporting a vulnerability

Report it privately through
[GitHub's private vulnerability reporting](https://github.com/clearstackio/querylane/security/advisories/new),
or email ajaya@clearstack.io. Please do not open a public issue.

We aim to acknowledge a report within three working days, and to publish a
fix and a GitHub security advisory once it is confirmed.

Include the querylane version (or commit), how to reproduce the problem, and
what an attacker could see or do.

## Supported versions

querylane is pre-1.0. Only the latest release is supported.

## The privacy model

querylane's guarantees, and the duties it leaves to the host app (building the
scope on the server, filtering a renamed query parameter, keeping request bodies
out of APM), are described in [docs/guides/security.md](docs/guides/security.md).

## Releases

Releases are published to rubygems.org from GitHub Actions with trusted
publishing (no long-lived API key) and carry a Sigstore attestation. Any other
push needs MFA (`rubygems_mfa_required`).
