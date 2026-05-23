# Security Policy

ObviousSaveMD treats Markdown as plain text. It does not render Markdown into HTML, does not use `WKWebView`, and does not fetch remote Markdown resources.

## Supported Versions

This project is pre-release. Security notes apply to the current `main` branch after publication unless a release process is added later.

## Supported Security Checks

When opening a document, the app rejects:

- symlinks
- directories and other non-regular files
- named pipes and other blocking special files
- files larger than the configured read limit
- files containing NUL bytes
- invalid UTF-8

Read and decode work runs off the main actor, and stale open results are ignored if the current document has changed or a newer open request has happened.

## Current Limitations

- The app bundle is not sandboxed.
- Save-side symlink and non-regular-file checks are preflight checks before Foundation's atomic write.
- Very large but valid files under the read limit may still be expensive for AppKit text layout.
- There is not yet a formal private vulnerability disclosure channel for this personal project.

## Reporting

For non-sensitive concerns, open a GitHub issue after the repository is published. Do not post exploit details, private files, or secrets in a public issue. If a private disclosure channel is added later, use that channel for sensitive reports.
