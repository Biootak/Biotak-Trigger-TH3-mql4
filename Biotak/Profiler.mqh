  #ifndef TH3_PROFILER_MQH
#define TH3_PROFILER_MQH

#property strict

// Compile-time lightweight profiler (no inputs, no behavior change when disabled).
// Enable by defining ENABLE_TH3_PROFILER (no numeric expression needed).

#ifdef ENABLE_TH3_PROFILER

#define TH3_PROF_MAX_TAGS 64

struct STH3ProfTag {
    string name;
    long totalUs;
    int count;
    long maxUs;
    datetime lastPrint;
    ulong startUs;
    bool running;
    bool used;
};

static STH3ProfTag g_th3ProfTags[TH3_PROF_MAX_TAGS];
static bool g_th3ProfInit = false;

void TH3ProfInitOnce() {
    if(g_th3ProfInit) return;
    for(int i = 0; i < TH3_PROF_MAX_TAGS; i++) {
        g_th3ProfTags[i].name = "";
        g_th3ProfTags[i].totalUs = 0;
        g_th3ProfTags[i].count = 0;
        g_th3ProfTags[i].maxUs = 0;
        g_th3ProfTags[i].lastPrint = 0;
        g_th3ProfTags[i].startUs = 0;
        g_th3ProfTags[i].running = false;
        g_th3ProfTags[i].used = false;
    }
    g_th3ProfInit = true;
}

int TH3ProfFindOrAddTag(const string name) {
    TH3ProfInitOnce();

    // Find existing
    for(int i = 0; i < TH3_PROF_MAX_TAGS; i++) {
        if(g_th3ProfTags[i].used && g_th3ProfTags[i].name == name) return i;
    }

    // Add new
    for(int i = 0; i < TH3_PROF_MAX_TAGS; i++) {
        if(!g_th3ProfTags[i].used) {
            g_th3ProfTags[i].used = true;
            g_th3ProfTags[i].name = name;
            g_th3ProfTags[i].totalUs = 0;
            g_th3ProfTags[i].count = 0;
            g_th3ProfTags[i].maxUs = 0;
            g_th3ProfTags[i].lastPrint = 0;
            return i;
        }
    }

    // No space: reuse slot 0 (deterministic, avoids allocations)
    return 0;
}

ulong TH3ProfNowUs() {
    return GetMicrosecondCount();
}

// Start/Stop by tag name (no local variables, avoids macro token-pasting).
void TH3ProfStartTag(const string tag) {
    int idx = TH3ProfFindOrAddTag(tag);
    g_th3ProfTags[idx].startUs = TH3ProfNowUs();
    g_th3ProfTags[idx].running = true;
}

void TH3ProfEndTag(const string tag) {
    int idx = TH3ProfFindOrAddTag(tag);
    if(!g_th3ProfTags[idx].running) return;

    ulong endUs = TH3ProfNowUs();
    long elapsedUs = (endUs >= g_th3ProfTags[idx].startUs) ? (long)(endUs - g_th3ProfTags[idx].startUs) : 0;
    g_th3ProfTags[idx].running = false;

    g_th3ProfTags[idx].totalUs += elapsedUs;
    g_th3ProfTags[idx].count += 1;
    if(elapsedUs > g_th3ProfTags[idx].maxUs) g_th3ProfTags[idx].maxUs = elapsedUs;

    // Print at most once per 5 seconds per tag to avoid log spam
    // PERF: Use GetTickCount() (ms) instead of TimeCurrent() syscall
    datetime now = CacheGetFrameTime();
    if(now == 0) now = TimeCurrent();
    if(g_th3ProfTags[idx].lastPrint == 0 || (now - g_th3ProfTags[idx].lastPrint) >= 5) {
        double avgMs = (g_th3ProfTags[idx].count > 0)
                       ? (((double)g_th3ProfTags[idx].totalUs / (double)g_th3ProfTags[idx].count) / 1000.0)
                       : 0.0;
        double maxMs = (double)g_th3ProfTags[idx].maxUs / 1000.0;
        LOG_I(LOG_CAT_PERF, StringFormat("[PROF] %s | count=%d avg=%.3fms max=%.3fms",
              tag, (int)g_th3ProfTags[idx].count, avgMs, maxMs));
        g_th3ProfTags[idx].lastPrint = now;
    }
}

// Convenience macros (MQL-safe)
#define TH3_PROF_START(tag) TH3ProfStartTag(#tag)
#define TH3_PROF_END(tag)   TH3ProfEndTag(#tag)

#else

#define TH3_PROF_START(tag)
#define TH3_PROF_END(tag)

#endif // ENABLE_TH3_PROFILER

#endif // TH3_PROFILER_MQH
