# tabgha

Automated gathering of Roman Catholic liturgical texts into a tree of
`romanliturgy` XML files. *"Gather up the fragments left over, that nothing be
lost"* (John 6:12, at Tabgha).

This part automates the source → XML transformation that was previously done by
hand (copy/paste from a browser, then manual tagging). It is one component of a
larger project built on XSLT 1.0.

## Pipeline

Format-specific front-ends feed a shared normalize → transform backend:

```
source ──► [1] fetch/extract ──► [2] normalize ──► [3] transform ──► romanliturgy XML
            curl | unzip | pdf*    xmllint --html     xsltproc (XSLT 1.0)
```

1. **fetch / extract** — `curl` for URLs, file copy for local HTML. (ODT via
   `unzip -p file.odt content.xml` and PDF via `pdftohtml`/`pdftotext` are planned.)
2. **normalize** — `xmllint --html --xmlout` turns messy HTML5 into well-formed XML.
3. **transform** — `xsltproc` applies an XSLT 1.0 stylesheet.

The result is checked for well-formedness with `xmllint --noout`. A source that yields
no readings generates no file: `tabgha` skips it silently and exits successfully.

## Usage

```sh
bin/tabgha [options] <source>      # <source> = URL or local .html file

  -l LANG    language code -> root @lingua and filename (default: en)
  -o KEY     output day-key -> build/<KEY>-<LANG>.xml (default: out)
  -s FILE    stylesheet (default: xslt/usccb-readings.xsl)
  -b FILE    book table (default: $TABGHA_I10N, else ~/Documents/Liturgie/xml/xsl/i10n.xml)
  -k         keep intermediate files
```

Example (reproduces the reference pair):

```sh
bin/tabgha -o example -l en example-input.html
# -> build/example-en.xml
```

## Layout

```
bin/tabgha                 driver script (the 3-stage pipeline)
xslt/usccb-readings.xsl    XSLT 1.0 stylesheet for USCCB daily-readings pages
example-input.html         reference source page (USCCB, 2026-05-25)
example-output.xml         hand-written reference output (the gold target)
build/                     generated output (gitignored)
```

## Status — what works vs. TODO

**Working** against the reference pair:
- `<die>`: the date for a fixed-date celebration, from the pager just above the title
  (`July 25, 2026` → `July 25`); the liturgical day for a movable one, in the website's
  wording when its title names the day (`Monday of the Fourteenth Week in Ordinary
  Time`), else from a small table following the liturgical books (Mary, Mother of the
  Church → `Monday after Pentecost`); and
  `<gradus>` from the rank named in the title (Solemnity → `solemnitas`, Feast →
  `festum`, Memorial → `memoria`; none for an Optional Memorial); each element is omitted when the page has none;
- an `<elementum>` per reading block, with the correct `@nomen`
  (`lectio`, or `lectio-prima` / `lectio-secunda` when there are two readings before the
  Gospel / `epistula` ("Epistle", Easter Vigil)
  / `psalmus-responsorialis` / `alleluia` / `versus-ante-evangelium` (Lent: "Verse Before the Gospel", a plain `<para>`) / `evangelium`);
- **Palm Sunday**: the "At the Procession with Palms" Gospel is skipped (Missal, not
  Lectionary) and "At the Mass - " is dropped from the first reading's name;
- **"or" blocks**: a block named "or" / "Or" / "Or:" takes the `@nomen` of the block
  before it and is joined to it by `<vel/>`; a shorter form of the same reading gives
  `optio="longior"` / `optio="brevior"`, different books their book codes, different
  passages of the same book `optio="1"`, `"2"`…, an unrecognised book `optio="?"` + a
  stderr report;
- **OR-split**: a block containing an "OR:" marker becomes several same-`@nomen`
  elementa joined by `<vel/>`, each with its own `<referentia>`. `@optio` is set
  to the book code for "different passage" alternatives (Gen/Act in the example),
  or `optio="?"` + a stderr report when it cannot be derived;
- `<referentia>` with mandatory `@elibro`, references parsed per the rule
  *single verse = bare `<cap>/<vers>`, contiguous range = `<ab>…</ab> <ad>…</ad>`*
  (Genesis, Psalm verses, and Gospel match the gold file). A range may cross chapters
  (`5:10-6:3`), and a bare verse after it stays in the chapter named last. References in
  the same chapter are separated by `,`, references in different chapters by `;`
  (`Hebrews 4:14-16; 5:7-9`, `Psalm 42:3, 5; 43:3, 4`);
