#               Biotak Trigger TH3

##         

**Biotak Trigger TH3**                     MetaTrader 4                   TH (Time Harmonic)                                         .

**         :** 3.04 - Performance & Memory Audit Complete

---

##             

###               

```
    Biotak Trigger TH3.mq4          #                    
    Biotak Trigger TH3.ex4          #                 
    Biotak/                          #               
        Configuration/               #                   
        Core/                        #                  
        UI/                          #                    
        Events/                      #                
        Tests/                       #               
```

###                

```
Event Handlers   UI/Visualization   Core Logic   Configuration
```

                                       .                             UI       .

---

##               

### 1.                      
- **PropertiesAndInputs.mqh** -                                     
- **ConstantsAndEnums.mqh** -          enum                     
- **GlobalVariables.mqh** -                               

### 2.            
- **THCalculations.mqh** -                          TH
- **BasePriceManager.mqh** -                                   30      
- **TimeframeFunctions.mqh** -                     
- **FractalTimeframes.mqh** -                          
- **StandardTimeframes.mqh** -                               

### 3.                    
- **ObjectFunctions.mqh** -                          
- **ObjectManager.mqh** -                       
- **LabelFunctions.mqh** -                             
- **ExtendedDrawingFunctions.mqh** -                  
- **DynamicColorFunctions.mqh** -                   

### 4.                
- **EventHandlers.mqh** -                           
- **EventHandlers_DEBUG.mqh** -                                

### 5.                   
- **UtilityFunctions.mqh** -                 
- **HistoricalDataFunctions.mqh** -                       
- **AlertFunctions.mqh** -            
- **PerformanceMonitor.mqh** -                           

### 6.                       
- **MarketHoursDetector.mqh** -                     
- **DynamicTradingDayDetector.mqh** -                          
- **BasePriceHistoryManager.mqh** -                         
- **GlobalVariablesManager.mqh** -                         

---

##              

### 1.            TH (Time Harmonic)

                                                :

```
TH = (BasePrice   Percentage) / 100
```

**         :**
- **BasePrice:**           (               30      )
- **Percentage:**                               

**    :**
```
    BasePrice = 1.10000   Percentage = 2.08% (M1)
TH = (1.10000   2.08) / 100 = 0.02288
```

---

### 2.                          

                                   :

|           |             |      (%) |
|----------|-------------|----------|
| M1 | M1 | 2.08 |
| M5 | M4 | 4.17 |
| M15/M30 | M16 | 8.33 |
| H1 | H1+M4 | 16.67 |
| H4 | H4+M16 | 33.33 |
| D1 | H17+M4 | 70.83 |
| W1 | D11+H9+M4 | 500.00 |
| MN1 | D45+H12+M16 | 2083.33 |

**    :**                                                                     .

---

### 3.                 

                  -                      :
- **     **                          
- **      **                            

```
Structure = TH (              )
Pattern = 0.5   Structure (          )
Trigger = 0.25   Structure (               )
```

**         M15:**
```
Structure = M15 TH = 0.08330
Pattern = 0.08330   0.5 = 0.04165 (      ~H1 trigger)
Trigger = 0.08330   0.25 = 0.02083 (      ~M4 structure)
```

---

### 4.                        

#### Short Step (SS)   Long Step (LS)
```
SS = Structure   1.5
LS = Structure   2.0
```

#### Control (C)
```
Control = (SS + LS) / 2 = Structure   1.75
```

#### M Distance
```
M = Control   3 = Structure   5.25
```

#### E Step   TP
```
E = Structure   0.75
TP = E   3 = Structure   2.25
```

**         :**
```
    Structure = 0.08330 (M16)
SS = 0.08330   1.5 = 0.12495
LS = 0.08330   2.0 = 0.16660
Control = 0.08330   1.75 = 0.14578
M = 0.08330   5.25 = 0.43733
E = 0.08330   0.75 = 0.06248
TP = 0.08330   2.25 = 0.18743
```

---

### 5.                  (Base Price)

####                     
- **      :**    30       (         00:00  00:30  01:00  ...)
- **         :**                     M30
- **    :**            GMT/UTC             

####                     

