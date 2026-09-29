// TH3Tool_D.mqh - TH3Tool.mqh split 2026-09-29: exact lines 4227-4302, byte-identical, zero renames.
#ifndef TH3_TOOL_D_MQH
#define TH3_TOOL_D_MQH

//+------------------------------------------------------------------+
//| Cycle TH3 Frequency (Keys 3 and 4)                              |
//|         TH3 (  3    4)                                 |
//+------------------------------------------------------------------+
void CycleTH3Frequency() {
    if(g_th3FreqIndex < MIN_TH3_FREQ_INDEX || g_th3FreqIndex > MAX_TH3_FREQ_INDEX) {
        g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
    }
    
    g_th3FreqIndex++;
    if(g_th3FreqIndex > MAX_TH3_FREQ_INDEX)
        g_th3FreqIndex = MIN_TH3_FREQ_INDEX;
    g_th3FreqOverride = GetFrequencyByIndex(g_th3FreqIndex);
    
    // ========================================
    
    UpdateAllTH3Objects();
    
    // Update frequency label
    UpdateTH3FrequencyLabel(g_th3FreqOverride);
    
    Print("==================== TH3 Frequency: ", DoubleToString(g_th3FreqOverride, 3), "%");
}

void DecrementTH3Frequency() {
    if(g_th3FreqIndex < MIN_TH3_FREQ_INDEX || g_th3FreqIndex > MAX_TH3_FREQ_INDEX) {
        g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
    }
    
    g_th3FreqIndex--;
    if(g_th3FreqIndex < MIN_TH3_FREQ_INDEX)
        g_th3FreqIndex = MAX_TH3_FREQ_INDEX;
    g_th3FreqOverride = GetFrequencyByIndex(g_th3FreqIndex);
    
    // ========================================
    
    UpdateAllTH3Objects();
    
    // Update frequency label
    UpdateTH3FrequencyLabel(g_th3FreqOverride);
    
    Print("==================== TH3 Frequency: ", DoubleToString(g_th3FreqOverride, 3), "%");
}


//+------------------------------------------------------------------+
//| Find Optimal Frequency with Learning Data                        |
//|                                        |
//| Returns: result count + fills waves and consolidation params    |
//+------------------------------------------------------------------+
int FindOptimalFrequencyForABCD_WithLearningData(
    datetime tX, double pX, datetime tA, double pA,
    datetime tB, double pB, datetime tC, double pC,
    FrequencySearchResult &results[],
    WaveAnalysis &waves_out,
    double &consolidationFactor_out,
    double maxErrorPercent = 5.0)
{
    //        
    ArrayResize(results, 0);
    
    double AB_Distance = MathAbs(pB - pA);
    if(AB_Distance <= 0) return 0;
    
    //      
    waves_out = AnalyzeThreeWaves(tX, pX, tA, pA, tB, pB, tC, pC);
    
    //   consolidation (    waves    
    consolidationFactor_out = CalculateConsolidationFactor(tA, tB, tC, waves_out);
    
    //          
    int resultCount = FindOptimalFrequencyForABCD(tX, pX, tA, pA, tB, pB, tC, pC, results, maxErrorPercent);
    
    return resultCount;
}

#endif // TH3_TOOL_D_MQH
