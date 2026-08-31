  //+------------------------------------------------------------------+
//|                                              MemoryManager.mqh   |
//|                     Memory Management & Leak Detection           |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef MEMORY_MANAGER_MQH
#define MEMORY_MANAGER_MQH
#property strict

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define MEMORY_CHECK_INTERVAL_SECONDS 60    // Check every minute
#define MEMORY_WARNING_THRESHOLD 0.8        // Warn at 80% usage
#define MEMORY_CRITICAL_THRESHOLD 0.95      // Critical at 95% usage

//+------------------------------------------------------------------+
//| Memory Tracking Structure                                         |
//+------------------------------------------------------------------+
struct MemoryStats {
    int totalObjectsCreated;
    int totalObjectsDeleted;
    int currentObjectCount;
    int peakObjectCount;
    datetime lastCheckTime;
    bool warningIssued;
    bool criticalIssued;
};

static MemoryStats g_memoryStats;
static bool g_memoryStatsInitialized = false;
static uint g_memStats_lastCheckMs = 0;    // GetTickCount-based interval gate

//+------------------------------------------------------------------+
//| Initialize Memory Manager                                        |
//+------------------------------------------------------------------+
void InitializeMemoryManager()
{
    g_memoryStats.totalObjectsCreated = 0;
    g_memoryStats.totalObjectsDeleted = 0;
    g_memoryStats.currentObjectCount = 0;
    g_memoryStats.peakObjectCount = 0;
    g_memoryStats.lastCheckTime = TimeCurrent();
    g_memoryStats.warningIssued = false;
    g_memoryStats.criticalIssued = false;
    g_memoryStatsInitialized = true;
    
    Print("  Memory Manager initialized");
}

