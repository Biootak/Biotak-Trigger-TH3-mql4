# -*- coding: utf-8 -*-
# align the [step1] gate + probe-budget [custom-price-mode] with the icon
# generation (P-UI-98d v2: baked circular handles, park-not-mask)
import io

p = "tools/panel-wiring-audit.py"
s = io.open(p, encoding="utf-8").read()

reps = []

# the face's marker rules: the dot became a BAKED ICON, parked (not deleted)
# when set, and the L-switch ownership moved INTO the show condition
reps.append(('''        if "S1MarkName(" not in face_fn or "OBJ_ARROW" not in face_fn:
            problems.append("the step-1 marker dot has no owner in the face - "
                            "the red marker the user asked for is gone "
                            "(P-UI-98d)")''',
             '''        if "S1MarkName(" not in face_fn or "S1_HANDLE_RES" not in face_fn:
            problems.append("the step-1 marker handle has no owner in the face - "
                            "the red circular drag icon the user asked for is "
                            "gone (P-UI-98d v2)")
        if "HandsetHandleAt(mark" not in face_fn:
            problems.append("the red handle is not placed through the shared "
                            "screen-middle projector - two placement idioms "
                            "drift (P-UI-98d v2)")'''))

reps.append(('''        if "ObjectDelete(0, mark)" not in face_fn:
            problems.append("a SET handle's dot is masked instead of deleted - "
                            "another mask writer can resurrect a dead marker "
                            "(P-UI-98d)")''',
             '''        if "HandsetHandlePark(mark)" not in face_fn:
            problems.append("a SET handle's icon is left on the chart - a set "
                            "line cannot be grabbed, so nothing may point at it "
                            "either (P-UI-98d v2)")'''))

reps.append(('''        if "OBJPROP_TIMEFRAMES, lineTf" not in face_fn:
            problems.append("the marker dot does not wear the line family's "
                            "mask - the L switch would not own it with the "
                            "lines (P-UI-98d)")''',
             '''        if "g_linesVisible" not in face_fn:
            problems.append("the handle's show condition forgot the LINES "
                            "switch - the markers must obey the L switch with "
                            "the lines (P-UI-98d v2)")'''))

for old, new in reps:
    assert s.count(old) == 1, old[:60]
    s = s.replace(old, new)

io.open(p, "w", encoding="utf-8", newline="").write(s)
print("panel-wiring gate aligned")

# probe-budget: the green marker check referenced clrGreen (the old arrow)
p2 = "tools/probe-budget-audit.py"
s2 = io.open(p2, encoding="utf-8").read()
old2 = '''    sync_fn = body(events, "void CustomPriceMarkerSync(")
    if not sync_fn or "clrGreen" not in sync_fn:
        problems.append("the custom line's green marker has no owner "
                        "(P-UI-98d)")'''
new2 = '''    sync_fn = body(events, "void CustomPriceMarkerSync(")
    if not sync_fn or "CP_HANDLE_RES" not in sync_fn:
        problems.append("the custom line's green circular handle has no owner "
                        "(P-UI-98d v2)")'''
assert s2.count(old2) == 1
s2 = s2.replace(old2, new2)
io.open(p2, "w", encoding="utf-8", newline="").write(s2)
print("probe-budget gate aligned")
