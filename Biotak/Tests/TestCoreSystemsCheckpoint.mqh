//+------------------------------------------------------------------+
//|                                  TestCoreSystemsCheckpoint.mqh   |
//|                                      Biotak Trigger TH3 Indicator |
//|                    Checkpoint 5: Verify Core Systems Work         |
//+------------------------------------------------------------------+
//| This test file verifies that all four core systems implemented   |
//| in Tasks 1-4 work independently:                                 |
//|   1. Object Cache System (ObjectCache.mqh)                       |
//|   2. Property Change Detector (PropertyChangeDetector.mqh)       |
//|   3. Visibility Manager (VisibilityManager.mqh)                  |
//|   4. Redraw Flag Manager (RedrawFlagManager.mqh)                 |
//+------------------------------------------------------------------+

#property copyright "Biotak"
#property strict

// Include all core systems
#include "../ObjectCache.mqh"
#include "../PropertyChangeDetector.mqh"
#include "../VisibilityManager.mqh"
#include "../RedrawFlagManager.mqh"

//+------------------------------------------------------------------+
//| Test Object Cache System                                          |
//+------------------------------------------------------------------+
bool TestObjectCacheSystem() {
    Print("========================================");
    Print("Testing Object Cache System");
    Print("========================================");
    
    // Clear cache to start fresh
    CacheClear();
    
    // Test 1: Cache should be empty after clear
    if(CacheGetSize() != 0) {
        Print("FAIL: Cache not empty after clear");
        return false;
    }
    Print("PASS: Cache clear works");
    
    // Test 2: Add object to cache
    CacheAddObject("TestLine1", 1.12345, clrRed, STYLE_SOLID, 2);
    if(CacheGetSize() != 1) {
        Print("FAIL: Cache size incorrect after add");
        return false;
    }
    Print("PASS: Cache add works");
    
    // Test 3: Check object exists
    if(!CacheObjectExists("TestLine1")) {
        Print("FAIL: Object not found in cache");
        return false;
    }
    Print("PASS: Cache existence check works");
    
    // Test 4: Get cached object
    SObjectCacheEntry entry;
    if(!CacheGetObject("TestLine1", entry)) {
        Print("FAIL: Could not retrieve cached object");
        return false;
    }
    if(entry.name != "TestLine1" || entry.lastPrice != 1.12345 || 
       entry.lastColor != clrRed || entry.lastStyle != STYLE_SOLID || 
       entry.lastWidth != 2) {
        Print("FAIL: Cached object properties incorrect");
        return false;
    }
    Print("PASS: Cache get works");
    
    // Test 5: Update cached object
    CacheUpdateObject("TestLine1", 1.12346, clrBlue, STYLE_DASH, 3);
    if(!CacheGetObject("TestLine1", entry)) {
        Print("FAIL: Could not retrieve updated object");
        return false;
    }
    if(entry.lastPrice != 1.12346 || entry.lastColor != clrBlue || 
       entry.lastStyle != STYLE_DASH || entry.lastWidth != 3) {
        Print("FAIL: Cached object not updated correctly");
        return false;
    }
    Print("PASS: Cache update works");
    
    // Test 6: Add multiple objects
    CacheAddObject("TestLine2", 1.23456, clrGreen, STYLE_DOT, 1);
    CacheAddObject("TestLine3", 1.34567, clrYellow, STYLE_DASHDOT, 4);
    if(CacheGetSize() != 3) {
        Print("FAIL: Cache size incorrect after multiple adds");
        return false;
    }
    Print("PASS: Multiple cache entries work");
    
    // Test 7: Remove object from cache
    CacheRemoveObject("TestLine2");
    if(CacheGetSize() != 2) {
        Print("FAIL: Cache size incorrect after remove");
        return false;
    }
    if(CacheObjectExists("TestLine2")) {
        Print("FAIL: Removed object still exists in cache");
        return false;
    }
    Print("PASS: Cache remove works");
    
    // Test 8: Clear cache again
    CacheClear();
    if(CacheGetSize() != 0) {
        Print("FAIL: Cache not empty after second clear");
        return false;
    }
    Print("PASS: Cache clear works after operations");
    
    Print("========================================");
    Print("Object Cache System: ALL TESTS PASSED");
    Print("========================================");
    return true;
}

