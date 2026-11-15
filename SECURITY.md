# Security Policy

M3U TV signs in to your M3U Editor or Xtream server and stores those logins on your devices. We take security reports seriously and treat them as our top priority.

## Reporting a vulnerability

**Please don't report security problems in public issues, discussions, or public Discord channels.**

Report them privately through GitHub:

1. Go to the [Security tab](https://github.com/m3ue/m3u-tv/security) of this repository.
2. Click **Report a vulnerability**.
3. Fill in the form. Only the maintainers can see it.

Or send a direct message to **shparkison** on [Discord](https://discord.gg/rS3abJ5dz7). Please don't post it in a channel, even to ask who to talk to.

Please include:

- what the problem is and what an attacker could do with it,
- the M3U TV version (shown in **Settings**), the platform (Android TV, Apple TV, iOS, Android, Windows, macOS, Linux, web), and where you installed it from,
- steps to reproduce, or a proof of concept.

If the problem is on the server side, such as an M3U Editor API that the app calls, please report it on the [M3U Editor repository](https://github.com/m3ue/m3u-editor/security) instead.

## What happens next

- We'll acknowledge your report within **3 days**.
- We'll confirm whether it's a vulnerability, and keep you updated while we work on a fix.
- Serious problems get a fix and a release as quickly as we can. App store releases depend on store review, so updates can take a few extra days to reach every platform.
- Once a fixed release is out, we publish a [GitHub security advisory](https://github.com/m3ue/m3u-tv/security/advisories) and explain what to update and why in the release notes and on the [blog](https://m3ue.sparkison.dev/blog).
- We'll credit you in the advisory, unless you'd rather we didn't.

Please give us a reasonable chance to release a fix before you disclose the problem publicly.

## Supported versions

Security fixes go into the next release. We don't backport fixes to older versions, so please keep the app up to date.

| Version | Supported |
| ------- | --------- |
| Latest release | ✅ |
| Older releases | ❌ |

## Scope

In scope:

- the M3U TV app on every platform it's published for
- how the app stores and sends logins, tokens, and other data
- anything that lets another app, website, or device on your network read your logins or control the app without your permission

Out of scope:

- problems that need physical access to an unlocked device, or a rooted or jailbroken one
- vulnerabilities in your IPTV provider or media server
- vulnerabilities in the operating system, or in mpv, ExoPlayer, or other upstream players that are already public
- unofficial builds or modified copies of the app

Not sure if something is in scope? Report it anyway, and we'll work it out together.
