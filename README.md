# Notes

A native Markdown notebook for GNOME, written in Vala with GTK 4 and libadwaita.
Markdown is parsed and rendered by the app itself into native widgets: no web
engine and no HTML library.

## Build and run

```sh
meson setup build
ninja -C build
./build/src/gnome-markdown            # opens your notes library
./build/src/gnome-markdown file.md    # opens a specific file
```

To add it to your app grid (installs to `~/.local`):

```sh
meson setup build --prefix=$HOME/.local --reconfigure
ninja -C build install
```

## How notes are stored

Notes are plain `.md` files in `~/Documents/Notes` (you can pick another folder from the menu).

- Subfolders of that folder are the sidebar **Folders** (one level deep).
- **Trash** is the hidden `.trash` folder inside it.
- Favorites and window state live in `~/.config/org.example.Notes/state.ini`.

Changes are saved automatically shortly after you stop typing, and when you switch
notes or close the window. This also applies to files opened from outside the
library. A new note named `Untitled` is renamed after its first line when you
leave it.

## Markdown support

CommonMark plus the GitHub extensions:

- Headings, emphasis, links (including reference links), images, block quotes, lists and code
- Tables with alignment, task lists (clickable in View mode), strikethrough, bare URLs

A paragraph written directly under the first `#` title, with no blank line in
between, is shown as a subtitle.

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
| `src/note-store.vala` | The notes folder, trash, favorites, file monitoring |
| `src/editor.vala` | Source editor with list continuation and shortcuts |
| `src/app.css` | Styling |

The app ID `org.example.Notes` is a placeholder. Change `app_id` and `resource_path` in
`meson.build`, the prefix in `src/notes.gresource.xml`, the template path in
`src/window.vala`, and the icon file name before publishing.