//+------------------------------------------------------------------+
//| Track Object Creation                                            |
//+------------------------------------------------------------------+
void TrackObjectCreation(const string objectName)
{
    if(!g_memoryStatsInitialized) InitializeMemoryManager();
    
    g_memoryStats.totalObjectsCreated++;
    g_memoryStats.currentObjectCount++;
    
    if(g_memoryStats.currentObjectCount > g_memoryStats.peakObjectCount) {
        g_memoryStats.peakObjectCount = g_memoryStats.currentObjectCount;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    if(g_memoryStats.totalObjectsCreated % 100 == 0) {
        Print("   Memory: ", g_memoryStats.currentObjectCount, " objects (Peak: ", 
              g_memoryStats.peakObjectCount, ")");
    }
    #endif
}

//+------------------------------------------------------------------+
//| Track Object Deletion                                            |
//+------------------------------------------------------------------+
void TrackObjectDeletion(const string objectName)
{
    if(!g_memoryStatsInitialized) InitializeMemoryManager();
    
    g_memoryStats.totalObjectsDeleted++;
    g_memoryStats.currentObjectCount--;
    
    if(g_memoryStats.currentObjectCount < 0) {
        Print("   WARNING: Negative object count detected - resetting");
        g_memoryStats.currentObjectCount = 0;
    }
}

//+------------------------------------------------------------------+
//| Check Memory Health                                              |
//+------------------------------------------------------------------+
void CheckMemoryHealth()
{
    if(!g_memoryStatsInitialized) InitializeMemoryManager();
    
    // PERF: Use GetTickCount() ms-based check instead of TimeCurrent() syscall
    uint nowMs = GetTickCount();
    if(nowMs - g_memStats_lastCheckMs < (uint)MEMORY_CHECK_INTERVAL_SECONDS * 1000) {
        return; // Too soon
    }
    g_memStats_lastCheckMs = nowMs;
    g_memoryStats.lastCheckTime = CacheGetFrameTime();
    
    // Get actual object count from MT4
    int actualCount = ObjectsTotal(0, -1, -1);
    
    // Sync our tracking with reality
    if(MathAbs(actualCount - g_memoryStats.currentObjectCount) > 10) {
        Print("   Memory tracking drift detected: tracked=", g_memoryStats.currentObjectCount,
              ", actual=", actualCount, " - syncing");
        g_memoryStats.currentObjectCount = actualCount;
    }
    
    // Calculate usage percentage
    double usagePercent = (double)actualCount / MT4_OBJECT_LIMIT;
    
    // Issue warnings
    if(usagePercent >= MEMORY_CRITICAL_THRESHOLD) {
        if(!g_memoryStats.criticalIssued) {
            Print("  CRITICAL: Memory usage at ", DoubleToString(usagePercent * 100, 1), "%");
            Print("   Objects: ", actualCount, "/", MT4_OBJECT_LIMIT);
            Print("   Consider reducing Max Levels or closing other indicators");
            g_memoryStats.criticalIssued = true;
        }
    }
    else if(usagePercent >= MEMORY_WARNING_THRESHOLD) {
        if(!g_memoryStats.warningIssued) {
            Print("   WARNING: Memory usage at ", DoubleToString(usagePercent * 100, 1), "%");
            Print("   Objects: ", actualCount, "/", MT4_OBJECT_LIMIT);
            g_memoryStats.warningIssued = true;
        }
    }
    else {
        // Reset warnings if usage drops
        g_memoryStats.warningIssued = false;
        g_memoryStats.criticalIssued = false;
    }
}

//+------------------------------------------------------------------+
//| Detect Memory Leaks                                              |
//+------------------------------------------------------------------+
bool DetectMemoryLeaks()
{
    if(!g_memoryStatsInitialized) return false;
    
    int expectedCount = g_memoryStats.totalObjectsCreated - g_memoryStats.totalObjectsDeleted;
    int actualCount = ObjectsTotal(0, -1, -1);
    
    int difference = actualCount - expectedCount;
    
    if(difference > 50) { // Threshold for leak detection
        Print("   MEMORY LEAK DETECTED:");
        Print("   Expected objects: ", expectedCount);
        Print("   Actual objects: ", actualCount);
        Print("   Leaked objects: ", difference);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Memory Statistics                                            |
//+------------------------------------------------------------------+
void PrintMemoryStatistics()
{
    if(!g_memoryStatsInitialized) {
        Print("Memory Manager not initialized");
        return;
    }
    
    int actualCount = ObjectsTotal(0, -1, -1);
    double usagePercent = (double)actualCount / MT4_OBJECT_LIMIT * 100.0;
    
    Print("====================");
    Print("   MEMORY STATISTICS                                         ");
    Print("====================");
    Print("   Current Objects: ", actualCount, " (", DoubleToString(usagePercent, 1), "%)");
    Print("   Peak Objects: ", g_memoryStats.peakObjectCount);
    Print("   Total Created: ", g_memoryStats.totalObjectsCreated);
    Print("   Total Deleted: ", g_memoryStats.totalObjectsDeleted);
    Print("   MT4 Limit: ", MT4_OBJECT_LIMIT);
    Print("====================");
}

//+------------------------------------------------------------------+
//| Cleanup All Tracked Objects                                      |
//+------------------------------------------------------------------+
void CleanupAllObjects(const string prefix = "")
{
    int deletedCount = 0;
    
    if(StringLen(prefix) > 0) {
        // Delete objects with specific prefix
        deletedCount = ObjectsDeleteAll(0, prefix, -1, -1);
    } else {
        // Delete all objects on chart
        deletedCount = ObjectsDeleteAll(0, -1, -1);
    }
    
    if(deletedCount > 0) {
        Print("  Cleaned up ", deletedCount, " objects", 
              (StringLen(prefix) > 0) ? " with prefix: " + prefix : "");
    }
    
    // Reset stats if all objects deleted
    if(StringLen(prefix) == 0) {
        g_memoryStats.currentObjectCount = 0;
        g_memoryStats.totalObjectsDeleted += deletedCount;
    }
}

//+------------------------------------------------------------------+
//| Deinitialize Memory Manager                                      |
//+------------------------------------------------------------------+
void DeinitializeMemoryManager()
{
    if(!g_memoryStatsInitialized) return;
    
    Print("====================");
    Print("Memory Manager Shutdown");
    PrintMemoryStatistics();
    
    // Check for leaks one last time
    if(DetectMemoryLeaks()) {
        Print("   Memory leaks detected during shutdown");
    }
    
    g_memoryStatsInitialized = false;
    Print("====================");
}

#endif // MEMORY_MANAGER_MQH
