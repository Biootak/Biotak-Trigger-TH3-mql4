//+------------------------------------------------------------------+
//|                                          FrequencyLearning.mqh   |
//|                     Machine Learning for Frequency Selection     |
//|                     سیستم یادگیری ماشین برای انتخاب فرکانس       |
//|                     GOLD VERSION - Bug-Free & Optimized          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| CONSTANTS - No Magic Numbers                                     |
//+------------------------------------------------------------------+
#define MAX_LEARNING_DATA_SIZE 10000        // Maximum patterns to store (circular buffer)
#define MIN_PATTERNS_FOR_LEARNING 5         // Minimum patterns before weight adjustment
#define FREQUENCY_CHANGE_THRESHOLD 0.001    // Minimum change to detect frequency modification
#define BUFFER_SAFETY_MARGIN 100            // Safety margin before hitting max size
#define MAX_PATTERN_NAME_LENGTH 100         // ✅ Security: Maximum pattern name length
#define MAX_FILENAME_LENGTH 200             // ✅ Security: Maximum filename length (Windows=260)

// GOLD FIX #2: Enhanced circular buffer with overflow protection
// CIRCULAR BUFFER IMPLEMENTATION:
// وقتی تعداد پترن‌ها به MAX_LEARNING_DATA_SIZE می‌رسد، قدیمی‌ترین پترن حذف می‌شود
// این باعث می‌شود که حافظه همیشه محدود بماند و جدیدترین داده‌ها نگه داشته شوند
// When pattern count reaches MAX_LEARNING_DATA_SIZE, oldest pattern is removed
// This ensures memory stays bounded and newest data is retained

//+------------------------------------------------------------------+
//| Pattern Learning Data Structure (MUST BE BEFORE USAGE)          |
//| ساختار داده یادگیری الگو                                         |
//+------------------------------------------------------------------+
struct PatternLearningData {
    // شناسه‌ها
    string patternName;
    datetime timestamp;
    string symbol;
    int timeframe;
    
    // ویژگی‌های موج (Wave features)
    double XA_Pips;
    double AB_Pips;
    double BC_Pips;
    int XA_Minutes;
    int AB_Minutes;
    int BC_Minutes;
    
    // ویژگی‌های محاسبه شده (Calculated features)
    double AB_Speed;              // سرعت موج AB (pips/min)
    double AB_Angle;              // زاویه Gann موج AB
    double speedConsistency;      // ثبات سرعت (0-1)
    double AB_XA_Ratio;           // نسبت Fibonacci
    double BC_AB_Ratio;           // نسبت BC به AB
    double timeSymmetry;          // تقارن زمانی
    double consolidationFactor;   // ضریب consolidation
    int requiredRestCandles;      // کندل‌های استراحت مورد نیاز
    double dailyATR;              // ATR روزانه
    
    // انتخاب فرکانس (Frequency selection)
    double suggestedFrequency;    // فرکانس پیشنهادی سیستم
    int suggestedFreqIndex;       // ایندکس فرکانس پیشنهادی
    int targetStep;               // گام هدف (3, 5, or 7)
    double errorPercent;          // درصد خطا
    double totalScore;            // امتیاز کل
    
    // بازخورد کاربر (User feedback)
    bool feedbackReceived;        // آیا بازخورد دریافت شده؟
    bool userApproved;            // آیا کاربر تایید کرد؟
    double userSelectedFrequency; // فرکانس انتخابی کاربر
    int userSelectedFreqIndex;    // ایندکس فرکانس انتخابی کاربر
    int userSelectedStep;         // گام انتخابی کاربر
    double actualErrorPercent;    // خطای واقعی بعد از تایید کاربر
    
    // اسکرین‌شات (Screenshot)
    string screenshotFilename;
};

// Global learning data array with size tracking
static PatternLearningData g_learningData[];
static int g_learningDataCount = 0;
static bool g_learningDataInitialized = false;
#define SCREENSHOT_RENDER_DELAY_MS 300      // Delay for chart rendering before screenshot
#define SCREENSHOT_WIDTH 1920               // Full HD width
#define SCREENSHOT_HEIGHT 1080              // Full HD height
// MAX_FILENAME_LENGTH defined at top of file (line 16)
#define WEIGHT_ADJUSTMENT_FACTOR 0.02       // Gradual weight adjustment rate
#define MIN_CONSOLIDATION_WEIGHT 0.01       // Minimum consolidation weight
#define MAX_CONSOLIDATION_WEIGHT 0.15       // Maximum consolidation weight
#define MIN_STEP_PRIORITY 0.3               // Minimum step priority
#define MAX_STEP_PRIORITY 0.9               // Maximum step priority
#define PATTERN_BARS_PADDING 30             // Extra bars for screenshot visibility

//+------------------------------------------------------------------+
//| GOLD FIX #2: Safe array append with circular buffer overflow     |
//| PERF FIX: Use write index instead of O(n) array shift           |
//+------------------------------------------------------------------+
// Circular buffer head index (points to oldest entry)
static int g_learningDataHead = 0;
// Total entries ever written (for CSV row tracking)
static int g_learningDataTotalWritten = 0;

bool SafeAppendLearningData(const PatternLearningData &newData) {
    // ✅ SECURITY FIX: Validate pattern name length
    if(StringLen(newData.patternName) > MAX_PATTERN_NAME_LENGTH) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ SafeAppendLearningData: Pattern name too long (", 
              StringLen(newData.patternName), " chars), truncating to ", MAX_PATTERN_NAME_LENGTH);
        #endif
        // Cannot modify const reference, but validation prevents buffer overflow
        return false;
    }
    
    // Initialize if needed
    if(!g_learningDataInitialized) {
        ArrayResize(g_learningData, 0);
        g_learningDataCount = 0;
        g_learningDataHead = 0;
        g_learningDataTotalWritten = 0;
        g_learningDataInitialized = true;
    }
    
    // PERF FIX: Use circular write instead of O(n) array shift
    if(g_learningDataCount >= MAX_LEARNING_DATA_SIZE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Learning data buffer full, overwriting oldest entry at index ", g_learningDataHead);
        #endif
        
        // Overwrite oldest entry directly (O(1) instead of O(n))
        g_learningData[g_learningDataHead] = newData;
        g_learningDataHead = (g_learningDataHead + 1) % MAX_LEARNING_DATA_SIZE;
        g_learningDataTotalWritten++;
        return true;
    }
    
    // Safe resize with reserve to avoid +1 pattern
    int newSize = g_learningDataCount + 1;
    if(ArrayResize(g_learningData, newSize, 256) < newSize) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ Failed to resize learning data array");
        #endif
        return false;
    }
    
    // Append new data
    g_learningData[g_learningDataCount] = newData;
    g_learningDataCount++;
    g_learningDataTotalWritten++;
    
    return true;
}

//+------------------------------------------------------------------+
//| ERROR CODES                                                       |
//+------------------------------------------------------------------+
enum LEARNING_ERROR_CODE {
    LEARNING_SUCCESS = 0,
    LEARNING_ERROR_INVALID_INDEX = -1,
    LEARNING_ERROR_FILE_OPEN_FAILED = -2,
    LEARNING_ERROR_FILE_WRITE_FAILED = -3,
    LEARNING_ERROR_INVALID_DATA = -4,
    LEARNING_ERROR_MEMORY_LIMIT = -5,
    LEARNING_ERROR_STATE_CONFLICT = -6
};

//+------------------------------------------------------------------+
//| Learned Weights Structure                                        |
//| ساختار وزن‌های یادگیری شده                                       |
//+------------------------------------------------------------------+
struct LearnedWeights {
    double stepPriorityWeight;      // وزن اولویت گام
    double errorWeight;             // وزن خطای ریاضی
    double speedConsistencyWeight;  // وزن ثبات سرعت
    double timeSymmetryWeight;      // وزن تقارن زمانی
    double fibonacciWeight;         // وزن Fibonacci
    double freqDeviationWeight;     // وزن انحراف از فرکانس پیشنهادی
    double consolidationWeight;     // وزن consolidation
    
    // تنظیمات اولویت گام
    double step5Priority;           // اولویت Step 5
    double step3_7Priority;         // اولویت Step 3 و 7
    double step1Priority;           // اولویت Step 1
    
    // آمار یادگیری
    int totalPatterns;
    int approvedPatterns;
    int rejectedPatterns;
    datetime lastUpdate;
};

//+------------------------------------------------------------------+
//| GLOBAL STATE - Thread-Safe Management                            |
//+------------------------------------------------------------------+
// NOTE: g_learningData[] and g_learningDataCount already declared above

// الگوی فعلی در انتظار بازخورد
static string g_currentPatternForFeedback = "";
static int g_currentPatternIndex = -1;

// حالت تنظیم دستی (deprecated - no longer used)
static bool g_adjustmentMode = false;
static int g_adjustmentPatternIndex = -1;

// سیستم یادگیری هوشمند (بدون دکمه)
static double g_lastSuggestedFrequency = 0.0;
static int g_lastSuggestedFreqIndex = 0;
static datetime g_patternCreationTime = 0;
static bool g_waitingForFeedback = false;
static int g_pendingPatternIndex = -1;

// State lock flag (atomic using GlobalVariable)
// استفاده از GlobalVariable برای atomic operations
static string STATE_LOCK_NAME = "Biotak_FreqLearning_Lock";

// پوشه گزارشات (Reports folder)
static string REPORTS_FOLDER = "BiotakReports";

// وزن‌های یادگیری شده
static LearnedWeights g_weights;

// مسیر فایل‌ها (در پوشه پروژه)
static string LEARNING_CSV_FILE = "Biotak_Learning_Data.csv";
static string WEIGHTS_FILE = "Biotak_Learned_Weights.txt";

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS                                             |
//+------------------------------------------------------------------+
// Note: External functions are defined in TH3Tool.mqh which is included before this file
// No forward declarations needed - functions are already available

//+------------------------------------------------------------------+
//| STATE LOCK MANAGEMENT (Atomic using GlobalVariable)              |
//| مدیریت قفل State (Atomic با استفاده از GlobalVariable)           |
//| CRITICAL FIX: Thread-safe locking mechanism                      |
//| PERFORMANCE: Uses cached ChartID string                          |
//+------------------------------------------------------------------+
bool AcquireStateLock() {
    string lockName = STATE_LOCK_NAME + "_" + GetCachedChartIdStr();
    
    // Ensure the GlobalVariable exists (initialized to 0 = unlocked)
    if(!GlobalVariableCheck(lockName)) {
        GlobalVariableSet(lockName, 0.0);
        GlobalVariableTemp(lockName); // Make it temporary (auto-cleanup)
    }
    
    // ATOMIC acquire: only succeeds if current value is 0 (unlocked)
    // GlobalVariableSetOnCondition is truly atomic — no TOCTOU race
    if(!GlobalVariableSetOnCondition(lockName, 1.0, 0.0)) {
        // Lock is held by another operation
        return false;
    }
    
    return true;
}

void ReleaseStateLock() {
    string lockName = STATE_LOCK_NAME + "_" + GetCachedChartIdStr();
    
    // Release lock: set back to 0 (unlocked) instead of deleting
    // This keeps the GV alive for the next atomic SetOnCondition call
    if(GlobalVariableCheck(lockName)) {
        GlobalVariableSet(lockName, 0.0);
    }
}

//+------------------------------------------------------------------+
//| SAFE MATH OPERATIONS                                             |
//| Note: These functions are now provided by FloatingPointHelper.mqh|
//| Removed duplicate definitions to avoid conflicts                 |
//+------------------------------------------------------------------+
// SafeDivide() - Use from FloatingPointHelper.mqh
// ClampValue() - Use from FloatingPointHelper.mqh

//+------------------------------------------------------------------+
//| FILE PATH SANITIZATION - Use function from InputValidationEnhanced.mqh |
//+------------------------------------------------------------------+
// NOTE: SanitizeFilename() is now provided by InputValidationEnhanced.mqh
// No need to duplicate it here

//+------------------------------------------------------------------+
//| SAFE FILE OPERATIONS - RAII Pattern Implementation               |
//| CRITICAL FIX: Guaranteed cleanup with RAII-style wrapper         |
//+------------------------------------------------------------------+

// File Handle Wrapper (RAII Pattern for MQL4)
class CFileHandle {
private:
    int m_handle;
    string m_filename;
    bool m_isOpen;
    
public:
    // Constructor
    CFileHandle() : m_handle(INVALID_HANDLE), m_filename(""), m_isOpen(false) {}
    
    // Open file
    bool Open(string filename, int flags, string delimiter = "") {
        if(m_isOpen) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("⚠️ File already open: ", m_filename);
            #endif
            return false;
        }
        
        if(delimiter != "") {
            m_handle = FileOpen(filename, flags, delimiter);
        } else {
            m_handle = FileOpen(filename, flags);
        }
        
