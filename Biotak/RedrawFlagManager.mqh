//+------------------------------------------------------------------+
//|                                           RedrawFlagManager.mqh  |
//|                                  Biotak Trigger TH3 Indicator    |
//|                          Zone and Level Flickering Fix - Task 4  |
//+------------------------------------------------------------------+
//| Redraw Flag Management System                                     |
//| Manages the g_redrawNeeded flag to control when drawing          |
//| operations should occur, preventing unnecessary redraws          |
//| and reducing flickering.                                         |
//|                                                                   |
//| Requirements: 5.1, 5.4, 14.1, 14.2, 14.3, 14.4, 14.5            |
//+------------------------------------------------------------------+

#property strict

//+------------------------------------------------------------------+
//| Check if Redraw is Needed                                        |
//| Returns the current state of the redraw flag                     |
//|                                                                   |
//| Returns:                                                          |
//|   bool - true if redraw is needed, false otherwise               |
//|                                                                   |
//| Requirements: 5.1, 5.4, 14.3, 14.4                              |
//+------------------------------------------------------------------+
bool IsRedrawNeeded() {
    return g_redrawNeeded;
}

//+------------------------------------------------------------------+
//| Set Redraw Flag                                                  |
//| Sets the redraw flag to the specified value                      |
//|                                                                   |
//| Parameters:                                                       |
//|   needed - true to enable redraw, false to disable               |
//|                                                                   |
//| Requirements: 14.1, 14.2                                         |
//+------------------------------------------------------------------+
void SetRedrawFlag(const bool needed) {
    g_redrawNeeded = needed;
}

//+------------------------------------------------------------------+
//| Clear Redraw Flag                                                |
//| Resets the redraw flag to false after a successful draw          |
//| Should be called after the drawing pipeline completes            |
//|                                                                   |
//| Requirements: 5.5, 14.2, 14.5                                    |
//+------------------------------------------------------------------+
void ClearRedrawFlag() {
    g_redrawNeeded = false;
}

//+------------------------------------------------------------------+
//| Request Redraw                                                   |
//| Triggers a redraw on the next OnCalculate invocation             |
//| Used when settings change or other events require redraw         |
//|                                                                   |
//| Requirements: 14.1                                               |
//+------------------------------------------------------------------+
void RequestRedraw() {
    g_redrawNeeded = true;
}

//+------------------------------------------------------------------+
//| Check if Redraw Should Be Skipped                                |
//| Convenience function that returns the inverse of IsRedrawNeeded  |
//| Useful for early-exit patterns in OnCalculate                    |
//|                                                                   |
//| Returns:                                                          |
//|   bool - true if redraw should be skipped, false otherwise       |
//|                                                                   |
//| Requirements: 5.1, 14.3, 14.4                                    |
//+------------------------------------------------------------------+
bool ShouldSkipRedraw() {
    return !g_redrawNeeded;
}

//+------------------------------------------------------------------+
