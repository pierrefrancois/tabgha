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

  Status: scaffold. Implemented against the confirmed rules:
    - an <elementum> per reading block (div.b-verse). NOTE @nomen is NOT unique:
      alternative versions share @nomen, differ by @optio, and are separated by
      <vel> (usually empty). A block with an "OR:" marker should therefore yield
      several same-@nomen elementa + <vel> (TODO at bottom), not one.
    - section name -> @nomen
    - <referentia> with mandatory @elibro, and references parsed per the rule
      "single verse = bare <cap>/<vers>; contiguous range = <ab>..</ab> <ad>..</ad>"
  Clearly-marked TODOs remain for parts of the spec not yet settled (see bottom).
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

  <!-- <die>: the current date in the pager just above the title,
       <li class="current"><time>May 25, 2026</time></li> -> "May 25" (year dropped).
       Empty (=> no <die> element) when the page has no such date. -->
  <xsl:variable name="date-text"
      select="normalize-space((//li[contains(concat(' ', normalize-space(@class), ' '), ' current ')]/time)[1])"/>
  <xsl:variable name="die">
    <xsl:choose>
      <xsl:when test="contains($date-text, ',')">
        <xsl:value-of select="normalize-space(substring-before($date-text, ','))"/>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$date-text"/></xsl:otherwise>
    </xsl:choose>
  </xsl:variable>

  <!-- <gradus>: rank named in the celebration title (<h2> of div.b-lectionary).
       Solemnity -> solemnitas, Feast -> festum, Memorial -> memoria; otherwise
       (e.g. a plain weekday) no <gradus> element. -->
  <xsl:variable name="title-lc"
      select="translate(normalize-space((//div[contains(concat(' ', normalize-space(@class), ' '), ' b-lectionary ')]//h2)[1]),
                        'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')"/>
  <xsl:variable name="gradus">
    <xsl:choose>
      <xsl:when test="contains($title-lc, 'solemnity')">solemnitas</xsl:when>
      <xsl:when test="contains($title-lc, 'feast')">festum</xsl:when>
      <xsl:when test="contains($title-lc, 'memorial')">memoria</xsl:when>
    </xsl:choose>
  </xsl:variable>

  <!-- Book name -> elibro code lookup (extend as new sources appear). -->
  <xsl:variable name="books-rtf">
    <book name="Genesis" code="Gen"/>
    <book name="Exodus" code="Ex"/>
    <book name="Leviticus" code="Lev"/>
    <book name="Numbers" code="Num"/>
    <book name="Deuteronomy" code="Deut"/>
    <book name="Psalms" code="Ps"/>
    <book name="Psalm" code="Ps"/>
    <book name="Isaiah" code="Is"/>
    <book name="Jeremiah" code="Ier"/>
    <book name="Acts" code="Act"/>
    <book name="Romans" code="Rom"/>
    <book name="Matthew" code="Mt"/>
    <book name="Mark" code="Mc"/>
    <book name="Luke" code="Lc"/>
    <book name="John" code="Io"/>
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
       nesting/mixing is handled by depth-matching. NB en deliberately omits the
       single pair (U+2018/U+2019) because U+2019 doubles as the apostrophe. -->
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
    <xsl:variable name="name"
        select="normalize-space(.//h3[contains(concat(' ', normalize-space(@class), ' '), ' name ')])"/>
    <xsl:variable name="header-address"
        select="normalize-space(.//div[contains(concat(' ', normalize-space(@class), ' '), ' address ')]//a)"/>
    <xsl:variable name="body"
        select=".//div[contains(concat(' ', normalize-space(@class), ' '), ' content-body ')]/p"/>

    <xsl:variable name="nomen">
      <xsl:choose>
        <xsl:when test="starts-with($name, 'Reading')">lectio</xsl:when>
        <xsl:when test="contains($name, 'Psalm')">psalmus-responsorialis</xsl:when>
        <xsl:when test="contains($name, 'Alleluia') or contains($name, 'Acclamation')">alleluia</xsl:when>
        <xsl:when test="contains($name, 'Gospel')">evangelium</xsl:when>
        <xsl:otherwise>ignotum</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:variable name="is-reading" select="$nomen = 'lectio' or $nomen = 'evangelium'"/>

    <!-- "OR:" delimiters inside the body split one block into alternative options.
         Each option becomes a full <elementum> (same @nomen, distinct @optio),
         joined by <vel/>. See memory: elementum-optio-vel. -->
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

  <!-- Emit one <elementum> for option number $seg of a reading block. -->
  <xsl:template name="emit-option">
    <xsl:param name="body"/>
    <xsl:param name="seg"/>
    <xsl:param name="nomen"/>
    <xsl:param name="is-reading"/>
    <xsl:param name="multi"/>
    <xsl:param name="header-address"/>

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
        <xsl:otherwise><xsl:value-of select="normalize-space($seg-nodes[self::a][1])"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <xsl:variable name="bk" select="$books[starts-with($address, @name)][1]"/>
    <xsl:variable name="code">
      <xsl:choose>
        <xsl:when test="$bk"><xsl:value-of select="$bk/@code"/></xsl:when>
        <xsl:otherwise>?</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <elementum nomen="{$nomen}">
      <!-- @optio only when this block has alternatives. For "different passage"
           alternatives optio = book code; unknown -> "?" (reported, file still written). -->
      <xsl:if test="$multi">
        <xsl:attribute name="optio"><xsl:value-of select="$code"/></xsl:attribute>
        <xsl:if test="$code = '?'">
          <xsl:message>tabgha: could not derive @optio (nomen=<xsl:value-of select="$nomen"/>, address="<xsl:value-of select="$address"/>") — left optio="?"</xsl:message>
        </xsl:if>
      </xsl:if>

      <xsl:if test="$is-reading"><thema/></xsl:if>

      <xsl:if test="string($address)">
        <referentia elibro="{$code}">
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
       Grammar handled: comma-separated references; ' and ' also separates verses.
       A reference is either C:V, C:V-V2 (range), or a bare V (chapter carried over).
       Single verse  -> bare <cap>/<vers>;  contiguous range -> <ab>..</ab> <ad>..</ad>.
  -->
  <xsl:template name="emit-references">
    <xsl:param name="text"/>
    <xsl:param name="chapter"/>
    <xsl:variable name="t" select="normalize-space($text)"/>
    <xsl:if test="$t != ''">
      <xsl:variable name="first" select="normalize-space(substring-before(concat($t, ','), ','))"/>
      <xsl:variable name="rest"  select="substring-after($t, ',')"/>
      <!-- chapter context updates only when this segment names a chapter (has ':') -->
      <xsl:variable name="chap">
        <xsl:choose>
          <xsl:when test="contains($first, ':')"><xsl:value-of select="normalize-space(substring-before($first, ':'))"/></xsl:when>
          <xsl:otherwise><xsl:value-of select="$chapter"/></xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:call-template name="emit-and-group">
        <xsl:with-param name="group" select="$first"/>
        <xsl:with-param name="chapter" select="$chap"/>
      </xsl:call-template>
      <xsl:call-template name="emit-references">
        <xsl:with-param name="text" select="$rest"/>
        <xsl:with-param name="chapter" select="$chap"/>
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
        <xsl:with-param name="chapter" select="$chapter"/>
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

  <!-- emit one reference: bare verse or ab/ad range -->
  <xsl:template name="emit-item">
    <xsl:param name="item"/>
    <xsl:param name="chapter"/>
    <xsl:variable name="it" select="normalize-space($item)"/>
    <xsl:if test="$it != ''">
      <xsl:variable name="cap">
        <xsl:choose>
          <xsl:when test="contains($it, ':')"><xsl:value-of select="normalize-space(substring-before($it, ':'))"/></xsl:when>
          <xsl:otherwise><xsl:value-of select="$chapter"/></xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:variable name="vpart">
        <xsl:choose>
          <xsl:when test="contains($it, ':')"><xsl:value-of select="normalize-space(substring-after($it, ':'))"/></xsl:when>
          <xsl:otherwise><xsl:value-of select="$it"/></xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:choose>
        <xsl:when test="contains($vpart, '-')">
          <!-- TODO: cross-chapter ranges (right side "C:V") not yet handled -->
          <ab><cap><xsl:value-of select="$cap"/></cap><vers><xsl:value-of select="normalize-space(substring-before($vpart, '-'))"/></vers></ab>
          <ad><cap><xsl:value-of select="$cap"/></cap><vers><xsl:value-of select="normalize-space(substring-after($vpart, '-'))"/></vers></ad>
        </xsl:when>
        <xsl:otherwise>
          <cap><xsl:value-of select="$cap"/></cap><vers><xsl:value-of select="$vpart"/></vers>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:if>
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
    <xsl:variable name="t" select="normalize-space($text)"/>
    <xsl:if test="$t != ''">
      <xsl:variable name="first" select="normalize-space(substring-before(concat($t, ','), ','))"/>
      <xsl:variable name="rest" select="substring-after($t, ',')"/>
      <xsl:variable name="chap">
        <xsl:choose>
          <xsl:when test="contains($first, ':')"><xsl:value-of select="normalize-space(substring-before($first, ':'))"/></xsl:when>
          <xsl:otherwise><xsl:value-of select="$chapter"/></xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <stropha>
        <xsl:call-template name="emit-and-group">
          <xsl:with-param name="group" select="$first"/>
          <xsl:with-param name="chapter" select="$chap"/>
        </xsl:call-template>
      </stropha>
      <xsl:call-template name="emit-strophe-refs">
        <xsl:with-param name="text" select="$rest"/>
        <xsl:with-param name="chapter" select="$chap"/>
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
