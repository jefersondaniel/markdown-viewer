# Notes

A native Markdown reader and editor for GNOME, written in Vala with GTK 4 and
libadwaita. Open a folder to browse its Markdown files in the sidebar, then read or
edit them. Markdown is parsed and rendered by the app itself into native widgets:
no web engine and no HTML library.

## Install

Download `markdown-viewer.flatpak` from the
[latest release](https://github.com/jefersondaniel/markdown-viewer/releases/latest) and open it
with GNOME Software, or run:

```sh
flatpak install --user markdown-viewer.flatpak
```

This needs the [Flathub](https://flathub.org/setup) remote, which provides the GNOME runtime.

## Build and run

```sh
meson setup build
ninja -C build
./build/src/gnome-markdown              # reopens the last folder
./build/src/gnome-markdown ~/notes      # opens a folder
./build/src/gnome-markdown file.md      # opens a single file
```

To add it to your app grid (installs to `~/.local`):

```sh
meson setup build --prefix=$HOME/.local --reconfigure
ninja -C build install
```

## How it works

- **Sidebar:** the open folder as a tree of subfolders and Markdown files (`.md`,
  `.markdown`). Hidden files are left out. It updates by itself when files change on disk.
- **Search:** the field at the top of the sidebar finds files by name or content.
- **Right-click:** a file or folder offers Rename, Show in Files and Move to Trash.
  On folders it also offers New Note and New Folder.
- **Trash:** files go to the system trash, with Undo.
- **Saving:** automatic, shortly after you stop typing, and when you switch files or
  close the window.
- **New notes:** they start as `Untitled.md` and are renamed after their first line
  when you leave them.
- **State:** the last folder, the last file and the window state are kept in
  `~/.config/io.github.jefersondaniel.MarkdownViewer/state.ini`.

## Markdown support

CommonMark plus the GitHub extensions:

- Headings, emphasis, links (including reference links), images, block quotes, lists and code
- Tables with alignment, task lists (clickable in View mode), strikethrough, bare URLs

A paragraph written directly under the first `#` title, with no blank line in
between, is shown as a subtitle. The **Markdown Guide** in the main menu shows
everything in action.

### Supported HTML

These inline tags are supported:

- `<b>`, `<strong>`, `<i>`, `<em>`, `<u>`, `<ins>`, `<s>`, `<del>`
- `<code>`, `<kbd>`, `<mark>`, `<sub>`, `<sup>`, `<small>`
- `<a href>`, `<br>`, `<img src alt width>`

These block tags are supported:

- `<p>`, `<div>` and `<center>`, including `align="center|right"`
- `<h1>` to `<h6>`
- `<details>` with `<summary>`
- `<hr>`

HTML comments are hidden. Any other tag is dropped, but the text inside it is kept.

## Code layout

| Path | Purpose |
|:--|:--|
| `src/markdown/parser.vala` | Block parser (lists, quotes, tables, HTML blocks…) |
| `src/markdown/inline-parser.vala` | Emphasis, links, code spans, entities, inline HTML |
| `src/markdown/renderer.vala` | Document tree → GTK widgets |
| `src/window.blp`, `src/window.vala` | Main window (Blueprint layout + logic) |
| `src/widgets/file-tree.vala` | Sidebar folder tree and file search |
| `src/editor.vala` | Source editor with list continuation and shortcuts |
| `src/files.vala` | File name helpers |
| `src/app.css` | Styling of rendered Markdown |

## Releasing

The [Flatpak workflow](.github/workflows/flatpak.yml) builds the app on every push and pull
request. To publish a release:

1. Set the new version in `meson.build`.
2. Add a matching `<release>` entry to `data/app.metainfo.xml.in`.
3. Tag the commit and push the tag:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

The workflow checks that the tag matches both versions, builds the bundle, and attaches
`markdown-viewer.flatpak` to a new GitHub release. The Flatpak manifest is in
`build-aux/flatpak/`.
