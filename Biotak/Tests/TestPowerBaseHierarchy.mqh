//+------------------------------------------------------------------+
//| TestPowerBaseHierarchy.mqh                                        |
//| Unit Tests for Power Base Hierarchy Fix                          |
//| Tests GetHighestStructureLevel function                          |
//+------------------------------------------------------------------+

#include "../ExtendedDrawingFunctions.mqh"

//+------------------------------------------------------------------+
//| Test Result Structure                                             |
//+------------------------------------------------------------------+
struct TestResult {
    string testName;
    bool passed;
    string errorMessage;
};

//+------------------------------------------------------------------+
//| Test: Power Base = 2                                              |
//+------------------------------------------------------------------+
TestResult Test_PowerBase2() {
    TestResult result;
    result.testName = "Power Base = 2";
    result.passed = true;
    result.errorMessage = "";
    
    // Setup intervals for Base=2: L1=2, L2=4, L3=8, L4=16, L5=32
    int intervals[5];
    intervals[0] = 2;
    intervals[1] = 4;
    intervals[2] = 8;
    intervals[3] = 16;
    intervals[4] = 32;
    
    // Test cases
    if(GetHighestStructureLevel(2, intervals) != 1) {
        result.passed = false;
        result.errorMessage = "Step 2 should be L1";
        return result;
    }
    
    if(GetHighestStructureLevel(4, intervals) != 2) {
        result.passed = false;
        result.errorMessage = "Step 4 should be L2 (not L1)";
        return result;
    }
    
    if(GetHighestStructureLevel(8, intervals) != 3) {
        result.passed = false;
        result.errorMessage = "Step 8 should be L3 (not L1 or L2)";
        return result;
    }
    
    if(GetHighestStructureLevel(16, intervals) != 4) {
        result.passed = false;
        result.errorMessage = "Step 16 should be L4 (not L1, L2, or L3)";
        return result;
    }
    
    if(GetHighestStructureLevel(32, intervals) != 5) {
        result.passed = false;
        result.errorMessage = "Step 32 should be L5";
        return result;
    }
    
    if(GetHighestStructureLevel(3, intervals) != 0) {
        result.passed = false;
        result.errorMessage = "Step 3 should be Trigger (0)";
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Test: Power Base = 4                                              |
//+------------------------------------------------------------------+
TestResult Test_PowerBase4() {
    TestResult result;
    result.testName = "Power Base = 4";
    result.passed = true;
    result.errorMessage = "";
    
    // Setup intervals for Base=4: L1=4, L2=16, L3=64, L4=256, L5=1024
    int intervals[5];
    intervals[0] = 4;
    intervals[1] = 16;
    intervals[2] = 64;
    intervals[3] = 256;
    intervals[4] = 1024;
    
    // Test cases - CRITICAL: Step 16 should be L2 only, not L1
    if(GetHighestStructureLevel(4, intervals) != 1) {
        result.passed = false;
        result.errorMessage = "Step 4 should be L1";
        return result;
    }
    
    if(GetHighestStructureLevel(8, intervals) != 1) {
        result.passed = false;
        result.errorMessage = "Step 8 should be L1";
        return result;
    }
    
    if(GetHighestStructureLevel(12, intervals) != 1) {
        result.passed = false;
        result.errorMessage = "Step 12 should be L1";
        return result;
    }
    
    // CRITICAL TEST: Step 16 should be L2, not L1+L2
    if(GetHighestStructureLevel(16, intervals) != 2) {
        result.passed = false;
        result.errorMessage = "Step 16 should be L2 ONLY (not L1)";
        return result;
    }
    
    if(GetHighestStructureLevel(64, intervals) != 3) {
        result.passed = false;
        result.errorMessage = "Step 64 should be L3 ONLY";
        return result;
    }
    
    if(GetHighestStructureLevel(5, intervals) != 0) {
        result.passed = false;
        result.errorMessage = "Step 5 should be Trigger (0)";
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Test: Negative Steps                                              |
//+------------------------------------------------------------------+
TestResult Test_NegativeSteps() {
    TestResult result;
    result.testName = "Negative Steps";
    result.passed = true;
    result.errorMessage = "";
    
    int intervals[5];
    intervals[0] = 3;
    intervals[1] = 9;
    intervals[2] = 27;
    intervals[3] = 81;
    intervals[4] = 243;
    
    // Negative steps should work the same as positive
    if(GetHighestStructureLevel(-9, intervals) != 2) {
        result.passed = false;
        result.errorMessage = "Step -9 should be L2";
        return result;
    }
    
    if(GetHighestStructureLevel(-27, intervals) != 3) {
        result.passed = false;
        result.errorMessage = "Step -27 should be L3";
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Test: Invalid Inputs                                              |
//+------------------------------------------------------------------+
TestResult Test_InvalidInputs() {
    TestResult result;
    result.testName = "Invalid Inputs";
    result.passed = true;
    result.errorMessage = "";
    
    int intervals[5];
    intervals[0] = 3;
    intervals[1] = 9;
    intervals[2] = 27;
    intervals[3] = 81;
    intervals[4] = 243;
    
    // Step 0 (midpoint) should return 0
    if(GetHighestStructureLevel(0, intervals) != 0) {
        result.passed = false;
        result.errorMessage = "Step 0 (midpoint) should return 0";
        return result;
    }
    
    // Invalid array size
    int badIntervals[3];
    badIntervals[0] = 3;
    badIntervals[1] = 9;
    badIntervals[2] = 27;
    
    if(GetHighestStructureLevel(9, badIntervals) != 0) {
        result.passed = false;
        result.errorMessage = "Invalid array size should return 0";
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Run All Tests                                                     |
//+------------------------------------------------------------------+
void RunPowerBaseHierarchyTests() {
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║  POWER BASE HIERARCHY TESTS                                   ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");
    
    TestResult results[];
    ArrayResize(results, 4);
    
    results[0] = Test_PowerBase2();
    results[1] = Test_PowerBase4();
    results[2] = Test_NegativeSteps();
    results[3] = Test_InvalidInputs();
    
    int passed = 0;
    int failed = 0;
    
    for(int i = 0; i < ArraySize(results); i++) {
        if(results[i].passed) {
            Print("✅ ", results[i].testName, " - PASSED");
            passed++;
        } else {
            Print("❌ ", results[i].testName, " - FAILED: ", results[i].errorMessage);
            failed++;
        }
    }
    
    Print("───────────────────────────────────────────────────────────────");
    Print("Total: ", ArraySize(results), " | Passed: ", passed, " | Failed: ", failed);
    
    if(failed == 0) {
        Print("🎉 ALL TESTS PASSED!");
    } else {
        Print("⚠️ ", failed, " TEST(S) FAILED!");
    }
    
    Print("═══════════════════════════════════════════════════════════════");
}
