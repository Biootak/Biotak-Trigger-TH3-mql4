  //+------------------------------------------------------------------+
//|                                          ObjectCountManager.mqh  |
//|                     Object Count Management & Overflow Prevention|
//|                                                     Overflow      |
//+------------------------------------------------------------------+
#ifndef OBJECT_COUNT_MANAGER_MQH
#define OBJECT_COUNT_MANAGER_MQH
#property strict

//+------------------------------------------------------------------+
//| CONSTANTS - MT4 Object Limits                                    |
//+------------------------------------------------------------------+
#ifndef MT4_OBJECT_LIMIT
#define MT4_OBJECT_LIMIT 64000          // MT4 hard limit (~64K)
#endif
#ifndef CRITICAL_OBJECT_LIMIT
#define CRITICAL_OBJECT_LIMIT 50000     // Critical threshold (78% of limit)
#endif
#ifndef MAX_SAFE_OBJECTS
#define MAX_SAFE_OBJECTS 5000           // Warning threshold
#endif
#ifndef EMERGENCY_CLEANUP_AGE
#define EMERGENCY_CLEANUP_AGE 3600      // 1 hour (seconds)
#endif

//+------------------------------------------------------------------+
//| Global State                                                      |
//+------------------------------------------------------------------+
static uint g_lastObjectCountCheckMs = 0;   // GetTickCount-based (ms)
static int g_lastObjectCount = 0;
static datetime g_lastEmergencyCleanup = 0;

