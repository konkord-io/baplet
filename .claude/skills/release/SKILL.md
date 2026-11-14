---
name: release
description: Cut a Baplet release: tag, build the DMG in CI, write What's new, publish, verify the download.
disable-model-invocation: true
---

# Release Baplet

Tagging and publishing are public and permanent: published version numbers are never reused. Confirm the version with the user before tagging, and publish only on their explicit go. Read CLAUDE.md's "Releases" section first; its rules are what the in-app updater depends on.

## 1. Preflight

- `main` is checked out, pulled, and `git status` is clean.
- The latest CI run on `main` passed: `gh run list --branch main --workflow CI --limit 1`. If it's still running, wait with `gh run watch`.
- Find the previous tag (`git tag --sort=-v:refname | head -1`) and the app changes since then: `git log --oneline --no-merges <prev>..main -- baplet bapletTests`.
- Propose the next version to the user (semver: patch for fixes, minor for features) and get a yes.

Done when: the user has confirmed `vX.Y.Z`, and CI on the commit being tagged is green.

## 2. Build

- `git tag vX.Y.Z && git push origin vX.Y.Z`
- Watch the Release workflow: `gh run list --workflow Release --limit 1`, then `gh run watch <id> --exit-status`. It runs the tests, `make dmg`, and creates a **draft** release.

Done when: `gh release view vX.Y.Z --json isDraft,assets` shows a draft with exactly `Baplet-X.Y.Z.dmg` and `Baplet.dmg`, both with a `sha256:` digest, and the two digests are equal.

## 3. What's new

- Turn the app commits from step 1 into short user-facing bullets: what users notice, not internals.
- Replace the `## What's new` placeholder in the draft (`gh release view vX.Y.Z --json body -q .body`, edit, then `gh release edit vX.Y.Z --notes-file <file>`). Keep the Installing section. The update window shows these notes to users.
- Show the notes to the user.

Done when: the draft body has no placeholder line left.

## 4. Publish

- The user downloads `Baplet-X.Y.Z.dmg` from the draft and tries it, or tells you to skip that.
- On their go, they press Publish, or you run `gh release edit vX.Y.Z --draft=false --latest`.

Done when: `gh release list --limit 1` shows `vX.Y.Z` as Latest.

## 5. Verify

- `curl -s https://api.github.com/repos/konkord-io/baplet/releases/latest` reports `tag_name` `vX.Y.Z` with a `Baplet.dmg` asset (this is what the updater reads).
- `curl -sL https://github.com/konkord-io/baplet/releases/latest/download/Baplet.dmg` downloads, and its `shasum -a 256` equals the published digest.
- Run CLAUDE.md's "Website and README" drift check, so the site still matches the app.
- If the release changed the updater itself, ask the user to update an installed copy in `/Applications` via Settings → About → Check for Updates and confirm the new version.

Done when: the API's latest tag, the download's SHA-256 and the published digest all match `vX.Y.Z`. Report them to the user.
