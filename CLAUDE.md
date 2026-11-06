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
  `lingua` attribute. One file per language per day. (Day-key prefix scheme still being defined.)
- **Tree layout:** mirrors the liturgical books, with subsections like `ordo-missae` and
  `lectionarium`. Provisional — expected to be reshaped.
- **`romanliturgy` schema is implicit and evolving** — defined by examples and incremental
  decisions, not a DTD/XSD/RelaxNG. Only `xmllint` well-formedness is enforced today. Treat
  conventions as provisional and re-confirm. Key rule learned so far: inside `<referentia>`
  (which lists references and must carry an `elibro` attribute), a single verse is a bare
  `<cap>/<vers>`, while a contiguous range is bracketed `<ab>…</ab>` … `<ad>…</ad>`.
- **Citation grammar:** operator precedence is `:` / `,` / `and` / `-`, outermost first. `,`
  separates strophes in psalms, so `3 and 5` is one strophe. `:` can also appear inside a range
  (`5:10-6:3`) or an `and` item: it sets the current chapter until the next `:`, so the last verse
  of `5:10-6:3, 5` is 6:5.
- **`<die>` / `<gradus>` come from the source, never from the user.** `<die>` = day + month
  as written near the title, year dropped (`May 25`). `<gradus>` = Latin rank from the title:
  Solemnity → `solemnitas`, Feast → `festum`, Memorial → `memoria`. Omit the element when
  the source has no such information (no empty elements).
- **XSLT namespace note (verified 2026-06-05):** `xmllint --html --xmlout` emits a
  **no-namespace** tree, so the HTML stylesheet matches **bare** element names (`div`, `h3`).
  The namespace gotcha *does* apply to ODT's `content.xml`, which is namespaced — those
  stylesheets must bind prefixes (e.g. `text:p`) or they silently match nothing.
- **Run the reference transform:** `bin/tabgha -o example example-input.html` → `build/example-en.xml`.
