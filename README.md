# Parergon

*English · [Italiano](README.it.md)*

**Parergon** is a [KOReader](https://koreader.rocks) plugin that writes your highlights,
your notes and a personal index into a **copy** of an EPUB book. KOReader keeps
annotations in a separate file, so only KOReader can show them. In the copy they become
part of the book: any reading app shows them, and you can print, share or archive the book
with them.

The original book and its annotations are never modified.

The name comes from the Greek *parergon*, "what stands beside the work".

## What it does

- **Highlights and underlines** written into the text. They keep KOReader's style, or use
  a style you choose: background, solid, dashed or wavy underline, with a different style
  for each color if you like. Black and white screens can use a uniform gray.
- **Reader's notes**, in two ways:
  - in the text, right after the passage, in square brackets and optionally in italics;
  - as pop-ups: a `[1]` reference in the text leads to the note. The notes are collected on
    a "Reader's notes" page at the end of the book, with a link back to each passage.
- **Personal index** at the end of the book and in the book's table of contents,
  organized by themes you write in your notes (see below).
- **Reading note** on the title page, for example "Read and annotated by Maria in
  November 2026". You can edit the sentence before the copy is created.
- **Analysis** of your annotations that changes nothing. It shows where each annotation is
  in the book and, if one cannot be written, why.

The copy is called `Title (annotated).epub` and is saved in the same folder as the
original. It has its own identifier, so reading apps do not mix it up with the original.
When you create the copy again, the new one replaces the old one. Parergon warns you if
the old copy has annotations made directly on it.

## Requirements

- KOReader **2024.07** or later, on any device: jailbroken Kindle, Kobo, PocketBook, BOOX
  and other Android devices, Linux, macOS, Windows.
- **EPUB** books (EPUB 2 or 3) without DRM. Protected books are refused.

## Installation

1. Download `parergon-<version>.zip` from the [latest release](../../releases/latest) and
   unzip it: you get a `parergon.koplugin` folder.
2. Copy the folder into KOReader's `plugins` folder:

   | Device | Folder |
   |---|---|
   | Kindle | `koreader/plugins/` on the Kindle's storage, with the Kindle connected to a computer |
   | Kobo | `.adds/koreader/plugins/` |
   | PocketBook | `applications/koreader/plugins/` |
   | BOOX and other Android devices | `koreader/plugins/` on the internal storage |

3. Restart KOReader.

With a book open, the plugin is under **Tools → Parergon**. You can also assign it to a
gesture: *Parergon: write annotations into the book*.

## Usage

1. Read and annotate the book in KOReader as usual.
2. Open **Tools → Parergon → Create consolidated copy…**.
3. Choose what goes into the copy: highlights, notes (in the text or as pop-ups), personal
   index, reading note, and all annotations or only those with a note. Your choices are
   remembered.
4. Tap **Create**. When the copy is ready, Parergon shows a summary and offers to open it.

The other menu items are **Analyze annotations**, **Highlight style**, **Style by
color**, **Colors**, **Pop-up note reference** (on the line or superscript) and
**Language**. The language can be Automatic (same as KOReader), English or Italian.

### Pop-up notes in KOReader

To see the notes in a pop-up instead of jumping to the notes page, turn on *Settings →
Taps and gestures → Links → Show footnotes in popup* in KOReader. The option is off by
default. When it is on, the note appears at the bottom of the page.

## Personal index and themes

In your notes you can write **themes** with a hash sign attached to the word:

```
#travel
#art/greek-art
This passage picks up the first chapter.
```

- `#theme` puts the annotation under a theme, and `#theme/sub-theme` under a sub-theme. An
  annotation with several themes appears under each of them.
- Themes are never written into the text of the book: the copy keeps only your comment.
- In the index, hyphens and underscores become spaces: `#greek-art` reads "greek art".
- A line `# Title`, with a space after the hash sign, gives the index entry its title.
  Without one, the title is the first line of your comment or the start of the passage.
- Annotations without a theme go under "Other annotations". If no note has a theme, the
  index is organized by chapter.

You can choose which annotations go into the index (all, those with a theme, those with a
note) and whether themes are sorted alphabetically or in book order. The book's table of
contents lists the themes and, if you want, the sub-themes too (option *Sub-themes in the
table of contents*).

If you already write `#theme` in your notes in some other way, for example with a KOReader
user patch, Parergon recognizes it: the convention is the same.

## Known limitations

- A passage that continues into another chapter (another file of the book) is not
  written. Passages across several paragraphs of the same chapter are written.
- When two highlights overlap, the first one is written (the longer one, if both start
  at the same place) and the other is skipped and listed in the summary. If one lies
  entirely inside the other and has a note or themes, they are kept: the note appears after
  the end of the longer highlight.
- When a passage appears more than once in the same paragraph and its position is
  uncertain, Parergon skips it rather than mark the wrong place.
- A highlight whose text was edited in KOReader may not be found.
- Readers that do not use KOReader's rendering engine may show the styles a little
  differently. On the black and white readers of Kobo and PocketBook, the *Uniform gray*
  option works best.

Every skipped annotation is listed, with the reason, in the summary and in the analysis.

## License

Copyright © 2026 Antonio Vigilante.

[GNU Affero General Public License v3.0](parergon.koplugin/LICENSE) or later, the same as
KOReader.
