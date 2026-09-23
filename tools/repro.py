"""repro: reproduce one chart section's step-3 proof off the terminal's bars."""
import datetime as dt
import sys

sys.path.insert(0, "tools")
import step3_survey as s
import mt4_history as mh


def T(x):
    return dt.datetime.fromtimestamp(x, dt.timezone.utc).strftime("%m-%d %H:%M")


def main():
    p = mh.find(symbol="XAUUSD", tf=60)
    bars = mh.load(p[0])
    print("H1 bars:", len(bars))
    atr = s.atr14(bars)
    pivs = s.six_pivots(bars, atr)
    print("total pivots:", len(pivs))
    tc = int(dt.datetime(2026, 9, 2, 4, 0, tzinfo=dt.timezone.utc).timestamp())
    ci = next(i for i, b in enumerate(bars) if b[0] >= tc)
    print("C bar idx", ci, T(bars[ci][0]), "L=", round(bars[ci][3], 1))
    C = bars[ci][3]
    a = atr[ci]
    print("ATR at C:", round(a, 2))
    hs = [q for q in pivs if q[0] >= ci and q[1] == "H"]
    if not hs:
        print("NO H pivot after C")
        return
    print("first H pivots after C:")
    for r2 in hs[:6]:
        print("  ", T(bars[r2[0]][0]), "H=", round(r2[2], 1),
              "conf@", T(bars[r2[3]][0]))
    dist = hs[0][2] - C
    print("dist C->firstH =", round(dist, 1), "-> step=", round(dist / 3.0, 1),
          "vs ATR", round(a, 1))


if __name__ == "__main__":
    main()
