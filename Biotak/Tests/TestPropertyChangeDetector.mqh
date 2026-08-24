//+------------------------------------------------------------------+
//|                                   TestPropertyChangeDetector.mqh |
//|                                      Biotak Trigger TH3 Indicator |
//|                         Unit Tests for Property Change Detection  |
//+------------------------------------------------------------------+
#property copyright "Biotak"
#property strict

// Include the modules being tested
#include "../ObjectCache.mqh"
#include "../PropertyChangeDetector.mqh"

//+------------------------------------------------------------------+
//| Test HasPriceChanged with epsilon comparison                      |
//+------------------------------------------------------------------+
bool TestHasPriceChanged() {
    Print("Testing HasPriceChanged...");
    
    // Test 1: Identical prices should return false
    if(HasPriceChanged(1.12345, 1.12345)) {
        Print("FAIL: Identical prices detected as changed");
        return false;
    }
    
    // Test 2: Significantly different prices should return true
    if(!HasPriceChanged(1.12345, 1.12346)) {
        Print("FAIL: Different prices not detected");
        return false;
    }
    
    // Test 3: Difference within epsilon should return false
    if(HasPriceChanged(1.123456789, 1.123456788)) {
        Print("FAIL: Epsilon-level difference detected as changed");
        return false;
    }
    
    // Test 4: Zero prices should return false
    if(HasPriceChanged(0.0, 0.0)) {
        Print("FAIL: Zero prices detected as changed");
        return false;
    }
    
    // Test 5: Large price difference should return true
    if(!HasPriceChanged(1.0, 2.0)) {
        Print("FAIL: Large price difference not detected");
        return false;
    }
    
    Print("PASS: HasPriceChanged tests passed");
    return true;
}

//+------------------------------------------------------------------+
//| Test HasColorChanged                                              |
//+------------------------------------------------------------------+
bool TestHasColorChanged() {
    Print("Testing HasColorChanged...");
    
    // Test 1: Identical colors should return false
    if(HasColorChanged(clrRed, clrRed)) {
        Print("FAIL: Identical colors detected as changed");
        return false;
    }
    
    // Test 2: Different colors should return true
    if(!HasColorChanged(clrRed, clrBlue)) {
        Print("FAIL: Different colors not detected");
        return false;
    }
    
    // Test 3: Color values (numeric comparison)
    if(HasColorChanged(C'255,0,0', C'255,0,0')) {
        Print("FAIL: Identical RGB colors detected as changed");
        return false;
    }
    
    Print("PASS: HasColorChanged tests passed");
    return true;
}

//+------------------------------------------------------------------+
//| Test HasStyleChanged                                              |
//+------------------------------------------------------------------+
bool TestHasStyleChanged() {
    Print("Testing HasStyleChanged...");
    
    // Test 1: Identical styles should return false
    if(HasStyleChanged(STYLE_SOLID, STYLE_SOLID)) {
        Print("FAIL: Identical styles detected as changed");
        return false;
    }
    
    // Test 2: Different styles should return true
    if(!HasStyleChanged(STYLE_SOLID, STYLE_DASH)) {
        Print("FAIL: Different styles not detected");
        return false;
    }
    
    Print("PASS: HasStyleChanged tests passed");
    return true;
}

//+------------------------------------------------------------------+
//| Test HasWidthChanged                                              |
//+------------------------------------------------------------------+
bool TestHasWidthChanged() {
    Print("Testing HasWidthChanged...");
    
    // Test 1: Identical widths should return false
    if(HasWidthChanged(2, 2)) {
        Print("FAIL: Identical widths detected as changed");
        return false;
    }
    
    // Test 2: Different widths should return true
    if(!HasWidthChanged(1, 3)) {
        Print("FAIL: Different widths not detected");
        return false;
    }
    
    Print("PASS: HasWidthChanged tests passed");
    return true;
}

//+------------------------------------------------------------------+
//| Test HasAnyPropertyChanged                                        |
//+------------------------------------------------------------------+
bool TestHasAnyPropertyChanged() {
    Print("Testing HasAnyPropertyChanged...");
    
    // Test 1: No changes should return false
    if(HasAnyPropertyChanged(1.12345, 1.12345, clrRed, clrRed, STYLE_SOLID, STYLE_SOLID, 2, 2)) {
        Print("FAIL: No changes detected as changed");
        return false;
    }
    
    // Test 2: Price change should return true
    if(!HasAnyPropertyChanged(1.12345, 1.12346, clrRed, clrRed, STYLE_SOLID, STYLE_SOLID, 2, 2)) {
        Print("FAIL: Price change not detected");
        return false;
    }
    
    // Test 3: Color change should return true
    if(!HasAnyPropertyChanged(1.12345, 1.12345, clrRed, clrBlue, STYLE_SOLID, STYLE_SOLID, 2, 2)) {
        Print("FAIL: Color change not detected");
        return false;
    }
    
    // Test 4: Style change should return true
    if(!HasAnyPropertyChanged(1.12345, 1.12345, clrRed, clrRed, STYLE_SOLID, STYLE_DASH, 2, 2)) {
        Print("FAIL: Style change not detected");
        return false;
    }
    
    // Test 5: Width change should return true
    if(!HasAnyPropertyChanged(1.12345, 1.12345, clrRed, clrRed, STYLE_SOLID, STYLE_SOLID, 2, 3)) {
        Print("FAIL: Width change not detected");
        return false;
    }
    
    Print("PASS: HasAnyPropertyChanged tests passed");
    return true;
}

