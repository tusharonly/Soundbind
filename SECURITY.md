# Security policy

## Supported versions

Soundbind is a small side project. Only the latest release receives fixes.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Report it privately through GitHub: go to the repository's **Security** tab and choose **Report a vulnerability**, or use this link:

https://github.com/tusharonly/Soundbind/security/advisories/new

Include what you found, how to reproduce it, and which version of Soundbind and macOS you used. I will reply as soon as I can; this is maintained in spare time, so it may take a few days.

## What Soundbind can access

Knowing the app's limits helps judge a report:

- It runs in the macOS App Sandbox.
- It has no network access and sends no data anywhere.
- It can read only the audio files you choose, which it copies into its own container.
- It registers global keyboard shortcuts without Accessibility permission, so it cannot read your keystrokes.

Releases are ad hoc signed and not notarized by Apple. The Homebrew cask clears the macOS quarantine flag after install, which skips Gatekeeper's check; build from source if you would rather not rely on the published binary.
