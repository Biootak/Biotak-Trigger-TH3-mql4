#!/usr/bin/env python3
# P-DRAW-INK / P-ORPHAN-ALL: restate the two gates the new law made stale and add the
# two new blocks. The file is CRLF (repo law): every splice goes through \n and lands
# back as \r\n, or a later str_replace edit would produce mixed endings.
import io, sys

P = "tools/check-regressions.js"
raw = open(P, "rb").read().decode("utf-8")
txt = raw.replace("\r\n", "\n")

REPL = []

# ---------------------------------------------------------------- P-DRAW-75 (value)
old75 = """    if (!apFn) broken.push('`DrawStyleApplyOnCreate` is gone or unreadable \u2014 it is the one writer onto a fresh drawing (P-DRAW-75)');
    else if (!/DRAW_CAP_COLOR\\) != 0 && \\(int\\)s_dkColor\\[k\\] >= 0/.test(apFn))
      broken.push('the create path writes an unchosen colour \u2014 clrNONE (-1) paints white, anchors alone (P-DRAW-75)');
"""
new75 = """    if (!apFn) broken.push('`DrawStyleApplyOnCreate` is gone or unreadable \u2014 it is the one writer onto a fresh drawing (P-DRAW-75)');
    else {
      // P-DRAW-INK (2026-10-04): the VALUE the guard guards changed when the hand\u2019s own
      // report arrived \u2014 \u00ab\u0686\u0631\u0627 \u0631\u0646\u06af\u0634 \u067e\u06cc\u0634\u200c\u0641\u0631\u0636 \u06a9\u0647 \u0645\u06cc\u06a9\u0634\u0645 \u0633\u0641\u06cc\u062f \u0647\u0633\u062a\u0634\u061f \u0622\u062e\u0631\u06cc\u0646 \u062a\u063a\u06cc\u06cc\u0631\u0627\u062a \u0622\u0628\u06cc \u0628\u0648\u062f\u00bb. A kind with no
      // colour of its own now takes the LAST ink the hand picked ANYWHERE before it takes
      // the terminal\u2019s factory white. What has not changed is the law this entry exists
      // for: the value that reaches the object is never clrNONE.
      if (!/color want = s_dkColor\\[k\\];/.test(apFn) || !/if\\(\\(int\\)want < 0\\) want = s_dkAnyClr;/.test(apFn))
        broken.push('the create path no longer falls back to the last ink \u2014 a fibo of a kind never coloured is born factory-white while the hand is drawing in blue (P-DRAW-INK)');
      if (!/DRAW_CAP_COLOR\\) != 0 && \\(int\\)want >= 0/.test(apFn))
        broken.push('the create path writes an unchosen colour \u2014 clrNONE (-1) paints white, anchors alone (P-DRAW-75)');
    }
"""
REPL.append((old75, new75))

old75pass = """      console.log('[PASS] P-DRAW-75 a colour never chosen is never written: the create path keeps the terminal default until the first real pick');"""
new75pass = """      console.log('[PASS] P-DRAW-75/P-DRAW-INK the create path writes only a colour the hand chose: the kind\u2019s own memory first, else the last ink picked anywhere, else the terminal default');"""
REPL.append((old75pass, new75pass))

