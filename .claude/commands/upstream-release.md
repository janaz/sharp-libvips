---
description: Merge upstream changes and release a new @revizly npm version
---

## Context

- Current branch: !`git branch --show-current`
- Commits in upstream/main not yet in revizlify: !`git fetch upstream && git log --oneline upstream/main ^revizlify`
- Current npm version: !`cat npm/linux-x64/package.json | grep '"version"'`
- Latest revizly tag: !`git tag --list | sort -V | tail -1`

## Your task

Perform the full upstream merge and release cycle for this fork:

### 1. Merge upstream

Run `git merge upstream/main` and resolve conflicts following these rules:

- **modify/delete conflicts** (platforms removed in revizlify): always `git rm` the file — keep them deleted.
- **versions.properties**: take upstream's version bumps AND keep `VERSION_DE265` line.
- **npm/linux-x64/package.json**, **npm/linux-arm64/package.json**, **npm/dev/package.json**, **npm/package.json**: keep the `@revizly` name and current revizly version (do NOT take upstream's `@img` name or their version number).
- **build/posix.sh**, **check-latest-versions.sh**, **populate-npm-workspace.sh**, **.github/workflows/ci.yml**: take upstream's changes (they won't conflict with our de265 additions).

After resolving all conflicts, `git add` the resolved files and `git commit` to complete the merge.

### 2. Bump npm version

Read the current version from `npm/linux-x64/package.json`. Increment the patch number by 1 (e.g. `1.0.29` → `1.0.30`).

Update the version in all four package.json files:
- `npm/package.json`
- `npm/linux-x64/package.json`
- `npm/linux-arm64/package.json`
- `npm/dev/package.json`

Commit: `bump npm versions`

### 3. Push and tag

```
git push origin revizlify
```

Determine the new tag: read `VERSION_VIPS` from `versions.properties`, find the latest existing tag matching `v{VERSION_VIPS}-revizlyN`, and increment N by 1 (or start at 1 if none exist).

```
git tag v{VERSION_VIPS}-revizly{N}
git push origin v{VERSION_VIPS}-revizly{N}
```

### 4. Monitor CI

Use `/loop 3m` to poll `https://api.github.com/repos/janaz/sharp-libvips/actions/runs?per_page=3` until a run appears for the new tag. Then poll its jobs endpoint until all jobs complete.

- If all jobs succeed: report success. The npm packages are published automatically by CI.
- If any job fails: report which job and step failed, then stop.
