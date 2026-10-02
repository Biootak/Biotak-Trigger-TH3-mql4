#!/usr/bin/env python3
"""
THE MUTATION GATE — prove the gates can FAIL, or admit they cannot.

WHY. A green gate proves something only if that gate is able to go red. On 2026-10-01 a
band's `.cnt` pill read 4 for a two-member group and EVERY gate was green, because none
of them measured the number: the check existed, the assertion did not. The industry
answer to exactly that asymmetry is mutation testing — put the defect back, and the
suite must die (Zeller's delta debugging asks the same question of a failing input: what
is the MINIMAL change between the passing and the failing case?). This tool does it for
this project's rules, one rule at a time:

  * apply the mutation (the exact inverse of a fixed defect, by literal string),
  * run the gate that owns the rule,
  * KILLED  = the gate failed AND its message names the rule — the objective evidence
              is the gate's own failing line, printed here,
  * SURVIVED = the gate passed, so the rule is NOT gated: a blind spot, and a build fail,
  * STALE    = the anchor is gone (the code moved), which is its own alarm: a mutation
              that no longer applies is a check that no longer runs.

SAFETY. Every mutated file is restored from an in-memory copy in a `finally`, and every
touched file's sha256 is verified against its pre-run hash before this tool reports
anything. It never uses git (your uncommitted work is not its business), it mutates one
file at a time, and it takes about two seconds. Run it when nobody else is editing the
tree: an outside write during the ~0.3 s a mutation is on disk would be overwritten.

  python tools/mutation_gate.py            # every mutation
  python tools/mutation_gate.py P-DRAW-121 # one rule
  python tools/mutation_gate.py --list     # the mutations + which register entries lack one

Exit 0 = every mutation was killed and the tree is byte-identical to how it was found.
"""

import hashlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

#--- the gates a mutation may be aimed at: key -> (runner, path from ROOT, label)
GATES = {
    "gear": ("python", "tools/check-gear-panel.py", "gear panel gate"),
    "lifecycle": ("node", "tools/object_lifecycle_check.js", "object lifecycle gate"),
    "regression": ("node", "tools/check-regressions.js", "regression gate"),
    "resources": ("node", "tools/check-resources.js", "resource gate"),
}

GEAR_B = "Biotak/DrawStrip_GearB.mqh"
STRIP_BASE = "Biotak/DrawStrip_Base.mqh"
GEAR_SIM = "tools/sim-gear-panel.py"
GEAR_GATE = "tools/check-gear-panel.py"
REGISTER = "tools/check-regressions.js"

#--- ONE RULE PER MUTATION. `find` is the fixed spelling, `replace` puts the defect back;
#--- `expect` is the text the owning gate must print (its own message, so a gate that
#--- fails for an unrelated reason does not count as a kill).
MUTATIONS = [
    {
        "id": "P-DRAW-121",
        "gate": "gear",
        "rule": "a band's pill counts members, never the accordion's nav",
        "what": "the row loop stops excluding DSTRIP_GRK_GROUP",
        "file": GEAR_B,
        "find": "      if(s_dsGRKind[r] != DSTRIP_GRK_GROUP &&\r\n"
                "         s_dsGRCol[r] == col && s_dsGRY[r] >= y0 && s_dsGRY[r] < y1) n++;",
        "replace": "      if(s_dsGRCol[r] == col && s_dsGRY[r] >= y0 && s_dsGRY[r] < y1) n++;",
        "expect": "P-DRAW-121",
    },
    {
        "id": "P-DRAW-121b",
        "gate": "gear",
        "rule": "the mirror's nav detector must be able to fire (self-test)",
        "what": "the mirror stops noticing group headers inside a band's range",
        "file": GEAR_SIM,
        "find": "            if b[3] and str(b[3][0]) == str(GRK_GROUP):",
        "replace": "            if False and b[3] and str(b[3][0]) == str(GRK_GROUP):",
        "expect": "detector is blind",
    },
    {
        "id": "P-DRAW-121c",
        "gate": "regression",
        "rule": "the gate must assert the count rule and its numbers",
        "what": "the gear gate stops asserting the rule (the register must notice)",
        "file": GEAR_GATE,
        "find": "        check(M.count_rule_excludes_nav(),",
        "replace": "        check(True,   # MUTATION: the assertion removed",
        "expect": "must assert the rule",
    },
    {
        "id": "P-DRAW-122",
        "gate": "lifecycle",
        "rule": "a painted layer is re-asserted every pass",
        "what": "DrawStripRect writes its layer only at birth again",
        "file": GEAR_B,
        "find": "   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_BGCOLOR, face);",
        "replace": "   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);\r\n"
                   "   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);\r\n"
                   "   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);\r\n"
                   "   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);\r\n"
                   "   dirty |= DrawStripSetInt(nm, OBJPROP_BGCOLOR, face);",
        "expect": "P-DRAW-122",
    },
    {
        "id": "P-DRAW-120",
        "gate": "regression",
        "rule": "a face re-asserts its own layer every paint",
        "what": "DrawStripFaceZ writes its layer only at birth again",
        "file": GEAR_B,
        "find": "   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);\r\n"
                "   int pw = DrawStripResW(res), ph = DrawStripResH(res);",
        "replace": "   int pw = DrawStripResW(res), ph = DrawStripResH(res);",
        "expect": "P-DRAW-120",
    },
    {
        "id": "P-DRAW-125",
        "gate": "regression",
        "rule": "the diagnostic repaints only an open, laid-out panel",
        "what": "the dump paints a shut panel again (head+foot of a closed panel, body deleted)",
        "file": GEAR_B,
        "find": "   if(s_dsGear != 0 && s_dsGearH > 0)\r\n"
                "   {\r\n"
                "      s_dsDiagArm = true;",
        "replace": "   if(true)\r\n"
                   "   {\r\n"
                   "      s_dsDiagArm = true;",
        "expect": "P-DRAW-125",
    },
    {
        "id": "P-DRAW-125b",
        "gate": "regression",
        "rule": "every writer asks the object's own TYPE, not its name alone",
        "what": "DrawStripForeign stops reading OBJPROP_TYPE (a foreign name is never reclaimed)",
        "file": STRIP_BASE,
        "find": "   if((int)ObjectGetInteger(0, nm, OBJPROP_TYPE) == type) return;",
        "replace": "   if(true) return;",
        "expect": "P-DRAW-125",
    },
]

