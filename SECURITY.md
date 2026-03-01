# Security Policy

## Reporting a Vulnerability

If you discover a security issue in this project, please do **not** open a public issue first.

Please report responsibly by contacting the maintainer privately, including:
- A clear description of the issue
- Steps to reproduce
- Potential impact
- Suggested fix (if available)

We will acknowledge the report as soon as possible and work on a fix.

## Scope

This project is a read-only monitoring script for RAID/disk health checks.
Security-sensitive areas include:
- Command execution paths
- Email/reporting pathways
- Handling of local state files
- Any future integrations with external services

## Hardening Notes

- Keep runtime privileges minimal
- Restrict `STATE_DIR` permissions
- Avoid storing secrets in repository
- Use environment variables for deployment-specific settings
