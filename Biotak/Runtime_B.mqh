// Runtime_B.mqh - RuntimeSettings.mqh split 2026-09-29: exact lines 1447-1587, byte-identical, zero renames.
#ifndef RUNTIME_B_MQH
#define RUNTIME_B_MQH

//==============================================================================
// PER-TARGET TRANSPARENCY — every COLOR row's target is adjustable from the
// palette footer TR track / mixer (PaletteKindTransparency). Same visual
// fade curve as trigger/lines, same per-target static cache discipline:
// recompute ONLY when base, transparency or chart background changes, so
// per-frame draw calls cost one syscall + three integer compares.
// Stores default to 0 (solid) — existing charts look identical until the
// user touches TR. Persisted via OV_SST/LST/CPT/FCT (no migration: new keys).
//==============================================================================
int TransparencyVisual(const int t)
{
    int tc = (int)MathMax(0, MathMin(100, t));
    // Stronger visual fade for line objects: 60 -> 84, 50 -> 75, 30 -> 51
    return 100 - ((100 - tc) * (100 - tc)) / 100;
}

color BlendColorTowardsBG(const color base, const int tVis, const color bg)
{
    if(tVis <= 0) return base;
    if(tVis >= 100) return bg;
    int fr = ((int)base) & 0xFF;
    int fg = (((int)base) >> 8) & 0xFF;
    int fb = (((int)base) >> 16) & 0xFF;
    int br = ((int)bg) & 0xFF;
    int bgc = (((int)bg) >> 8) & 0xFF;
    int bb = (((int)bg) >> 16) & 0xFF;
    int outR = (fr * (100 - tVis) + br * tVis) / 100;
    int outG = (fg * (100 - tVis) + bgc * tVis) / 100;
    int outB = (fb * (100 - tVis) + bb * tVis) / 100;
    return (color)(outR | (outG << 8) | (outB << 16));
}

color GetSSRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_ssTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_ssLevelColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_ssLevelColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_ssLevelColor, tVis, bg);
    return s_out;
}

color GetLSRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_lsTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_lsLevelColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_lsLevelColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_lsLevelColor, tVis, bg);
    return s_out;
}

color GetCustomPriceRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_customPriceTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_customPriceLevelColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_customPriceLevelColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_customPriceLevelColor, tVis, bg);
    return s_out;
}

color GetFactorRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_factorTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_factorLevelColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_factorLevelColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_factorLevelColor, tVis, bg);
    return s_out;
}

color GetBoxBorderRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_boxBorderTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_boxBorderColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_boxBorderColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_boxBorderColor, tVis, bg);
    return s_out;
}

// EFFECTIVE BOX FILL — TV-parity 2026-09-07 (Style tab bucket). Same cache
// discipline as the border helper. 100% = chart background (invisible).
color GetBoxFillRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_boxFillTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_boxFillColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_boxFillColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_boxFillColor, tVis, bg);
    return s_out;
}
// Fill visible on chart? (transparency < 100). The BOX rect is the fill layer:
// FILL true + fill color when visible, bg + FILL false when invisible (the old
// hollow look — pre-fill charts stay pixel-identical).
bool BoxFillVisible() { return (ClampSettingInt(g_boxFillTransparency, 0, 100) < 100); }

// EFFECTIVE USER-TEXT COLOR — factory white means Auto: pure-white text on a
// light chart is invisible, so it renders dark brown there (same luminance
// gate as the INFO label); any explicit pick (incl. white on dark) is honored
// untouched. Cached like the other render getters.
color GetBKTextRenderColor()
{
    static color s_c = clrNONE; static color s_bg = clrNONE; static color s_out = clrNONE;
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_c == g_bkTextColor && s_bg == bg) return s_out;
    s_c = g_bkTextColor; s_bg = bg;
    s_out = g_bkTextColor;
    // P-UI-117: the gate and the readable ink are the palette owner's now
    // (`BioChartBgIsLight`, `BIO_CLR_ON_LIGHT`). This block used to carry its own
    // copy of the 299/587/114 arithmetic and its own `C'150,70,0'`, annotated
    // "same luminance gate as the INFO label" — a rule in two places is a rule
    // that drifts, and only one of the two could ever have followed a change.
    if(g_bkTextColor == C'255,255,255' && BioChartBgIsLight())
        s_out = BIO_CLR_ON_LIGHT;
    return s_out;
}

// User-text font string from the Bold/Italic mirrors ("Arial" + suffixes).
string BKTextFont()
{
   string f = "Arial";
   if(g_bkBold && g_bkItalic) return f + " Bold Italic";
   if(g_bkBold) return f + " Bold";
   if(g_bkItalic) return f + " Italic";
   return f;
}

#endif // RUNTIME_B_MQH
