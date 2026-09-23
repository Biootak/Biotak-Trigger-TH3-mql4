"""icon-ref-scan — one-off trace: every icon path the product code names, vs disk.

A referenced-but-missing raster is a blank cell on the user's chart, and a
referenced-but-not-#resource'd raster is a ghost (R-ICON). This is a diagnosis
pass, not a gate: it prints the three classes.
"""
import os
import re
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

NAME = re.compile(r"Icons[\\/]+([A-Za-z0-9_]+\.bmp)")
RES = re.compile(r'#resource\s+"([^"]+)"')

refs = {}          # icon name -> set of referencing files ("RES:x.mqh" for #resource)
for f in glob.glob(os.path.join(ROOT, "Biotak", "**", "*.mqh"), recursive=True) + \
         glob.glob(os.path.join(ROOT, "*.mq4")):
    txt = open(f, encoding="utf-8", errors="replace").read()
    base = os.path.basename(f)
    for m in NAME.finditer(txt):
        refs.setdefault(m.group(1), set()).add(base)
    for m in RES.finditer(txt):
        icon = os.path.basename(m.group(1))
        refs.setdefault(icon, set()).add("RES:" + base)

disk = set(os.listdir(os.path.join(ROOT, "Files", "Icons")))
manifest = set(x.strip() for x in open(os.path.join(ROOT, "tools", "icon-manifest.txt")) if x.strip())

print("icons named by product code:", len(refs))

missing = [k for k in sorted(refs) if k not in disk]
print("\n1) REFERENCED BUT NOT ON DISK (%d)  <- a blank cell on the chart" % len(missing))
for k in missing:
    print("   %-28s <- %s" % (k, ", ".join(sorted(refs[k]))))

ghost = [k for k in sorted(refs) if k in disk and not any(r.startswith("RES:") for r in refs[k])]
print("\n2) named without a #resource in the naming file (%d)" % len(ghost))
for k in ghost:
    print("   %-28s <- %s" % (k, ", ".join(sorted(refs[k]))))

outman = [k for k in sorted(refs) if k in disk and k not in manifest]
print("\n3) on disk but NOT in the icon manifest (%d)  <- regenerating loses them" % len(outman))
for k in outman:
    print("   %-28s <- %s" % (k, ", ".join(sorted(refs[k]))))

unused = [k for k in sorted(disk) if k not in refs]
print("\n4) on disk, referenced by no product module (%d)  <- dead weight" % len(unused))
print("   " + ", ".join(unused))