//+------------------------------------------------------------------+
//| Test Property Change Detector                                     |
//+------------------------------------------------------------------+
bool TestPropertyChangeDetectorSystem() {
    Print("========================================");
    Print("Testing Property Change Detector");
    Print("========================================");
    
    // Test 1: Price change detection
    if(HasPriceChanged(1.12345, 1.12345)) {
        Print("FAIL: Identical prices detected as changed");
        return false;
    }
    if(!HasPriceChanged(1.12345, 1.12346)) {
        Print("FAIL: Different prices not detected");
        return false;
    }
    Print("PASS: Price change detection works");
    
    // Test 2: Color change detection
    if(HasColorChanged(clrRed, clrRed)) {
        Print("FAIL: Identical colors detected as changed");
        return false;
    }
    if(!HasColorChanged(clrRed, clrBlue)) {
        Print("FAIL: Different colors not detected");
        return false;
    }
    Print("PASS: Color change detection works");
    
    // Test 3: Style change detection
    if(HasStyleChanged(STYLE_SOLID, STYLE_SOLID)) {
        Print("FAIL: Identical styles detected as changed");
        return false;
    }
    if(!HasStyleChanged(STYLE_SOLID, STYLE_DASH)) {
        Print("FAIL: Different styles not detected");
        return false;
    }
    Print("PASS: Style change detection works");
    
    // Test 4: Width change detection
    if(HasWidthChanged(2, 2)) {
        Print("FAIL: Identical widths detected as changed");
        return false;
    }
    if(!HasWidthChanged(2, 3)) {
        Print("FAIL: Different widths not detected");
        return false;
    }
    Print("PASS: Width change detection works");
    
    // Test 5: Comprehensive change detection
    if(HasAnyPropertyChanged(1.12345, 1.12345, clrRed, clrRed, STYLE_SOLID, STYLE_SOLID, 2, 2)) {
        Print("FAIL: No changes detected as changed");
        return false;
    }
    if(!HasAnyPropertyChanged(1.12345, 1.12346, clrRed, clrRed, STYLE_SOLID, STYLE_SOLID, 2, 2)) {
        Print("FAIL: Price change not detected in comprehensive check");
        return false;
    }
    Print("PASS: Comprehensive change detection works");
    
    // Test 6: Detailed change result
    SPropertyChangeResult result = DetectPropertyChanges(1.12345, 1.12346, clrRed, clrBlue, 
                                                         STYLE_SOLID, STYLE_DASH, 2, 3);
    if(!result.priceChanged || !result.colorChanged || !result.styleChanged || 
       !result.widthChanged || !result.anyChanged) {
        Print("FAIL: Detailed change detection incorrect");
        return false;
    }
    Print("PASS: Detailed change detection works");
    
    // Test 7: Cache-based detection
    SObjectCacheEntry cached;
    cached.lastPrice = 1.12345;
    cached.lastColor = clrRed;
    cached.lastStyle = STYLE_SOLID;
    cached.lastWidth = 2;
    
    if(HasAnyPropertyChanged(cached, 1.12345, clrRed, STYLE_SOLID, 2)) {
        Print("FAIL: Cache-based no changes detected as changed");
        return false;
    }
    if(!HasAnyPropertyChanged(cached, 1.12346, clrRed, STYLE_SOLID, 2)) {
        Print("FAIL: Cache-based price change not detected");
        return false;
    }
    Print("PASS: Cache-based detection works");
    
    Print("========================================");
    Print("Property Change Detector: ALL TESTS PASSED");
    Print("========================================");
    return true;
}