# ---------------------------------------------------------------- P-DRAW-09c (bit map)
oldmap = """      if (bAt < 0) broken.push('DrawStyleUnpack() no longer splits its two numbers \u2014 half the look would be read out of the other half\\u2019s bits');
      else if (aS.join(',') !== uA.join(','))
        broken.push(`the pack and the unpack disagree on A\\u2019s layout (pack << ${aS.join(',')} vs unpack >> ${uA.join(',')}): one of the two reads another slot\\u2019s bits`);
      else if (bS.join(',') !== uB.join(','))
        broken.push(`the pack and the unpack disagree on B\\u2019s layout (pack << ${bS.join(',')} vs unpack >> ${uB.join(',')})`);
"""
newmap = """      // P-DRAW-INK (2026-10-04): the contract is the BIT MAP, not the order the two
      // functions happen to name their fields in \u2014 the unpack reads the presence bit it
      // was given by P-DRAW-INK first, and that is a field, not a disagreement. The
      // comparison is a set for that reason, and it still catches the defect it was
      // written for: a shift edited on ONE side (a number that appears in one list and
      // not the other).
      const sameBits = (x, y) => x.slice().sort((p, q) => p - q).join(',') === y.slice().sort((p, q) => p - q).join(',');
      if (bAt < 0) broken.push('DrawStyleUnpack() no longer splits its two numbers \u2014 half the look would be read out of the other half\u2019s bits');
      else if (!sameBits(aS, uA))
        broken.push(`the pack and the unpack disagree on A\\u2019s bit map (pack << ${aS.join(',')} vs unpack >> ${uA.join(',')}): one of the two reads another slot\\u2019s bits`);
      else if (!sameBits(bS, uB))
        broken.push(`the pack and the unpack disagree on B\\u2019s bit map (pack << ${bS.join(',')} vs unpack >> ${uB.join(',')})`);
"""
REPL.append((oldmap, newmap))

# ---------------------------------------------------------------- the two new blocks
anchor = """      console.log('[PASS] P-DRAW-09c the last look is the default across attaches: one reserved slot in the presets\\u2019 own file, written by the same single writer, and the pack and the unpack agree on every bit');
    }
  }

  console.log('');
"""