        if(m_handle == INVALID_HANDLE) {
            int error = GetLastError();
            #ifdef ENABLE_DEBUG_LOGS
            Print("❌ File open failed: ", filename, " (Error: ", error, ")");
            #endif
            return false;
        }
        
        m_filename = filename;
        m_isOpen = true;
        return true;
    }
    
    // Get handle (for FileRead/Write operations)
    int Handle() const { return m_handle; }
    
    // Check if open
    bool IsOpen() const { return m_isOpen; }
    
    // Explicit close
    void Close() {
        if(m_isOpen && m_handle != INVALID_HANDLE) {
            int tempHandle = m_handle;
            m_handle = INVALID_HANDLE;
            m_isOpen = false;
            
            FileClose(tempHandle);
            int error = GetLastError();
            if(error != 0) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("⚠️ FileClose() error: ", error, " for file: ", m_filename);
                #endif
            }
        }
    }
    
    // Destructor (automatic cleanup)
    ~CFileHandle() {
        Close();
    }
};

// Legacy wrapper functions for backward compatibility
int SafeFileOpen(string filename, int flags, string delimiter = "") {
    int handle = INVALID_HANDLE;
    
    if(delimiter != "") {
        handle = FileOpen(filename, flags, delimiter);
    } else {
        handle = FileOpen(filename, flags);
    }
    
    if(handle == INVALID_HANDLE) {
        int error = GetLastError();
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ File open failed: ", filename, " (Error: ", error, ")");
        #endif
    }
    
    return handle;
}

