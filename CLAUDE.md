# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: tabgha

`tabgha` automates building a tree of XML files — a database of prayers and readings for the
Roman Catholic Liturgy — by retrieving source documents and transforming them into a common
`romanliturgy` XML format. The name evokes John 6:12 (gathering up the fragments left over at
Tabgha so that nothing is lost): the project gathers liturgical "fragments" so none are lost.

It is part of a larger existing project that uses XSLT 1.0; XML records were previously written
by hand after copy/paste from a browser. This part automates the source → XML transformation.

## Status

Working prototype for one source type: USCCB daily-readings HTML, via `bin/tabgha` and
`xslt/usccb-readings.xsl`. It has only been tested against one real page. See "Status" in
`README.md` for what works and what is left. Specifications evolve (no formal schema exists for
`romanliturgy`). A worked reference pair lives in the repo root: `example-input.html` (a USCCB
daily-readings page) → `example-output.xml`.

## Architecture (three-stage pipeline, all tools present)

Format-specific front-ends feed a shared normalize → transform backend:

1. **Fetch / extract** — web HTML via `curl`, or a local HTML file. Planned, not yet written: local
   `.odt` via `unzip -p file.odt content.xml` (already XML); local `.pdf` via `pdftohtml -xml` or
   `pdftotext` (structure is heuristic; scanned PDFs would need OCR, not yet set up).
2. **Normalize** — `xmllint --html --xmlout` repairs HTML5 into well-formed XHTML for XSLT input.
3. **Transform** — `xsltproc` (XSLT 1.0) applies a stylesheet producing `romanliturgy` XML.

Sources are multiple (web + local) and multilingual.

## Non-obvious conventions

- **Output filenames:** `‹day-key›-‹lang›.xml`, e.g. `s0531-en.xml` (`s0531` = May 31;
  `to271` = Sunday of the 27th week of Ordinary Time). The `‹lang›` suffix matches the root
  `lingua` attribute. One file per language per celebration: when two celebrations share a day,
  the day-key takes one extra letter or symbol (Christmas Night and Day: `s1225n`, `s1225d`). A vigil Mass is filed under the eve's date with
  `+`: the vigil of Saints Peter and Paul (June 29, `s0629-en.xml`) is `s0628+-en.xml`.
  (Day-key prefix scheme still being defined.)
- **Tree layout:** mirrors the liturgical books, with subsections like `ordo-missae` and
  `lectionarium`. Provisional — expected to be reshaped.
- **`romanliturgy` schema is implicit and evolving** — defined by examples and incremental
  decisions, not a DTD/XSD/RelaxNG. Only `xmllint` well-formedness is enforced today. Treat
  conventions as provisional and re-confirm. Key rule learned so far: inside `<referentia>`
  (which lists references and must carry an `elibro` attribute), a single verse is a bare
  `<cap>/<vers>`, while a contiguous range is bracketed `<ab>…</ab>` … `<ad>…</ad>`.
- **Citation grammar:** (a non-breaking space in a reference counts as a space; a final full stop is dropped; "See John 15:16" → `<confer/>` as the first child of `<referentia>`) operator precedence is `:` / `,` (or `;`) / `and` / `-`, outermost first.
  `,` separates references in the same chapter, `;` references in different chapters
  (`Hebrews 4:14-16; 5:7-9`); the item after `;` names its chapter, so both split alike. `,` and `;`
  separate strophes in psalms, so `3 and 5` is one strophe. `:` can also appear inside a range
  (`5:10-6:3`) or an `and` item: it sets the current chapter until the next `:`, so the last verse
  of `5:10-6:3, 5` is 6:5.
- **`<die>` / `<gradus>` come from the source, never from the user, and are included whenever
  possible.** `<die>` is either a date, day + month as written near the title with the year
  dropped (`May 25`), or a day of the liturgical calendar (`Monday in the 6th week of Ordinary
  Time`; `Saturday after the Second Sunday after Pentecost` for the Memorial of the Immaculate
  Heart of Mary). Fixed-date celebrations take the date; movable ones take the liturgical day,
  in the website's wording. When the website does not name the day (it titles only the
  celebration), it is taken from the official liturgical books, via a table in the stylesheet. `<gradus>` = Latin rank from the title:
  Solemnity → `solemnitas`, Feast → `festum`, Memorial → `memoria`; an Optional Memorial
  gets no `<gradus>`. Omit the element when the source has no such information (no empty
  elements).
- **Easter Vigil** (`tp10-en.xml`): each of the 6 or 7 readings is `<elementum nomen="lectio" optio="n">`, where `n`
  is its sequential number (here `@optio` numbers the reading instead of marking an alternative).
  Then come `<elementum nomen="epistula">`, `<elementum nomen="alleluia">` and
  `<elementum nomen="evangelium">`. USCCB labels the alleluia block "Responsorial Psalm"
  (Psalm 118), so the block after the epistle is mapped to `alleluia` by position. Psalms are
  numbered the same way; when there are several options after one reading, a letter is added:
  `optio="1a"`, `optio="1b"`.
- **"or" blocks:** a source block introduced by "or" ("Or", "Or:") takes the same `@nomen` as the
  block before it. It is an alternative to that block, so the two are joined by `<vel/>`. When
  no other option applies (like Sunday years `a`/`b`/`c`), a longer and a shorter form of the
  same reading get `optio="longior"` and `optio="brevior"`. The stylesheet treats the "or"
  block as the shorter form when it is in the same book and starts inside the main reading's
  range; different books get their book codes; different passages of the same book are
  numbered `optio="1"`, `optio="2"`… (All Souls: Romans 5:5-11 or Romans 6:3-9); a book that
  is not recognised gets `optio="?"` and a report.
- **Reading names:** a day with two readings before the Gospel (every Sunday, Palm Sunday
  included, and other solemnities) has `nomen="lectio-prima"` and `nomen="lectio-secunda"`; `lectio`
  is kept for days with a single reading and for exceptional celebrations like the Easter Vigil.
  The stylesheet counts the "Reading" blocks, "or" blocks excluded: exactly two → prima/secunda.
- **Palm Sunday:** the block "At the Procession with Palms - Gospel" is skipped (it belongs to the
  Missal, not the Lectionary; it will be added there later), and "At the Mass - " is dropped from
  the first reading's name.
- **XSLT namespace note (verified 2026-06-05):** `xmllint --html --xmlout` emits a
  **no-namespace** tree, so the HTML stylesheet matches **bare** element names (`div`, `h3`).
  The namespace gotcha *does* apply to ODT's `content.xml`, which is namespaced — those
  stylesheets must bind prefixes (e.g. `text:p`) or they silently match nothing.
- **Book table lives outside this repo:** `~/Documents/Liturgie/xml/xsl/i10n.xml` (the liturgy
  project's file; the user allows editing its `xsl/` folder). Each `<liber elibro="Lc">` has
  `<versio lingua="en" siglum="Luke">`: the siglum is the book's short name as the source writes
  it, and is what tabgha matches (driver option `-b`). The Psalms have no `<liber>` there, so the
  stylesheet adds `Psalm`/`Psalms` → `Ps` itself. The file has an external DTD; the driver runs
  `xsltproc --novalid --nonet` so it is never fetched.
- **Run the reference transform:** `bin/tabgha -o example example-input.html` → `build/example-en.xml`.