//+------------------------------------------------------------------+
//| Check if we can safely create new objects                        |
//|                                                                  |
//| Returns: true if safe, false if limit reached                   |
//+------------------------------------------------------------------+
bool CanCreateObject()
{
    //
    // OPTIMIZATION: Cache check (update every 5 seconds via GetTickCount)
    //
    uint nowMs = GetTickCount();
    if((nowMs - g_lastObjectCountCheckMs) < 5000 && g_lastObjectCount > 0) {
        // Use cached count
        if(g_lastObjectCount < MAX_SAFE_OBJECTS) {
            return true; // Fast path
        }
    }
    
    //
    // Get current object count
    //
    int totalObjects = ObjectsTotal(0, -1, -1);
    g_lastObjectCount = totalObjects;
    g_lastObjectCountCheckMs = nowMs;
    
    //                                                                
    // CRITICAL: Check if limit reached
    //                                                                
    if(totalObjects >= CRITICAL_OBJECT_LIMIT) {
        Print("  CRITICAL: Object limit reached (", totalObjects, "/", MT4_OBJECT_LIMIT, ")");
        Print("   Forcing emergency cleanup...");
        
        // Emergency cleanup
        int cleanedCount = EmergencyCleanupObjects();
        
        // Re-check after cleanup
        totalObjects = ObjectsTotal(0, -1, -1);
        g_lastObjectCount = totalObjects;
        g_lastObjectCountCheckMs = GetTickCount();
        
        if(totalObjects >= CRITICAL_OBJECT_LIMIT) {
            Print("  FATAL: Cannot free objects (", totalObjects, " remaining)");
            Print("   Please close some charts or remove other indicators");
            return false;
        }
        
        Print("  Emergency cleanup successful: ", cleanedCount, " objects removed");
        Print("   Current count: ", totalObjects);
    }
    
    //                                                                
    // WARNING: Approaching limit
    //                                                                
    if(totalObjects >= MAX_SAFE_OBJECTS) {
        // Throttle warning (once per minute via GetTickCount)
        static uint s_lastWarningMs = 0;
        if((nowMs - s_lastWarningMs) > 60000) {
            Print("   WARNING: Approaching object limit (", totalObjects, "/", MAX_SAFE_OBJECTS, ")");
            Print("   Consider reducing Max Levels in settings");
            s_lastWarningMs = nowMs;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Emergency Object Cleanup                                         |
//|                                                                  |
//| Returns: Number of objects deleted                               |
//+------------------------------------------------------------------+
int EmergencyCleanupObjects()
{
    datetime currentTime = TimeCurrent();
    
    //                                                                
    // Prevent cleanup spam (minimum 30 seconds between cleanups)
    //                                                                
    if(currentTime - g_lastEmergencyCleanup < 30) {
        Print("   EmergencyCleanup: Too soon since last cleanup, skipping");
        return 0;
    }
    
    g_lastEmergencyCleanup = currentTime;
    
    int deletedCount = 0;
    datetime cutoffTime = currentTime - EMERGENCY_CLEANUP_AGE;
    
    Print("   Emergency cleanup starting...");
    Print("   Cutoff time: ", TimeToString(cutoffTime, TIME_DATE|TIME_MINUTES));
    
    //                                                                
    // PHASE 1: Delete old temporary objects (labels, zones)
    // OPTIMIZATION: Cache prefix and length
    //                                                                
    string cachedPrefix = inpObjectPrefix;
    int prefixLen = StringLen(cachedPrefix);
    
    int totalObjects = ObjectsTotal(0, -1, -1);
    for(int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, -1);
        
        // Skip TH3 structures (user drawings - never delete)
        if(StringFind(objName, "TH3_Structure_") >= 0) {
            continue;
        }
        
        // Skip custom price line (user setting)
        if(StringFind(objName, "CustomPriceHorizontalLine") >= 0) {
            continue;
        }
        
        // CRITICAL FIX: Skip current indicator objects (prevent self-deletion)
        // OPTIMIZED: Use StringSubstr for faster prefix check
        if(StringLen(objName) >= prefixLen && StringSubstr(objName, 0, prefixLen) == cachedPrefix) {
            continue;
        }
        
        // Get object creation time
        datetime objTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME);
        
        // Delete if older than cutoff
        if(objTime > 0 && objTime < cutoffTime)
        {
            if(ObjectDelete(0, objName)) {
                deletedCount++;
            }
        }
    }
    
    Print("   Phase 1: Deleted ", deletedCount, " old objects");
    
    //                                                                
    // PHASE 2: If still critical, delete ALL non-essential objects
    //                                                                
    totalObjects = ObjectsTotal(0, -1, -1);
    if(totalObjects >= CRITICAL_OBJECT_LIMIT) {
        Print("   Still critical after Phase 1, starting Phase 2...");
        
        int phase2Deleted = 0;
        
        // Delete all zones (can be recreated)
        phase2Deleted += ObjectsDeleteAll(0, "Zone_", -1, -1);
        
        // Delete all mid-zones (can be recreated)
        phase2Deleted += ObjectsDeleteAll(0, "Mid_", -1, -1);
        
        // Delete all labels except mode labels
        for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
        {
            string objName = ObjectName(0, i, -1, -1);
            
            // Keep mode labels (important for user)
            if(StringFind(objName, "StepMode_Label") >= 0 ||
               StringFind(objName, "BasisMode_Label") >= 0 ||
               StringFind(objName, "Factor_Label") >= 0 ||
               StringFind(objName, "LockStatus_Label") >= 0) {
                continue;
            }
            
            // Delete other labels
            if(ObjectGetInteger(0, objName, OBJPROP_TYPE) == OBJ_LABEL) {
                if(ObjectDelete(0, objName)) {
                    phase2Deleted++;
                }
            }
        }
        
        deletedCount += phase2Deleted;
        Print("   Phase 2: Deleted ", phase2Deleted, " non-essential objects");
    }
    
    //                                                                
    // PHASE 3: Force chart redraw
    //                                                                
    ChartRedraw();
    
    Print("  Emergency cleanup complete: ", deletedCount, " total objects removed");
    
    return deletedCount;
}

//+------------------------------------------------------------------+
//| Get Current Object Count (cached)                                |
//|                         (     )                                  |
//+------------------------------------------------------------------+
int GetCurrentObjectCount()
{
    uint nowMs = GetTickCount();
    
    // Use cache if recent (< 5 seconds)
    if((nowMs - g_lastObjectCountCheckMs) < 5000 && g_lastObjectCount > 0) {
        return g_lastObjectCount;
    }
    
    // Update cache
    g_lastObjectCount = ObjectsTotal(0, -1, -1);
    g_lastObjectCountCheckMs = nowMs;
    
    return g_lastObjectCount;
}

//+------------------------------------------------------------------+
//| Invalidate Object Count Cache (force refresh on next query)      |
//+------------------------------------------------------------------+
void InvalidateObjectCountCache()
{
    g_lastObjectCountCheckMs = 0;
    g_lastObjectCount = 0;
}

//+------------------------------------------------------------------+
//| Cleanup Object Count Manager                                     |
//|                                                                  |
//+------------------------------------------------------------------+
void CleanupObjectCountManager()
{
    g_lastObjectCountCheckMs = 0;
    g_lastObjectCount = 0;
    g_lastEmergencyCleanup = 0;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  ObjectCountManager cleaned up");
    #endif
}

//+------------------------------------------------------------------+
//| Print Object Count Statistics                                    |
//|                                                                  |
//+------------------------------------------------------------------+
void PrintObjectCountStats()
{
    int totalObjects = ObjectsTotal(0, -1, -1);
    
    // Count by type
    int lines = 0, labels = 0, rectangles = 0, trends = 0, other = 0;
    
    for(int i = 0; i < totalObjects; i++)
    {
        string objName = ObjectName(0, i, -1, -1);
        int objType = (int)ObjectGetInteger(0, objName, OBJPROP_TYPE);
        
        switch(objType)
        {
            case OBJ_HLINE:
            case OBJ_VLINE:
                lines++;
                break;
            case OBJ_LABEL:
                labels++;
                break;
            case OBJ_RECTANGLE:
            case OBJ_RECTANGLE_LABEL:
                rectangles++;
                break;
            case OBJ_TREND:
                trends++;
                break;
            default:
                other++;
                break;
        }
    }
    
    Print("====================");
    Print("   OBJECT COUNT STATISTICS                                       ");
    Print("====================");
    Print("   Total Objects: ", totalObjects, " / ", MT4_OBJECT_LIMIT);
    Print("   Usage: ", DoubleToString(100.0 * totalObjects / MT4_OBJECT_LIMIT, 1), "%");
    Print("====================");
    Print("   Lines:      ", lines);
    Print("   Labels:     ", labels);
    Print("   Rectangles: ", rectangles);
    Print("   Trends:     ", trends);
    Print("   Other:      ", other);
    Print("====================");
}

#endif // OBJECT_COUNT_MANAGER_MQH