```
1.    30       (         00    30):
   -                                 M30
   
2.        M1 Power:
   M1_Power = BasePrice   0.0208
   
3.             :
   Delta% = |M1_New - M1_Old| / |M1_Old|   100
   
4.              (Threshold):
       Delta% >= 0.066%:
        ACCEPT:             BasePrice
        :
        SKIP:           BasePrice     
```

####          

```
    : 14:30 GMT
M30 Close (14:00-14:30): 1.10250
BasePrice     : 1.10000

      :
M1_Old = 1.10000   0.0208 = 0.022880
M1_New = 1.10250   0.0208 = 0.023012
Delta% = |0.023012 - 0.022880| / 0.022880   100 = 0.577%

     : 0.577% >= 0.066%     ACCEPT
BasePrice      = 1.10250
```

####            (Sanity Check)

                                :
```
    |RestoredPrice - CurrentBid| / CurrentBid   100 > 10%:
      REJECT:            Bid     
     :
     ACCEPT:                            
```

---

### 6.                  ATR

#### Weighted ATR
                 6           :

```
ATR = (ATR  1 + ATR   1 + ATR   2 + ATR   3 + ATR    5 + ATR    8) / 20
```

**      :**
- ATR :     1
- ATR  :     1
- ATR  :     2
- ATR  :     3
- ATR   :     5
- ATR   :     8
- **     :** 20

#### True Range (TR)
```
TR = max(High - Low, |High - PrevClose|, |Low - PrevClose|)
```

#### Hybrid ATR
                        :
```
ATR_target = ATR_current    (target_minutes / current_minutes)
```

**    :**
```
ATR_H1 = 0.00150
       ATR_H4:
ATR_H4 = 0.00150    (240 / 60) = 0.00150   2 = 0.00300
```

####                 ATR
```
Structure = Weighted ATR
Pattern = Structure   0.5
Trigger = Structure   0.25
```

---

### 7.                  

####                                   

|           |         |       |
|----------|---------|-------|
| M1 | M1 | 1 |
| M5 | M4 | 4 |
| M15 | M16 | 16 |
| M30 | M16 | 16 |
| H1 | H1+M4 | 64 |
| H4 | H4+M16 | 256 |
| D1 | H17+M4 | 1024 |
| W1 | D11+H9+M4 | 16384 |
| MN1 | D45+H12+M16 | 65536 |

####              
```
"H1+M4"   "H1.4"
"H4+M16"   "H4.16"
"D11+H9+M4"   "D11.9.4"
```

---

### 8.              (L1-L5)

                                      :

```
L1 =               
L2 =               (4          )
L3 =               (16          )
L4 =               (64          )
L5 =                 (256          )
```

**         M15:**
```
L1 = M16 (16      )
L2 = H1+M4 (64      )
L3 = H4+M16 (256      )
L4 = H17+M4 (1024      )
L5 = D11+H9+M4 (16384      )
```

####                (Overlap)
```
    Step % Interval[L] == 0:
       Step        L              
```

**    :**
```
    Interval[L1]=2, Interval[L2]=6, Interval[L3]=18
Step 6:             L1+L2
Step 18:             L1+L2+L3
```

---

### 9. Shared Pattern Step

      SS                :

```
Shared Pattern Step = Current_SS + Higher_Pattern_SS
```

**          :**
```
Current_SS = (2   Current_Structure) - Current_Pattern
Higher_Pattern_SS = (2   Higher_Structure) - Higher_Pattern
Shared_Step = Current_SS + Higher_Pattern_SS
```

**    :**
```
Current (M16): Structure=0.0833, Pattern=0.0417
Higher (H1.4): Structure=0.1667, Pattern=0.0833

Current_SS = (2   0.0833) - 0.0417 = 0.1249
Higher_SS = (2   0.1667) - 0.0833 = 0.2501
Shared_Step = 0.1249 + 0.2501 = 0.3750
```

---

### 10.                

####            TH
```
         :
- lastPrice:                      
- lastDigits:                  
- lastPercentage:                 
- lastResult:             
- lastCacheTime:                       

                 :
|price - lastPrice| < tolerance
AND digits == lastDigits
AND percentage == lastPercentage

tolerance = price   0.0000001 (0.00001%)
```

