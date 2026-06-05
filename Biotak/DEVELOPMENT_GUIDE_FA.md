#                               Biotak Trigger TH3

                                                                                                                  .

##  .                  (Level Pipeline)

                                  (Pipeline)                           `LevelPipeline.mqh`                   :
1. **CalculateLevels**:                                      (Step)                 .
2. **ClassifyLevels**:                (      SS  LS               )                        .
3. **BuildZones**:                    (Zones)                   .
4. **DeriveTriggers**:                                    .
5. **Render**:                            .

###                
                                                    :
1.              `ENUM_STEP_CALCULATION_MODE` (     `ConstantsAndEnums.mqh`).
2.                        `ModeDefinitions.mqh` (      `BuildNewModeConfig`).
3.                                `GetModeDefinition`         `ModeDefinitions.mqh`.
4.              (Suffix)              `GetAllModeSuffixes`    `LevelPipeline.mqh`                           .

##  .                 Full   Lite

                                                 `BUILD_LITE`               :

###      Full (    )
-                          : **Profiler**  **Frequency Optimizer**   **TH3 Tool (ABCD)**.
-                                                           .

###      Lite (   )
-              `#define BUILD_LITE`                           `BuildConfig.mqh`            .
-                                                                                                 .
-                 (Inputs)                              .

##  .                 (Validation)

                                                        :
- **                       **:                                     `SafeDivide`                             .
- **            (Object Management)**:                                                                                        .
- **               **:                                                                    (MAX_SAFE_PRICE).
- **Include Guards**:                                                                      .

##  .               

- `Biotak Trigger TH3.mq4`:                    .
- `Biotak Trigger TH3 Lite.mq4`:                   .
- `ModeDefinitions.mqh`:                                        .
- `LevelPipeline.mqh`:                            .
- `BuildConfig.mqh`:                                 (Debug/Production/Lite).

---
*                        Biotak -     *