#--- the register's own entries, so "no mutation yet" is a NUMBER and not a feeling.
SECTION_RX = r"//\s*--\s*\d+\.\s*(P-[A-Z0-9]+(?:-\d+)?)"


def short_list(ids, cap=14):
    return ", ".join(ids[:cap]) + (" (+%d more)" % (len(ids) - cap) if len(ids) > cap else "")


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def run_gate(key):
    runner, rel_path, _label = GATES[key]
    cmd = [runner, os.path.join(ROOT, rel_path)]
    try:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=600)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, str(e)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def register_entries():
    import re
    try:
        with open(os.path.join(ROOT, REGISTER), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return set()
    return {m.group(1) for m in re.finditer(SECTION_RX, text)}


def ascii_safe(s):
    """A gate may print a real em dash; this console is not UTF-8, so never echo bytes
    back raw — a proof line that renders as a question mark is not a proof line."""
    return "".join(c if ord(c) < 128 else "-" for c in s)


def proof_line(out, needle):
    for ln in out.splitlines():
        if needle in ln:
            return ascii_safe(ln.strip())[:150]
    tail = out.strip().splitlines()
    return ascii_safe(tail[-1])[:150] if tail else "(no output)"


def main():
    argv = [a for a in sys.argv[1:]]
    picked = [a for a in argv if not a.startswith("-")]
    entries = register_entries()
    covered = {m["id"] for m in MUTATIONS}

    if "--list" in argv:
        print("MUTATIONS (one rule each)")
        for m in MUTATIONS:
            print("  %-13s %-11s %s" % (m["id"], GATES[m["gate"]][2], m["rule"]))
            print("                %s: %s" % (m["file"], m["what"]))
        print("")
        print("register entries: %d, with a kill witness: %d"
              % (len(entries), len(covered & entries)))
        print("without one: %s" % (short_list(sorted(entries - covered))))
        return 0

    todo = [m for m in MUTATIONS if not picked or any(p in m["id"] for p in picked)]
    if not todo:
        print("no mutation matches %s" % ", ".join(picked))
        return 2

    touched = sorted({m["file"] for m in todo})
    before = {f: sha(os.path.join(ROOT, f)) for f in touched}

    print("=" * 72)
    print("MUTATION GATE  (a rule is only gated if its inverse fails a gate)")
    print("=" * 72)
    killed, survived, stale = [], [], []  # killed / not gated / anchor gone
    for m in todo:
        path = os.path.join(ROOT, m["file"])
        with open(path, encoding="utf-8", newline="") as fh:
            orig = fh.read()
        hits = orig.count(m["find"])
        label = "%-13s %-11s" % (m["id"], GATES[m["gate"]][2])
        if hits != 1:
            stale.append(m)
            print("  %s STALE   anchor found %d time(s) in %s — the rule moved or the "
                  "spelling changed" % (label, hits, m["file"]))
            print("                %s" % m["what"])
            continue
        try:
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(orig.replace(m["find"], m["replace"]))
            rc, out = run_gate(m["gate"])
        finally:
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(orig)
        if rc is None:
            survived.append(m)
            print("  %s ERROR   gate did not run: %s" % (label, ascii_safe(out)))
            continue
        if rc != 0 and m["expect"] in out:
            killed.append(m)
            print("  %s KILLED  %s" % (label, m["what"]))
            print("                proof: %s" % proof_line(out, m["expect"]))
        elif rc == 0:
            survived.append(m)
            print("  %s SURVIVED the gate passed with the defect back: %s" % (label, m["what"]))
            print("                rule: %s" % m["rule"])
        else:
            survived.append(m)
            print("  %s SURVIVED (wrong reason) the gate failed without naming the rule "
                  "(%r)" % (label, m["expect"]))
            print("                proof: %s" % proof_line(out, "FAIL"))

    #--- the tree must be exactly as we found it, or nothing here is trustworthy.
    after = {f: sha(os.path.join(ROOT, f)) for f in touched}
    drifted = [f for f in touched if before[f] != after[f]]
    print("")
    if drifted:
        print("TREE NOT RESTORED — %s" % ", ".join(drifted))
        return 2
    missing = sorted(entries - covered)
    print("mutations: %d  killed: %d  survived: %d  stale: %d   (tree restored, %d file(s) "
          "byte-identical)" % (len(todo), len(killed), len(survived), len(stale),
                               len(touched)))
    print("register entries: %d, covered by a mutation: %d%s"
          % (len(entries), len(covered & entries),
             ("\nwithout one: " + short_list(missing)) if missing else ""))
    if survived or stale:
        print("")
        print("FAIL: %d rule(s) are not gated (survived) and %d mutation(s) no longer "
              "apply (stale)." % (len(survived), len(stale)))
        return 1
    print("")
    print("PASS - every mutation was killed by the gate that owns its rule, and the tree "
          "is byte-identical to how it was found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
