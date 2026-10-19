# Markdown Guide
A quick tour of what Notes can show

Open a folder and its Markdown files appear in the sidebar. Pick one to read it, press **Edit** to change it, and it saves by itself as you type.

## Text
You can write **bold**, *italic*, ~~strikethrough~~, `inline code` and [links](https://www.gnome.org). Bare addresses like https://www.gnome.org become links too.

> Block quotes are written with `>` at the start of a line.\
> — The Notes guide

## Lists
- Bullet lists use `-`, `*` or `+`
- Indent items to nest them
  - like this
1. Numbered lists use `1.`
2. and count up on their own

## Tasks
- [x] Write `- [ ]` for an open task
- [x] and `- [x]` for a finished one
- [ ] Tick the boxes in View mode, and the file is updated

## Code
```js
function greet(name) {
  console.log(`Hello, ${name}!`);
}

greet("GNOME");
```

## Tables

| You type | You get |
|:---------|:--------|
| `**bold**` | **bold** |
| `*italic*` | *italic* |
| `~~strike~~` | ~~strike~~ |
| `` `code` `` | `code` |
| `[link](https://www.gnome.org)` | [link](https://www.gnome.org) |

## HTML
A small set of HTML works too: <kbd>Ctrl</kbd>+<kbd>E</kbd> keys, <mark>highlights</mark>, H<sub>2</sub>O, E = mc<sup>2</sup> and <u>underline</u>.

<details>
<summary>Supported tags</summary>

- Inline: `b`, `strong`, `i`, `em`, `u`, `ins`, `s`, `del`, `code`, `kbd`, `mark`, `sub`, `sup`, `small`, `a`, `br`, `img`
- Blocks: `p`, `div`, `center` (with `align`), `h1`–`h6`, `details` with `summary`, `hr`
- Other tags are left out, but the text inside them is kept.

</details>

---

Press <kbd>Ctrl</kbd>+<kbd>?</kbd> to see all keyboard shortcuts.