void SafeFileClose(int &handle) {
    if(handle != INVALID_HANDLE) {
        int tempHandle = handle;
        handle = INVALID_HANDLE; // Reset immediately
        
        FileClose(tempHandle);
        int error = GetLastError();
        if(error != 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("⚠️ FileClose() error detected (Error: ", error, "), handle forcibly reset");
            #endif
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize Learning System                                       |
//| مقداردهی اولیه سیستم یادگیری                                     |
//+------------------------------------------------------------------+
LEARNING_ERROR_CODE InitializeLearningSystem()
{
    // ایجاد پوشه گزارشات اگر وجود نداره
    CreateReportsFolder();
    
    // بارگذاری وزن‌های ذخیره شده
    LoadLearnedWeights();
    
    // بارگذاری داده‌های یادگیری قبلی
    LEARNING_ERROR_CODE result = LoadLearningDataFromCSV();
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("🎓 LEARNING SYSTEM INITIALIZED");
    Print("========================================");
    Print("Total Patterns: ", g_learningDataCount);
    Print("Approved: ", g_weights.approvedPatterns);
    Print("Rejected: ", g_weights.rejectedPatterns);
    #endif
    
    double accuracy = (g_weights.totalPatterns > 0) ? 
                      (100.0 * g_weights.approvedPatterns / g_weights.totalPatterns) : 0.0;
    #ifdef ENABLE_DEBUG_LOGS
    Print("Accuracy: ", DoubleToString(accuracy, 1), "%");
    Print("Last Update: ", TimeToString(g_weights.lastUpdate));
    Print("Reports Folder: ", REPORTS_FOLDER);
    Print("========================================");
    #endif
    
    return result;
}

//+------------------------------------------------------------------+
//| Create Reports Folder                                            |
//| ایجاد پوشه گزارشات                                               |
//+------------------------------------------------------------------+
void CreateReportsFolder()
{
    // MT4 automatically creates folders when FileOpen is called
    string testFile = REPORTS_FOLDER + "\\test.txt";
    int handle = SafeFileOpen(testFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
    
    if(handle != INVALID_HANDLE) {
        SafeFileClose(handle);
        FileDelete(testFile);
        #ifdef ENABLE_DEBUG_LOGS
        Print("✅ Reports folder ready: MQL5/Files/", REPORTS_FOLDER);
        #endif
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Could not create reports folder");
        #endif
    }
}

//+------------------------------------------------------------------+
//| Load Learned Weights from File                                   |
//| بارگذاری وزن‌های یادگیری شده از فایل                             |
//+------------------------------------------------------------------+
void LoadLearnedWeights()
{
    // مقادیر پیش‌فرض
    g_weights.stepPriorityWeight = 0.50;
    g_weights.errorWeight = 0.40;
    g_weights.speedConsistencyWeight = 0.20;
    g_weights.timeSymmetryWeight = 0.15;
    g_weights.fibonacciWeight = 0.15;
    g_weights.freqDeviationWeight = 0.10;
    g_weights.consolidationWeight = 0.05;
    
    g_weights.step5Priority = 0.5;
    g_weights.step3_7Priority = 0.7;
    g_weights.step1Priority = 0.9;
    
    g_weights.totalPatterns = 0;
    g_weights.approvedPatterns = 0;
    g_weights.rejectedPatterns = 0;
    g_weights.lastUpdate = 0;
    
    // تلاش برای بارگذاری از فایل
    int handle = SafeFileOpen(WEIGHTS_FILE, FILE_READ|FILE_TXT|FILE_ANSI);
    if(handle == INVALID_HANDLE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("ℹ️ No saved weights found, using defaults");
        #endif
        return;
    }
    
    while(!FileIsEnding(handle)) {
        string line = FileReadString(handle);
        if(StringLen(line) == 0) continue;
        
        string parts[];
        int count = StringSplit(line, '=', parts);
        if(count != 2) continue;
        
        string key = parts[0];
        double value = StringToDouble(parts[1]);
        
        // Parse and validate weights
        if(key == "stepPriorityWeight") g_weights.stepPriorityWeight = ClampValue(value, 0.0, 1.0);
        else if(key == "errorWeight") g_weights.errorWeight = ClampValue(value, 0.0, 1.0);
        else if(key == "speedConsistencyWeight") g_weights.speedConsistencyWeight = ClampValue(value, 0.0, 1.0);
        else if(key == "timeSymmetryWeight") g_weights.timeSymmetryWeight = ClampValue(value, 0.0, 1.0);
        else if(key == "fibonacciWeight") g_weights.fibonacciWeight = ClampValue(value, 0.0, 1.0);
        else if(key == "freqDeviationWeight") g_weights.freqDeviationWeight = ClampValue(value, 0.0, 1.0);
        else if(key == "consolidationWeight") g_weights.consolidationWeight = ClampValue(value, MIN_CONSOLIDATION_WEIGHT, MAX_CONSOLIDATION_WEIGHT);
        else if(key == "step5Priority") g_weights.step5Priority = ClampValue(value, MIN_STEP_PRIORITY, MAX_STEP_PRIORITY);
        else if(key == "step3_7Priority") g_weights.step3_7Priority = ClampValue(value, MIN_STEP_PRIORITY, MAX_STEP_PRIORITY);
        else if(key == "step1Priority") g_weights.step1Priority = ClampValue(value, MIN_STEP_PRIORITY, MAX_STEP_PRIORITY);
        else if(key == "totalPatterns") g_weights.totalPatterns = (int)MathMax(0, value);
        else if(key == "approvedPatterns") g_weights.approvedPatterns = (int)MathMax(0, value);
        else if(key == "rejectedPatterns") g_weights.rejectedPatterns = (int)MathMax(0, value);
        else if(key == "lastUpdate") g_weights.lastUpdate = (datetime)value;
    }
    
    SafeFileClose(handle);
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ Learned weights loaded from file");
    #endif
}

//+------------------------------------------------------------------+
//| Save Learned Weights to File                                     |
//| ذخیره وزن‌های یادگیری شده در فایل                                |
//| CRITICAL FIX: RAII pattern + comprehensive error handling        |
//+------------------------------------------------------------------+
LEARNING_ERROR_CODE SaveLearnedWeights()
{
    // RAII Pattern: Automatic cleanup on scope exit
    CFileHandle file;
    
    if(!file.Open(WEIGHTS_FILE, FILE_WRITE|FILE_TXT|FILE_ANSI)) {
        return LEARNING_ERROR_FILE_OPEN_FAILED;
    }
    
    // Helper macro for write operations
    #define WRITE_WEIGHT(name, value) \
        if(!FileWriteString(file.Handle(), name "=" + DoubleToString(value, 4) + "\n")) { \
            return LEARNING_ERROR_FILE_WRITE_FAILED; \
        }
    
    #define WRITE_INT(name, value) \
        if(!FileWriteString(file.Handle(), name "=" + IntegerToString(value) + "\n")) { \
            return LEARNING_ERROR_FILE_WRITE_FAILED; \
        }
    
    // Write all weights with error checking
    WRITE_WEIGHT("stepPriorityWeight", g_weights.stepPriorityWeight);
    WRITE_WEIGHT("errorWeight", g_weights.errorWeight);
    WRITE_WEIGHT("speedConsistencyWeight", g_weights.speedConsistencyWeight);
    WRITE_WEIGHT("timeSymmetryWeight", g_weights.timeSymmetryWeight);
    WRITE_WEIGHT("fibonacciWeight", g_weights.fibonacciWeight);
    WRITE_WEIGHT("freqDeviationWeight", g_weights.freqDeviationWeight);
    WRITE_WEIGHT("consolidationWeight", g_weights.consolidationWeight);
    WRITE_WEIGHT("step5Priority", g_weights.step5Priority);
    WRITE_WEIGHT("step3_7Priority", g_weights.step3_7Priority);
    WRITE_WEIGHT("step1Priority", g_weights.step1Priority);
    WRITE_INT("totalPatterns", g_weights.totalPatterns);
    WRITE_INT("approvedPatterns", g_weights.approvedPatterns);
    WRITE_INT("rejectedPatterns", g_weights.rejectedPatterns);
    WRITE_INT("lastUpdate", (int)TimeCurrent());
    
    #undef WRITE_WEIGHT
    #undef WRITE_INT
    
    // File automatically closed by destructor
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ Learned weights saved to file");
    #endif
    return LEARNING_SUCCESS;
}

//+------------------------------------------------------------------+
//| Load Learning Data from CSV                                      |
//| بارگذاری داده‌های یادگیری از CSV                                 |
//+------------------------------------------------------------------+
LEARNING_ERROR_CODE LoadLearningDataFromCSV()
{
    int handle = SafeFileOpen(LEARNING_CSV_FILE, FILE_READ|FILE_CSV|FILE_ANSI, ",");
    if(handle == INVALID_HANDLE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("ℹ️ No previous learning data found");
        #endif
        return LEARNING_SUCCESS; // Not an error - first run
    }
    
    // خواندن header
    string header = FileReadString(handle);
    
    // خواندن داده‌ها
    ArrayResize(g_learningData, 0);
    g_learningDataCount = 0;
    
    while(!FileIsEnding(handle) && g_learningDataCount < MAX_LEARNING_DATA_SIZE) {
        PatternLearningData data;
        
        // خواندن یک ردیف با error handling
        string timestamp = FileReadString(handle);
        if(StringLen(timestamp) == 0) break;
        
        data.timestamp = StringToTime(timestamp);
        data.symbol = FileReadString(handle);
        data.timeframe = (int)StringToInteger(FileReadString(handle));
        
        data.XA_Pips = StringToDouble(FileReadString(handle));
        data.AB_Pips = StringToDouble(FileReadString(handle));
        data.BC_Pips = StringToDouble(FileReadString(handle));
        
        data.XA_Minutes = (int)StringToInteger(FileReadString(handle));
        data.AB_Minutes = (int)StringToInteger(FileReadString(handle));
        data.BC_Minutes = (int)StringToInteger(FileReadString(handle));
        
        data.AB_Speed = StringToDouble(FileReadString(handle));
        data.AB_Angle = StringToDouble(FileReadString(handle));
        data.speedConsistency = StringToDouble(FileReadString(handle));
        
        data.AB_XA_Ratio = StringToDouble(FileReadString(handle));
        data.BC_AB_Ratio = StringToDouble(FileReadString(handle));
        data.timeSymmetry = StringToDouble(FileReadString(handle));
        
        data.consolidationFactor = StringToDouble(FileReadString(handle));
        data.requiredRestCandles = (int)StringToInteger(FileReadString(handle));
        data.dailyATR = StringToDouble(FileReadString(handle));
        
        data.suggestedFrequency = StringToDouble(FileReadString(handle));
        data.targetStep = (int)StringToInteger(FileReadString(handle));
        data.errorPercent = StringToDouble(FileReadString(handle));
        data.totalScore = StringToDouble(FileReadString(handle));
        
        string approved = FileReadString(handle);
        data.feedbackReceived = (approved != "PENDING");
        data.userApproved = (approved == "YES");
        
        data.userSelectedFrequency = StringToDouble(FileReadString(handle));
        data.userSelectedFreqIndex = (int)StringToInteger(FileReadString(handle));
        data.userSelectedStep = (int)StringToInteger(FileReadString(handle));
        data.actualErrorPercent = StringToDouble(FileReadString(handle));
        data.screenshotFilename = FileReadString(handle);
        
        // افزودن به آرایه - PERF FIX: Reserve extra slots
        ArrayResize(g_learningData, g_learningDataCount + 1, 256);
        g_learningData[g_learningDataCount] = data;
        g_learningDataCount++;
    }
    
    SafeFileClose(handle);
    
    if(g_learningDataCount >= MAX_LEARNING_DATA_SIZE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Learning data limit reached (", MAX_LEARNING_DATA_SIZE, ")");
        Print("   Consider archiving old data");
        #endif
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ Loaded ", g_learningDataCount, " patterns from CSV");
    #endif
    return LEARNING_SUCCESS;
}

//+------------------------------------------------------------------+
//| Save Pattern for Learning                                        |
//| ذخیره الگو برای یادگیری                                          |
//+------------------------------------------------------------------+
LEARNING_ERROR_CODE SavePatternForLearning(
    string patternName, 
    datetime tX, double pX,
    datetime tA, double pA,
    datetime tB, double pB,
    datetime tC, double pC,
    double suggestedFreq,
    int suggestedFreqIdx,
    int targetStep,
    double errorPercent,
    double totalScore,
    WaveAnalysis &waves,
    double consolidationFactor)
{
    // ========================================
    // STATE LOCK - Prevent race conditions
    // ========================================
    if(!AcquireStateLock()) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ State locked - another operation in progress");
        #endif
        return LEARNING_ERROR_STATE_CONFLICT;
    }
    
    // ========================================
    // SECURITY: Memory limit check with bounds validation
    // ========================================
    if(g_learningDataCount < 0) {
        ReleaseStateLock();
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ Cannot save pattern - corrupted count: ", g_learningDataCount);
        #endif
        return LEARNING_ERROR_MEMORY_LIMIT;
    }
    
    // CIRCULAR BUFFER: When limit reached, remove oldest entry
    // این باعث می‌شود که همیشه جدیدترین پترن‌ها نگه داشته شوند
    if(g_learningDataCount >= MAX_LEARNING_DATA_SIZE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Learning data limit reached (", MAX_LEARNING_DATA_SIZE, ") - removing oldest pattern");
        #endif
        
        // Shift all entries one position left (remove first, oldest entry)
        for(int i = 0; i < g_learningDataCount - 1; i++) {
            g_learningData[i] = g_learningData[i + 1];
        }
        g_learningDataCount--;
        
        // CRITICAL FIX: Resize array to prevent memory leak
        ArrayResize(g_learningData, g_learningDataCount);
        
        // Update CSV file to reflect removal
        UpdateLearningCSV();
    }
    
    // ========================================
    // اگر پترن قبلی در انتظار بود، اون رو نادیده بگیر
    // ========================================
    if(g_waitingForFeedback && g_pendingPatternIndex >= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("========================================");
        Print("⚠️ NEW PATTERN CREATED");
        Print("========================================");
        Print("Previous pattern (Index: ", g_pendingPatternIndex, ") was not finalized");
        Print("Previous pattern will remain as PENDING in CSV");
        Print("Starting new pattern...");
        Print("========================================");
        #endif
        
        ResetSmartFeedbackState();
    }
    
    // ========================================
    // ایجاد ساختار داده با validation
    // ========================================
    PatternLearningData data;
    
    // شناسه‌ها - Sanitize inputs
    data.patternName = SanitizeFilename(patternName);
    data.timestamp = TimeCurrent();
    data.symbol = GetCachedSymbol();
    data.timeframe = _Period;
    
    // ویژگی‌های موج - Validate positive values
    int cachedDig = GetCachedDigits();
    double cachedPt = GetCachedPoint();
    double pipSize = (cachedDig == 3 || cachedDig == 5) ? cachedPt * 10 : cachedPt;
    if(pipSize <= 0) pipSize = 0.0001; // Fallback
    
    data.XA_Pips = MathAbs(waves.XA_Distance) / pipSize;
    data.AB_Pips = MathAbs(waves.AB_Distance) / pipSize;
    data.BC_Pips = MathAbs(waves.BC_Distance) / pipSize;
    data.XA_Minutes = MathMax(0, waves.XA_Minutes);
    data.AB_Minutes = MathMax(0, waves.AB_Minutes);
    data.BC_Minutes = MathMax(0, waves.BC_Minutes);
    
    // ویژگی‌های محاسبه شده - Clamp to valid ranges
    data.AB_Speed = MathMax(0, waves.AB_Speed);
    data.AB_Angle = ClampValue(waves.AB_Angle, 0, 90);
    data.speedConsistency = ClampValue(waves.speedConsistency, 0, 1);
    data.AB_XA_Ratio = MathMax(0, waves.AB_XA_Ratio);
    data.BC_AB_Ratio = MathMax(0, waves.BC_AB_Ratio);
    data.timeSymmetry = ClampValue(waves.timeSymmetry, 0, 1);
    // CRITICAL FIX: Validate division operand
    if(MathAbs(pipSize) > 0.000001) {
        data.dailyATR = MathMax(0, GetCachedDailyATR() / pipSize);
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ SavePatternData: pipSize too small (", pipSize, ")");
        #endif
        data.dailyATR = 0;
    }
    
    // انتخاب فرکانس - Validate ranges
    data.suggestedFrequency = ClampValue(suggestedFreq, 0, 120);
    data.suggestedFreqIndex = MathMax(0, suggestedFreqIdx);
    data.targetStep = MathMax(1, targetStep);
    data.errorPercent = MathMax(0, errorPercent);
    data.totalScore = totalScore;
    
    // بازخورد (هنوز دریافت نشده)
    data.feedbackReceived = false;
    data.userApproved = false;
    data.userSelectedFrequency = 0;
    data.userSelectedFreqIndex = 0;
    data.userSelectedStep = 0;
    data.actualErrorPercent = 0;
    
    // ========================================
    // آماده‌سازی نام فایل‌ها - Safe filename generation
    // ========================================
    string timestamp = TimeToString(data.timestamp, TIME_DATE) + "_" + 
                       IntegerToString(TimeHour(data.timestamp)) + 
                       IntegerToString(TimeMinute(data.timestamp)) + 
                       IntegerToString(TimeSeconds(data.timestamp));
    StringReplace(timestamp, ".", "_");
    StringReplace(timestamp, ":", "_");
    StringReplace(timestamp, " ", "_");
    
    // SECURITY FIX: Sanitize symbol to prevent path traversal
    string safeSymbol = SanitizeFilename(GetCachedSymbol());
    
    string patternFolder = REPORTS_FOLDER + "\\Pattern_" + 
                           IntegerToString(g_learningDataCount + 1) + "_" + 
                           safeSymbol + "_" + timestamp;
    
    data.screenshotFilename = patternFolder + "\\screenshot.gif";
    
    // ========================================
    // افزودن به آرایه - PERF FIX: Reserve extra
    // ========================================
    ArrayResize(g_learningData, g_learningDataCount + 1, 256);
    g_learningData[g_learningDataCount] = data;
    g_currentPatternIndex = g_learningDataCount;
    g_learningDataCount++;
    
    g_currentPatternForFeedback = patternName;
    
    // ========================================
    // ذخیره فوری در CSV
    // ========================================
    LEARNING_ERROR_CODE csvResult = AppendToLearningCSV(data);
    if(csvResult != LEARNING_SUCCESS) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Failed to save to CSV, but pattern stored in memory");
        #endif
    }
    
    // ========================================
    // تولید گزارش جداگانه
    // ========================================
    GeneratePatternReport(data, g_currentPatternIndex, patternFolder);
    
    // ========================================
    // سیستم یادگیری هوشمند
    // ========================================
    g_lastSuggestedFrequency = suggestedFreq;
    g_lastSuggestedFreqIndex = suggestedFreqIdx;
    g_patternCreationTime = TimeCurrent();
    g_waitingForFeedback = true;
    g_pendingPatternIndex = g_currentPatternIndex;
    
    // Release lock
    ReleaseStateLock();
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("📊 PATTERN SAVED FOR LEARNING");
    Print("========================================");
    Print("Pattern: ", patternName);
    Print("Pattern Index: ", g_currentPatternIndex);
    Print("Suggested: ", DoubleToString(suggestedFreq, 3), "% → Step ", targetStep);
    Print("Error: ", DoubleToString(errorPercent, 3), "%");
    Print("Score: ", DoubleToString(totalScore, 2));
    Print("========================================");
    Print("⌨️  Press [5] to approve & save report");
    Print("========================================");
    #endif
    
    return LEARNING_SUCCESS;
}

//+------------------------------------------------------------------+
//| Append to Learning CSV File                                      |
//| افزودن به فایل CSV یادگیری                                       |
//+------------------------------------------------------------------+
LEARNING_ERROR_CODE AppendToLearningCSV(PatternLearningData &data)
{
    int handle = SafeFileOpen(LEARNING_CSV_FILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
    
    if(handle == INVALID_HANDLE) {
        return LEARNING_ERROR_FILE_OPEN_FAILED;
    }
    
    // بررسی اینکه فایل خالی است (نوشتن header)
    if(FileSize(handle) == 0) {
        FileWrite(handle, 
            "Timestamp", "Symbol", "Timeframe",
            "XA_Pips", "AB_Pips", "BC_Pips",
            "XA_Min", "AB_Min", "BC_Min",
            "AB_Speed", "AB_Angle", "SpeedConsistency",
            "AB_XA_Ratio", "BC_AB_Ratio", "TimeSymmetry",
            "Consolidation", "RequiredRest", "DailyATR",
            "SuggestedFreq", "TargetStep", "ErrorPercent", "TotalScore",
            "UserApproved", "UserFreq", "UserFreqIdx", "UserStep", "ActualError",
            "Screenshot");
    }
    
    // رفتن به انتهای فایل
    FileSeek(handle, 0, SEEK_END);
    
    // نوشتن ردیف داده
    FileWrite(handle,
        TimeToString(data.timestamp, TIME_DATE|TIME_SECONDS),
        data.symbol,
        IntegerToString(data.timeframe),
        DoubleToString(data.XA_Pips, 1),
        DoubleToString(data.AB_Pips, 1),
        DoubleToString(data.BC_Pips, 1),
        IntegerToString(data.XA_Minutes),
        IntegerToString(data.AB_Minutes),
        IntegerToString(data.BC_Minutes),
        DoubleToString(data.AB_Speed, 3),
        DoubleToString(data.AB_Angle, 2),
        DoubleToString(data.speedConsistency, 3),
        DoubleToString(data.AB_XA_Ratio, 3),
        DoubleToString(data.BC_AB_Ratio, 3),
        DoubleToString(data.timeSymmetry, 3),
        DoubleToString(data.consolidationFactor, 3),
        IntegerToString(data.requiredRestCandles),
        DoubleToString(data.dailyATR, 1),
        DoubleToString(data.suggestedFrequency, 3),
        IntegerToString(data.targetStep),
        DoubleToString(data.errorPercent, 3),
        DoubleToString(data.totalScore, 2),
        data.userApproved ? "YES" : (data.feedbackReceived ? "NO" : "PENDING"),
        DoubleToString(data.userSelectedFrequency, 3),
        IntegerToString(data.userSelectedFreqIndex),
        IntegerToString(data.userSelectedStep),
        DoubleToString(data.actualErrorPercent, 3),
        data.screenshotFilename);
    
    SafeFileClose(handle);
    return LEARNING_SUCCESS;
}

//+------------------------------------------------------------------+
//| Rewrite entire CSV file (used after circular buffer removal)     |
//| بازنویسی کامل فایل CSV (استفاده می‌شود بعد از حذف از بافر دایره‌ای) |
//+------------------------------------------------------------------+
LEARNING_ERROR_CODE UpdateLearningCSV()
{
    // بازنویسی کل فایل با داده‌های فعلی
    int handle = SafeFileOpen(LEARNING_CSV_FILE, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
    
    if(handle == INVALID_HANDLE) {
        return LEARNING_ERROR_FILE_OPEN_FAILED;
    }
    
    // نوشتن header
    FileWrite(handle, 
        "Timestamp", "Symbol", "Timeframe",
        "XA_Pips", "AB_Pips", "BC_Pips",
        "XA_Min", "AB_Min", "BC_Min",
        "AB_Speed", "AB_Angle", "SpeedConsistency",
        "AB_XA_Ratio", "BC_AB_Ratio", "TimeSymmetry",
        "Consolidation", "RequiredRest", "DailyATR",
        "SuggestedFreq", "TargetStep", "ErrorPercent", "TotalScore",
        "UserApproved", "UserFreq", "UserFreqIdx", "UserStep", "ActualError",
        "Screenshot");
    
    // نوشتن تمام ردیف‌ها
    for(int i = 0; i < g_learningDataCount; i++) {
        PatternLearningData d = g_learningData[i];
        
        FileWrite(handle,
            TimeToString(d.timestamp, TIME_DATE|TIME_SECONDS),
            d.symbol, IntegerToString(d.timeframe),
            DoubleToString(d.XA_Pips, 1), DoubleToString(d.AB_Pips, 1), DoubleToString(d.BC_Pips, 1),
            IntegerToString(d.XA_Minutes), IntegerToString(d.AB_Minutes), IntegerToString(d.BC_Minutes),
            DoubleToString(d.AB_Speed, 3), DoubleToString(d.AB_Angle, 2), DoubleToString(d.speedConsistency, 3),
            DoubleToString(d.AB_XA_Ratio, 3), DoubleToString(d.BC_AB_Ratio, 3), DoubleToString(d.timeSymmetry, 3),
            DoubleToString(d.consolidationFactor, 3), IntegerToString(d.requiredRestCandles), DoubleToString(d.dailyATR, 1),
            DoubleToString(d.suggestedFrequency, 3), IntegerToString(d.targetStep), 
            DoubleToString(d.errorPercent, 3), DoubleToString(d.totalScore, 2),
            d.userApproved ? "YES" : (d.feedbackReceived ? "NO" : "PENDING"),
            DoubleToString(d.userSelectedFrequency, 3), IntegerToString(d.userSelectedFreqIndex),
            IntegerToString(d.userSelectedStep), DoubleToString(d.actualErrorPercent, 3),
            d.screenshotFilename);
    }
    
    SafeFileClose(handle);
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ CSV rewritten after circular buffer cleanup");
    #endif
    
    return LEARNING_SUCCESS;
}

//+------------------------------------------------------------------+
//| Update Single Row in Learning CSV (Optimized)                    |
//| آپدیت یک ردیف در CSV یادگیری (بهینه شده)                         |
//+------------------------------------------------------------------+
LEARNING_ERROR_CODE UpdateLearningCSVRow(int index)
{
    if(index < 0 || index >= g_learningDataCount) {
        return LEARNING_ERROR_INVALID_INDEX;
    }
    
    // بازنویسی کل فایل (ساده‌ترین روش برای MT4)
    int handle = SafeFileOpen(LEARNING_CSV_FILE, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
    
    if(handle == INVALID_HANDLE) {
        return LEARNING_ERROR_FILE_OPEN_FAILED;
    }
    
    // نوشتن header
    FileWrite(handle, 
        "Timestamp", "Symbol", "Timeframe",
        "XA_Pips", "AB_Pips", "BC_Pips",
        "XA_Min", "AB_Min", "BC_Min",
        "AB_Speed", "AB_Angle", "SpeedConsistency",
        "AB_XA_Ratio", "BC_AB_Ratio", "TimeSymmetry",
        "Consolidation", "RequiredRest", "DailyATR",
        "SuggestedFreq", "TargetStep", "ErrorPercent", "TotalScore",
        "UserApproved", "UserFreq", "UserFreqIdx", "UserStep", "ActualError",
        "Screenshot");
    
    // نوشتن تمام ردیف‌ها
    for(int i = 0; i < g_learningDataCount; i++) {
        PatternLearningData d = g_learningData[i];
        
        FileWrite(handle,
            TimeToString(d.timestamp, TIME_DATE|TIME_SECONDS),
            d.symbol, IntegerToString(d.timeframe),
            DoubleToString(d.XA_Pips, 1), DoubleToString(d.AB_Pips, 1), DoubleToString(d.BC_Pips, 1),
            IntegerToString(d.XA_Minutes), IntegerToString(d.AB_Minutes), IntegerToString(d.BC_Minutes),
            DoubleToString(d.AB_Speed, 3), DoubleToString(d.AB_Angle, 2), DoubleToString(d.speedConsistency, 3),
            DoubleToString(d.AB_XA_Ratio, 3), DoubleToString(d.BC_AB_Ratio, 3), DoubleToString(d.timeSymmetry, 3),
            DoubleToString(d.consolidationFactor, 3), IntegerToString(d.requiredRestCandles), DoubleToString(d.dailyATR, 1),
            DoubleToString(d.suggestedFrequency, 3), IntegerToString(d.targetStep), 
            DoubleToString(d.errorPercent, 3), DoubleToString(d.totalScore, 2),
            d.userApproved ? "YES" : (d.feedbackReceived ? "NO" : "PENDING"),
            DoubleToString(d.userSelectedFrequency, 3), IntegerToString(d.userSelectedFreqIndex),
            IntegerToString(d.userSelectedStep), DoubleToString(d.actualErrorPercent, 3),
            d.screenshotFilename);
    }
    
    SafeFileClose(handle);
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ CSV updated");
    #endif
    
    return LEARNING_SUCCESS;
}

//+------------------------------------------------------------------+
//| Analyze and Update Weights (Machine Learning Core)              |
//| تحلیل و آپدیت وزن‌ها (هسته یادگیری ماشین)                        |
//+------------------------------------------------------------------+
void AnalyzeAndUpdateWeights()
{
    // شمارش الگوهای تایید شده و رد شده
    int approvedCount = 0;
    int rejectedCount = 0;
    int pendingCount = 0;
    
    for(int i = 0; i < g_learningDataCount; i++) {
        if(!g_learningData[i].feedbackReceived) {
            pendingCount++;
            continue;
        }
        
        if(g_learningData[i].userApproved) {
            approvedCount++;
        } else {
            rejectedCount++;
        }
    }
    
    g_weights.totalPatterns = g_learningDataCount;
    g_weights.approvedPatterns = approvedCount;
    g_weights.rejectedPatterns = rejectedCount;
    g_weights.lastUpdate = TimeCurrent();
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("📊 LEARNING STATISTICS");
    Print("========================================");
    Print("Total: ", g_learningDataCount);
    #endif
    
    int totalFeedback = approvedCount + rejectedCount;
    if(totalFeedback > 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("Approved: ", approvedCount, " (", DoubleToString(100.0 * approvedCount / totalFeedback, 1), "%)");
        Print("Rejected: ", rejectedCount, " (", DoubleToString(100.0 * rejectedCount / totalFeedback, 1), "%)");
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("Pending: ", pendingCount);
    Print("========================================");
    #endif
    
    // اگر داده کافی نداریم، وزن‌ها رو تغییر نمیدیم
    if(totalFeedback < MIN_PATTERNS_FOR_LEARNING) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("ℹ️ Not enough data for weight adjustment (need ", MIN_PATTERNS_FOR_LEARNING, "+)");
        #endif
        SaveLearnedWeights();
        return;
    }
    
    // ========================================
    // تحلیل الگوهای تایید شده
    // ========================================
    double avgApprovedScore = 0;
    double avgRejectedScore = 0;
    
    for(int i = 0; i < g_learningDataCount; i++) {
        if(!g_learningData[i].feedbackReceived) continue;
        
        if(g_learningData[i].userApproved) {
            avgApprovedScore += g_learningData[i].totalScore;
        } else {
            avgRejectedScore += g_learningData[i].totalScore;
        }
    }
    
    avgApprovedScore = SafeDivide(avgApprovedScore, approvedCount, 0.0, EPSILON_GENERAL);
    avgRejectedScore = SafeDivide(avgRejectedScore, rejectedCount, 0.0, EPSILON_GENERAL);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("Avg Approved Score: ", DoubleToString(avgApprovedScore, 2));
    Print("Avg Rejected Score: ", DoubleToString(avgRejectedScore, 2));
    #endif
    
    // ========================================
    // تحلیل ویژگی‌های مهم
    // ========================================
    
    // 1. تحلیل Step Priority (سیستم پیشنهاد داده)
    int step1_approved = 0, step3_approved = 0, step4_approved = 0, step5_approved = 0, step7_approved = 0;
    int step1_rejected = 0, step3_rejected = 0, step4_rejected = 0, step5_rejected = 0, step7_rejected = 0;
    
    for(int i = 0; i < g_learningDataCount; i++) {
        if(!g_learningData[i].feedbackReceived) continue;
        
        int step = g_learningData[i].targetStep;
        bool approved = g_learningData[i].userApproved;
        
        if(step == 1) {
            if(approved) step1_approved++; else step1_rejected++;
        } else if(step == 3) {
            if(approved) step3_approved++; else step3_rejected++;
        } else if(step == 4) {
            if(approved) step4_approved++; else step4_rejected++;
        } else if(step == 5) {
            if(approved) step5_approved++; else step5_rejected++;
        } else if(step == 7) {
            if(approved) step7_approved++; else step7_rejected++;
        }
    }
    
    // محاسبه نرخ موفقیت هر Step
    double step1_rate = SafeDivide(step1_approved, step1_approved + step1_rejected, 0.5, EPSILON_GENERAL);
    double step3_rate = SafeDivide(step3_approved, step3_approved + step3_rejected, 0.5, EPSILON_GENERAL);
    double step4_rate = SafeDivide(step4_approved, step4_approved + step4_rejected, 0.5, EPSILON_GENERAL);
    double step5_rate = SafeDivide(step5_approved, step5_approved + step5_rejected, 0.5, EPSILON_GENERAL);
    double step7_rate = SafeDivide(step7_approved, step7_approved + step7_rejected, 0.5, EPSILON_GENERAL);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("Step Success Rates (System Suggested):");
    Print("  Step 1: ", DoubleToString(step1_rate * 100, 1), "% (", step1_approved, "/", step1_approved + step1_rejected, ")");
    Print("  Step 3: ", DoubleToString(step3_rate * 100, 1), "% (", step3_approved, "/", step3_approved + step3_rejected, ")");
    Print("  Step 4: ", DoubleToString(step4_rate * 100, 1), "% (", step4_approved, "/", step4_approved + step4_rejected, ")");
    Print("  Step 5: ", DoubleToString(step5_rate * 100, 1), "% (", step5_approved, "/", step5_approved + step5_rejected, ")");
    Print("  Step 7: ", DoubleToString(step7_rate * 100, 1), "% (", step7_approved, "/", step7_approved + step7_rejected, ")");
    #endif
    
    // ========================================
    // 2. تحلیل Step انتخابی کاربر (User Selected)
    // ========================================
    int userStep1_count = 0, userStep3_count = 0, userStep4_count = 0, userStep5_count = 0, userStep7_count = 0;
    
    for(int i = 0; i < g_learningDataCount; i++) {
        if(!g_learningData[i].feedbackReceived) continue;
        
        int userStep = g_learningData[i].userSelectedStep;
        
        if(userStep == 1) userStep1_count++;
        else if(userStep == 3) userStep3_count++;
        else if(userStep == 4) userStep4_count++;
        else if(userStep == 5) userStep5_count++;
        else if(userStep == 7) userStep7_count++;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    Print("User Step Preferences (What user actually selected):");
    Print("  Step 1: ", userStep1_count, " times (", DoubleToString(SafeDivide(100.0 * userStep1_count, totalFeedback, 0.0, EPSILON_GENERAL), 1), "%)");
    Print("  Step 3: ", userStep3_count, " times (", DoubleToString(SafeDivide(100.0 * userStep3_count, totalFeedback, 0.0, EPSILON_GENERAL), 1), "%)");
    Print("  Step 4: ", userStep4_count, " times (", DoubleToString(SafeDivide(100.0 * userStep4_count, totalFeedback, 0.0, EPSILON_GENERAL), 1), "%)");
    Print("  Step 5: ", userStep5_count, " times (", DoubleToString(SafeDivide(100.0 * userStep5_count, totalFeedback, 0.0, EPSILON_GENERAL), 1), "%)");
    Print("  Step 7: ", userStep7_count, " times (", DoubleToString(SafeDivide(100.0 * userStep7_count, totalFeedback, 0.0, EPSILON_GENERAL), 1), "%)");
    #endif
    
    // پیدا کردن محبوب‌ترین Step
    int maxCount = MathMax(userStep1_count, MathMax(userStep3_count, MathMax(userStep4_count, MathMax(userStep5_count, userStep7_count))));
    
    if(maxCount > 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("");
        Print("🎯 USER PREFERENCE DETECTED:");
        #endif
        if(userStep4_count == maxCount) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   → User prefers Step 4 (", userStep4_count, " times)");
            Print("   → Adjusting priorities to favor Step 4");
            #endif
            
            // تنظیم اولویت‌ها: Step 4 رو ترجیح بده
            g_weights.step5Priority = 0.6;  // Step 5 کمی کم‌اولویت‌تر
            g_weights.step3_7Priority = 0.55; // Step 3/7 کمی کم‌اولویت‌تر
            
        } else if(userStep5_count == maxCount) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   → User prefers Step 5 (", userStep5_count, " times)");
            #endif
            g_weights.step5Priority = 0.4;  // Step 5 خیلی اولویت‌دار
        } else if(userStep3_count == maxCount || userStep7_count == maxCount) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   → User prefers Step 3/7 (", MathMax(userStep3_count, userStep7_count), " times)");
            #endif
            g_weights.step3_7Priority = 0.5;  // Step 3/7 اولویت‌دار
        }
    }
    
    // تنظیم اولویت‌ها بر اساس نرخ موفقیت (فقط اگر داده کافی داریم)
    if(step5_approved + step5_rejected >= 2) {
        double adjustedPriority = 0.5 * (2.0 - step5_rate);
        g_weights.step5Priority = (g_weights.step5Priority + adjustedPriority) / 2.0; // میانگین
    }
    
    if(step3_approved + step3_rejected >= 2 || step7_approved + step7_rejected >= 2) {
        double avgRate = SafeDivide(step3_rate + step7_rate, 2.0, 0.5, EPSILON_GENERAL);
        double adjustedPriority = 0.7 * (2.0 - avgRate);
        g_weights.step3_7Priority = (g_weights.step3_7Priority + adjustedPriority) / 2.0; // میانگین
    }
    
    g_weights.step1Priority = 0.9; // ثابت
    
    // محدود کردن به بازه معقول
    g_weights.step5Priority = ClampValue(g_weights.step5Priority, MIN_STEP_PRIORITY, MAX_STEP_PRIORITY);
    g_weights.step3_7Priority = ClampValue(g_weights.step3_7Priority, MIN_STEP_PRIORITY, MAX_STEP_PRIORITY);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    Print("Adjusted Step Priorities:");
    Print("  Step 5: ", DoubleToString(g_weights.step5Priority, 3));
    Print("  Step 3/7: ", DoubleToString(g_weights.step3_7Priority, 3));
    Print("  Step 1: ", DoubleToString(g_weights.step1Priority, 3));
    #endif
    
    // ========================================
    // 3. تحلیل Consolidation Factor
    // ========================================
    double avgConsolidation_approved = 0;
    double avgConsolidation_rejected = 0;
    
    for(int i = 0; i < g_learningDataCount; i++) {
        if(!g_learningData[i].feedbackReceived) continue;
        
        if(g_learningData[i].userApproved) {
            avgConsolidation_approved += g_learningData[i].consolidationFactor;
        } else {
            avgConsolidation_rejected += g_learningData[i].consolidationFactor;
        }
    }
    
    avgConsolidation_approved = SafeDivide(avgConsolidation_approved, approvedCount, 0.0, EPSILON_GENERAL);
    avgConsolidation_rejected = SafeDivide(avgConsolidation_rejected, rejectedCount, 0.0, EPSILON_GENERAL);
    
    // اگر consolidation در approved ها بالاتر باشه، وزنش رو افزایش میدیم
    double consolidationDiff = avgConsolidation_approved - avgConsolidation_rejected;
    g_weights.consolidationWeight += consolidationDiff * WEIGHT_ADJUSTMENT_FACTOR;
    
    g_weights.consolidationWeight = ClampValue(g_weights.consolidationWeight, MIN_CONSOLIDATION_WEIGHT, MAX_CONSOLIDATION_WEIGHT);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("Consolidation Analysis:");
    Print("  Approved avg: ", DoubleToString(avgConsolidation_approved, 3));
    Print("  Rejected avg: ", DoubleToString(avgConsolidation_rejected, 3));
    Print("  New weight: ", DoubleToString(g_weights.consolidationWeight, 4));
    #endif
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    #endif
    
    // ذخیره وزن‌های جدید
    SaveLearnedWeights();
}

//+------------------------------------------------------------------+
//| Get Learned Weights for Scoring                                  |
//| دریافت وزن‌های یادگیری شده برای امتیازدهی                        |
//+------------------------------------------------------------------+
LearnedWeights GetLearnedWeights()
{
    return g_weights;
}

//+------------------------------------------------------------------+
//| Get Step Priority from Learned Weights                           |
//| دریافت اولویت گام از وزن‌های یادگیری شده                         |
//+------------------------------------------------------------------+
double GetLearnedStepPriority(int step)
{
    if(step == 5) {
        return g_weights.step5Priority;
    } else if(step == 3 || step == 7) {
        return g_weights.step3_7Priority;
    } else if(step == 1) {
        return g_weights.step1Priority;
    } else {
        return 1.0; // پیش‌فرض
    }
}

//+------------------------------------------------------------------+
//| Quick Approve with Key 5                                         |
//| تایید سریع با کلید 5                                             |
//+------------------------------------------------------------------+
void QuickApprovePattern()
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("🔑 KEY 5 PRESSED - Quick Approve");
    Print("========================================");
    Print("g_waitingForFeedback: ", g_waitingForFeedback);
    Print("g_pendingPatternIndex: ", g_pendingPatternIndex);
    Print("g_learningDataCount: ", g_learningDataCount);
    #endif
    
    if(!g_waitingForFeedback || g_pendingPatternIndex < 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ No pattern waiting for feedback");
        Print("   Reason: ", !g_waitingForFeedback ? "Not waiting" : "Invalid index");
        #endif
        return;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ Calling AutoApprovePendingPattern...");
    #endif
    AutoApprovePendingPattern();
    #ifdef ENABLE_DEBUG_LOGS
    Print("⚡ Quick approved with key [5]");
    #endif
}

//+------------------------------------------------------------------+
//| Check Smart Feedback (Deprecated - No longer used)              |
//| بررسی بازخورد هوشمند (منسوخ شده - دیگر استفاده نمی‌شود)         |
//+------------------------------------------------------------------+
void CheckSmartFeedback()
{
    // این تابع دیگر استفاده نمیشه - فقط کلید 5 کار می‌کنه
    // This function is no longer used - only key 5 works
    // Kept for backward compatibility
    return;
}

//+------------------------------------------------------------------+
//| Confirm Adjusted Frequency (Deprecated - No longer used)        |
//| تایید فرکانس تنظیم شده (منسوخ شده - دیگر استفاده نمی‌شود)       |
//+------------------------------------------------------------------+
void ConfirmAdjustedFrequency()
{
    // این تابع دیگر استفاده نمیشه - سیستم دکمه‌ها حذف شده
    // This function is no longer used - button system removed
    // Kept for backward compatibility
    return;
}

//+------------------------------------------------------------------+
//| Handle Feedback Button Click (Deprecated - No longer used)      |
//| مدیریت کلیک دکمه بازخورد (منسوخ شده - دیگر استفاده نمی‌شود)     |
//+------------------------------------------------------------------+
void OnFeedbackButtonClick(string buttonName)
{
    // این تابع دیگر استفاده نمیشه - سیستم دکمه‌ها حذف شده
    // This function is no longer used - button system removed
    // Kept for backward compatibility
    #ifdef ENABLE_DEBUG_LOGS
    Print("⚠️ Button system is deprecated. Use key [5] to approve patterns.");
    #endif
    return;
}

//+------------------------------------------------------------------+
//| Auto-Approve Pending Pattern                                     |
//| تایید خودکار پترن در انتظار                                      |
//+------------------------------------------------------------------+
void AutoApprovePendingPattern()
{
    if(g_pendingPatternIndex < 0 || g_pendingPatternIndex >= g_learningDataCount) return;
    
    int idx = g_pendingPatternIndex;
    
    // ========================================
    // بررسی اینکه آیا فرکانس تغییر کرده
    // Check if frequency has changed
    // ========================================
    double currentFreq = GetCurrentTH3Frequency();
    bool frequencyChanged = (MathAbs(currentFreq - g_lastSuggestedFrequency) > FREQUENCY_CHANGE_THRESHOLD);
    
    if(frequencyChanged) {
        // فرکانس تغییر کرده - به عنوان REJECTED ذخیره کن
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Frequency changed from ", DoubleToString(g_lastSuggestedFrequency, 3), 
              "% to ", DoubleToString(currentFreq, 3), "%");
        Print("   Saving as REJECTED...");
        #endif
        
        // رد پترن و ذخیره فرکانس جدید
        g_learningData[idx].feedbackReceived = true;
        g_learningData[idx].userApproved = false;
        g_learningData[idx].userSelectedFrequency = currentFreq;
        g_learningData[idx].userSelectedFreqIndex = g_th3FrequencyIndex;
        
        // محاسبه گام واقعی که کاربر انتخاب کرد
        CalculateUserSelectedStep(idx);
        
        // گرفتن اسکرین‌شات
        TakePatternScreenshot(idx);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("========================================");
        Print("❌ REJECTED (Frequency Changed)");
        Print("========================================");
        Print("Pattern: ", g_learningData[idx].patternName);
        Print("Original: ", DoubleToString(g_learningData[idx].suggestedFrequency, 3), "% → Step ", g_learningData[idx].targetStep);
        Print("User Selected: ", DoubleToString(g_learningData[idx].userSelectedFrequency, 3), "% → Step ", g_learningData[idx].userSelectedStep);
        Print("Error: ", DoubleToString(g_learningData[idx].actualErrorPercent, 3), "%");
        Print("Screenshot & Report saved");
        Print("========================================");
        #endif
        
        // آپدیت CSV
        UpdateLearningCSVRow(idx);
        
        // آپدیت گزارش پترن
        UpdatePatternReport(idx, "REJECTED");
        
        // مهندسی معکوس
        PerformReverseEngineering(idx);
        
        // تحلیل و آپدیت وزن‌ها
        AnalyzeAndUpdateWeights();
        
    } else {
        // فرکانس تغییر نکرده - تایید
        // گرفتن اسکرین‌شات قبل از تایید
        TakePatternScreenshot(idx);
        
        // تایید پترن
        g_learningData[idx].feedbackReceived = true;
        g_learningData[idx].userApproved = true;
        g_learningData[idx].userSelectedFrequency = g_learningData[idx].suggestedFrequency;
        g_learningData[idx].userSelectedFreqIndex = g_learningData[idx].suggestedFreqIndex;
        g_learningData[idx].userSelectedStep = g_learningData[idx].targetStep;
        g_learningData[idx].actualErrorPercent = g_learningData[idx].errorPercent;
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("========================================");
        Print("✅ APPROVED (Key 5 pressed)");
        Print("========================================");
        Print("Pattern: ", g_learningData[idx].patternName);
        Print("Frequency: ", DoubleToString(g_learningData[idx].suggestedFrequency, 3), "%");
        Print("Step: ", g_learningData[idx].targetStep);
        Print("Screenshot & Report saved");
        Print("========================================");
        #endif
        
        // آپدیت CSV
        UpdateLearningCSVRow(idx);
        
        // آپدیت گزارش پترن
        UpdatePatternReport(idx, "APPROVED");
        
        // تحلیل و آپدیت وزن‌ها
        AnalyzeAndUpdateWeights();
    }
    
    // ========================================
    // ⚠️ CRITICAL: State رو ریست میکنیم - دیگه نمیشه تغییر داد
    // Reset state - pattern is now finalized and cannot be changed
    // ========================================
    ResetSmartFeedbackState();
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ Pattern finalized. Create new pattern to continue learning.");
    #endif
}

//+------------------------------------------------------------------+
//| Calculate User Selected Step (Helper Function)                   |
//| محاسبه گام انتخابی کاربر (تابع کمکی)                             |
//+------------------------------------------------------------------+
void CalculateUserSelectedStep(int idx)
{
    if(idx < 0 || idx >= g_learningDataCount) return;
    
    string patternName = g_learningData[idx].patternName;
    string lineAB = patternName + "_Line_AB";
    string lineBC = patternName + "_Line_BC";
    
    if(ObjectFind(0, lineAB) >= 0 && ObjectFind(0, lineBC) >= 0) {
        datetime tA = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 0);
        double pA = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 0);
        datetime tB = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 1);
        double pB = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 1);
        datetime tC = (datetime)ObjectGetInteger(0, lineBC, OBJPROP_TIME, 1);
        double pC = ObjectGetDouble(0, lineBC, OBJPROP_PRICE, 1);
        
        double AB_Distance = MathAbs(pB - pA);
        
        // Validate AB_Distance to prevent division by zero
        if(AB_Distance < 0.0001) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("⚠️ Invalid AB_Distance, using default step");
            #endif
            g_learningData[idx].userSelectedStep = 5;
            g_learningData[idx].actualErrorPercent = 0;
            return;
        }
        
        bool isBullish = (pB > pA);
        double baseUnit = AB_Distance * (g_learningData[idx].userSelectedFrequency / 100.0);
        
        // محاسبه D
        double pD = isBullish ? (pC + AB_Distance) : (pC - AB_Distance);
        
        // پیدا کردن نزدیک‌ترین Step
        int bestStep = 5;
        double minError = 1000000.0;
        
        for(int step = 1; step <= 10; step++) {
            double stepPrice = isBullish ? (pC + step * baseUnit) : (pC - step * baseUnit);
            double error = MathAbs(pD - stepPrice);
            
            if(error < minError) {
                minError = error;
                bestStep = step;
            }
        }
        
        g_learningData[idx].userSelectedStep = bestStep;
        g_learningData[idx].actualErrorPercent = SafeDivide(minError, AB_Distance, 0.0, EPSILON_GENERAL) * 100.0;
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Pattern objects not found, using default step");
        #endif
        g_learningData[idx].userSelectedStep = 5;
        g_learningData[idx].actualErrorPercent = 0;
    }
}