- `<thema/>` / `<verbum-domini/>` placement; `<br>` → `<l/>`; `&nbsp;` stripped;
- **quote detection**: recursive, nesting-aware, per-language `<q>` wrapping
  (`en` = `“ ”` + `‘ ’`; `fr` = `« »`; `de` = `» «` + `„ “`), with edge spaces trimmed
  so tags hug the text. All 14 quotes in the example match the gold file's boundaries.
  Apostrophe safety: the matcher is open-driven, so a lone `’` (U+2019) is never a
  close — "mother's" stays text; only an apostrophe *inside* a real `‘…’` span is a
  (rare, accepted) hazard. NB `xmllint --html` needs the page's declared charset to
  decode curly quotes; undeclared sources need an explicit encoding.

- **`<para>` indentation** (canonical, deterministic): the first text line sits
  flush against `<para>`; every later line is indented `6 + 2×N` spaces, where `N`
  is the number of `<q>` quotes open at that line's start (quote-nesting only —
  non-quote source indentation is flattened); `</para>` aligns at column 4.
  Consecutive breaks (`<br><br>`) collapse to a single break, leading/trailing
  breaks and per-line trailing whitespace are stripped, and a repeat marker `<r/>`
  is kept on the same line as the preceding text, separated by one space;
- **psalm structure**: for `psalmus-responsorialis`, reference comma-segments are
  grouped into `<stropha>`; the first `R.` refrain becomes the antiphon definition
  `<para><r>…</r></para>`; each strophe is a `<para>` of `<n/>`-broken lines ending
  in ` <r/>` (space + repeat marker). (`<n/>` = hard break for psalms; `<l/>` =
  soft break for prose readings.)
- **alleluia/acclamation**: one `<para>` with `<l/>` breaks; first `R.` → antiphon
  definition `<r>…</r>`, last `R.` → ` <r/>` kept inline on the final verse line.
  A doubled antiphon is collapsed ("Alleluia, alleluia." → `<r>Alleluia.</r>`) only
  when the comma-parts are the same word, so multi-word antiphons are left intact.

**TODO** (spec still settling):
- ODT and PDF front-ends;
- testing on more USCCB pages (only the example page has been run so far);
- `<gradus>` rank words in other languages (English only), and dates in forms other
  than "Month DD, YYYY";
- `@optio` for the Sunday (`a`/`b`/`c`) and weekday (`1`/`2`) cycles;
- building the XML tree (everything goes into a flat `build/` for now; the day-key
  scheme and tree layout are still being defined).

There is **no formal schema** for `romanliturgy`; it is defined by examples and
evolves. Once the rules settle, a RelaxNG schema could validate output via
`xmllint --relaxng`.

## Verifying against the gold

Line breaks are carried by `<l/>`/`<n/>` tags, so physical newlines in the XML are
insignificant whitespace. The hand-curated gold (`example-output.xml`) may therefore
**soft-wrap** a long line across physical lines for editor readability without an
`<l/>`; the machine-generated build does not. Because of this, do **not** compare the
two with an exact `diff` — use a whitespace-normalized comparison:

```sh
bin/tabgha -o example -l en example-input.html
diff <(tr -s ' \t\n' ' ' < build/example-en.xml) <(tr -s ' \t\n' ' ' < example-output.xml)
# empty = build and gold are semantically identical
```

(This assumes the downstream XSLT collapses inter-text whitespace — consistent with
the explicit-break-tag design, but that project is not in this repo, so confirm there
if rendered output ever looks wrong.)

## License

tabgha is free software, licensed under the **GNU General Public License v3.0 or
later** (`GPL-3.0-or-later`) — see [LICENSE](LICENSE). You may use, study, share and
modify it; any *distributed* derivative must remain open-source under the same terms.

**Third-party content (not under the GPL):** the reference files
`example-input.html` and `example-output.xml` contain USCCB / New American Bible
(Revised Edition) text that is © USCCB / Confraternity of Christian Doctrine. It is
included only as a worked illustration and is **not** covered by this project's
license — see [NOTICE](NOTICE).
