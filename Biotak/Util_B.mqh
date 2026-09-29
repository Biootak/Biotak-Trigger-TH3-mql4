// Util_B.mqh - UtilityFunctions.mqh split 2026-09-29: exact lines 1447-1520, byte-identical, zero renames.
#ifndef UTIL_B_MQH
#define UTIL_B_MQH

// The UNCONDITIONAL form: every hand-set line, whatever gesture is live. For the
// callers where the press provably belongs to another layer — a UI owner claimed
// it, so no gesture of ours can be holding either line — and asking would only
// leave a line selected under somebody else's drag.
void HandLinesDropAll()
{
   if(g_customPriceLineCreated)
      HandLineDropSelection(g_customPriceHorizontalLineName);
   HandLineDropSelection(g_s1MarkAboveName);
   HandLineDropSelection(g_s1MarkBelowName);
}

// The ONE writer of "the line's price goes back". Guarded twice: an invalid or
// already-correct price is not a write. The caller owns everything the price
// implies (the anchor, the marker, the frame) — this function owns the number.
void HandLinesRestorePrice(const string name, const double price)
{
   if(name == "") return;
   if(!(price > 0.0) || !MathIsValidNumber(price)) return;
   if(ObjectFind(0, name) < 0) return;
   double now = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   if(now > 0.0 && MathIsValidNumber(now) && MathAbs(now - price) <= _Point * 0.5)
      return;   // already where the user left it — no write, no repaint
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-100c (2026-09-22) — THE LINE IS THE ANCHOR'S PICTURE, AND THE ANCHOR WINS.
//
// REPORTED, with a screenshot: «خط کاستوم پرایس رو بردم پایین، میخواستم باکس بکشم»
// — while a BOX was being drawn, the custom price line followed the cursor down
// and STAYED there. The selection guard above stops the one mechanism this
// project has already measured (MT4 carries every SELECTED object with a drag),
// but the symptom survived it, so the invariant is now stated as a LAW instead
// of as a cause:
//
//   OUTSIDE a gesture of our own, the line object MUST sit on the anchor the
//   whole ladder is derived from (`g_customTHStartPrice`). Any other price is
//   a displacement by definition, and the ladder is already drawn for the
//   anchor — the line is the only thing that is wrong.
//
// WHY THIS IS SAFE, AND WHY IT IS NOT A FIGHT WITH THE TERMINAL. A legitimate
// move of this line is always one of two things, and both are excluded here:
//   * OUR gesture (the claim/carry/native drag) — `g_customPriceLineDragging`
//     is live, so the heal stands down;
//   * the terminal's own grab — which the claim picks up (terminalGrab) in the
//     same press, and whose RELEASE anchors the new price (P-UI-61), so by the
//     time any caller of this function runs, the anchor already holds it.
// What is left is exactly the reported case: somebody ELSE's gesture (a box, a
// fib, a pan) moved an object that had no business moving.
//
// The callers are the two places that KNOW a foreign gesture owns the mouse:
// the box layer's own event (BaseKnotTool, before it consumes the event) and
// the 250 ms net. Cost: two guarded reads, and a write only on drift.
// ══════════════════════════════════════════════════════════════════════════
void HandLineHealToAnchor()
{
   if(g_customPriceLineDragging) return;            // our own hand is on it
   if(!g_customPriceLineCreated) return;
   if(!(g_customTHStartPrice > 0.0) || !MathIsValidNumber(g_customTHStartPrice)) return;
   if(ObjectFind(0, g_customPriceHorizontalLineName) < 0) return;
   double now = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
   if(now > 0.0 && MathIsValidNumber(now) &&
      MathAbs(now - g_customTHStartPrice) <= _Point * 0.5) return;   // already on it
   HandLinesRestorePrice(g_customPriceHorizontalLineName, g_customTHStartPrice);
   // The dot is re-projected by the ride channel on the very same mouse stream
   // (HandsetMarkersRide), so this owner does not touch it — one writer per
   // object, and the marker already has one.
   _LOG_GATE_W Print("[W][GEN] custom price line healed back to the anchor: ",
                     DoubleToString(now, Digits), " -> ",
                     DoubleToString(g_customTHStartPrice, Digits),
                     " (a foreign gesture had moved the line)");
}

#endif // UTIL_B_MQH
