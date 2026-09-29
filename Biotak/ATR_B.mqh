// ATR_B.mqh - ATRCalculations.mqh split 2026-09-29: exact lines 1321-1571, byte-identical, zero renames.
#ifndef ATR_B_MQH
#define ATR_B_MQH

//+------------------------------------------------------------------+
//| Test ATR Calculations Module                                     |
//|                   ATR                                            |
//| AUDIT FIX: Comprehensive test suite for all ATR functions        |
//+------------------------------------------------------------------+
void TestATRCalculations() {
    Print("====================");
    Print("   ATR CALCULATIONS MODULE TESTS                                 ");
    Print("====================");
    
    int passCount = 0;
    int totalTests = 0;
    
    //                                                                
    // Test 1: Cache Initialization
    //                                                                
    totalTests++;
    InitializeATRCache();
    if(g_atrCacheInitialized && g_multiTFCacheInitialized) {
        Print("  Test 1: Cache initialization - PASS");
        passCount++;
    } else {
        Print("  Test 1: Cache initialization - FAIL");
    }
    
    //                                                                
    // Test 2: GetEffectiveTimeframe
    //                                                                
    totalTests++;
    int effectiveTF = GetEffectiveTimeframe();
    if(effectiveTF > 0) {
        Print("  Test 2: GetEffectiveTimeframe (", effectiveTF, ") - PASS");
        passCount++;
    } else {
        Print("  Test 2: GetEffectiveTimeframe - FAIL");
    }
    
    //                                                                
    // Test 3: GetEffectiveBars
    //                                                                
    totalTests++;
    int effectiveBars = GetEffectiveBars();
    if(effectiveBars > 0) {
        Print("  Test 3: GetEffectiveBars (", effectiveBars, ") - PASS");
        passCount++;
    } else {
        Print("  Test 3: GetEffectiveBars - FAIL");
    }
    
    //                                                                
    // Test 4: CalculateTrueRange
    //                                                                
    totalTests++;
    double tr = CalculateTrueRange(1);
    if(!IsZero(tr, EPSILON_PRICE) && IsValidPrice(tr, EPSILON_PRICE)) {
        Print("  Test 4: CalculateTrueRange (", DoubleToString(tr, Digits), ") - PASS");
        passCount++;
    } else {
        Print("  Test 4: CalculateTrueRange - FAIL (TR=", tr, ")");
    }
    
    //                                                                
    // Test 5: CalculateSimpleATR
    //                                                                
    totalTests++;
    double simpleATR = CalculateSimpleATR(14);
    if(!IsZero(simpleATR, EPSILON_PRICE) && IsValidPrice(simpleATR, EPSILON_PRICE)) {
        Print("  Test 5: CalculateSimpleATR(14) (", DoubleToString(simpleATR, Digits), ") - PASS");
        passCount++;
    } else {
        Print("  Test 5: CalculateSimpleATR - FAIL (ATR=", simpleATR, ")");
    }
    
    //                                                                
    // Test 6: CalculateATRBatch
    //                                                                
    totalTests++;
    double batchResults[];
    CalculateATRBatch(batchResults);
    if(ArraySize(batchResults) == 6 && !IsZero(batchResults[0], EPSILON_PRICE)) {
        Print("  Test 6: CalculateATRBatch - PASS");
        Print("   ATR =", DoubleToString(batchResults[0], Digits));
        Print("   ATR  =", DoubleToString(batchResults[1], Digits));
        Print("   ATR  =", DoubleToString(batchResults[2], Digits));
        passCount++;
    } else {
        Print("  Test 6: CalculateATRBatch - FAIL");
    }
    
    //                                                                
    // Test 7: CalculateWeightedATR
    //                                                                
    totalTests++;
    double weightedATR = CalculateWeightedATR();
    if(!IsZero(weightedATR, EPSILON_PRICE) && IsValidPrice(weightedATR, EPSILON_PRICE)) {
        Print("  Test 7: CalculateWeightedATR (", DoubleToString(weightedATR, Digits), ") - PASS");
        passCount++;
    } else {
        Print("  Test 7: CalculateWeightedATR - FAIL (ATR=", weightedATR, ")");
    }
    
    //                                                                
    // Test 8: Cache Validation
    //                                                                
    totalTests++;
    if(g_atrCache.valid && AreEqual(g_atrCache.weightedATR, weightedATR, EPSILON_PRICE)) {
        Print("  Test 8: Cache validation - PASS");
        passCount++;
    } else {
        Print("  Test 8: Cache validation - FAIL");
    }
    
    //                                                                
    // Test 9: GetCurrentTimeframeMinutes
    //                                                                
    totalTests++;
    int currentMinutes = GetCurrentTimeframeMinutes();
    if(currentMinutes > 0) {
        Print("  Test 9: GetCurrentTimeframeMinutes (", currentMinutes, ") - PASS");
        passCount++;
    } else {
        Print("  Test 9: GetCurrentTimeframeMinutes - FAIL");
    }
    
    //                                                                
    // Test 10: CalculateHybridATR
    //                                                                
    totalTests++;
    double hybridATR = CalculateHybridATR(currentMinutes, 60); // Scale to H1
    if(!IsZero(hybridATR, EPSILON_PRICE) && IsValidPrice(hybridATR, EPSILON_PRICE)) {
        Print("  Test 10: CalculateHybridATR (", DoubleToString(hybridATR, Digits), ") - PASS");
        passCount++;
    } else {
        Print("  Test 10: CalculateHybridATR - FAIL (ATR=", hybridATR, ")");
    }
    
    //                                                                
    // Test 11: GetATRForTimeframe with Multi-TF Cache
    //                                                                
    totalTests++;
    double tfATR1 = GetATRForTimeframe(60);
    double tfATR2 = GetATRForTimeframe(60); // Should hit cache
    if(AreEqual(tfATR1, tfATR2, EPSILON_PRICE) && g_multiTFCacheCount > 0) {
        Print("  Test 11: Multi-TF cache - PASS (", g_multiTFCacheCount, " entries)");
        passCount++;
    } else {
        Print("  Test 11: Multi-TF cache - FAIL");
    }
    
    //                                                                
    // Test 12: CalculateATRBasedStep
    //                                                                
    totalTests++;
    double atrStep = CalculateATRBasedStep();
    if(!IsZero(atrStep, EPSILON_PRICE) && IsValidPrice(atrStep, EPSILON_PRICE)) {
        Print("  Test 12: CalculateATRBasedStep (", DoubleToString(atrStep, Digits), ") - PASS");
        passCount++;
    } else {
        Print("  Test 12: CalculateATRBasedStep - FAIL");
    }
    
    //                                                                
    // Test 13: CalculateATRFractalValues
    //                                                                
    totalTests++;
    double structure, pattern, trigger;
    CalculateATRFractalValues(structure, pattern, trigger);
    if(!IsZero(structure, EPSILON_PRICE) && 
       AreEqual(pattern, structure * 0.5, EPSILON_PRICE) &&
       AreEqual(trigger, structure * 0.25, EPSILON_PRICE)) {
        Print("  Test 13: CalculateATRFractalValues - PASS");
        Print("   Structure=", DoubleToString(structure, Digits));
        Print("   Pattern=", DoubleToString(pattern, Digits));
        Print("   Trigger=", DoubleToString(trigger, Digits));
        passCount++;
    } else {
        Print("  Test 13: CalculateATRFractalValues - FAIL");
    }
    
    //                                                                
    // Test 14: InvalidateATRCache
    //                                                                
    totalTests++;
    InvalidateATRCache();
    if(!g_atrCache.valid) {
        Print("  Test 14: InvalidateATRCache - PASS");
        passCount++;
    } else {
        Print("  Test 14: InvalidateATRCache - FAIL");
    }
    
    //                                                                
    // Test 15: GetATRCacheStats
    //                                                                
    totalTests++;
    // Recalculate to populate cache
    CalculateWeightedATR();
    string stats = GetATRCacheStats();
    if(StringLen(stats) > 0) {
        Print("  Test 15: GetATRCacheStats - PASS");
        Print(stats);
        passCount++;
    } else {
        Print("  Test 15: GetATRCacheStats - FAIL");
    }
    
    //                                                                
    // Test 16: Edge Case - Invalid Period
    //                                                                
    totalTests++;
    double invalidATR = CalculateSimpleATR(-1);
    if(IsZero(invalidATR, EPSILON_PRICE)) {
        Print("  Test 16: Edge case (invalid period) - PASS");
        passCount++;
    } else {
        Print("  Test 16: Edge case (invalid period) - FAIL");
    }
    
    //                                                                
    // Test 17: Edge Case - Zero Division Protection
    //                                                                
    totalTests++;
    double zeroATR = CalculateHybridATR(0, 60);
    if(IsZero(zeroATR, EPSILON_PRICE)) {
        Print("  Test 17: Edge case (zero division) - PASS");
        passCount++;
    } else {
        Print("  Test 17: Edge case (zero division) - FAIL");
    }
    
    //                                                                
    // Final Results
    //                                                                
    Print("====================");
    Print("   TEST RESULTS                                                  ");
    Print("====================");
    Print("   Passed: ", passCount, " / ", totalTests);
    Print("   Success Rate: ", DoubleToString(100.0 * passCount / totalTests, 1), "%");
    
    if(passCount == totalTests) {
        Print("   Status:   ALL TESTS PASSED                                  ");
    } else {
        Print("   Status:    SOME TESTS FAILED                                 ");
    }
    
    Print("====================");
    
    // Cleanup
    CleanupATRCache();
}

#endif // ATR_B_MQH