####    ATR
```
         :
- weightedATR:       ATR        
- lastUpdate:                       
- barCount:              
- cachedTimeframe:                 
- valid:              

                 :
|barCount - cachedBarCount| <= 1
AND (currentTime - lastUpdate) < 30 seconds
AND timeframe == cachedTimeframe
```

####                 (Batch)
```
          :        TR                                 

1.        TR      264          
2.                   ATR , ATR  , ..., ATR   
3.                 O(n m)    O(n+m)
```

---

##                

###            TH
-                                          
-                           : TH_BASIS, ATR_BASIS
-                             (L1-L5)

###                 
-                                 30      
-                                  
-                            

###                
-                   OnCalculate (      < 100ms         < 500ms)
-                      (        MT4: ~64K)
-                            TTL

###            
-                                       TH
-                    

---

##            

###              
- **      :** MetaTrader 4 (MT4)
- **    :** MQL4 (MetaQuotes Language 4)
- **             :** `.mq4` (             ), `.mqh` (         include), `.ex4` (                    )

###           
- **        :** MetaEditor (      MT4)
- **       :**                             `.mq4`
- **     :**                       `.ex4`

###             

####            MetaEditor
```
F7 -                  
F5 -                   Strategy Tester
Ctrl+F5 -           
```

####        
```
#                    MT4:
#            : MT4_Data_Folder/MQL4/Indicators/
#          Include: MT4_Data_Folder/MQL4/Include/
```

---

##              

###      SOLID      MQL4
- **S**ingle Responsibility:         `.mqh`                     
- **O**pen/Closed:                                                    
- **L**iskov Substitution:                                         
- **I**nterface Segregation:                                            
- **D**ependency Inversion:                                           

###              
- **Manager Pattern:** BasePriceManager, ObjectManager
- **Factory Functions:**             (              )
- **Event Handler:** OnInit, OnCalculate, OnChartEvent

---

##                  

###            
```
Memory Cache (         static) < 1ms 
  Global Variables < 10ms 
              < 100ms
```

###               MT4
-                         TH
-                 /         
-                     static                      
-                                               

---

##       

###              MQL4
```
         (                      )
 
                (                    )
 
        Property-Based (                           )
```

###              
- `TestBasePriceHistoryManager.mqh` -                      
- `TestBasePriceValidation.mqh` -                         
- `TestFindLastM1CandleInBlock.mqh` -              
- `TestMergeHistoryLists.mqh` -                  
- `TestMultiChartSupport.mqh` -                     
- `TestRebuildProperties.mqh` -                     

---

##                   

###     
- **                :**                      (                     )
- **            :**                          
- **           :**                       OnDeinit

###                    
-                                  (> 0              )
-                                   
-                                    
-                                  
-                                   

---

##           

###         
```
L0:                                      TH
L1:                                 
L2:                                /      
L3:                                                
```

###            
- **Fail Fast:**                                 OnInit
- **Graceful Degradation:**                                     
- **Safe Defaults:**            EMPTY_VALUE                     

---

##                      

###      
-            (              TH            )
-        3-4        
-        30                 MQL4
-                         

###                      (    MQL4)
- **     :** `CalculateTHLevel()`, `DrawHorizontalLine()`
- **       :**        `g_`              `inp`              
- **       :** `UPPER_CASE`                  
- **       :** `PascalCase.mqh`

---

##                    MT4

- **             :** ~64K       
- **            :**                       
- **      :**             async
- **          :** OnCalculate               

---

##           

###                
1. **   :**                 /                         
2. **     :**               `.mqh`                 
3. **     :**                                  
4. **          :**                                       

###               
-                     static        
-                         Print()         
-                     
-                                   
-                                     

---

##               

###               
                  :
-            `.mqh`             
-                           
-                            
-         property-based           

###             
1.                   
2.                          
3.             
4.             
5.          

---

##                 

###        
-         :               
- `README.md`:                  
-             :                      

###               
- MetaEditor: IDE      MT4
- Strategy Tester:              
- Performance Monitor:                

---

**                 :**      3.04
**     :**                      
