"""ICON-DIET one-shot purge (2026-09-12, P-UI-28).

Source of truth: tools/icon-manifest.txt (written by gen-th3-icons.js) —
the exact runtime-reachable set.
  1. Deletes every Files/Icons/*.bmp NOT in the manifest (dead weight).
  2. Drops every #resource line in BiotakPanels.mqh / BiotakMenu.mqh whose
     file is NOT in the manifest (would embed a ghost).
Idempotent: re-running deletes/drops nothing.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, 'Files', 'Icons')
MANIFEST = os.path.join(ROOT, 'tools', 'icon-manifest.txt')
TARGETS = [os.path.join(ROOT, 'Biotak', 'BiotakPanels.mqh'),
           os.path.join(ROOT, 'Biotak', 'BiotakMenu.mqh')]
RES_RE = re.compile(r'^#resource\s+"\\\\Files\\\\Icons\\\\([^"]+)"\s*$')


def main():
    with open(MANIFEST, 'r', encoding='utf-8') as fh:
        manifest = set(l.strip() for l in fh if l.strip())
    print('manifest: %d files' % len(manifest))

    removed = 0
    for f in sorted(os.listdir(ICONS)):
        if not f.endswith('.bmp'):
            continue
        if f not in manifest:
            os.remove(os.path.join(ICONS, f))
            removed += 1
    print('deleted %d dead BMPs from Files/Icons' % removed)

    pruned_total = 0
    for target in TARGETS:
        with open(target, 'r', encoding='utf-8', newline='') as fh:
            lines = fh.read().split('\n')
        kept = []
        pruned = 0
        for ln in lines:
            m = RES_RE.match(ln.strip())
            if m and m.group(1) not in manifest:
                pruned += 1
                continue
            kept.append(ln)
        if pruned:
            with open(target, 'w', encoding='utf-8', newline='') as fh:
                fh.write('\n'.join(kept))
        print('%s: pruned %d stale #resource lines' % (
            os.path.basename(target), pruned))
        pruned_total += pruned

    # Verify: every manifest file on disk, every #resource on the manifest.
    missing_disk = [f for f in manifest
                    if not os.path.exists(os.path.join(ICONS, f))]
    print('manifest files missing on disk: %d' % len(missing_disk))
    for f in missing_disk:
        print('  MISSING-DISK: %s' % f)
    return 0 if not missing_disk else 1


if __name__ == '__main__':
    sys.exit(main())