//+------------------------------------------------------------------+
//| Test DetectPropertyChanges                                        |
//+------------------------------------------------------------------+
bool TestDetectPropertyChanges() {
    Print("Testing DetectPropertyChanges...");
    
    // Test 1: No changes
    SPropertyChangeResult result1 = DetectPropertyChanges(1.12345, 1.12345, clrRed, clrRed, 
                                                          STYLE_SOLID, STYLE_SOLID, 2, 2);
    if(result1.anyChanged || result1.priceChanged || result1.colorChanged || 
       result1.styleChanged || result1.widthChanged) {
        Print("FAIL: No changes incorrectly detected");
        return false;
    }
    
    // Test 2: Only price changed
    SPropertyChangeResult result2 = DetectPropertyChanges(1.12345, 1.12346, clrRed, clrRed, 
                                                          STYLE_SOLID, STYLE_SOLID, 2, 2);
    if(!result2.anyChanged || !result2.priceChanged || result2.colorChanged || 
       result2.styleChanged || result2.widthChanged) {
        Print("FAIL: Price change not correctly detected");
        return false;
    }
    
    // Test 3: Multiple changes
    SPropertyChangeResult result3 = DetectPropertyChanges(1.12345, 1.12346, clrRed, clrBlue, 
                                                          STYLE_SOLID, STYLE_DASH, 2, 3);
    if(!result3.anyChanged || !result3.priceChanged || !result3.colorChanged || 
       !result3.styleChanged || !result3.widthChanged) {
        Print("FAIL: Multiple changes not correctly detected");
        return false;
    }
    
    Print("PASS: DetectPropertyChanges tests passed");
    return true;
}

//+------------------------------------------------------------------+
//| Test cache-based overloaded functions                             |
//+------------------------------------------------------------------+
bool TestCacheBasedDetection() {
    Print("Testing cache-based detection functions...");
    
    // Create a cached entry
    SObjectCacheEntry cached;
    cached.name = "TestObject";
    cached.lastPrice = 1.12345;
    cached.lastColor = clrRed;
    cached.lastStyle = STYLE_SOLID;
    cached.lastWidth = 2;
    cached.exists = true;
    
    // Test 1: No changes
    if(HasAnyPropertyChanged(cached, 1.12345, clrRed, STYLE_SOLID, 2)) {
        Print("FAIL: Cache-based no changes detected as changed");
        return false;
    }
    
    // Test 2: Price change
    if(!HasAnyPropertyChanged(cached, 1.12346, clrRed, STYLE_SOLID, 2)) {
        Print("FAIL: Cache-based price change not detected");
        return false;
    }
    
    // Test 3: DetectPropertyChanges with cache
    SPropertyChangeResult result = DetectPropertyChanges(cached, 1.12346, clrBlue, STYLE_DASH, 3);
    if(!result.anyChanged || !result.priceChanged || !result.colorChanged || 
       !result.styleChanged || !result.widthChanged) {
        Print("FAIL: Cache-based DetectPropertyChanges failed");
        return false;
    }
    
    Print("PASS: Cache-based detection tests passed");
    return true;
}

//+------------------------------------------------------------------+
//| Run all PropertyChangeDetector tests                              |
//+------------------------------------------------------------------+
bool RunPropertyChangeDetectorTests() {
    Print("========================================");
    Print("Running PropertyChangeDetector Tests");
    Print("========================================");
    
    bool allPassed = true;
    
    allPassed = allPassed && TestHasPriceChanged();
    allPassed = allPassed && TestHasColorChanged();
    allPassed = allPassed && TestHasStyleChanged();
    allPassed = allPassed && TestHasWidthChanged();
    allPassed = allPassed && TestHasAnyPropertyChanged();
    allPassed = allPassed && TestDetectPropertyChanges();
    allPassed = allPassed && TestCacheBasedDetection();
    
    Print("========================================");
    if(allPassed) {
        Print("ALL TESTS PASSED");
    } else {
        Print("SOME TESTS FAILED");
    }
    Print("========================================");
    
    return allPassed;
}

//+------------------------------------------------------------------+
