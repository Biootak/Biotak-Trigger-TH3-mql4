// DrawKindProfile.mqh - P-UNIFY-4 (2026-10-19): ONE row per drawing kind.
//
// Until this file the same drawing kind was described in five places: the
// classifier (`Toolbar_A`), the capability table (`DrawKindCaps`), the level
// family (`DrawKindHasLevels`), the two pen families (`FibPenServesType`,
// `PenStackServesType`) and the look vocabulary (three ids in `FibPen`, three
// slot numbers in `Toolbar_A`). A kind added to one of them and forgotten in
// another compiled green and was half-served.
//
// THE PROFILE IS THE ONE DESCRIPTION. `DrawKindProfileGet` answers, for a kind:
//   * `geom`     - how the drawing's points become seats (LEVEL / LINE / SHAPE / POINT);
//   * `pen`      - which pen owns its visible width (LEVEL pen, OBJECT pen, none);
//   * `lookMask` - which looks the STYLE slot may offer (zero for the rest).
// The capability mask stays in `DrawKindCaps` until the next step: it is a file
// gate's own anchor and moving it here would change a gate, not a pixel.
//
// THE TYPE MAP IS THE KERNEL. `DrawKindOfType` is the switch that used to live in
// `DrawKindOf`; the profile's type queries and both pens ask it, so an added MT4
// type is one case here, never a second list elsewhere.
//
// THE PEN EXCEPTIONS LIVE HERE. Two kinds cover more than one MT4 type and the
// extra type has no level pen: a fibo TIME ZONES draws vertical levels and a fibo
// ARC is a circle (P-UNIFY-3). A standard-deviation or regression channel has no
// fill/level family the object pen can copy. `DrawTypePenFamily` names those four
// refusals ONCE; the old `FibPenServesType`/`PenStackServesType` lists were the
// same four facts spelled in two files.
#ifndef DRAW_KIND_PROFILE_MQH
#define DRAW_KIND_PROFILE_MQH

//--- THE LOOK IDS. Frozen like the `FF_` addresses: an id is written on the
//--- object as `[LKn]` and in a template's style word, so a renumber is a
//--- rename of every drawing a previous build saved. `_3D` (4) is retired and
//--- must never be reused (P-LOOK-3D).
#define DRAW_LOOK_NEON   1
#define DRAW_LOOK_CAPS   2
#define DRAW_LOOK_WASH   3
#define DRAW_LOOK_COUNT  3
#define DRAW_LOOK_TAG    "[LK"
#define DRAW_LOOK_BIT_NEON 0x01
#define DRAW_LOOK_BIT_CAPS 0x02
#define DRAW_LOOK_BIT_WASH 0x04
#define DRAW_LOOK_ALL      (DRAW_LOOK_BIT_NEON | DRAW_LOOK_BIT_CAPS | DRAW_LOOK_BIT_WASH)

//--- THE GEOMETRY FAMILIES. A level family seats N rows between its anchors; a
//--- line has one seat per row; a shape has an outline; a point has one anchor.
#define DKG_NONE    0
#define DKG_LEVEL   1
#define DKG_LINE    2
#define DKG_SHAPE   3
#define DKG_POINT   4

//--- THE PEN FAMILIES. The level pen states per-level lines (`FibPen`); the
//--- object pen copies the whole drawing (line/shape, `PenStack`).
#define DKPEN_NONE   0
#define DKPEN_LEVEL  1
#define DKPEN_OBJECT 2

struct DrawKindProfile
{
   int geom;
   int pen;
   int lookMask;
};

//--- THE TABLE. Every kind has a row; an unknown kind answers NONE/NONE/0.
//--- `DrawKindOfType` stays in Toolbar_A beside the classifier (its cases are the
//--- type map the P-UNIFY-2 gate reads); this table asks it.
void DrawKindProfileGet(const EDrawKind k, DrawKindProfile &p)
{
   p.geom = DKG_NONE;
   p.pen = DKPEN_NONE;
   p.lookMask = 0;
   if(DrawKindHasLevels(k)) p.geom = DKG_LEVEL;
   switch(k)
   {
      case DK_LINE:
      case DK_HLINE:
      case DK_VLINE:
      case DK_TANGLE:
         p.geom = DKG_LINE;
         p.pen = DKPEN_OBJECT;
         break;
      case DK_CHANNEL:
      case DK_GANN:
      case DK_RECT:
      case DK_TRIANGLE:
      case DK_ELLIPSE:
      case DK_CYCLES:
         p.geom = DKG_SHAPE;
         p.pen = DKPEN_OBJECT;
         break;
      case DK_FIBO:
      case DK_FIBOFAN:
      case DK_FIBOCHAN:
      case DK_EXPANSION:
         p.pen = DKPEN_LEVEL;
         p.lookMask = DRAW_LOOK_ALL;
         break;
      case DK_PITCHFORK:
         //--- P-UNIFY-3: its rails ARE its level family; a whole-object copy would
         //--- carry a copy of the levels, so it keeps the native fold and no look.
         break;
      case DK_ARROW:
      case DK_TEXT:
         p.geom = DKG_POINT;
         break;
      default:
         break;
   }
}

int DrawKindGeom(const EDrawKind k)
{
   DrawKindProfile p;
   DrawKindProfileGet(k, p);
   return p.geom;
}
int DrawKindPenFamily(const EDrawKind k)
{
   DrawKindProfile p;
   DrawKindProfileGet(k, p);
   return p.pen;
}
int DrawKindLookMask(const EDrawKind k)
{
   DrawKindProfile p;
   DrawKindProfileGet(k, p);
   return p.lookMask;
}

//--- THE FOUR OBJECT-LEVEL REFUSALS. The kind says "the level pen can state
//--- this drawing"; the TYPE says whether the terminal really draws the lines
//--- the pen would state. A time-zones fibo's levels are vertical, an arc's are
//--- a circle, and a regression / standard-deviation channel has no fill body the
//--- object pen could copy. One owner, asked by every caller.
int DrawTypePenFamily(const int t)
{
   if(t == OBJ_FIBOTIMES || t == OBJ_FIBOARC) return DKPEN_NONE;
   if(t == OBJ_STDDEVCHANNEL || t == OBJ_REGRESSION) return DKPEN_NONE;
   return DrawKindPenFamily(DrawKindOfType(t));
}
int DrawTypeLookMask(const int t)
{
   if(DrawTypePenFamily(t) != DKPEN_LEVEL) return 0;
   return DrawKindLookMask(DrawKindOfType(t));
}

#endif // DRAW_KIND_PROFILE_MQH
