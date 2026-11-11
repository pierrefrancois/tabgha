<?xml version="1.0" encoding="utf-8"?>
<!--
  usccb-readings.xsl — transform a normalized USCCB daily-readings page (XHTML,
  as produced by xmllint's HTML parser) into romanliturgy XML.

  Copyright (C) 2026 Pierre François
  SPDX-License-Identifier: GPL-3.0-or-later
  Free software under the GNU General Public License, version 3 or (at your
  option) any later version. See the LICENSE file for the full text.

  XSLT 1.0, run with xsltproc. NOTE: xmllint's HTML parser emits a NO-namespace
  tree (the <html> element has no xmlns), so source patterns use bare element
  names (div, h3, ...). When we add the ODT front-end, content.xml IS namespaced
  (text:p, ...) and those stylesheets WILL need prefix bindings.

  Implements the confirmed rules, among them:
    - an <elementum> per reading block (div.b-verse). NOTE @nomen is NOT unique:
      alternative versions share @nomen, differ by @optio, and are separated by
      <vel> (usually empty). A block with an "OR:" marker therefore yields several
      same-@nomen elementa joined by <vel/>.
    - section name -> @nomen
    - <referentia> with mandatory @elibro, and references parsed per the rule
      "single verse = bare <cap>/<vers>; contiguous range = <ab>..</ab> <ad>..</ad>"
  See "Status" in README.md for the full list and what is left to do.
-->
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:exsl="http://exslt.org/common"
    extension-element-prefixes="exsl"
    exclude-result-prefixes="exsl">

  <xsl:output method="xml" encoding="utf-8" indent="yes"/>
  <!-- No strip-space: inside reading text, a whitespace-only text node between
       inline <span>s is significant (e.g. the space in "LORD loves"). -->

  <!-- Record language; supplied by the driver (-l). -->
  <xsl:param name="lingua" select="'en'"/>

  <!-- celebration title (<h2> of div.b-lectionary), as written and lower-cased -->
  <xsl:variable name="title"
      select="normalize-space((//div[contains(concat(' ', normalize-space(@class), ' '), ' b-lectionary ')]//h2)[1])"/>
  <xsl:variable name="title-lc"
      select="translate($title, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')"/>

  <!-- Movable celebrations whose day the website does not give: the day as the
       official liturgical books name it. Matched on the lower-cased title. -->
  <xsl:variable name="movable-rtf">
    <day match="immaculate heart">Saturday after the Second Sunday after Pentecost</day>
    <day match="sacred heart">Friday after the Second Sunday after Pentecost</day>
    <day match="mother of the church">Monday after Pentecost</day>
  </xsl:variable>
  <xsl:variable name="movable" select="exsl:node-set($movable-rtf)/day[contains($title-lc, @match)][1]"/>

  <!-- <die>: a fixed-date celebration takes the date, a movable one the day of the
       liturgical calendar:
       1. a movable celebration from the table above -> the liturgical books' wording;
       2. a title that is itself a liturgical day (a weekday or Sunday of a season,
          a day of Holy Week) -> the title, as the website words it;
       3. otherwise the date in the pager just above the title,
          <li class="current"><time>May 25, 2026</time></li> -> "May 25" (year dropped).
       Empty (=> no <die> element) when none applies. -->
  <xsl:variable name="date-text"
      select="normalize-space((//li[contains(concat(' ', normalize-space(@class), ' '), ' current ')]/time)[1])"/>
  <xsl:variable name="die">
    <xsl:choose>
      <xsl:when test="$movable"><xsl:value-of select="$movable"/></xsl:when>
      <xsl:when test="contains($title-lc, ' week ') or contains($title-lc, 'sunday')
                      or contains($title-lc, 'ash wednesday') or contains($title-lc, 'holy thursday')
                      or contains($title-lc, 'good friday') or contains($title-lc, 'holy saturday')">
        <xsl:value-of select="$title"/>
      </xsl:when>
      <xsl:when test="contains($date-text, ',')">
        <xsl:value-of select="normalize-space(substring-before($date-text, ','))"/>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$date-text"/></xsl:otherwise>
    </xsl:choose>
  </xsl:variable>

  <!-- <gradus>: rank named in the celebration title (<h2> of div.b-lectionary).
       Solemnity -> solemnitas, Feast -> festum, Memorial -> memoria; otherwise
       (e.g. a plain weekday, or an Optional Memorial) no <gradus> element. -->
  <xsl:variable name="gradus">
    <xsl:choose>
      <xsl:when test="contains($title-lc, 'solemnity')">solemnitas</xsl:when>
      <xsl:when test="contains($title-lc, 'feast')">festum</xsl:when>
      <xsl:when test="contains($title-lc, 'optional memorial')"/>
      <xsl:when test="contains($title-lc, 'memorial')">memoria</xsl:when>
    </xsl:choose>
  </xsl:variable>

  <!-- Book name -> elibro code lookup, read from the liturgy project's book table
       (xsl/i10n.xml): <liber elibro="Lc"><versio lingua="en" siglum="Luke">.
       The siglum is the book's short name as the source writes it. The Psalms have
       no <liber> there, so they are added here. Path supplied by the driver (-b). -->
  <xsl:param name="i10n" select="''"/>
  <xsl:variable name="books-rtf">
    <xsl:if test="string($i10n)">
      <xsl:for-each select="document($i10n)/i10n/liber/versio[@lingua = $lingua][@siglum != '']">
        <book name="{@siglum}" code="{../@elibro}"/>
      </xsl:for-each>
    </xsl:if>
    <book name="Psalms" code="Ps"/>
    <book name="Psalm" code="Ps"/>
  </xsl:variable>
  <xsl:variable name="books" select="exsl:node-set($books-rtf)/book"/>

  <!-- Sentinel for a line break (<br>) while quote-parsing the flattened body;
       turned back into <l/> on output. U+E000 is a private-use char (never in text). -->
  <xsl:variable name="BR" select="'&#xE000;'"/>
  <xsl:variable name="BIG" select="100000000"/>
  <!-- chars stripped from the para's leading/trailing edges: break sentinel + whitespace -->
  <xsl:variable name="EDGE" select="concat($BR, ' &#10;&#9;')"/>
  <xsl:variable name="UC" select="'ABCDEFGHIJKLMNOPQRSTUVWXYZ'"/>
  <xsl:variable name="LC" select="'abcdefghijklmnopqrstuvwxyz'"/>

  <!-- Active quote pairs PER LANGUAGE. Every pair has distinct open/close chars, so
       nesting/mixing is handled by depth-matching. -->
  <xsl:variable name="quotes-rtf">
    <lang code="en">
      <pair open="&#x201C;" close="&#x201D;"/>
      <!-- single pair: only ever fires when an opening ' (U+2018) is present, so a
           lone apostrophe ' (U+2019) is never mistaken for a close (option #2). -->
      <pair open="&#x2018;" close="&#x2019;"/>
    </lang>
    <lang code="fr">
      <pair open="&#xAB;" close="&#xBB;"/>
      <pair open="&#x201C;" close="&#x201D;"/>
    </lang>
    <lang code="de">
      <pair open="&#x201E;" close="&#x201C;"/>
      <pair open="&#x201A;" close="&#x2018;"/>
      <pair open="&#xBB;" close="&#xAB;"/>
    </lang>
  </xsl:variable>
  <!-- pairs for the current language; empty (=> no quote wrapping) if unknown -->
  <xsl:variable name="qpairs" select="exsl:node-set($quotes-rtf)/lang[@code=$lingua]/pair"/>

  <!-- A reading block: <div class="... b-verse ..."> -->
  <xsl:variable name="verse-blocks"
      select="//div[contains(concat(' ', normalize-space(@class), ' '), ' b-verse ')]"/>

  <xsl:template match="/">
    <romanliturgy lingua="{$lingua}">
      <xsl:if test="string($die) != ''"><die><xsl:value-of select="$die"/></die></xsl:if>
      <xsl:if test="string($gradus) != ''"><gradus><xsl:value-of select="$gradus"/></gradus></xsl:if>
      <xsl:apply-templates select="$verse-blocks" mode="reading"/>
    </romanliturgy>
  </xsl:template>

  <xsl:template match="div" mode="reading">
    <xsl:variable name="name">
      <xsl:apply-templates select="." mode="block-name"/>
    </xsl:variable>
    <xsl:variable name="header-address">
      <xsl:apply-templates select="." mode="block-address"/>
    </xsl:variable>
    <xsl:variable name="header-confer">
      <xsl:call-template name="has-see">
        <xsl:with-param name="raw" select=".//div[contains(concat(' ', normalize-space(@class), ' '), ' address ')]//a"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:variable name="body"
        select=".//div[contains(concat(' ', normalize-space(@class), ' '), ' content-body ')]/p"/>

    <!-- An "or" block (name "or", "Or", "Or:") is an alternative to the block before
         it: same @nomen, joined to it by <vel/>. -->
    <xsl:variable name="is-or" select="translate(translate($name, ':', ''), 'OR', 'or') = 'or'"/>
    <xsl:variable name="main"
        select="preceding::div[contains(concat(' ', normalize-space(@class), ' '), ' b-verse ')]
                  [not(translate(normalize-space(translate(.//h3[contains(concat(' ', normalize-space(@class), ' '), ' name ')], '&#xA0;', ' ')), 'OR:', 'or') = 'or')][1]"/>
    <xsl:variable name="next"
        select="following::div[contains(concat(' ', normalize-space(@class), ' '), ' b-verse ')][1]"/>
    <xsl:variable name="next-name">
      <xsl:apply-templates select="$next" mode="block-name"/>
    </xsl:variable>
    <xsl:variable name="next-is-or" select="translate(translate($next-name, ':', ''), 'OR', 'or') = 'or'"/>

    <xsl:variable name="nomen">
      <xsl:call-template name="nomen-of">
        <xsl:with-param name="name">
          <xsl:choose>
            <xsl:when test="$is-or and $main"><xsl:apply-templates select="$main" mode="block-name"/></xsl:when>
            <xsl:otherwise><xsl:value-of select="$name"/></xsl:otherwise>
          </xsl:choose>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:variable>
    <xsl:variable name="is-reading" select="$nomen = 'lectio' or $nomen = 'evangelium'"/>

    <!-- @optio of a block that has "or" alternatives, or is one (empty otherwise):
         a shorter form of the same reading -> longior / brevior; a different passage ->
         the book code; undecidable -> "?" (reported). -->
    <xsl:variable name="optio">
      <xsl:choose>
        <xsl:when test="$is-or and $main">
          <xsl:call-template name="alternative-kind">
            <xsl:with-param name="main-address"><xsl:apply-templates select="$main" mode="block-address"/></xsl:with-param>
            <xsl:with-param name="alt-address" select="$header-address"/>
            <xsl:with-param name="role" select="'alt'"/>
            <!-- 2 for the first "or" block after the main one, 3 for the next... -->
            <xsl:with-param name="alt-number"
                select="1 + count(preceding::div[contains(concat(' ', normalize-space(@class), ' '), ' b-verse ')])
                          - count($main/preceding::div[contains(concat(' ', normalize-space(@class), ' '), ' b-verse ')])"/>
          </xsl:call-template>
        </xsl:when>
        <xsl:when test="$next-is-or">
          <xsl:call-template name="alternative-kind">
            <xsl:with-param name="main-address" select="$header-address"/>
            <xsl:with-param name="alt-address"><xsl:apply-templates select="$next" mode="block-address"/></xsl:with-param>
            <xsl:with-param name="role" select="'main'"/>
          </xsl:call-template>
        </xsl:when>
      </xsl:choose>
    </xsl:variable>

    <xsl:if test="$is-or and $main"><vel/></xsl:if>

    <!-- "OR:" delimiters inside the body split one block into alternative options.
         Each option becomes a full <elementum> (same @nomen, distinct @optio),
         joined by <vel/>. -->
    <xsl:variable name="delims"
        select="$body/node()[descendant-or-self::strong[starts-with(normalize-space(.), 'OR')]]"/>
    <xsl:variable name="multi" select="count($delims) &gt; 0"/>

    <!-- option 1: nodes before the first delimiter; reference from the header -->
    <xsl:call-template name="emit-option">
      <xsl:with-param name="body" select="$body"/>
      <xsl:with-param name="seg" select="1"/>
      <xsl:with-param name="nomen" select="$nomen"/>
      <xsl:with-param name="is-reading" select="$is-reading"/>
      <xsl:with-param name="multi" select="$multi"/>
      <xsl:with-param name="header-address" select="$header-address"/>
      <xsl:with-param name="header-confer" select="string($header-confer)"/>
      <xsl:with-param name="optio" select="string($optio)"/>
    </xsl:call-template>

    <!-- each further option follows a delimiter, introduced by <vel/> -->
    <xsl:for-each select="$delims">
      <vel/>
      <xsl:call-template name="emit-option">
        <xsl:with-param name="body" select="$body"/>
        <xsl:with-param name="seg" select="position() + 1"/>
        <xsl:with-param name="nomen" select="$nomen"/>
        <xsl:with-param name="is-reading" select="$is-reading"/>
        <xsl:with-param name="multi" select="$multi"/>
        <xsl:with-param name="header-address" select="''"/>
      </xsl:call-template>
    </xsl:for-each>
  </xsl:template>

  <!-- a block's name (h3.name) and reference (div.address a), normalized
       (a non-breaking space, as in "Or&#xA0;", counts as a space) -->
  <xsl:template match="div" mode="block-name">
    <xsl:value-of select="normalize-space(translate(.//h3[contains(concat(' ', normalize-space(@class), ' '), ' name ')], '&#xA0;', ' '))"/>
  </xsl:template>
  <xsl:template match="div" mode="block-address">
    <xsl:call-template name="strip-see">
      <xsl:with-param name="raw" select="normalize-space(.//div[contains(concat(' ', normalize-space(@class), ' '), ' address ')]//a)"/>
    </xsl:call-template>
  </xsl:template>

  <!-- '1' when the reference is introduced by "See" (written <confer/> in <referentia>) -->
  <xsl:template name="has-see">
    <xsl:param name="raw"/>
    <xsl:if test="starts-with(normalize-space(translate($raw, '&#xA0;', ' ')), 'See ')">1</xsl:if>
  </xsl:template>

  <!-- every reference text passes through here: a non-breaking space counts as a
       space, a final full stop is dropped, and "See 2 Timothy 1:10" -> "2 Timothy 1:10" (the
       "See" itself becomes <confer/>, see has-see) -->
  <xsl:template name="strip-see">
    <xsl:param name="raw"/>
    <xsl:variable name="n" select="normalize-space(translate($raw, '&#xA0;', ' '))"/>
    <!-- a full stop ending the reference ("Luke 2:1-14.") is punctuation, not part of the verse -->
    <xsl:variable name="s">
      <xsl:choose>
        <xsl:when test="substring($n, string-length($n)) = '.'"><xsl:value-of select="normalize-space(substring($n, 1, string-length($n) - 1))"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$n"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="starts-with($s, 'See ')"><xsl:value-of select="substring-after($s, 'See ')"/></xsl:when>
      <xsl:otherwise><xsl:value-of select="$s"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- section name -> @nomen -->
  <xsl:template name="nomen-of">
    <xsl:param name="name"/>
    <xsl:choose>
      <xsl:when test="starts-with($name, 'Reading')">lectio</xsl:when>
      <xsl:when test="contains($name, 'Psalm')">psalmus-responsorialis</xsl:when>
      <xsl:when test="contains($name, 'Alleluia') or contains($name, 'Acclamation')">alleluia</xsl:when>
      <xsl:when test="contains($name, 'Verse Before the Gospel')">versus-ante-evangelium</xsl:when>
      <xsl:when test="contains($name, 'Gospel')">evangelium</xsl:when>
      <xsl:otherwise>ignotum</xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- @optio for a main block ($role='main') or its "or" alternative ($role='alt').
       Same book, and the alternative starts inside the main reading's range ->
       a shorter form: longior (main) / brevior (alt). Different books -> each one's
       book code. Different passages of the same book -> numbered: 1 (main), 2, 3...
       (alt, by position). A book that is not recognised -> "?" (reported by emit-option). -->
  <xsl:template name="alternative-kind">
    <xsl:param name="main-address"/>
    <xsl:param name="alt-address"/>
    <xsl:param name="role"/>
    <xsl:param name="alt-number" select="2"/>
    <xsl:variable name="mbk" select="$books[starts-with(concat($main-address, ' '), concat(@name, ' '))][1]"/>
    <xsl:variable name="abk" select="$books[starts-with(concat($alt-address, ' '), concat(@name, ' '))][1]"/>
    <xsl:variable name="mnum" select="normalize-space(substring-after($main-address, $mbk/@name))"/>
    <xsl:variable name="anum" select="normalize-space(substring-after($alt-address, $abk/@name))"/>
    <xsl:variable name="m-start"><xsl:call-template name="start-key"><xsl:with-param name="ref" select="$mnum"/></xsl:call-template></xsl:variable>
    <xsl:variable name="a-start"><xsl:call-template name="start-key"><xsl:with-param name="ref" select="$anum"/></xsl:call-template></xsl:variable>
    <xsl:variable name="m-end"><xsl:call-template name="end-key"><xsl:with-param name="ref" select="$mnum"/></xsl:call-template></xsl:variable>
    <xsl:choose>
      <xsl:when test="$mbk and $abk and $mbk/@code = $abk/@code
                      and number($a-start) &gt;= number($m-start) and number($a-start) &lt;= number($m-end)">
        <xsl:choose>
          <xsl:when test="$role = 'main'">longior</xsl:when>
          <xsl:otherwise>brevior</xsl:otherwise>
        </xsl:choose>
      </xsl:when>
      <xsl:when test="$mbk and $abk and $mbk/@code != $abk/@code">
        <xsl:choose>
          <xsl:when test="$role = 'main'"><xsl:value-of select="$mbk/@code"/></xsl:when>
          <xsl:otherwise><xsl:value-of select="$abk/@code"/></xsl:otherwise>
        </xsl:choose>
      </xsl:when>
      <xsl:when test="$mbk and $abk">
        <xsl:choose>
          <xsl:when test="$role = 'main'">1</xsl:when>
          <xsl:otherwise><xsl:value-of select="$alt-number"/></xsl:otherwise>
        </xsl:choose>
      </xsl:when>
      <xsl:otherwise>?</xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- comparable key chapter*1000 + verse (verse letters dropped) for the first
       C:V of a reference, and for its last verse ("13:1-23" -> 13001 / 13023) -->
  <xsl:template name="start-key">
    <xsl:param name="ref"/>
    <xsl:variable name="first" select="normalize-space(substring-before(concat(translate($ref, '—;', '-,'), ','), ','))"/>
    <xsl:variable name="cv" select="substring-before(concat($first, '-'), '-')"/>
    <xsl:value-of select="1000 * number(normalize-space(substring-before($cv, ':')))
                          + number(normalize-space(translate(substring-after($cv, ':'), $LC, '')))"/>
  </xsl:template>
  <xsl:template name="end-key">
    <xsl:param name="ref"/>
    <xsl:variable name="chap">
      <xsl:call-template name="end-chapter">
        <xsl:with-param name="text" select="$ref"/>
        <xsl:with-param name="chapter" select="''"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:variable name="last">
      <xsl:call-template name="last-word">
        <xsl:with-param name="s" select="normalize-space(translate($ref, ',-—:;', '     '))"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:value-of select="1000 * number($chap) + number(translate($last, $LC, ''))"/>
  </xsl:template>

  <!-- Emit one <elementum> for option number $seg of a reading block. -->
  <xsl:template name="emit-option">
    <xsl:param name="body"/>
    <xsl:param name="seg"/>
    <xsl:param name="nomen"/>
    <xsl:param name="is-reading"/>
    <xsl:param name="multi"/>
    <xsl:param name="header-address"/>
    <xsl:param name="optio" select="''"/>
    <xsl:param name="header-confer" select="''"/>

    <!-- nodes of this segment: those with exactly $seg-1 preceding OR-delimiters,
         delimiters themselves excluded -->
    <xsl:variable name="seg-nodes"
        select="$body/node()
                 [not(descendant-or-self::strong[starts-with(normalize-space(.), 'OR')])]
                 [(1 + count(preceding-sibling::node()[descendant-or-self::strong[starts-with(normalize-space(.), 'OR')]])) = $seg]"/>

    <!-- reference text: the header for option 1, else the first inline <a> -->
    <xsl:variable name="address">
      <xsl:choose>
        <xsl:when test="$seg = 1 and string($header-address)"><xsl:value-of select="$header-address"/></xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="strip-see">
            <xsl:with-param name="raw" select="normalize-space($seg-nodes[self::a][1])"/>
          </xsl:call-template>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <!-- the book name must be followed by a space: "John" must not match "Johnny" -->
    <xsl:variable name="bk" select="$books[starts-with(concat($address, ' '), concat(@name, ' '))][1]"/>
    <xsl:variable name="code">
      <xsl:choose>
        <xsl:when test="$bk"><xsl:value-of select="$bk/@code"/></xsl:when>
        <xsl:otherwise>?</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <elementum nomen="{$nomen}">
      <!-- @optio only when this block has alternatives. For "different passage"
           alternatives optio = book code; unknown -> "?" (reported, file still written). -->
      <xsl:variable name="eff-optio">
        <xsl:choose>
          <xsl:when test="string($optio)"><xsl:value-of select="$optio"/></xsl:when>
          <xsl:when test="$multi"><xsl:value-of select="$code"/></xsl:when>
        </xsl:choose>
      </xsl:variable>
      <xsl:if test="string($eff-optio)">
        <xsl:attribute name="optio"><xsl:value-of select="$eff-optio"/></xsl:attribute>
        <xsl:if test="$eff-optio = '?'">
          <xsl:message>tabgha: could not derive @optio (nomen=<xsl:value-of select="$nomen"/>, address="<xsl:value-of select="$address"/>") — left optio="?"</xsl:message>
        </xsl:if>
      </xsl:if>

      <xsl:if test="$is-reading"><thema/></xsl:if>

      <xsl:if test="string($address)">
        <referentia elibro="{$code}">
          <!-- "See John 15:16" -> <confer/> before the reference -->
          <xsl:variable name="confer">
            <xsl:choose>
              <xsl:when test="$seg = 1 and string($header-address)"><xsl:value-of select="$header-confer"/></xsl:when>
              <xsl:otherwise>
                <xsl:call-template name="has-see">
                  <xsl:with-param name="raw" select="$seg-nodes[self::a][1]"/>
                </xsl:call-template>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:variable>
          <xsl:if test="string($confer)"><confer/></xsl:if>
          <xsl:if test="$bk">
            <xsl:variable name="numeric" select="normalize-space(substring-after($address, $bk/@name))"/>
            <xsl:choose>
              <xsl:when test="$nomen = 'psalmus-responsorialis'">
                <!-- each comma-segment of a psalm reference becomes its own <stropha> -->
                <xsl:call-template name="emit-strophe-refs">
                  <xsl:with-param name="text" select="$numeric"/>
                  <xsl:with-param name="chapter" select="''"/>
                </xsl:call-template>
              </xsl:when>
              <xsl:otherwise>
                <xsl:call-template name="emit-references">
                  <xsl:with-param name="text" select="$numeric"/>
                  <xsl:with-param name="chapter" select="''"/>
                </xsl:call-template>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:if>
        </referentia>
      </xsl:if>

      <!-- flatten body to a string (br -> sentinel), trim edge breaks -->
      <xsl:variable name="flat">
        <xsl:apply-templates select="$seg-nodes[not(self::a)]" mode="flat"/>
      </xsl:variable>
      <xsl:variable name="flat-trimmed">
        <xsl:call-template name="strip-edge-breaks">
          <xsl:with-param name="s" select="string($flat)"/>
        </xsl:call-template>
      </xsl:variable>
      <!-- collapse paragraph breaks (<br><br>): a whitespace-only line between two
           breaks is dropped, merging the surrounding breaks into one. -->
      <xsl:variable name="body-lines">
        <xsl:call-template name="drop-blank-lines">
          <xsl:with-param name="s" select="string($flat-trimmed)"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:choose>
        <xsl:when test="$nomen = 'psalmus-responsorialis'">
          <!-- psalm: antiphon definition <para> + one <para> per strophe (each ending <r/>) -->
          <xsl:call-template name="psalm-body">
            <xsl:with-param name="lines" select="string($body-lines)"/>
            <xsl:with-param name="acc" select="''"/>
            <xsl:with-param name="defined" select="0"/>
          </xsl:call-template>
        </xsl:when>
        <xsl:when test="$nomen = 'alleluia'">
          <!-- one <para>: first R. -> <r>antiphon</r>, later R. -> <r/>, verse with <l/> -->
          <para>
            <xsl:call-template name="alleluia-body">
              <xsl:with-param name="lines" select="string($body-lines)"/>
              <xsl:with-param name="defined" select="0"/>
              <xsl:with-param name="atstart" select="1"/>
            </xsl:call-template>
            <xsl:text>&#10;    </xsl:text>
          </para>
        </xsl:when>
        <xsl:otherwise>
          <para>
            <xsl:call-template name="emit-quoted">
              <xsl:with-param name="text" select="string($body-lines)"/>
            </xsl:call-template>
            <xsl:text>&#10;    </xsl:text>
          </para>
        </xsl:otherwise>
      </xsl:choose>

      <xsl:if test="$is-reading"><verbum-domini/></xsl:if>
    </elementum>
  </xsl:template>

  <!-- ===== reference list parsing =================================================
       Grammar handled: references separated by ',' (same chapter) or ';' (the next one
       names a new chapter, so both split alike); ' and ' also separates verses.
       A reference is either C:V, C:V-V2 (range), C:V-C2:V2 (cross-chapter range), or
       a bare V or V-V2 (chapter carried over from the last one named).
       Single verse  -> bare <cap>/<vers>;  contiguous range -> <ab>..</ab> <ad>..</ad>.
  -->
  <xsl:template name="emit-references">
    <xsl:param name="text"/>
    <xsl:param name="chapter"/>
    <xsl:variable name="t" select="normalize-space(translate($text, ';', ','))"/>
    <xsl:if test="$t != ''">
      <xsl:variable name="first" select="normalize-space(substring-before(concat($t, ','), ','))"/>
      <xsl:variable name="rest"  select="substring-after($t, ',')"/>
      <xsl:call-template name="emit-and-group">
        <xsl:with-param name="group" select="$first"/>
        <xsl:with-param name="chapter" select="$chapter"/>
      </xsl:call-template>
      <xsl:call-template name="emit-references">
        <xsl:with-param name="text" select="$rest"/>
        <xsl:with-param name="chapter">
          <xsl:call-template name="end-chapter">
            <xsl:with-param name="text" select="$first"/>
            <xsl:with-param name="chapter" select="$chapter"/>
          </xsl:call-template>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

  <!-- split a comma-segment on ' and ' (e.g. "3 and 5") -->
  <xsl:template name="emit-and-group">
    <xsl:param name="group"/>
    <xsl:param name="chapter"/>
    <xsl:variable name="g" select="normalize-space($group)"/>
    <xsl:if test="$g != ''">
      <xsl:variable name="first" select="normalize-space(substring-before(concat($g, ' and '), ' and '))"/>
      <xsl:variable name="rest"  select="substring-after($g, ' and ')"/>
      <xsl:call-template name="emit-item">
        <xsl:with-param name="item" select="$first"/>
        <xsl:with-param name="chapter" select="$chapter"/>
      </xsl:call-template>
      <xsl:call-template name="emit-and-group">
        <xsl:with-param name="group" select="$rest"/>
        <xsl:with-param name="chapter">
          <xsl:call-template name="end-chapter">
            <xsl:with-param name="text" select="$first"/>
            <xsl:with-param name="chapter" select="$chapter"/>
          </xsl:call-template>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

  <!-- emit one reference: bare verse or ab/ad range -->
  <xsl:template name="emit-item">
    <xsl:param name="item"/>
    <xsl:param name="chapter"/>
    <!-- an em dash marks a range whose two ends are in different chapters
         (Matthew 26:14—27:66); parse it like '-' -->
    <xsl:variable name="it" select="normalize-space(translate($item, '—', '-'))"/>
    <xsl:if test="$it != ''">
      <!-- split on '-' first: either side of a range may name its own chapter -->
      <xsl:variable name="from" select="normalize-space(substring-before(concat($it, '-'), '-'))"/>
      <xsl:variable name="to"   select="normalize-space(substring-after($it, '-'))"/>
      <xsl:variable name="from-cap">
        <xsl:choose>
          <xsl:when test="contains($from, ':')"><xsl:value-of select="normalize-space(substring-before($from, ':'))"/></xsl:when>
          <xsl:otherwise><xsl:value-of select="$chapter"/></xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:variable name="from-vers">
        <xsl:choose>
          <xsl:when test="contains($from, ':')"><xsl:value-of select="normalize-space(substring-after($from, ':'))"/></xsl:when>
          <xsl:otherwise><xsl:value-of select="$from"/></xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:choose>
        <xsl:when test="contains($it, '-')">
          <!-- the end of a range stays in the start's chapter unless it names its own -->
          <xsl:variable name="to-cap">
            <xsl:choose>
              <xsl:when test="contains($to, ':')"><xsl:value-of select="normalize-space(substring-before($to, ':'))"/></xsl:when>
              <xsl:otherwise><xsl:value-of select="$from-cap"/></xsl:otherwise>
            </xsl:choose>
          </xsl:variable>
          <xsl:variable name="to-vers">
            <xsl:choose>
              <xsl:when test="contains($to, ':')"><xsl:value-of select="normalize-space(substring-after($to, ':'))"/></xsl:when>
              <xsl:otherwise><xsl:value-of select="$to"/></xsl:otherwise>
            </xsl:choose>
          </xsl:variable>
          <ab><cap><xsl:value-of select="$from-cap"/></cap><vers><xsl:value-of select="$from-vers"/></vers></ab>
          <ad><cap><xsl:value-of select="$to-cap"/></cap><vers><xsl:value-of select="$to-vers"/></vers></ad>
        </xsl:when>
        <xsl:otherwise>
          <cap><xsl:value-of select="$from-cap"/></cap><vers><xsl:value-of select="$from-vers"/></vers>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:if>
  </xsl:template>

  <!-- the chapter in force after $text: the last one it names (the number just
       before its last ':'), else the incoming $chapter. "5:10-6:3" -> 6 -->
  <xsl:template name="end-chapter">
    <xsl:param name="text"/>
    <xsl:param name="chapter"/>
    <xsl:choose>
      <xsl:when test="contains($text, ':')">
        <xsl:call-template name="end-chapter">
          <xsl:with-param name="text" select="substring-after($text, ':')"/>
          <xsl:with-param name="chapter">
            <xsl:call-template name="last-word">
              <xsl:with-param name="s" select="normalize-space(translate(substring-before($text, ':'), '-—', '  '))"/>
            </xsl:call-template>
          </xsl:with-param>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$chapter"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template name="last-word">
    <xsl:param name="s"/>
    <xsl:choose>
      <xsl:when test="contains($s, ' ')">
        <xsl:call-template name="last-word">
          <xsl:with-param name="s" select="substring-after($s, ' ')"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$s"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- ===== psalm body ============================================================
       psalmus-responsorialis differs from prose readings: its reference comma-
       segments each become a <stropha>; the first "R." refrain is the antiphon
       DEFINITION -> <para><r>..</r></para>; each following strophe is a <para> of
       <n/>-separated lines ending with the repeat marker <r/>. -->

  <!-- like emit-references, but wraps each comma-segment in <stropha> -->
  <xsl:template name="emit-strophe-refs">
    <xsl:param name="text"/>
    <xsl:param name="chapter"/>
    <xsl:variable name="t" select="normalize-space(translate($text, ';', ','))"/>
    <xsl:if test="$t != ''">
      <xsl:variable name="first" select="normalize-space(substring-before(concat($t, ','), ','))"/>
      <xsl:variable name="rest" select="substring-after($t, ',')"/>
      <stropha>
        <xsl:call-template name="emit-and-group">
          <xsl:with-param name="group" select="$first"/>
          <xsl:with-param name="chapter" select="$chapter"/>
        </xsl:call-template>
      </stropha>
      <xsl:call-template name="emit-strophe-refs">
        <xsl:with-param name="text" select="$rest"/>
        <xsl:with-param name="chapter">
          <xsl:call-template name="end-chapter">
            <xsl:with-param name="text" select="$first"/>
            <xsl:with-param name="chapter" select="$chapter"/>
          </xsl:call-template>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

  <!-- walk the flattened psalm body line-by-line (split on $BR), grouping strophes
       between "R." refrains. $defined=1 once the antiphon definition is emitted. -->
  <xsl:template name="psalm-body">
    <xsl:param name="lines"/>
    <xsl:param name="acc"/>
    <xsl:param name="defined"/>
    <xsl:choose>
      <xsl:when test="$lines = ''">
        <xsl:if test="normalize-space($acc) != ''">
          <xsl:call-template name="flush-strophe">
            <xsl:with-param name="acc" select="$acc"/>
            <xsl:with-param name="repeat" select="0"/>
          </xsl:call-template>
        </xsl:if>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="has-more" select="contains($lines, $BR)"/>
        <xsl:variable name="line">
          <xsl:choose>
            <xsl:when test="$has-more"><xsl:value-of select="substring-before($lines, $BR)"/></xsl:when>
            <xsl:otherwise><xsl:value-of select="$lines"/></xsl:otherwise>
          </xsl:choose>
        </xsl:variable>
        <xsl:variable name="rest">
          <xsl:if test="$has-more"><xsl:value-of select="substring-after($lines, $BR)"/></xsl:if>
        </xsl:variable>
        <xsl:choose>
          <xsl:when test="starts-with(normalize-space($line), 'R.') and $defined = 0">
            <!-- first refrain: antiphon definition -->
            <para><r><xsl:call-template name="strip-refrain-prefix"><xsl:with-param name="line" select="$line"/></xsl:call-template></r></para>
            <xsl:call-template name="psalm-body">
              <xsl:with-param name="lines" select="string($rest)"/>
              <xsl:with-param name="acc" select="''"/>
              <xsl:with-param name="defined" select="1"/>
            </xsl:call-template>
          </xsl:when>
          <xsl:when test="starts-with(normalize-space($line), 'R.')">
            <!-- repeat refrain: close the current strophe with <r/> -->
            <xsl:call-template name="flush-strophe">
              <xsl:with-param name="acc" select="$acc"/>
              <xsl:with-param name="repeat" select="1"/>
            </xsl:call-template>
            <xsl:call-template name="psalm-body">
              <xsl:with-param name="lines" select="string($rest)"/>
              <xsl:with-param name="acc" select="''"/>
              <xsl:with-param name="defined" select="1"/>
            </xsl:call-template>
          </xsl:when>
          <xsl:otherwise>
            <!-- strophe line: accumulate, rejoining with the break sentinel -->
            <xsl:variable name="newacc">
              <xsl:choose>
                <xsl:when test="$acc = ''"><xsl:value-of select="$line"/></xsl:when>
                <xsl:otherwise><xsl:value-of select="concat($acc, $BR, $line)"/></xsl:otherwise>
              </xsl:choose>
            </xsl:variable>
            <xsl:call-template name="psalm-body">
              <xsl:with-param name="lines" select="string($rest)"/>
              <xsl:with-param name="acc" select="string($newacc)"/>
              <xsl:with-param name="defined" select="$defined"/>
            </xsl:call-template>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- emit one strophe <para>: <n/>-broken, quote-wrapped, optional trailing <r/> -->
  <xsl:template name="flush-strophe">
    <xsl:param name="acc"/>
    <xsl:param name="repeat"/>
    <xsl:variable name="trimmed">
      <xsl:call-template name="strip-edge-breaks"><xsl:with-param name="s" select="$acc"/></xsl:call-template>
    </xsl:variable>
    <para>
      <xsl:call-template name="emit-quoted">
        <xsl:with-param name="text" select="string($trimmed)"/>
        <xsl:with-param name="brk" select="'n'"/>
      </xsl:call-template>
      <xsl:if test="$repeat = 1"><xsl:text> </xsl:text><r/></xsl:if>
      <xsl:text>&#10;    </xsl:text>
    </para>
  </xsl:template>

  <!-- alleluia/acclamation body, all in one <para>: a soft <l/> break separates
       items; first "R." line -> <r>antiphon</r> (definition), later "R." -> <r/>. -->
  <xsl:template name="alleluia-body">
    <xsl:param name="lines"/>
    <xsl:param name="defined"/>
    <xsl:param name="atstart"/>
    <xsl:if test="$lines != ''">
      <xsl:variable name="has-more" select="contains($lines, $BR)"/>
      <xsl:variable name="line">
        <xsl:choose>
          <xsl:when test="$has-more"><xsl:value-of select="substring-before($lines, $BR)"/></xsl:when>
          <xsl:otherwise><xsl:value-of select="$lines"/></xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:variable name="rest">
        <xsl:if test="$has-more"><xsl:value-of select="substring-after($lines, $BR)"/></xsl:if>
      </xsl:variable>
      <xsl:variable name="is-refrain" select="starts-with(normalize-space($line), 'R.')"/>
      <!-- line separator: a repeat refrain (the closing <r/>) hugs the previous line
           with a single space; every other line starts a new <l/>-broken line. -->
      <xsl:choose>
        <xsl:when test="$atstart = 1"/>
        <xsl:when test="$is-refrain and $defined = 1"><xsl:text> </xsl:text></xsl:when>
        <xsl:otherwise><l/><xsl:text>&#10;      </xsl:text></xsl:otherwise>
      </xsl:choose>
      <xsl:choose>
        <xsl:when test="$is-refrain and $defined = 0">
          <r>
            <xsl:call-template name="collapse-repeats">
              <xsl:with-param name="text">
                <xsl:call-template name="strip-refrain-prefix"><xsl:with-param name="line" select="$line"/></xsl:call-template>
              </xsl:with-param>
            </xsl:call-template>
          </r>
        </xsl:when>
        <xsl:when test="$is-refrain">
          <r/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="emit-quoted">
            <xsl:with-param name="text" select="$line"/>
            <xsl:with-param name="brk" select="'l'"/>
          </xsl:call-template>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:call-template name="alleluia-body">
        <xsl:with-param name="lines" select="string($rest)"/>
        <xsl:with-param name="defined">
          <xsl:choose><xsl:when test="$is-refrain">1</xsl:when><xsl:otherwise><xsl:value-of select="$defined"/></xsl:otherwise></xsl:choose>
        </xsl:with-param>
        <xsl:with-param name="atstart" select="0"/>
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

  <!-- collapse a doubled antiphon to a single token: "Alleluia, alleluia." ->
       "Alleluia." Only fires when the two comma-separated parts are the same word
       (case-insensitive), so multi-word antiphons (e.g. the psalm) are untouched. -->
  <xsl:template name="collapse-repeats">
    <xsl:param name="text"/>
    <xsl:variable name="t" select="normalize-space($text)"/>
    <xsl:variable name="hasdot" select="substring($t, string-length($t), 1) = '.'"/>
    <xsl:variable name="core">
      <xsl:choose>
        <xsl:when test="$hasdot"><xsl:value-of select="substring($t, 1, string-length($t) - 1)"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$t"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="contains($core, ',')">
        <xsl:variable name="a" select="normalize-space(substring-before($core, ','))"/>
        <xsl:variable name="b" select="normalize-space(substring-after($core, ','))"/>
        <xsl:choose>
          <xsl:when test="not(contains($b, ',')) and translate($a, $UC, $LC) = translate($b, $UC, $LC)">
            <xsl:value-of select="$a"/><xsl:if test="$hasdot">.</xsl:if>
          </xsl:when>
          <xsl:otherwise><xsl:value-of select="$text"/></xsl:otherwise>
        </xsl:choose>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$text"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- strip "R." and an optional "(n)" antiphon-verse marker from a refrain line -->
  <xsl:template name="strip-refrain-prefix">
    <xsl:param name="line"/>
    <xsl:variable name="a" select="normalize-space(substring-after(normalize-space($line), 'R.'))"/>
    <xsl:choose>
      <xsl:when test="starts-with($a, '(')"><xsl:value-of select="normalize-space(substring-after($a, ')'))"/></xsl:when>
      <xsl:otherwise><xsl:value-of select="$a"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- ===== reading body (<para>) =================================================
       Stage 1 (mode="flat"): flatten to a string. <br> becomes the sentinel $BR,
       &nbsp; becomes a normal space, everything else is its text.
  -->
  <xsl:template match="br" mode="flat"><xsl:value-of select="$BR"/></xsl:template>
  <xsl:template match="text()" mode="flat">
    <!-- nbsp -> space (real indentation); source newlines/tabs are insignificant HTML
         formatting and are DELETED (translate replacement shorter than search drops
         the extra chars). The only output newlines come from emit-runs after a break. -->
    <xsl:value-of select="translate(., '&#160;&#10;&#9;', ' ')"/>
  </xsl:template>
  <xsl:template match="*" mode="flat"><xsl:apply-templates mode="flat"/></xsl:template>

  <!-- Stage 2: wrap quoted speech in <q>, recursively, honouring nesting and the
       per-language pair set $qpairs. Edge spaces inside a quote are trimmed so the
       tags hug the text. The line-break sentinel is turned back into <l/>. -->
  <xsl:template name="emit-quoted">
    <xsl:param name="text"/>
    <xsl:param name="brk" select="'l'"/>
    <!-- quote-nesting depth: each line after a break is indented 6 + 2*depth spaces -->
    <xsl:param name="depth" select="0"/>
    <xsl:variable name="minpos">
      <xsl:call-template name="min-open-pos">
        <xsl:with-param name="pairs" select="$qpairs"/>
        <xsl:with-param name="text" select="$text"/>
        <xsl:with-param name="best" select="$BIG"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="number($minpos) &gt;= $BIG">
        <xsl:call-template name="emit-runs"><xsl:with-param name="text" select="$text"/><xsl:with-param name="brk" select="$brk"/><xsl:with-param name="depth" select="$depth"/></xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="pair"
            select="$qpairs[contains($text, @open) and (string-length(substring-before($text, @open)) + 1) = number($minpos)][1]"/>
        <xsl:variable name="open" select="string($pair/@open)"/>
        <xsl:variable name="close" select="string($pair/@close)"/>
        <xsl:variable name="prefix" select="substring-before($text, $open)"/>
        <xsl:variable name="rest" select="substring-after($text, $open)"/>
        <xsl:variable name="cpos">
          <xsl:call-template name="close-pos">
            <xsl:with-param name="s" select="$rest"/>
            <xsl:with-param name="open" select="$open"/>
            <xsl:with-param name="close" select="$close"/>
            <xsl:with-param name="depth" select="0"/>
            <xsl:with-param name="consumed" select="0"/>
          </xsl:call-template>
        </xsl:variable>
        <xsl:variable name="inner" select="substring($rest, 1, number($cpos) - 1)"/>
        <xsl:variable name="tail" select="substring($rest, number($cpos) + 1)"/>
        <xsl:call-template name="emit-runs"><xsl:with-param name="text" select="$prefix"/><xsl:with-param name="brk" select="$brk"/><xsl:with-param name="depth" select="$depth"/></xsl:call-template>
        <q>
          <xsl:call-template name="emit-quoted">
            <xsl:with-param name="text">
              <xsl:call-template name="trim-edges"><xsl:with-param name="s" select="$inner"/></xsl:call-template>
            </xsl:with-param>
            <xsl:with-param name="brk" select="$brk"/>
            <xsl:with-param name="depth" select="$depth + 1"/>
          </xsl:call-template>
        </q>
        <xsl:call-template name="emit-quoted"><xsl:with-param name="text" select="$tail"/><xsl:with-param name="brk" select="$brk"/><xsl:with-param name="depth" select="$depth"/></xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- smallest position (1-based) of any active opening delimiter in $text; $BIG if none -->
  <xsl:template name="min-open-pos">
    <xsl:param name="pairs"/>
    <xsl:param name="text"/>
    <xsl:param name="best"/>
    <xsl:choose>
      <xsl:when test="not($pairs)"><xsl:value-of select="$best"/></xsl:when>
      <xsl:otherwise>
        <xsl:variable name="idx">
          <xsl:choose>
            <xsl:when test="contains($text, $pairs[1]/@open)"><xsl:value-of select="string-length(substring-before($text, $pairs[1]/@open)) + 1"/></xsl:when>
            <xsl:otherwise><xsl:value-of select="$BIG"/></xsl:otherwise>
          </xsl:choose>
        </xsl:variable>
        <xsl:variable name="newbest">
          <xsl:choose>
            <xsl:when test="number($idx) &lt; number($best)"><xsl:value-of select="$idx"/></xsl:when>
            <xsl:otherwise><xsl:value-of select="$best"/></xsl:otherwise>
          </xsl:choose>
        </xsl:variable>
        <xsl:call-template name="min-open-pos">
          <xsl:with-param name="pairs" select="$pairs[position() &gt; 1]"/>
          <xsl:with-param name="text" select="$text"/>
          <xsl:with-param name="best" select="$newbest"/>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- 1-based index within $s of the close that matches the already-opened quote,
       counting nested opens. If never closed, returns end-of-string. -->
  <xsl:template name="close-pos">
    <xsl:param name="s"/>
    <xsl:param name="open"/>
    <xsl:param name="close"/>
    <xsl:param name="depth"/>
    <xsl:param name="consumed"/>
    <xsl:variable name="io">
      <xsl:choose>
        <xsl:when test="contains($s, $open)"><xsl:value-of select="string-length(substring-before($s, $open)) + 1"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$BIG"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:variable name="ic">
      <xsl:choose>
        <xsl:when test="contains($s, $close)"><xsl:value-of select="string-length(substring-before($s, $close)) + 1"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$BIG"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="number($ic) &gt;= $BIG">
        <xsl:value-of select="$consumed + string-length($s) + 1"/>
      </xsl:when>
      <xsl:when test="number($io) &lt; number($ic)">
        <xsl:call-template name="close-pos">
          <xsl:with-param name="s" select="substring($s, number($io) + 1)"/>
          <xsl:with-param name="open" select="$open"/>
          <xsl:with-param name="close" select="$close"/>
          <xsl:with-param name="depth" select="$depth + 1"/>
          <xsl:with-param name="consumed" select="$consumed + number($io)"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:when test="$depth = 0">
        <xsl:value-of select="$consumed + number($ic)"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:call-template name="close-pos">
          <xsl:with-param name="s" select="substring($s, number($ic) + 1)"/>
          <xsl:with-param name="open" select="$open"/>
          <xsl:with-param name="close" select="$close"/>
          <xsl:with-param name="depth" select="$depth - 1"/>
          <xsl:with-param name="consumed" select="$consumed + number($ic)"/>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- emit literal text, turning each line-break sentinel into the break element
       $brk (<l/> for prose readings, <n/> for psalms), then a newline + indent.
       Each line is indented 6 + 2*$depth spaces (6 = the <para> body base; +2 per
       open quote). The text BEFORE a break is right-trimmed (line-trailing space)
       and the text AFTER is left-trimmed (line-leading source indentation); interior
       spaces and spaces adjacent to a quote (a fragment with no break) are kept. -->
  <xsl:template name="emit-runs">
    <xsl:param name="text"/>
    <xsl:param name="brk" select="'l'"/>
    <xsl:param name="depth" select="0"/>
    <xsl:choose>
      <xsl:when test="contains($text, $BR)">
        <xsl:call-template name="trim-right">
          <xsl:with-param name="s" select="substring-before($text, $BR)"/>
        </xsl:call-template>
        <xsl:element name="{$brk}"/>
        <xsl:text>&#10;</xsl:text>
        <xsl:call-template name="emit-indent"><xsl:with-param name="n" select="6 + 2 * $depth"/></xsl:call-template>
        <xsl:call-template name="emit-runs">
          <xsl:with-param name="text">
            <xsl:call-template name="trim-left">
              <xsl:with-param name="s" select="substring-after($text, $BR)"/>
            </xsl:call-template>
          </xsl:with-param>
          <xsl:with-param name="brk" select="$brk"/>
          <xsl:with-param name="depth" select="$depth"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$text"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- emit $n literal spaces (line indentation) -->
  <xsl:template name="emit-indent">
    <xsl:param name="n"/>
    <xsl:if test="$n &gt; 0">
      <xsl:text> </xsl:text>
      <xsl:call-template name="emit-indent"><xsl:with-param name="n" select="$n - 1"/></xsl:call-template>
    </xsl:if>
  </xsl:template>

  <!-- strip break-sentinels + whitespace from the start and end of a para string,
       so no <l/> is emitted at the very beginning or end of <para> -->
  <xsl:template name="strip-edge-breaks">
    <xsl:param name="s"/>
    <xsl:variable name="l">
      <xsl:call-template name="strip-leading-breaks"><xsl:with-param name="s" select="$s"/></xsl:call-template>
    </xsl:variable>
    <xsl:call-template name="strip-trailing-breaks"><xsl:with-param name="s" select="string($l)"/></xsl:call-template>
  </xsl:template>
  <xsl:template name="strip-leading-breaks">
    <xsl:param name="s"/>
    <xsl:choose>
      <xsl:when test="string-length($s) &gt; 0 and contains($EDGE, substring($s, 1, 1))">
        <xsl:call-template name="strip-leading-breaks"><xsl:with-param name="s" select="substring($s, 2)"/></xsl:call-template>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$s"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template name="strip-trailing-breaks">
    <xsl:param name="s"/>
    <xsl:choose>
      <xsl:when test="string-length($s) &gt; 0 and contains($EDGE, substring($s, string-length($s), 1))">
        <xsl:call-template name="strip-trailing-breaks"><xsl:with-param name="s" select="substring($s, 1, string-length($s) - 1)"/></xsl:call-template>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$s"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- drop whitespace-only lines (the empty line a <br><br> leaves between two
       breaks), rejoining the survivors with a single break sentinel -->
  <xsl:template name="drop-blank-lines">
    <xsl:param name="s"/>
    <xsl:param name="acc" select="''"/>
    <xsl:variable name="has-more" select="contains($s, $BR)"/>
    <xsl:variable name="line">
      <xsl:choose>
        <xsl:when test="$has-more"><xsl:value-of select="substring-before($s, $BR)"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$s"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:variable name="newacc">
      <xsl:choose>
        <xsl:when test="normalize-space($line) = ''"><xsl:value-of select="$acc"/></xsl:when>
        <xsl:when test="$acc = ''"><xsl:value-of select="$line"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="concat($acc, $BR, $line)"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="$has-more">
        <xsl:call-template name="drop-blank-lines">
          <xsl:with-param name="s" select="substring-after($s, $BR)"/>
          <xsl:with-param name="acc" select="string($newacc)"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$newacc"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- trim leading/trailing spaces so <q> tags hug the quoted text -->
  <xsl:template name="trim-edges">
    <xsl:param name="s"/>
    <xsl:variable name="l">
      <xsl:call-template name="trim-left"><xsl:with-param name="s" select="$s"/></xsl:call-template>
    </xsl:variable>
    <xsl:call-template name="trim-right"><xsl:with-param name="s" select="string($l)"/></xsl:call-template>
  </xsl:template>
  <xsl:template name="trim-left">
    <xsl:param name="s"/>
    <xsl:choose>
      <xsl:when test="starts-with($s, ' ')">
        <xsl:call-template name="trim-left"><xsl:with-param name="s" select="substring($s, 2)"/></xsl:call-template>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$s"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template name="trim-right">
    <xsl:param name="s"/>
    <xsl:choose>
      <xsl:when test="substring($s, string-length($s), 1) = ' '">
        <xsl:call-template name="trim-right"><xsl:with-param name="s" select="substring($s, 1, string-length($s) - 1)"/></xsl:call-template>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$s"/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>

</xsl:stylesheet>
