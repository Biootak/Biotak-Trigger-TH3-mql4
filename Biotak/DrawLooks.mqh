// DrawLooks.mqh - P-UNIFY-4 (2026-10-19): the look vocabulary's ONE translator.
//
// The STYLE slot carries the five native MT4 styles (0..4) and, above them, the
// product's own looks (5..). Before this file the offset lived in three places:
// the writer subtracted `STYLE_DASHDOTDOT`, the reader added it back, and the
// icon painter asked a native-style function. `DrawLookFromSlot` / `DrawLookToSlot`
// are now that one law; `DrawLookNative` is the style the terminal can actually
// paint for a look, and `DrawLookName` is the one caption.
//
// The ids and their frozen numbers live in `DrawKindProfile.mqh` beside the kind
// that offers them; this file never invents one.
#ifndef DRAW_LOOKS_MQH
#define DRAW_LOOKS_MQH

int DrawLookCount()
{
   return DRAW_LOOK_COUNT;
}
bool DrawLookValid(const int lk)
{
   return (lk >= DRAW_LOOK_NEON && lk <= DRAW_LOOK_WASH);
}

//--- slot -> look id. 0..4 are native and answer 0 (the caller's "no look");
//--- 5..7 answer 1..3; the retired 8 and anything above answer 0 too, exactly
//--- as the old `cand >= NEON && cand <= WASH` range did (P-LOOK-3D).
int DrawLookFromSlot(const int st)
{
   if(st <= (int)STYLE_DASHDOTDOT) return 0;
   int lk = st - (int)STYLE_DASHDOTDOT;
   return (DrawLookValid(lk) ? lk : 0);
}

//--- look id -> slot. The inverse of the one law; -1 for "not a look".
int DrawLookToSlot(const int lk)
{
   return (DrawLookValid(lk) ? (int)STYLE_DASHDOTDOT + lk : -1);
}

//--- the native style the terminal holds for a look. Neon is the dash itself;
//--- Caps and Wash are solid with their follower beside the level. An invalid
//--- id answers -1 so a caller can decide its own fallback.
int DrawLookNative(const int lk)
{
   if(lk == DRAW_LOOK_NEON) return (int)STYLE_DASH;
   if(DrawLookValid(lk))    return (int)STYLE_SOLID;
   return -1;
}

string DrawLookName(const int lk)
{
   if(lk == DRAW_LOOK_NEON) return "Neon";
   if(lk == DRAW_LOOK_CAPS) return "Caps";
   if(lk == DRAW_LOOK_WASH) return "Wash";
   return "";
}

#endif // DRAW_LOOKS_MQH
