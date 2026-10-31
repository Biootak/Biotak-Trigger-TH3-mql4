//+------------------------------------------------------------------+
//|                                            Runtime_Save.mqh      |
//|  P-SESS-36 (2026-10-31) — THE SAVER OF THE PERSISTED OVERRIDES.   |
//|                                                                  |
//|  ONE OWNER, split out of Runtime_A.mqh at the P-SIZE-1500 ceiling |
//|  (contract §7): the throttle, the owe it raises and the drain    |
//|  that spends it. Nothing else lives here, and no caller changed: |
//|  RuntimeSettings.mqh includes this file beside Runtime_A, so the |
//|  name every panel/palette path already calls still resolves.     |
//+------------------------------------------------------------------+
#ifndef RUNTIME_SAVE_MQH
#define RUNTIME_SAVE_MQH

//--- throttled saver (panel/palette drags fire per mouse-move)
//
// A THROTTLE THAT DROPS IS A LOST CLICK. MEASURED on the live chart: the sessions
// switch on the RING still saved through this function while the card's own rows
// had already been moved to the immediate save (P-SESS-34). A switch that landed
// inside the 500 ms window was therefore DROPPED, the store kept the old value,
// and the next attach — which in MT4 is EVERY TIMEFRAME SWITCH
// (OnDeinit(REASON_CHARTCHANGE) then OnInit) — loaded that old value: the sessions
// were wiped by the OFF branch of SessionsTick and never came back.
// «تایم عوض میکنم سشن‌ها حذف میشن و برنمیگردن» is this one line.
//
// The window is still worth keeping (a drag really IS a stream of events), so the
// write is DEFERRED instead of discarded: a call inside the window raises an OWE,
// and `RuntimeSettingsSaveDrain()` spends it. The drain rides the 250 ms session
// tick and — the one that matters — the deinit, i.e. before the next attach reads
// the store back. Cost in steady state: one bool test per tick, one per click.
#define RUNTIME_SAVE_THROTTLE_MS 500
static uint s_saveThrottleMs = 0;
static bool s_saveOwed = false;

void RuntimeSettingsSaveOverridesThrottled()
{
   uint now = GetTickCount();
   if(now - s_saveThrottleMs < RUNTIME_SAVE_THROTTLE_MS) { s_saveOwed = true; return; }
   s_saveThrottleMs = now;
   s_saveOwed = false;
   RuntimeSettingsSaveOverrides();
}

bool RuntimeSettingsSaveOwed() { return s_saveOwed; }

void RuntimeSettingsSaveDrain()
{
   if(!s_saveOwed) return;
   s_saveOwed = false;
   s_saveThrottleMs = GetTickCount();
   RuntimeSettingsSaveOverrides();
}

#endif // RUNTIME_SAVE_MQH
