# The manual

The manuals are for the **people who use 65816X**. They are in English, written with ASD-STE100.
Each manual is one file.

| Manual | Content |
|---|---|
| [pdf/65816x.pdf](pdf/65816x.pdf) | the whole project |
| [pdf/ppu.pdf](pdf/ppu.pdf) | the video part: timing, memories, registers, pictures |

| Path | Content |
|---|---|
| `manuals.toml` | the list of manuals and the repository files that each one comes from |
| `content/en/<id>.md` | the text of each manual |
| `themes/<theme>.toml` | the look; `paper` is the default |
| `shots/` | pictures (none today) |
| `pdf/` | the finished PDFs |
| `sync.json` | hashes of the text and of the sources at the last build |
| `tools/mkmanual.py` | one text file to one PDF |
| `tools/manuals.py` | build, check, status |

## Keep it up to date

1. Run `make manual-check`. It lists the text and the sources that changed after the last build.
2. Read each change. Correct the text.
3. Run `make manual`. It needs Python 3.11 or later and `reportlab`.
4. Look at the PDF.
5. Commit the text, the PDF, and `sync.json` together.

Without `make` (Windows), run:

```
python manuals/tools/manuals.py build
```

## Rules of the text

- Write only what the repository says. Mark a missing fact as `[TO FILL: what is missing]`. Never invent a number, a command, or a behavior.
- Write for the reader: second person, short sentences, active voice.
- Write a "how to" as numbered steps with one action each. Say what the reader must see.
- Write each list item and each step on one line.
- In a box, put a blank line between two paragraphs.
- Keep backticks out of table header cells and out of TO FILL tags: the PDF cannot show them there.
- Put no color, font, or size in the text.

## Format

The first lines are `key: value`: `title`, `accent` (the highlighted word of the title), `lang`, `mark`,
`kicker`, `subtitle`, `footer`.

| Write | Result |
|---|---|
| `#`, `##`, `###` | chapter, section, part |
| `- item`, `1. step` | list, numbered steps |
| rows with `\|` | table |
| three backticks | code block |
| `![caption](shots/name.png)` | picture |
| `::: readme`, `note`, `try`, `warn`, `copy`, closed by `:::` | boxes |
| `**bold**`, `*italic*`, backticks | inline marks |

## Origin and license

`tools/mkmanual.py`, `tools/manuals.py`, and the themes come from the repository `f-accomando/bm`
(`core/scripts/` and `manuals/themes/`). Copyright © 2026 F. Accomando, BM Community License 1.0.
These files keep that license. The rest of 65816X has no license yet.
