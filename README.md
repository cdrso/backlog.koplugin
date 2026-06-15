# Backlog

**Per-article read tracking for anthology EPUBs in KOReader.**

## The problem

Some EPUBs aren't linear books, they're **collections of standalone, cross-linked essays or articles** (anthologies, blog archives, essay collections) that you read in **any order**, hopping between pieces via links.

KOReader treats the whole file as one book with a single progress bar, which tells you nothing useful here. And when you tap a link to a *referenced* article, there's no way to answer the one question that actually matters:

> **"Wait — have I already read this one?"**

**Backlog** answers it. It treats each **article** as a separate item — grouping them under their sections in magazines that nest articles that way — remembers which ones you've read, shows them all in one list, **dims the in-text links that point to articles you've already read** (like visited web links), and marks them read automatically as you finish — so you always know what's left, no matter how non-linearly you read.

## Screenshots

| | |
|:--:|:--:|
| <img src="screenshots/articles-list.jpg" width="360" alt="Articles list"><br>*Articles list — ▶ current, ✓ read, running count* | <img src="screenshots/menu.jpg" width="360" alt="Backlog menu under Tools"><br>*The Backlog menu, under Tools — incl. the fade-links option* |

## Features

- **Articles list** — every article with its status at a glance: **✓ read**, **▶ currently reading**, or unread, plus a **"N / total read"** counter. Magazines that group articles into sections get a header per section with its own read count.
- **Tap to jump** to any article; **long-press to toggle** its read/unread state. Tap a **section header** to jump to its first article, or long-press it to mark the whole section read.
- **Auto-mark on finish** — an article is marked read when you reach its end (configurable — see [Settings](#settings)).
- **Faded cross-references** — in the text, links pointing to articles you've already read are dimmed (like visited web links), so you can see at a glance which references you've been through. Adjustable strength, or off — see [Settings](#settings).
- **Jump to next unread** — one action that takes you straight to the next article you haven't read (bindable to a gesture).
- **Per-book persistence** — read state is saved with the book and keyed by each article's *location* in the document, so it **survives font changes (re-pagination) and restarts**.
- **Opt-in per book** — Backlog stays dormant until you open its article list for a book. Books you never use it on are left completely untouched (nothing is even written to their metadata).

## Requirements

- **KOReader** (a recent version) on any supported device: Kindle, Kobo, PocketBook, Android, or the Linux/macOS desktop build.
- A book with a **table of contents** (EPUB and other reflowable formats). The more its chapters are standalone articles, the more useful Backlog is.

## Installation

### Manual

1. Download the latest release (or clone this repo) to get the `backlog.koplugin` folder.
2. Copy it into KOReader's `plugins` directory:
   | Device | Path |
   | --- | --- |
   | Kindle | `/mnt/us/koreader/plugins/` |
   | Kobo | `.adds/koreader/plugins/` |
   | PocketBook | `applications/koreader/plugins/` |
   | Android | `koreader/plugins/` (in KOReader's data directory) |
   | Linux / desktop | `~/.config/koreader/plugins/` |
3. Restart KOReader.

### KOReader App Store

If you have the [App Store plugin](https://github.com/omer-faruq/appstore.koplugin), install Backlog right on the device: **Tools → App Store**, search **Backlog**, install. No computer needed.

## Usage

Open a book that's a collection of articles, then:

1. Tap the top of the screen → the **Tools** (wrench) menu → **Backlog (articles read) → Show articles.**
2. In the list:
   - **Tap** an article to jump to it.
   - **Long-press** an article to mark it read / unread.
   - In a magazine with sections: **tap a section header** to jump to its first article, or **long-press** it to mark the whole section read / unread.
3. As you read, finishing an article marks it read automatically (configurable below).

## Settings

All under **Tools → Backlog (articles read)**.

### Auto-mark read when…

| Mode | An article is auto-marked read when… |
| --- | --- |
| **End of article** *(default)* | you reach its last page |
| **On leaving** | you move on to another article, after reading most of it |
| **Either** | whichever happens first |
| **Off** | never — you mark articles read manually only |

Auto-marking is never triggered by *jumping* to an article (via a link or the list) — only by actually reading through it.

### Fade links to read articles

Controls the in-text dimming of links whose target article you've already read:

| Setting | Effect |
| --- | --- |
| **Off** | links are never dimmed |
| **Subtle** | lightly dimmed |
| **Medium** *(default)* | clearly dimmed but still readable |
| **Strong** | heavily dimmed / nearly ghosted |

On greyscale e-ink, "dimmed" is a lighter grey. The dimming is painted over the finished page — it never changes the text layout or triggers a re-render.

## How it works

Backlog reads the book's **table of contents** and treats each **article** — a leaf entry, one with no sub-entries — as a trackable item. In a flat anthology that's every top-level entry; in a magazine whose sections nest articles, it's the articles inside each section, grouped under that section in the list. It records read state in the book's KOReader sidecar (the per-book metadata KOReader already keeps), keyed by each article's **stable location in the document** (its xpointer) rather than a page number — which is why marks survive re-pagination. The EPUB itself is never modified.

## FAQ

**I installed Backlog but don't see it in the menu.**
Backlog is a *document-only* plugin — it only appears while a **book is open**, not on the home screen / file browser. Open a book, then look under **Tools (wrench) → Backlog (articles read)**.

**Cross-reference links aren't fading.**
Fading only applies to links pointing to an article you've **already marked read**, in a book Backlog is tracking, with **Fade links to read articles** not set to *Off*. On greyscale e-ink the dimming is a lighter grey, so it's subtler than on a colour screen — try **Strong** if you want more contrast.

**Does it modify my EPUB?**
No. Read state lives in KOReader's per-book sidecar (`.sdr`); the EPUB file is never touched.

## Development

The decision logic lives in `lib/model.lua` with **no KOReader dependencies**, so it's unit-tested in isolation:

```sh
busted spec/unit/model_spec.lua   # with the busted framework
luajit spec/run.lua               # or zero-install, with just LuaJIT
```

Linting uses a config that mirrors KOReader's own:

```sh
luacheck .
```

The KOReader-coupled glue (`main.lua`, `ui/articles_view.lua`, `ui/reflinks_overlay.lua`) is verified in the KOReader emulator.

## License

Released under the [MIT License](LICENSE).

## Acknowledgements

Built on [KOReader](https://github.com/koreader/koreader)'s plugin API.