//+------------------------------------------------------------------+
//| Perform Reverse Engineering Analysis                             |
//| انجام تحلیل مهندسی معکوس                                          |
//| Determines which features should change to reach user's frequency|
//+------------------------------------------------------------------+
void PerformReverseEngineering(int patternIndex)
{
    if(patternIndex < 0 || patternIndex >= g_learningDataCount) return;
    
    PatternLearningData d = g_learningData[patternIndex];
    
    // محاسبه تفاوت فرکانس
    double freqDiff = d.userSelectedFrequency - d.suggestedFrequency;
    double freqDiffPercent = SafeDivide(freqDiff, d.suggestedFrequency, 0.0, EPSILON_GENERAL) * 100.0;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("🔧 REVERSE ENGINEERING ANALYSIS");
    Print("========================================");
    Print("Frequency Difference: ", DoubleToString(freqDiff, 3), "% (", 
          DoubleToString(freqDiffPercent, 1), "%)");
    Print("");
    #endif
    
    // ========================================
    // تحلیل: چه ویژگی‌هایی باید تغییر کنند تا به فرکانس کاربر برسیم؟
    // Analysis: Which features should change to reach user's frequency?
    // ========================================
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("FEATURE ANALYSIS:");
    Print("Current pattern features vs. what they should be:");
    Print("");
    #endif
    
    // 1. تحلیل سرعت موج (Wave Speed)
    #ifdef ENABLE_DEBUG_LOGS
    Print("1. WAVE SPEED:");
    Print("   Current AB Speed: ", DoubleToString(d.AB_Speed, 3), " pips/min");
    #endif
    if(freqDiff > 0) {
        // کاربر فرکانس بالاتر خواست → موج باید سریع‌تر باشه
        double targetSpeed = d.AB_Speed * (1.0 + freqDiffPercent / 100.0);
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Should be FASTER: ~", DoubleToString(targetSpeed, 3), " pips/min");
        Print("   → Increase: +", DoubleToString(SafeDivide(targetSpeed - d.AB_Speed, d.AB_Speed, 0.0, EPSILON_GENERAL) * 100, 1), "%");
        #endif
    } else if(freqDiff < 0) {
        // کاربر فرکانس پایین‌تر خواست → موج باید کندتر باشه
        double targetSpeed = d.AB_Speed * (1.0 + freqDiffPercent / 100.0);
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Should be SLOWER: ~", DoubleToString(targetSpeed, 3), " pips/min");
        Print("   → Decrease: ", DoubleToString(SafeDivide(targetSpeed - d.AB_Speed, d.AB_Speed, 0.0, EPSILON_GENERAL) * 100, 1), "%");
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    #endif
    
    // 2. تحلیل زاویه Gann (Gann Angle)
    #ifdef ENABLE_DEBUG_LOGS
    Print("2. GANN ANGLE:");
    Print("   Current AB Angle: ", DoubleToString(d.AB_Angle, 2), " degrees");
    #endif
    if(freqDiff > 0) {
        double targetAngle = d.AB_Angle * (1.0 + freqDiffPercent / 200.0); // کمتر حساس
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Should be STEEPER: ~", DoubleToString(targetAngle, 2), " degrees");
        #endif
    } else if(freqDiff < 0) {
        double targetAngle = d.AB_Angle * (1.0 + freqDiffPercent / 200.0);
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Should be FLATTER: ~", DoubleToString(targetAngle, 2), " degrees");
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    #endif
    
    // 3. تحلیل Consolidation (انرژی جمع شده)
    #ifdef ENABLE_DEBUG_LOGS
    Print("3. CONSOLIDATION FACTOR:");
    Print("   Current: ", DoubleToString(d.consolidationFactor * 100, 1), "%");
    #endif
    if(freqDiff > 0 && d.consolidationFactor < 0.5) {
        // فرکانس بالاتر → consolidation بیشتر نیاز داره
        double targetConsolidation = ClampValue(d.consolidationFactor + (freqDiffPercent / 100.0 * 0.3), 0, 1);
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Should be HIGHER: ~", DoubleToString(targetConsolidation * 100, 1), "%");
        Print("   → More energy buildup needed for higher frequency");
        #endif
    } else if(freqDiff < 0 && d.consolidationFactor > 0.3) {
        // فرکانس پایین‌تر → consolidation کمتر
        double targetConsolidation = ClampValue(d.consolidationFactor + (freqDiffPercent / 100.0 * 0.3), 0, 1);
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Should be LOWER: ~", DoubleToString(targetConsolidation * 100, 1), "%");
        Print("   → Less consolidation for lower frequency");
        #endif
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Current level is appropriate");
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    #endif
    
    // 4. تحلیل نسبت Fibonacci
    #ifdef ENABLE_DEBUG_LOGS
    Print("4. FIBONACCI RATIOS:");
    Print("   Current AB/XA: ", DoubleToString(d.AB_XA_Ratio, 3));
    Print("   Current BC/AB: ", DoubleToString(d.BC_AB_Ratio, 3));
    #endif
    
    // محاسبه نسبت ایده‌آل بر اساس فرکانس کاربر
    double idealAB_XA = 1.0 + SafeDivide(d.userSelectedFrequency, 100.0, 0.0, EPSILON_GENERAL); // تقریبی
    #ifdef ENABLE_DEBUG_LOGS
    Print("   → Ideal AB/XA for ", DoubleToString(d.userSelectedFrequency, 1), "%: ~", DoubleToString(idealAB_XA, 3));
    #endif
    
    if(MathAbs(d.AB_XA_Ratio - idealAB_XA) > 0.2) {
        if(d.AB_XA_Ratio < idealAB_XA) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   → AB should be LONGER relative to XA");
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   → AB should be SHORTER relative to XA");
            #endif
        }
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Current ratio is close to ideal");
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    #endif
    
    // 5. تحلیل تقارن زمانی (Time Symmetry)
    #ifdef ENABLE_DEBUG_LOGS
    Print("5. TIME SYMMETRY:");
    Print("   Current: ", DoubleToString(d.timeSymmetry * 100, 1), "%");
    #endif
    if(d.timeSymmetry < 0.7) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Should be HIGHER for better prediction");
        Print("   → BC time should match AB time more closely");
        #endif
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Good time symmetry");
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    #endif
    
    // 6. تحلیل Step (گام هدف)
    #ifdef ENABLE_DEBUG_LOGS
    Print("6. TARGET STEP:");
    Print("   System suggested: Step ", d.targetStep, " (", DoubleToString(d.suggestedFrequency, 3), "%)");
    Print("   User selected: Step ", d.userSelectedStep, " (", DoubleToString(d.userSelectedFrequency, 3), "%)");
    #endif
    
    if(d.userSelectedStep != d.targetStep) {
        int stepDiff = d.userSelectedStep - d.targetStep;
        if(stepDiff > 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   → User prefers LARGER steps (", stepDiff, " steps more)");
            Print("   → Pattern should show stronger momentum");
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   → User prefers SMALLER steps (", MathAbs(stepDiff), " steps less)");
            Print("   → Pattern should show more conservative movement");
            #endif
        }
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   → Step selection matches (frequency adjustment only)");
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    #endif
    
    // ========================================
    // خلاصه و توصیه‌ها
    // Summary & Recommendations
    // ========================================
    #ifdef ENABLE_DEBUG_LOGS
    Print("SUMMARY & RECOMMENDATIONS:");
    Print("-------------------------");
    #endif
    
    if(MathAbs(freqDiffPercent) < 5.0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("✅ Minor adjustment - system was close");
        Print("   Fine-tune: Speed consistency and time symmetry");
        #endif
    }
    else if(MathAbs(freqDiffPercent) < 15.0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Moderate adjustment needed");
        Print("   Focus on: Wave speed and consolidation factor");
        #endif
    }
    else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ Major adjustment required");
        Print("   Review: All features - pattern type may be different");
        #endif
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("");
    Print("For similar patterns in the future:");
    #endif
    if(freqDiff > 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("→ Look for: Faster waves, steeper angles, more consolidation");
        Print("→ Expect: Higher frequency (", DoubleToString(d.userSelectedFrequency, 1), "% range)");
        #endif
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("→ Look for: Slower waves, flatter angles, less consolidation");
        Print("→ Expect: Lower frequency (", DoubleToString(d.userSelectedFrequency, 1), "% range)");
        #endif
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    #endif
}

//+------------------------------------------------------------------+
//| Take Pattern Screenshot                                          |
//| گرفتن اسکرین‌شات پترن                                             |
//| Takes screenshot when pattern is complete with all levels       |
//+------------------------------------------------------------------+
void TakePatternScreenshot(int patternIndex)
{
    if(patternIndex < 0 || patternIndex >= g_learningDataCount) return;
    
    PatternLearningData d = g_learningData[patternIndex];
    
    // بررسی اینکه آیا قبلاً اسکرین‌شات گرفته شده
    // Check if screenshot already taken
    if(d.screenshotFilename != "" && d.screenshotFilename != "FAILED") {
        // تلاش برای گرفتن اسکرین‌شات
        #ifdef ENABLE_DEBUG_LOGS
        Print("📸 Taking screenshot for pattern: ", d.patternName);
        #endif
        
        // ========================================
        // ایجاد پوشه اگر وجود نداره
        // Create folder if it doesn't exist
        // ========================================
        // MT4 can't create nested folders with ChartScreenShot
        // So we create a dummy file to force folder creation
        string folderPath = StringSubstr(d.screenshotFilename, 0, StringFind(d.screenshotFilename, "\\screenshot.gif"));
        string dummyFile = folderPath + "\\dummy.txt";
        int dummyHandle = SafeFileOpen(dummyFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
        if(dummyHandle != INVALID_HANDLE) {
            SafeFileClose(dummyHandle);
            FileDelete(dummyFile);
            #ifdef ENABLE_DEBUG_LOGS
            Print("✅ Folder created: ", folderPath);
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("⚠️ Could not create folder");
            #endif
        }
        
        // ========================================
        // تنظیم چارت برای اسکرین‌شات بهتر
        // Adjust chart for better screenshot
        // ========================================
        
        // ذخیره تنظیمات فعلی چارت
        int originalFirstVisible = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
        
        // پیدا کردن نقاط پترن برای محاسبه محدوده
        // Find pattern points to calculate range
        string patternName = d.patternName;
        string lineAB = patternName + "_Line_AB";
        
        if(ObjectFind(0, lineAB) >= 0) {
            datetime tA = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 0);
            
            // محاسبه محدوده زمانی پترن
            int patternStartBar = iBarShift(_Symbol, _Period, tA) + 10; // +10 برای فضای اضافی
            int patternEndBar = 0; // فعلی
            int patternBars = patternStartBar - patternEndBar + PATTERN_BARS_PADDING;
            
            // تنظیم زوم چارت تا پترن کامل دیده بشه
            if(patternBars > 0 && patternBars < 1000) {
                // MQL5: CHART_FIRST_VISIBLE_BAR is read-only, use ChartNavigate instead
                ChartNavigate(0, CHART_END, -patternStartBar);
                // MQL5: CHART_WIDTH_IN_BARS is read-only, adjust scale to approximate
                // (cannot set exact bars width in MQL5)
            }
        }
        
        // رفرش چارت و صبر برای رندر شدن
        ChartRedraw(0);
        // Sleep removed for MQL5 indicator compatibility
        
        // گرفتن اسکرین‌شات با سایز بزرگتر - MQL5: ChartScreenShot has 4 params (no ALIGN param)
        if(ChartScreenShot(0, d.screenshotFilename, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("✅ Screenshot saved: ", d.screenshotFilename);
            Print("   Size: ", SCREENSHOT_WIDTH, "x", SCREENSHOT_HEIGHT);
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("⚠️ Screenshot failed (Error: ", GetLastError(), ")");
            #endif
            g_learningData[patternIndex].screenshotFilename = "FAILED";
        }
        
        // بازگرداندن تنظیمات چارت
        ChartSetInteger(0, CHART_FIRST_VISIBLE_BAR, originalFirstVisible);
        ChartRedraw(0);
    }
}

//+------------------------------------------------------------------+
//| Generate Pattern Report (Individual File)                        |
//| تولید گزارش پترن (فایل جداگانه)                                  |
//| Creates a separate report file for each pattern                 |
//+------------------------------------------------------------------+
void GeneratePatternReport(PatternLearningData &data, int patternIndex, string patternFolder)
{
    // نام فایل گزارش در پوشه پترن
    // Report filename in pattern folder
    string filename = patternFolder + "\\report.txt";
    
    int handle = SafeFileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(handle == INVALID_HANDLE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ Failed to create pattern report");
        #endif
        return;
    }
    
    // ========================================
    // HEADER
    // ========================================
    FileWriteString(handle, "========================================\n");
    FileWriteString(handle, "PATTERN LEARNING REPORT\n");
    FileWriteString(handle, "========================================\n");
    FileWriteString(handle, "Pattern ID: " + IntegerToString(patternIndex + 1) + "\n");
    FileWriteString(handle, "Pattern Name: " + data.patternName + "\n");
    FileWriteString(handle, "Timestamp: " + TimeToString(data.timestamp, TIME_DATE|TIME_SECONDS) + "\n");
    FileWriteString(handle, "Symbol: " + data.symbol + "\n");
    FileWriteString(handle, "Timeframe: " + IntegerToString(PeriodMinutes((ENUM_TIMEFRAMES)data.timeframe)) + " minutes\n");
    FileWriteString(handle, "Screenshot: screenshot.gif (in same folder)\n");
    FileWriteString(handle, "\n");
    
    // ========================================
    // WAVE DATA
    // ========================================
    FileWriteString(handle, "WAVE DATA\n");
    FileWriteString(handle, "---------\n");
    FileWriteString(handle, "XA: " + DoubleToString(data.XA_Pips, 1) + " pips in " + IntegerToString(data.XA_Minutes) + " minutes\n");
    FileWriteString(handle, "AB: " + DoubleToString(data.AB_Pips, 1) + " pips in " + IntegerToString(data.AB_Minutes) + " minutes\n");
    FileWriteString(handle, "BC: " + DoubleToString(data.BC_Pips, 1) + " pips in " + IntegerToString(data.BC_Minutes) + " minutes\n");
    FileWriteString(handle, "AB Speed: " + DoubleToString(data.AB_Speed, 3) + " pips/min\n");
    FileWriteString(handle, "AB Angle: " + DoubleToString(data.AB_Angle, 2) + " degrees (Gann)\n");
    FileWriteString(handle, "\n");
    
    // ========================================
    // CALCULATED FEATURES
    // ========================================
    FileWriteString(handle, "CALCULATED FEATURES\n");
    FileWriteString(handle, "-------------------\n");
    FileWriteString(handle, "Speed Consistency: " + DoubleToString(data.speedConsistency * 100, 1) + "%\n");
    FileWriteString(handle, "AB/XA Ratio: " + DoubleToString(data.AB_XA_Ratio, 3) + " (Fibonacci)\n");
    FileWriteString(handle, "BC/AB Ratio: " + DoubleToString(data.BC_AB_Ratio, 3) + "\n");
    FileWriteString(handle, "Time Symmetry: " + DoubleToString(data.timeSymmetry * 100, 1) + "%\n");
    FileWriteString(handle, "Consolidation Factor: " + DoubleToString(data.consolidationFactor * 100, 1) + "%\n");
    FileWriteString(handle, "Required Rest Candles: " + IntegerToString(data.requiredRestCandles) + "\n");
    FileWriteString(handle, "Daily ATR: " + DoubleToString(data.dailyATR, 1) + " pips\n");
    FileWriteString(handle, "\n");
    
    // ========================================
    // SYSTEM SUGGESTION
    // ========================================
    FileWriteString(handle, "SYSTEM SUGGESTION\n");
    FileWriteString(handle, "-----------------\n");
    FileWriteString(handle, "Suggested Frequency: " + DoubleToString(data.suggestedFrequency, 3) + "%\n");
    FileWriteString(handle, "Frequency Index: " + IntegerToString(data.suggestedFreqIndex) + "\n");
    FileWriteString(handle, "Target Step: " + IntegerToString(data.targetStep) + "\n");
    FileWriteString(handle, "Error: " + DoubleToString(data.errorPercent, 3) + "%\n");
    FileWriteString(handle, "Total Score: " + DoubleToString(data.totalScore, 2) + "\n");
    FileWriteString(handle, "\n");
    
    // ========================================
    // CURRENT SYSTEM WEIGHTS (برای مهندسی معکوس)
    // ========================================
    FileWriteString(handle, "SYSTEM WEIGHTS (at time of suggestion)\n");
    FileWriteString(handle, "--------------------------------------\n");
    FileWriteString(handle, "Step Priority Weight: " + DoubleToString(g_weights.stepPriorityWeight, 4) + "\n");
    FileWriteString(handle, "Error Weight: " + DoubleToString(g_weights.errorWeight, 4) + "\n");
    FileWriteString(handle, "Speed Consistency Weight: " + DoubleToString(g_weights.speedConsistencyWeight, 4) + "\n");
    FileWriteString(handle, "Time Symmetry Weight: " + DoubleToString(g_weights.timeSymmetryWeight, 4) + "\n");
    FileWriteString(handle, "Fibonacci Weight: " + DoubleToString(g_weights.fibonacciWeight, 4) + "\n");
    FileWriteString(handle, "Freq Deviation Weight: " + DoubleToString(g_weights.freqDeviationWeight, 4) + "\n");
    FileWriteString(handle, "Consolidation Weight: " + DoubleToString(g_weights.consolidationWeight, 4) + "\n");
    FileWriteString(handle, "Step 5 Priority: " + DoubleToString(g_weights.step5Priority, 4) + "\n");
    FileWriteString(handle, "Step 3/7 Priority: " + DoubleToString(g_weights.step3_7Priority, 4) + "\n");
    FileWriteString(handle, "Step 1 Priority: " + DoubleToString(g_weights.step1Priority, 4) + "\n");
    FileWriteString(handle, "\n");
    FileWriteString(handle, "Learning Statistics:\n");
    FileWriteString(handle, "  Total Patterns: " + IntegerToString(g_weights.totalPatterns) + "\n");
    FileWriteString(handle, "  Approved: " + IntegerToString(g_weights.approvedPatterns) + "\n");
    FileWriteString(handle, "  Rejected: " + IntegerToString(g_weights.rejectedPatterns) + "\n");
    if(g_weights.totalPatterns > 0) {
        FileWriteString(handle, "  Accuracy: " + DoubleToString(SafeDivide(100.0 * g_weights.approvedPatterns, g_weights.totalPatterns, 0.0, EPSILON_GENERAL), 1) + "%\n");
    }
    FileWriteString(handle, "\n");
    
    // ========================================
    // USER FEEDBACK (will be updated later)
    // ========================================
    FileWriteString(handle, "USER FEEDBACK\n");
    FileWriteString(handle, "-------------\n");
    FileWriteString(handle, "Status: PENDING\n");
    FileWriteString(handle, "Waiting for user action...\n");
    FileWriteString(handle, "\n");
    
    FileWriteString(handle, "========================================\n");
    FileWriteString(handle, "END OF INITIAL REPORT\n");
    FileWriteString(handle, "========================================\n");
    
    SafeFileClose(handle);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("📄 Pattern report created: ", filename);
    #endif
}

//+------------------------------------------------------------------+
//| Update Pattern Report with Final Result                          |
//| آپدیت گزارش پترن با نتیجه نهایی                                   |
//+------------------------------------------------------------------+
void UpdatePatternReport(int patternIndex, string status)
{
    if(patternIndex < 0 || patternIndex >= g_learningDataCount) return;
    
    PatternLearningData d = g_learningData[patternIndex];
    
    // پیدا کردن فایل گزارش
    // Finding report file - must match GeneratePatternReport filename
    string timestamp = TimeToString(d.timestamp, TIME_DATE) + "_" + 
                       IntegerToString(TimeHour(d.timestamp)) + 
                       IntegerToString(TimeMinute(d.timestamp)) + 
                       IntegerToString(TimeSeconds(d.timestamp));
    StringReplace(timestamp, ".", "_");
    StringReplace(timestamp, ":", "_");
    StringReplace(timestamp, " ", "_");
    
    string patternFolder = REPORTS_FOLDER + "\\Pattern_" + 
                           IntegerToString(patternIndex + 1) + "_" + 
                           d.symbol + "_" + timestamp;
    
    string filename = patternFolder + "\\report.txt";
    
    // افزودن بخش آپدیت به انتهای فایل (نه جایگزینی)
    // Append update section to end of file (not replace)
    int handle = SafeFileOpen(filename, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(handle == INVALID_HANDLE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ Could not find pattern report to update");
        #endif
        return;
    }
    
    // رفتن به انتهای فایل
    FileSeek(handle, 0, SEEK_END);
    
    // نوشتن بخش آپدیت به صورت جدا و واضح
    FileWriteString(handle, "\n");
    FileWriteString(handle, "========================================\n");
    FileWriteString(handle, "USER FEEDBACK UPDATE\n");
    FileWriteString(handle, "========================================\n");
    FileWriteString(handle, "Update Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n");
    FileWriteString(handle, "Status: " + status + "\n");
    FileWriteString(handle, "\n");
    
    if(status == "APPROVED") {
        FileWriteString(handle, "✅ USER APPROVED THE SUGGESTION\n");
        FileWriteString(handle, "--------------------------------\n");
        FileWriteString(handle, "The user accepted the system's suggested frequency without changes.\n");
        FileWriteString(handle, "\n");
        FileWriteString(handle, "Final Frequency: " + DoubleToString(d.userSelectedFrequency, 3) + "%\n");
        FileWriteString(handle, "Final Frequency Index: " + IntegerToString(d.userSelectedFreqIndex) + "\n");
        FileWriteString(handle, "Final Step: " + IntegerToString(d.userSelectedStep) + "\n");
        FileWriteString(handle, "Final Error: " + DoubleToString(d.actualErrorPercent, 3) + "%\n");
        FileWriteString(handle, "\n");
        FileWriteString(handle, "CONCLUSION: System suggestion was accurate.\n");
    }
    else if(status == "REJECTED") {
        FileWriteString(handle, "❌ USER CHANGED THE FREQUENCY\n");
        FileWriteString(handle, "------------------------------\n");
        FileWriteString(handle, "The user modified the frequency before approval.\n");
        FileWriteString(handle, "\n");
        FileWriteString(handle, "COMPARISON:\n");
        FileWriteString(handle, "-----------\n");
        FileWriteString(handle, "System Suggested:\n");
        FileWriteString(handle, "  Frequency: " + DoubleToString(d.suggestedFrequency, 3) + "%\n");
        FileWriteString(handle, "  Frequency Index: " + IntegerToString(d.suggestedFreqIndex) + "\n");
        FileWriteString(handle, "  Target Step: " + IntegerToString(d.targetStep) + "\n");
        FileWriteString(handle, "  Error: " + DoubleToString(d.errorPercent, 3) + "%\n");
        FileWriteString(handle, "\n");
        FileWriteString(handle, "User Selected:\n");
        FileWriteString(handle, "  Frequency: " + DoubleToString(d.userSelectedFrequency, 3) + "%\n");
        FileWriteString(handle, "  Frequency Index: " + IntegerToString(d.userSelectedFreqIndex) + "\n");
        FileWriteString(handle, "  Actual Step: " + IntegerToString(d.userSelectedStep) + "\n");
        FileWriteString(handle, "  Actual Error: " + DoubleToString(d.actualErrorPercent, 3) + "%\n");
        FileWriteString(handle, "\n");
        FileWriteString(handle, "DIFFERENCE:\n");
        FileWriteString(handle, "-----------\n");
        FileWriteString(handle, "Frequency Difference: " + DoubleToString(d.userSelectedFrequency - d.suggestedFrequency, 3) + "%\n");
        FileWriteString(handle, "Step Difference: " + IntegerToString(d.userSelectedStep - d.targetStep) + "\n");
        FileWriteString(handle, "Error Improvement: " + DoubleToString(d.errorPercent - d.actualErrorPercent, 3) + "%\n");
        FileWriteString(handle, "\n");
        FileWriteString(handle, "REVERSE ENGINEERING ANALYSIS:\n");
        FileWriteString(handle, "------------------------------\n");
        FileWriteString(handle, "The system will analyze which features/weights should be adjusted\n");
        FileWriteString(handle, "to reach the user's selected frequency in similar future patterns.\n");
        FileWriteString(handle, "\n");
        FileWriteString(handle, "Key Questions for AI Analysis:\n");
        FileWriteString(handle, "1. Which wave features (speed, angle, ratios) correlate with this change?\n");
        FileWriteString(handle, "2. Should step priority weights be adjusted?\n");
        FileWriteString(handle, "3. Is consolidation factor more/less important than suggested?\n");
        FileWriteString(handle, "4. Should Fibonacci ratio weights change?\n");
        FileWriteString(handle, "\n");
        FileWriteString(handle, "CONCLUSION: System needs adjustment for similar patterns.\n");
    }
    
    FileWriteString(handle, "\n");
    FileWriteString(handle, "========================================\n");
    FileWriteString(handle, "END OF UPDATE\n");
    FileWriteString(handle, "========================================\n");
    
    SafeFileClose(handle);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ Pattern report updated: ", filename);
    #endif
}

//+------------------------------------------------------------------+
//| Generate Learning Report (AI-Readable Format)                    |
//| تولید گزارش یادگیری (فرمت قابل خواندن برای AI)                  |
//+------------------------------------------------------------------+
void GenerateLearningReport()
{
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE);
    StringReplace(timestamp, ".", "_");
    
    string filename = REPORTS_FOLDER + "\\Learning_Report_" + GetCachedSymbol() + "_" + timestamp + ".txt";
    
    int handle = SafeFileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(handle == INVALID_HANDLE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ Failed to create report file");
        #endif
        return;
    }
    
    // ========================================
    // HEADER - AI-Readable Format
    // ========================================
    FileWriteString(handle, "========================================\n");
    FileWriteString(handle, "BIOTAK TH3 FREQUENCY LEARNING REPORT\n");
    FileWriteString(handle, "AI-READABLE FORMAT FOR ANALYSIS\n");
    FileWriteString(handle, "========================================\n");
    FileWriteString(handle, "Generated: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n");
    FileWriteString(handle, "Symbol: " + GetCachedSymbol() + "\n");
    FileWriteString(handle, "Timeframe: " + IntegerToString(PeriodMinutes()) + " minutes\n");
    FileWriteString(handle, "Total Patterns: " + IntegerToString(g_learningDataCount) + "\n");
    FileWriteString(handle, "\n");
    
    // ========================================
    // STATISTICS SUMMARY
    // ========================================
    FileWriteString(handle, "STATISTICS\n");
    FileWriteString(handle, "----------\n");
    
    int totalFeedback = g_weights.approvedPatterns + g_weights.rejectedPatterns;
    FileWriteString(handle, "Approved: " + IntegerToString(g_weights.approvedPatterns) + 
                    " (" + DoubleToString(SafeDivide(100.0 * g_weights.approvedPatterns, totalFeedback, 0.0, EPSILON_GENERAL), 1) + "%)\n");
    FileWriteString(handle, "Rejected: " + IntegerToString(g_weights.rejectedPatterns) + 
                    " (" + DoubleToString(SafeDivide(100.0 * g_weights.rejectedPatterns, totalFeedback, 0.0, EPSILON_GENERAL), 1) + "%)\n");
    FileWriteString(handle, "Pending: " + IntegerToString(g_learningDataCount - totalFeedback) + "\n");
    FileWriteString(handle, "Accuracy: " + DoubleToString(SafeDivide(100.0 * g_weights.approvedPatterns, totalFeedback, 0.0, EPSILON_GENERAL), 2) + "%\n");
    FileWriteString(handle, "\n");
    
    // ========================================
    // CURRENT WEIGHTS (For AI to understand current model)
    // ========================================
    FileWriteString(handle, "CURRENT LEARNED WEIGHTS\n");
    FileWriteString(handle, "-----------------------\n");
    FileWriteString(handle, "stepPriorityWeight: " + DoubleToString(g_weights.stepPriorityWeight, 4) + "\n");
    FileWriteString(handle, "errorWeight: " + DoubleToString(g_weights.errorWeight, 4) + "\n");
    FileWriteString(handle, "speedConsistencyWeight: " + DoubleToString(g_weights.speedConsistencyWeight, 4) + "\n");
    FileWriteString(handle, "timeSymmetryWeight: " + DoubleToString(g_weights.timeSymmetryWeight, 4) + "\n");
    FileWriteString(handle, "fibonacciWeight: " + DoubleToString(g_weights.fibonacciWeight, 4) + "\n");
    FileWriteString(handle, "freqDeviationWeight: " + DoubleToString(g_weights.freqDeviationWeight, 4) + "\n");
    FileWriteString(handle, "consolidationWeight: " + DoubleToString(g_weights.consolidationWeight, 4) + "\n");
    FileWriteString(handle, "step5Priority: " + DoubleToString(g_weights.step5Priority, 4) + "\n");
    FileWriteString(handle, "step3_7Priority: " + DoubleToString(g_weights.step3_7Priority, 4) + "\n");
    FileWriteString(handle, "step1Priority: " + DoubleToString(g_weights.step1Priority, 4) + "\n");
    FileWriteString(handle, "\n");
    
    // ========================================
    // PATTERN DATA (Structured for AI parsing)
    // ========================================
    FileWriteString(handle, "PATTERN DATA (JSON-like format for AI)\n");
    FileWriteString(handle, "---------------------------------------\n");
    
    for(int i = 0; i < g_learningDataCount; i++) {
        PatternLearningData d = g_learningData[i];
        
        FileWriteString(handle, "\n--- PATTERN #" + IntegerToString(i + 1) + " ---\n");
        FileWriteString(handle, "{\n");
        FileWriteString(handle, "  \"id\": " + IntegerToString(i + 1) + ",\n");
        FileWriteString(handle, "  \"name\": \"" + d.patternName + "\",\n");
        FileWriteString(handle, "  \"timestamp\": \"" + TimeToString(d.timestamp, TIME_DATE|TIME_SECONDS) + "\",\n");
        FileWriteString(handle, "  \"symbol\": \"" + d.symbol + "\",\n");
        FileWriteString(handle, "  \"timeframe\": " + IntegerToString(d.timeframe) + ",\n");
        
        // Wave features
        FileWriteString(handle, "  \"waves\": {\n");
        FileWriteString(handle, "    \"XA_pips\": " + DoubleToString(d.XA_Pips, 2) + ",\n");
        FileWriteString(handle, "    \"AB_pips\": " + DoubleToString(d.AB_Pips, 2) + ",\n");
        FileWriteString(handle, "    \"BC_pips\": " + DoubleToString(d.BC_Pips, 2) + ",\n");
        FileWriteString(handle, "    \"XA_minutes\": " + IntegerToString(d.XA_Minutes) + ",\n");
        FileWriteString(handle, "    \"AB_minutes\": " + IntegerToString(d.AB_Minutes) + ",\n");
        FileWriteString(handle, "    \"BC_minutes\": " + IntegerToString(d.BC_Minutes) + ",\n");
        FileWriteString(handle, "    \"AB_speed\": " + DoubleToString(d.AB_Speed, 4) + ",\n");
        FileWriteString(handle, "    \"AB_angle\": " + DoubleToString(d.AB_Angle, 2) + "\n");
        FileWriteString(handle, "  },\n");
        
        // Calculated features
        FileWriteString(handle, "  \"features\": {\n");
        FileWriteString(handle, "    \"speedConsistency\": " + DoubleToString(d.speedConsistency, 4) + ",\n");
        FileWriteString(handle, "    \"AB_XA_ratio\": " + DoubleToString(d.AB_XA_Ratio, 4) + ",\n");
        FileWriteString(handle, "    \"BC_AB_ratio\": " + DoubleToString(d.BC_AB_Ratio, 4) + ",\n");
        FileWriteString(handle, "    \"timeSymmetry\": " + DoubleToString(d.timeSymmetry, 4) + ",\n");
        FileWriteString(handle, "    \"consolidationFactor\": " + DoubleToString(d.consolidationFactor, 4) + ",\n");
        FileWriteString(handle, "    \"requiredRestCandles\": " + IntegerToString(d.requiredRestCandles) + ",\n");
        FileWriteString(handle, "    \"dailyATR\": " + DoubleToString(d.dailyATR, 2) + "\n");
        FileWriteString(handle, "  },\n");
        
        // Frequency selection
        FileWriteString(handle, "  \"frequency\": {\n");
        FileWriteString(handle, "    \"suggested\": " + DoubleToString(d.suggestedFrequency, 4) + ",\n");
        FileWriteString(handle, "    \"suggestedIndex\": " + IntegerToString(d.suggestedFreqIndex) + ",\n");
        FileWriteString(handle, "    \"targetStep\": " + IntegerToString(d.targetStep) + ",\n");
        FileWriteString(handle, "    \"errorPercent\": " + DoubleToString(d.errorPercent, 4) + ",\n");
        FileWriteString(handle, "    \"totalScore\": " + DoubleToString(d.totalScore, 4) + "\n");
        FileWriteString(handle, "  },\n");
        
        // User feedback
        string status = "PENDING";
        if(d.feedbackReceived) {
            status = d.userApproved ? "APPROVED" : "REJECTED";
        }
        
        FileWriteString(handle, "  \"feedback\": {\n");
        FileWriteString(handle, "    \"status\": \"" + status + "\",\n");
        FileWriteString(handle, "    \"userFrequency\": " + DoubleToString(d.userSelectedFrequency, 4) + ",\n");
        FileWriteString(handle, "    \"userFreqIndex\": " + IntegerToString(d.userSelectedFreqIndex) + ",\n");
        FileWriteString(handle, "    \"userStep\": " + IntegerToString(d.userSelectedStep) + ",\n");
        FileWriteString(handle, "    \"actualError\": " + DoubleToString(d.actualErrorPercent, 4) + "\n");
        FileWriteString(handle, "  },\n");
        
        FileWriteString(handle, "  \"screenshot\": \"" + d.screenshotFilename + "\"\n");
        FileWriteString(handle, "}\n");
    }
    
    FileWriteString(handle, "\n========================================\n");
    FileWriteString(handle, "END OF REPORT\n");
    FileWriteString(handle, "========================================\n");
    
    SafeFileClose(handle);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("📄 LEARNING REPORT GENERATED");
    Print("========================================");
    Print("File: ", filename);
    Print("Location: MQL5/Files/", REPORTS_FOLDER);
    Print("Format: AI-readable JSON-like structure");
    Print("========================================");
    #endif
}

//+------------------------------------------------------------------+
//| Detect New Pattern Creation (for auto-approve)                  |
//| تشخیص ایجاد پترن جدید (برای تایید خودکار)                       |
//| Call this when a new AB=CD pattern is created                   |
//+------------------------------------------------------------------+
void OnNewPatternCreated()
{
    // اگر پترن قبلی در انتظار بود، تایید خودکار
    if(g_waitingForFeedback && g_pendingPatternIndex >= 0) {
        AutoApprovePendingPattern();
    }
}

//+------------------------------------------------------------------+
//| Detect Pattern Deletion (for ignore)                            |
//| تشخیص حذف پترن (برای نادیده گرفتن)                              |
//| Call this when an AB=CD pattern is deleted                      |
//+------------------------------------------------------------------+
void OnPatternDeleted(string patternName)
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("🗑️ PATTERN DELETION DETECTED");
    Print("========================================");
    Print("Deleted Pattern: ", patternName);
    Print("Current Pattern For Feedback: ", g_currentPatternForFeedback);
    Print("g_waitingForFeedback: ", g_waitingForFeedback);
    Print("g_pendingPatternIndex: ", g_pendingPatternIndex);
    #endif
    
    // اگر پترن حذف شده همان پترن در انتظار است، نادیده بگیر
    if(g_waitingForFeedback && g_pendingPatternIndex >= 0) {
        // بررسی اینکه آیا این پترن همان پترن در انتظار است
        // Check if deleted pattern matches pending pattern
        if(g_pendingPatternIndex < g_learningDataCount) {
            string pendingPatternName = g_learningData[g_pendingPatternIndex].patternName;
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("Pending Pattern Name: ", pendingPatternName);
            #endif
            
            // مقایسه نام پترن‌ها
            if(pendingPatternName == patternName || g_currentPatternForFeedback == patternName) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("✅ Match found - ignoring this pattern");
                Print("No feedback will be recorded");
                Print("========================================");
                #endif
                
                // ریست حالت بدون ذخیره
                ResetSmartFeedbackState();
                return;
            }
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("⚠️ No match - pattern was not pending for feedback");
    Print("========================================");
    #endif
}

//+------------------------------------------------------------------+
//| Reset Smart Feedback State                                       |
//| ریست حالت بازخورد هوشمند                                         |
//+------------------------------------------------------------------+
void ResetSmartFeedbackState()
{
    g_waitingForFeedback = false;
    g_pendingPatternIndex = -1;
    g_lastSuggestedFrequency = 0.0;
    g_lastSuggestedFreqIndex = 0;
    g_patternCreationTime = 0;
    g_currentPatternForFeedback = "";
    g_currentPatternIndex = -1;
}

//+------------------------------------------------------------------+
//| Cleanup Learning System                                          |
//| پاکسازی سیستم یادگیری                                            |
//+------------------------------------------------------------------+
void CleanupLearningSystem()
{
    // اگر پترن در انتظار هست، تایید خودکار قبل از خروج
    if(g_waitingForFeedback && g_pendingPatternIndex >= 0) {
        AutoApprovePendingPattern();
    }
    
    // ذخیره نهایی وزن‌ها
    SaveLearnedWeights();
    
    // تولید گزارش نهایی
    if(g_learningDataCount > 0) {
        GenerateLearningReport();
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("🎓 Learning system cleaned up");
    #endif
}
