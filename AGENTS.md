# Agent guide

Markdown Viewer is a GNOME Markdown reader and editor written in Vala with GTK 4, libadwaita and
GtkSourceView. See the README for what it does and how the code is organized.

## Build and test

```sh
meson setup build          # once
ninja -C build             # build
meson test -C build        # validate the desktop file and AppStream metadata
./build/src/gnome-markdown # run
```

The Flatpak manifest is `build-aux/flatpak/io.github.jefersondaniel.MarkdownViewer.json`.
It targets the GNOME 51 runtime, while local development uses the distribution's GTK
and libadwaita (GTK 4.16, libadwaita 1.6). Don't use API newer than those versions.

## Project rules

- Markdown is parsed and rendered by the code in `src/markdown/` into native GTK
  widgets. Don't add WebKit, an HTML renderer or a Markdown library.
- Inline HTML is limited to the subset listed in the README. Other tags are dropped,
  but their text is kept.
- Follow the GNOME Human Interface Guidelines and libadwaita patterns. Don't add
  styling or wording borrowed from other platforms.
- Mermaid diagrams are drawn by the library in `subprojects/mermaid-gtk/`, which is
  kept ready to move to its own repository. It must not use anything from the app's
  `src/`, and the app uses only its public API (`Mermaid.parse`, `Mermaid.View`).
  Its supported syntax is tracked in `subprojects/mermaid-gtk/FEATURES.md`: update
  that list and add a test case under `tests/cases/` with every change. Use the
  `mermaid` commit scope for it.
- The window layout lives in Blueprint files (`src/*.blp`). Styling of rendered
  Markdown lives in `src/app.css`.

## Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org/). Releases
are automatic: [release-please](https://github.com/googleapis/release-please) reads the
commit messages on `main` to pick the next version and write the changelog, so the
message format matters.

```
<type>(<optional scope>): <description>

<optional body>

<optional footers>
```

**Types**, and what they do to the next release:

| Type | Use it for | Release |
|:--|:--|:--|
| `feat` | A new feature or user-visible improvement | Minor version bump, listed under Features |
| `fix` | A bug fix | Patch version bump, listed under Bug Fixes |
| `perf` | A performance improvement | Patch version bump |
| `docs` | Documentation only | None |
| `style` | Formatting, no behavior change | None |
| `refactor` | Code changes that neither fix a bug nor add a feature | None |
| `test` | Tests | None |
| `build` | The build system, dependencies or the Flatpak manifest | None |
| `ci` | GitHub Actions workflows | None |
| `chore` | Anything else that doesn't affect the app | None |

**Breaking changes:** add `!` after the type (`feat!: ...`) or a `BREAKING CHANGE:`
footer. While the version is below 1.0.0 this bumps the minor version, and from 1.0.0
on it bumps the major version.

**Scopes** are optional and name the area that changed, for example `parser`,
`renderer`, `editor`, `sidebar`, `window`, `flatpak` or `ci`.

Rules:

- Write the description in the imperative mood, start it in lowercase, and don't end
  it with a period: `fix(parser): keep list items separate after a blank line`.
- Keep the first line under 72 characters.
- `feat` and `fix` descriptions end up in the changelog, so write them for people who
  use the app, not for people who read the code.
- Use the body to explain why the change was made when that isn't obvious.
- Make one logical change per commit. Split unrelated changes into separate commits.
- To release a specific version, add a `Release-As: 1.0.0` footer.

## Releasing

Don't edit `version.txt` or `CHANGELOG.md` by hand, and don't create tags. On every
push to `main`, release-please opens or updates a release pull request. Merging it
tags the release, publishes it on GitHub, and the release workflow builds the Flatpak
and attaches it.
