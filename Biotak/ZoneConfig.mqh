//+------------------------------------------------------------------+
//|                                              ZoneConfig.mqh       |
//|                       SINGLE OWNER of zone settings               |
//|                                                                   |
//|  Every mode pipeline reads its zone appearance from here:         |
//|    inpShowMidZones           -> enabled                           |
//|    inpMidZoneTransparency    -> transparency (0-100, clamped)     |
//|    inpMidZoneHeightPercent   -> heightPercent (1-100% -> 0.01-1.0)|
//|    inpMidZoneStyle           -> style (Lines/Filled/Empty/Hidden) |
//|    inpMidZoneBorderStyle/Width -> border appearance               |
//|                                                                   |
//|  Consumer: LevelPipeline.mqh -> BuildModeConfig()                 |
//|  This is the ONLY place zone settings are assembled from inputs.  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

#ifndef ZONE_CONFIG_MQH
#define ZONE_CONFIG_MQH

//+------------------------------------------------------------------+
//| ZONE CONFIGURATION STRUCTURE                                     |
//|          Zone                 |                                   |
//+------------------------------------------------------------------+
struct SUnifiedZoneConfig {
    bool enabled;                    //     zone
    int transparency;                //        (0-100)
    double heightPercent;            //             zone         step (0.0-1.0)
    bool separateStructureTrigger;   //     structure   trigger
    color defaultColor;              //
    ENUM_ZONE_STYLE style;           //        zone (Lines/Filled/Empty/Hidden)
    int borderStyle;                 // Box border line style (STYLE_*)
    int borderWidth;                 // Box border width (1-5)
};

//+------------------------------------------------------------------+
//| GET ZONE CONFIGURATION - single source of truth                  |
//|                                                                  |
//| Reads the MidZone input group, clamps values to safe ranges,     |
//| and returns the config consumed by every mode pipeline.          |
//| Height/transparency bounds live in ProjectConstants.mqh          |
//| (MIN_ZONE_HEIGHT_PERCENT / MAX_ZONE_HEIGHT_PERCENT).             |
//+------------------------------------------------------------------+
SUnifiedZoneConfig GetUnifiedZoneConfig()
{
    SUnifiedZoneConfig config;

    // Read from global input parameters with safe defaults
    config.enabled = inpShowMidZones;

    // Validate and clamp transparency
    config.transparency = inpMidZoneTransparency;
    if(config.transparency < 0) config.transparency = 0;
    if(config.transparency > 100) config.transparency = 100;

    // GOLD VERSION: Use configurable zone height from input parameter
    // Convert from percentage (1-100) to decimal (0.01-1.0)
    double heightPercentInput = inpMidZoneHeightPercent / 100.0;

    // Validate and clamp height percent (bounds from ProjectConstants.mqh)
    if(heightPercentInput < MIN_ZONE_HEIGHT_PERCENT) {
        heightPercentInput = MIN_ZONE_HEIGHT_PERCENT;
        #ifdef ENABLE_DEBUG_LOGS
        Print("   GetUnifiedZoneConfig: Zone height too small, clamped to ",
              MIN_ZONE_HEIGHT_PERCENT * 100, "%");
        #endif
    }
    if(heightPercentInput > MAX_ZONE_HEIGHT_PERCENT) {
        heightPercentInput = MAX_ZONE_HEIGHT_PERCENT;
        #ifdef ENABLE_DEBUG_LOGS
        Print("   GetUnifiedZoneConfig: Zone height too large, clamped to ",
              MAX_ZONE_HEIGHT_PERCENT * 100, "%");
        #endif
    }

    config.heightPercent = heightPercentInput;

    config.separateStructureTrigger = true;
    config.defaultColor = clrDarkGray;

    // GOLD VERSION: Add style support
    config.style = inpMidZoneStyle;

    // Box border style/width from inputs (solid/dashed/dotted hollow or filled boxes)
    config.borderStyle = inpMidZoneBorderStyle;
    config.borderWidth = inpMidZoneBorderWidth;

    return config;
}

#endif // ZONE_CONFIG_MQH