//+------------------------------------------------------------------+
//| Test Redraw Flag Manager                                          |
//+------------------------------------------------------------------+
bool TestRedrawFlagManagerSystem() {
    Print("========================================");
    Print("Testing Redraw Flag Manager");
    Print("========================================");
    
    // Test 1: Initial state (should be true by default)
    if(!IsRedrawNeeded()) {
        Print("FAIL: Initial redraw flag should be true");
        return false;
    }
    Print("PASS: Initial redraw flag is true");
    
    // Test 2: Clear flag
    ClearRedrawFlag();
    if(IsRedrawNeeded()) {
        Print("FAIL: Flag not cleared");
        return false;
    }
    if(!ShouldSkipRedraw()) {
        Print("FAIL: ShouldSkipRedraw incorrect after clear");
        return false;
    }
    Print("PASS: Clear flag works");
    
    // Test 3: Set flag
    SetRedrawFlag(true);
    if(!IsRedrawNeeded()) {
        Print("FAIL: Flag not set to true");
        return false;
    }
    if(ShouldSkipRedraw()) {
        Print("FAIL: ShouldSkipRedraw incorrect after set");
        return false;
    }
    Print("PASS: Set flag works");
    
    // Test 4: Request redraw
    ClearRedrawFlag();
    RequestRedraw();
    if(!IsRedrawNeeded()) {
        Print("FAIL: RequestRedraw did not set flag");
        return false;
    }
    Print("PASS: Request redraw works");
    
    // Test 5: Toggle flag multiple times
    SetRedrawFlag(false);
    if(IsRedrawNeeded()) {
        Print("FAIL: Flag not set to false");
        return false;
    }
    SetRedrawFlag(true);
    if(!IsRedrawNeeded()) {
        Print("FAIL: Flag not set back to true");
        return false;
    }
    Print("PASS: Flag toggle works");
    
    Print("========================================");
    Print("Redraw Flag Manager: ALL TESTS PASSED");
    Print("========================================");
    return true;
}

//+------------------------------------------------------------------+
//| Test Visibility Manager (without actual chart objects)           |
//| Note: Full testing requires chart objects, this tests logic only |
//+------------------------------------------------------------------+
bool TestVisibilityManagerSystem() {
    Print("========================================");
    Print("Testing Visibility Manager (Logic)");
    Print("========================================");
    
    // Test 1: ShouldObjectBeVisible with all visible
    // Assume g_isHidden = false and g_linesVisible = true
    bool shouldBeVisible = ShouldObjectBeVisible(false); // Non-line object
    if(!shouldBeVisible) {
        Print("FAIL: Non-line object should be visible when not hidden");
        return false;
    }
    Print("PASS: Non-line visibility check works");
    
    // Test 2: Line visibility check
    shouldBeVisible = ShouldObjectBeVisible(true); // Line object
    if(!shouldBeVisible) {
        Print("FAIL: Line object should be visible when lines visible");
        return false;
    }
    Print("PASS: Line visibility check works");
    
    // Note: Full testing of SetObjectVisibility, SetAllTHObjectsVisibility,
    // SetAllLineObjectsVisibility, and ApplyVisibilityState requires actual
    // chart objects and cannot be fully tested in this unit test context.
    // These functions will be tested during integration testing.
    
    Print("========================================");
    Print("Visibility Manager: LOGIC TESTS PASSED");
    Print("Note: Full testing requires chart objects");
    Print("========================================");
    return true;
}

//+------------------------------------------------------------------+
//| Run all checkpoint tests                                          |
//+------------------------------------------------------------------+
bool RunCheckpoint5Tests() {
    Print("");
    Print("################################################");
    Print("# CHECKPOINT 5: CORE SYSTEMS VERIFICATION      #");
    Print("################################################");
    Print("");
    
    bool allPassed = true;
    
    // Test each core system independently
    allPassed = allPassed && TestObjectCacheSystem();
    Print("");
    
    allPassed = allPassed && TestPropertyChangeDetectorSystem();
    Print("");
    
    allPassed = allPassed && TestRedrawFlagManagerSystem();
    Print("");
    
    allPassed = allPassed && TestVisibilityManagerSystem();
    Print("");
    
    Print("################################################");
    if(allPassed) {
        Print("# CHECKPOINT 5: ALL TESTS PASSED ✓             #");
        Print("# All core systems work independently          #");
    } else {
        Print("# CHECKPOINT 5: SOME TESTS FAILED ✗            #");
        Print("# Review failures above                        #");
    }
    Print("################################################");
    Print("");
    
    return allPassed;
}

//+------------------------------------------------------------------+