ink_block = """  // \u2500\u2500 P-DRAW-INK (2026-10-04) \u2014 THE LAST INK THE HAND CHOSE IS THE ONE IT DRAWS WITH \u2500\u2500
  // Report, on a chart whose fibos had been given a width and a look but never a colour:
  // \u00ab\u0686\u0631\u0627 \u0631\u0646\u06af\u0634 \u067e\u06cc\u0634\u200c\u0641\u0631\u0636 \u06a9\u0647 \u0645\u06cc\u06a9\u0634\u0645 \u0633\u0641\u06cc\u062f \u0647\u0633\u062a\u0634\u061f \u0622\u062e\u0631\u06cc\u0646 \u062a\u063a\u06cc\u06cc\u0631\u0627\u062a \u0622\u0628\u06cc \u0628\u0648\u062f \u0627\u06cc\u0646 \u0647\u0645 \u062f\u0631\u0633\u062a \u06a9\u0646 \u0628\u0631\u0627\u06cc \u0647\u0645\u0647 \u062c\u0627\u0647\u0627\u00bb \u2014 and the hand\u2019s own
  // disk said why. `Biotak\\DrawPresets.csv` carried `5;255;550091358208;771751935`: kind 5
  // (fibo), the last-look row, colour field 0xFFFFFF. P-DRAW-09c masked clrNONE with
  // `& 0xFFFFFF`, and -1 masks to WHITE \u2014 so the memory\u2019s emptiness came back from the
  // file as a colour nobody chose, the create path wrote it (it IS >= 0), and every fibo
  // born afterwards was white. Also measured in MQL4/Files: `Fibo 56218` and `Fibo 58985`
  // were born white this way, their whole `_FSD` pen included. Three things must hold:
  //   (a) the pack SAYS whether a colour is present (bit 33) and the unpack believes it,
  //       so a row written by the build without the bit reads as \u201cno colour of its own\u201d
  //       and P-DRAW-75\u2019s rule heals instead of painting white;
  //   (b) the one ink every kind shares is noted on every colour the hand picks, saved in
  //       a reserved slot of the same file, and restored BEFORE the preset bands (254 is
  //       outside every band on purpose, exactly like 255);
  //   (c) the create path wears it (P-DRAW-75 asserts the guard on the value it reaches).
  {
    const broken = [];
    const tbbLines = linesOf(path.join(BIOTAK, 'Toolbar_B.mqh')) || [];
    const tbb = codeOf(tbbLines);
    const packA = bodyOf(tbbLines, 'double DrawStylePackA(');
    const unpack = bodyOf(tbbLines, 'void DrawStyleUnpack(');
    if (!packA || !unpack) {
      broken.push('the look pack/unpack pair is gone from Biotak/Toolbar_B.mqh \u2014 a colour and a missing colour could not be told apart at all');
    } else {
      if (!/<< 33/.test(packA.text))
        broken.push('\u201cno colour of its own\u201d is masked as white again \u2014 the presence bit (33) left the pack, and `-1 & 0xFFFFFF` is 0xFFFFFF');
      if (!/>> 33/.test(unpack.text) || !/clrNONE/.test(unpack.text))
        broken.push('the unpack ignores the presence bit and reads the masked field as a colour \u2014 a kind that never had one comes back WHITE');
    }
    if (!/define DRAW_LASTINK_SLOT/.test(tbb))
      broken.push('the reserved last-ink slot is gone \u2014 the ink cannot survive an attach');
    const save = bodyOf(tbbLines, 'void DrawPresetsSave()');
    if (save && !/DRAW_LASTINK_SLOT/.test(save.text))
      broken.push('the save never writes the last ink \u2014 the next attach starts on the terminal default again');
    const load = bodyOf(tbbLines, 'void DrawPresetsLoad()');
    if (load) {
      const at = load.text.indexOf('i == DRAW_LASTINK_SLOT');
      const band = load.text.indexOf('i < DRAW_PRESET_BUILTIN');
      if (at < 0) broken.push('the load never restores the last ink');
      else if (band >= 0 && at > band)
        broken.push('the last-ink row is read BELOW the preset bands \u2014 slot 254 is outside every band on purpose, so that guard eats the row');
    }
    const write = bodyOf(tbbLines, 'bool DrawSlotWrite(');
    if (write && !/s_dkAnyClr = c;/.test(write.text))
      broken.push('the one colour writer stopped noting the last ink \u2014 the fallback would answer with a stale colour forever');
    if (broken.length) {
      failures.push('P-DRAW-INK: ' + broken.join('; ') + ' (Biotak/Toolbar_B.mqh: one presence bit in A, one reserved row, one ink for the kinds that never had a colour)');
    } else {
      console.log('[PASS] P-DRAW-INK the last colour the hand picks is the one a fresh drawing wears: the presence bit keeps clrNONE out of the file, and the shared ink is noted, saved and restored');
    }
  }

  // \u2500\u2500 P-ORPHAN-ALL (2026-10-04) \u2014 NO REMNANT OUTLIVES ITS MASTER \u2500\u2500
  // \u00ab\u0627\u06cc\u0646 \u0628\u0642\u0627\u06cc\u0634 \u0686\u0631\u0627 \u062d\u0630\u0641 \u0646\u0645\u06cc\u0634\u0647\u061f \u0628\u0631\u0627\u06cc \u06a9\u0644 \u067e\u0631\u0648\u0698\u0647 \u0631\u0648 \u0686\u06a9 \u06a9\u0646 \u06a9\u0647 \u0645\u062b\u0644 \u0627\u06cc\u0646 \u0646\u0628\u0627\u0634\u0647\u00bb \u2014 and MT4\u2019s own chart file agreed with the
  // screenshot: `profiles/default/chart01.chr` (written at the terminal\u2019s shutdown,
  // 2026-10-04 09:45) still carried all 36 `_FSD` pen rows of TWO fibos that were gone from
  // it (`Fibo 54705`, `Fibo 58985`). The pen had no orphan rule of its own until
  // P-LOOK-RAY2; the interior\u2019s and the 50 % line\u2019s had one each. What none of the three
  // had was a WITNESS, so a cleanup was invisible and could only be believed. Three laws
  // now hold for every companion family the drawing tool builds \u2014 the interior\u2019s child,
  // the box\u2019s 50 % line, the fibo pen\u2019s rows:
  //   (a) the pass that already walks every object every 2 s answers \u201cis your master
  //       still here?\u201d for each of them, through ONE deleter;
  //   (b) that deleter names the drop (and its missing master) on the flushed diag
  //       channel, so the cleanup is evidence rather than faith;
  //   (c) both delete routes \u2014 the strip\u2019s bin and the terminal\u2019s own native delete \u2014
  //       drop the family in the event itself, not 2 s later.
  // The inverse that must fail here: a family with a suffix, a builder and a parent
  // parser but no orphan rule on the pass.
  {
    const broken = [];
    const pickLines = linesOf(path.join(BIOTAK, 'DrawStrip_Pick.mqh')) || [];
    const pump = bodyOf(pickLines, 'void BoxExtrasPump()');
    const drop = bodyOf(pickLines, 'void DrawOrphanDrop(');
    if (!pump) broken.push('BoxExtrasPump() is gone from Biotak/DrawStrip_Pick.mqh \u2014 it is the chart-side pass every orphan rule rides');
    else {
      const families = [
        ['FillIsChild', 'the interior\u2019s child (`FillIsChild`/`FillChildParent`)'],
        ['BoxIsMidChild', 'the box\u2019s 50 % line (`BoxIsMidChild`/`BoxMidParent`)'],
        ['FibPenIsChild', 'the fibo pen\u2019s rows (`FibPenIsChild`/`FibPenFamIsChild`/`FibPenChildParent`)'],
      ];
      for (const [test, what] of families) {
        const at = pump.text.indexOf(test);
        if (at < 0) { broken.push(`the orphan rule for ${what} left the pass`); continue; }
        const seat = pump.text.slice(at, at + 900);
        if (!/ObjectFind\\(0, par\\) < 0\\)/.test(seat) || !/DrawOrphanDrop\\(nm, par\\)/.test(seat))
          broken.push(`the orphan rule for ${what} no longer deletes through DrawOrphanDrop \u2014 the companion of a deleted master survives the pass`);
      }
    }
    if (!drop) broken.push('DrawOrphanDrop() is gone \u2014 the one deleter, and the only witness a drop has');
    else if (!/ObjectDelete\\(0, nm\\)/.test(drop.text) || !/DrawStripDiagEmit\\(/.test(drop.text) || !/ORPHAN/.test(drop.text))
      broken.push('DrawOrphanDrop() no longer deletes AND names the drop \u2014 the cleanup is invisible again');
    const tbr = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Router.mqh')) || []);
    if (!/FibPenStraysDrop\\(sparam\\)/.test(tbr) || !/BoxMidDrop\\(sparam\\)/.test(tbr) || !/FillChildDrop\\(sparam\\)/.test(tbr))
      broken.push('the terminal\u2019s own delete branch stopped dropping the deleted drawing\u2019s families \u2014 a native delete leaves them on the chart');
    const tap = codeOf(linesOf(path.join(BIOTAK, 'DrawStrip_Tap.mqh')) || []);
    if (!/FibPenSync\\(DrawSelAt\\(j\\), true\\)/.test(tap) || !/FibPenSync\\(s_dsObj, true\\)/.test(tap))
      broken.push('the strip\u2019s bin stopped dropping the fibo pen \u2014 the rows outlive the drawing they were built for');
    if (broken.length) {
      failures.push('P-ORPHAN-ALL: ' + broken.join('; ') + ' (Biotak/DrawStrip_Pick.mqh + DrawStrip_Router.mqh + DrawStrip_Tap.mqh)');
    } else {
      console.log('[PASS] P-ORPHAN-ALL no remnant outlives its master: all three companion families answer for themselves on the 2 s pass through one deleter that witnesses every drop, and both delete routes drop them in the event itself');
    }
  }

  console.log('');
"""

REPL.append((anchor, anchor + ink_block))

out = txt
for old, new in REPL:
    n = out.count(old)
    if n != 1:
        print("!! anchor matched %d times: %r" % (n, old[:90]))
        sys.exit(1)
    out = out.replace(old, new)

open(P, "wb").write(out.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
print("patched", P)
