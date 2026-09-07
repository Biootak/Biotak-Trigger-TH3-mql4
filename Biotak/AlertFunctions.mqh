  #ifndef ALERT_FUNCTIONS_MQH
#define ALERT_FUNCTIONS_MQH

#property strict

// Cached current-bar open time: ShouldTriggerAlert runs per level per redraw
// (up to ~288 iTime calls); refresh the syscall at most every 250ms.
datetime CachedAlertBarTime()
{
   static datetime s_bar = 0;
   static uint s_ms = 0;
   uint now = GetTickCount();
   if(s_bar == 0 || now - s_ms >= 250)
   {
      s_bar = iTime(Symbol(), Period(), 0);
      s_ms = now;
   }
   return s_bar;
}

// Anti-spam: per-(bar,level) once (when inpAlertOnce) PLUS a global governor
// so a Monday gap / news spike crossing dozens of levels in one tick cannot
// lock the terminal with 50 popups: max 10 popups per bar, min 800ms apart.
#define ALERT_MAX_PER_BAR 10
#define ALERT_MIN_GAP_MS  800

// Helper function to check if alert should be triggered (prevents spam)
bool ShouldTriggerAlert(const string levelName) {
    datetime currentBarTime = CachedAlertBarTime();

    static datetime s_capBar = 0;
    static int s_capCount = 0;
    static uint s_lastPopupMs = 0;
    if(currentBarTime != s_capBar) { s_capBar = currentBarTime; s_capCount = 0; }

    if(inpAlertOnce) {
        // Same bar and same level, don't trigger
        if(!(currentBarTime > g_lastAlertTime || g_lastAlertLevel != levelName))
            return false;
    }

    uint now = GetTickCount();
    if(s_capCount >= ALERT_MAX_PER_BAR) return false;
    if(s_lastPopupMs != 0 && now - s_lastPopupMs < ALERT_MIN_GAP_MS) return false;

    g_lastAlertTime = currentBarTime;
    g_lastAlertLevel = levelName;
    s_capCount++;
    s_lastPopupMs = now;
    return true;
}

//                                       
void CheckAlerts(const string objectPrefix, double currentPrice) {
    //
    if(objectPrefix == "" || currentPrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("CheckAlerts: Invalid parameters - objectPrefix: ", objectPrefix, ", currentPrice: ", currentPrice);
        #endif
        return;
    }
    
    //                   /            
    // Skip High/Low alerts when Custom Price mode is active
    if(inpEnableHighLowAlerts && g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) {
        if(currentPrice >= g_highestHigh && ShouldTriggerAlert("HistoricalHigh")) {
            if(inpPlaySound) PlaySound(inpAlertSoundFile);
            if(inpSendNotification) SendNotification("Price reached Historical High Level: " + DoubleToString(g_highestHigh, Digits));
            if(inpSendEmail) SendMail("TH Indicator Alert", "Price reached Historical High Level: " + DoubleToString(g_highestHigh, Digits));
            Alert("Price reached Historical High Level: ", g_highestHigh);
        }
        if(currentPrice <= g_lowestLow && ShouldTriggerAlert("HistoricalLow")) {
            if(inpPlaySound) PlaySound(inpAlertSoundFile);
            if(inpSendNotification) SendNotification("Price reached Historical Low Level: " + DoubleToString(g_lowestLow, Digits));
            if(inpSendEmail) SendMail("TH Indicator Alert", "Price reached Historical Low Level: " + DoubleToString(g_lowestLow, Digits));
            Alert("Price reached Historical Low Level: ", g_lowestLow);
        }
    }
    
    //               TH
    if(inpEnableTHAlerts && IsTriggerLevelsEnabled()) {
        string prefix = objectPrefix + "TH_Level_";
        string lineNameMid = prefix + "Mid";
        double midpointLevel = ObjectGetDouble(0, lineNameMid, OBJPROP_PRICE1);
        
        //                
        if(midpointLevel != EMPTY_VALUE && MathAbs(currentPrice - midpointLevel) < GetCachedPoint()) {
            if(ShouldTriggerAlert("MidpointLevel")) {
                if(inpPlaySound) PlaySound(inpAlertSoundFile);
                if(inpSendNotification) SendNotification("Price reached Trigger TH Midpoint Level: " + DoubleToString(midpointLevel, Digits));
                if(inpSendEmail) SendMail("TH Indicator Alert", "Price reached Trigger TH Midpoint Level: " + DoubleToString(midpointLevel, Digits));
                Alert("Price reached Trigger TH Midpoint Level: ", midpointLevel);
            }
        }
        
        //           :                            
        int maxLevelsToCheck = inpMaxLevels;
        maxLevelsToCheck = MathMin(maxLevelsToCheck, 256); //              
        
        for(int stepCount = 1; stepCount <= maxLevelsToCheck; stepCount++) {
            string lineNameAbove = StringFormat("%sTriggerTH_Up_%d", prefix, stepCount);
            if(ObjectFind(0, lineNameAbove) >= 0) {
                double levelAbove = ObjectGetDouble(0, lineNameAbove, OBJPROP_PRICE1);
                if(levelAbove != EMPTY_VALUE && currentPrice >= levelAbove) {
                    string alertKey = StringFormat("TriggerTH_Up_%d", stepCount);
                    if(ShouldTriggerAlert(alertKey)) {
                        if(inpPlaySound) PlaySound(inpAlertSoundFile);
                        string msg = StringFormat("Price reached Trigger TH Level Above %d: %s", stepCount, DoubleToString(levelAbove, Digits));
                        if(inpSendNotification) SendNotification(msg);
                        if(inpSendEmail) SendMail("TH Indicator Alert", msg);
                        Alert("Price reached Trigger TH Level Above: ", levelAbove);
                    }
                }
            }
            
            string lineNameBelow = StringFormat("%sTriggerTH_Down_%d", prefix, stepCount);
            if(ObjectFind(0, lineNameBelow) >= 0) {
                double levelBelow = ObjectGetDouble(0, lineNameBelow, OBJPROP_PRICE1);
                if(levelBelow != EMPTY_VALUE && currentPrice <= levelBelow) {
                    string alertKey = StringFormat("TriggerTH_Down_%d", stepCount);
                    if(ShouldTriggerAlert(alertKey)) {
                        if(inpPlaySound) PlaySound(inpAlertSoundFile);
                        string msg = StringFormat("Price reached Trigger TH Level Below %d: %s", stepCount, DoubleToString(levelBelow, Digits));
                        if(inpSendNotification) SendNotification(msg);
                        if(inpSendEmail) SendMail("TH Indicator Alert", msg);
                        Alert("Price reached Trigger TH Level Below: ", levelBelow);
                    }
                }
            }
        }
    }
}
#endif // ALERT_FUNCTIONS_MQH
