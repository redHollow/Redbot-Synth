//+------------------------------------------------------------------+
//|                                           RedBot_Sniper_v50.mq5   |
//|                                                    Red Bot v5.0   |
//|     H1 Zone Sniper + D1 Trend + M5 Entry Timing                  |
//+------------------------------------------------------------------+
#property copyright "RedBot"
#property version   "5.00"
#property description "v5.0 H1 Sniper - Fewer trades, bigger moves"

//+------------------------------------------------------------------+
//| Inputs                                                             |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double RiskPerPosition   = 2.0;      // Max loss as % of balance
input double MaxLotSize        = 0.50;
input double MinLotSize        = 0.01;

input group "=== ATR SL/TP (H1 ATR — Sniper Mode) ==="
input int    ATR_Period        = 14;
input double SL_ATR_Mult      = 1.5;      // SL = H1 ATR x this (with bias)
input double TP_RR_Ratio      = 1.5;      // TP = SL x this (with bias) → 1.5x1.5 = 2.25x ATR
input double SL_ATR_Against   = 0.75;     // SL = H1 ATR x this (against bias)
input double TP_ATR_Against   = 1.0;      // TP = H1 ATR x this (against bias)

input group "=== Hybrid Mode (ADX Auto-Switch) ==="
input bool   UseHybridMode    = true;
input int    ADX_Period        = 14;
input double ADX_Sniper_Thresh = 25.0;    // Above this = sniper mode (trending)
input double ADX_Scalp_Thresh  = 20.0;    // Below this = scalp mode (choppy)
input double ScalpProfitTarget = 15.0;    // $15 total profit target in scalp mode
input double ScalpSL_ATR_Mult  = 1.5;     // Scalp SL = M5 ATR x this

input group "=== BE Protection & Trailing ==="
input bool   UseBELock         = true;
input double BE_Lock_Pct       = 1.0;      // Move SL to entry when profit hits this % of balance
input bool   UseTrailing       = true;
input double Trail_ATR_Mult    = 1.0;      // Trail distance = H1 ATR x this
input double Trail_Activate_Pct = 0.5;     // Activate trailing after this % of TP distance reached

input group "=== Time Filter ==="
input bool   UseTimeFilter     = true;
input int    TradeStartHour    = 8;
input int    TradeEndHour      = 17;
input bool   SkipSunday        = true;

input group "=== Cooldown ==="
input bool   UseCooldown       = true;
input int    CooldownAfterLosses = 2;
input int    CooldownBars      = 40;
input bool   UseDailySymbolLimit = true;
input double MaxDailySymbolLoss = 20.0;
input bool   SkipAfterFirstLoss = true;    // Skip symbol for day after first loss

input group "=== H1 Zone Settings ==="
input int    H1_ZoneLookback   = 50;
input int    H1_SwingStrength  = 3;
input int    H1_MaxZoneTouches = 2;        // Fewer touches = fresher zone
input double H1_ZoneTolerance  = 0.3;      // ATR multiplier for zone proximity

input group "=== M5 Entry Confirmation ==="
input bool   UseEngulfing      = true;
input bool   UseOrderBlocks    = true;
input bool   UsePinBar         = true;
input double MinEngulfRatio    = 1.3;
input double MinPinWickRatio   = 2.0;
input double MinCandleBodyATR  = 0.15;

input group "=== Stochastic Filter ==="
input bool   UseStochFilter    = true;
input int    Stoch_K           = 5;
input int    Stoch_D           = 8;
input int    Stoch_Slowing     = 8;
input double Stoch_SellLevel   = 55.0;
input double Stoch_BuyLevel    = 45.0;

input group "=== D1 Trend ==="
input int    EMA_Fast          = 7;
input int    EMA_Mid           = 21;

input group "=== GainX/PainX ==="
input bool   AutoDetectBias    = false;    // OFF - D1 trend decides direction
input bool   UseSpreadFilter   = true;
input double MaxSpreadATR      = 0.3;

input group "=== General ==="
input int    MagicNumber       = 234567;
input bool   ShowDashboard     = true;
input bool   LogSignalScans    = true;
input bool   EnablePushNotify  = true;
input bool   EnablePopupAlert  = true;

//+------------------------------------------------------------------+
//| Structures & Globals                                               |
//+------------------------------------------------------------------+
struct PriceZone
{
   double   priceHigh;
   double   priceLow;
   datetime timeFormed;
   int      barIndex;
   int      touches;
   int      zoneType;     // 1 = demand, -1 = supply
   bool     active;
};

// H1 zones - PRIMARY
PriceZone h1Zones[];
int h1TotalZones = 0;
int h1MaxZones = 20;

// Indicator handles
int handleATR_M5, handleStoch;
int handleATR_H1;
int handleD1_EMA_Fast, handleD1_EMA_Mid;
int handleADX_H1;
double atrM5[], stochMain[], stochSignal[];
double atrH1[];
double d1EmaFast[], d1EmaMid[];

// State
datetime lastBarTime = 0;
int stopsLevel = 0;
int activeMagic = 0;
bool isBuyOnly = false;
bool isSellOnly = false;
string symbolType = "UNKNOWN";
int naturalBias = 0;  // 1 = PainX (natural BUY), -1 = GainX (natural SELL), 0 = unknown

int winTrades = 0;
int lossTrades = 0;
int barsSinceLastTrade = 0;
int totalBarsScanned = 0;
int consecutiveLosses = 0;
int cooldownBarsLeft = 0;
bool profitBELocked = false;
double dailySymbolPnL = 0;
datetime dailySymbolResetDate = 0;
bool symbolBlockedToday = false;

string mtfD1Status = "?";
string lastSignalType = "";
double adxH1[];
int    currentMode = 0;   // 0 = sniper, 1 = scalp
string modeLabel = "SNIPER";
double dailyStartBalance = 0;
datetime dailyResetDate = 0;

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // M5 indicators
   handleATR_M5 = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   handleStoch  = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   
   // H1 ATR for SL/TP
   handleATR_H1 = iATR(_Symbol, PERIOD_H1, ATR_Period);
   
   // D1 trend
   handleD1_EMA_Fast = iMA(_Symbol, PERIOD_D1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleD1_EMA_Mid  = iMA(_Symbol, PERIOD_D1, EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
   
   // ADX for hybrid mode detection
   handleADX_H1 = iADX(_Symbol, PERIOD_H1, ADX_Period);
   
   if(handleATR_M5 == INVALID_HANDLE || handleStoch == INVALID_HANDLE ||
      handleATR_H1 == INVALID_HANDLE ||
      handleD1_EMA_Fast == INVALID_HANDLE || handleD1_EMA_Mid == INVALID_HANDLE ||
      (UseHybridMode && handleADX_H1 == INVALID_HANDLE))
   {
      Print("ERROR: Indicator init failed!");
      return(INIT_FAILED);
   }
   
   ArraySetAsSeries(atrM5, true);
   ArraySetAsSeries(stochMain, true);
   ArraySetAsSeries(stochSignal, true);
   ArraySetAsSeries(atrH1, true);
   ArraySetAsSeries(d1EmaFast, true);
   ArraySetAsSeries(d1EmaMid, true);
   ArraySetAsSeries(adxH1, true);
   ArrayResize(h1Zones, h1MaxZones);
   
   stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   // Auto-detect symbol direction
   if(AutoDetectBias)
   {
      string sn = _Symbol;
      StringToUpper(sn);
      if(StringFind(sn, "GAINX") >= 0 || StringFind(sn, "GAIN_X") >= 0)
      {
         isSellOnly = true;
         naturalBias = -1;
         symbolType = "GainX (SELL only)";
      }
      else if(StringFind(sn, "PAINX") >= 0 || StringFind(sn, "PAIN_X") >= 0)
      {
         isBuyOnly = true;
         naturalBias = 1;
         symbolType = "PainX (BUY only)";
      }
      else
      {
         naturalBias = 0;
         symbolType = "BI-DIR (D1 decides)";
      }
   }
   else
   {
      // Bi-directional but still detect natural bias for TP adjustment
      string sn = _Symbol;
      StringToUpper(sn);
      if(StringFind(sn, "GAINX") >= 0 || StringFind(sn, "GAIN_X") >= 0)
         naturalBias = -1;  // Natural SELL
      else if(StringFind(sn, "PAINX") >= 0 || StringFind(sn, "PAIN_X") >= 0)
         naturalBias = 1;   // Natural BUY
      else
         naturalBias = 0;
      symbolType = "BI-DIR (D1 decides)";
   }
   
   // Compute magic number per symbol
   activeMagic = MagicNumber;
   for(int i = 0; i < StringLen(_Symbol); i++)
      activeMagic += StringGetCharacter(_Symbol, i) * (i + 1);
   
   // Print startup info
   Print("=== RedBot v5.0 H1 HYBRID ===");
   Print("Symbol: ", _Symbol, " | Mode: ", symbolType);
   Print("Strategy: H1 Zones → M5 Entry → D1 Trend | BI-DIRECTIONAL");
   if(UseHybridMode)
   {
      Print("HYBRID MODE: ADX > ", DoubleToString(ADX_Sniper_Thresh, 0), " = SNIPER | ADX < ", DoubleToString(ADX_Scalp_Thresh, 0), " = SCALP");
      Print("Sniper: SL ", DoubleToString(SL_ATR_Mult, 1), "x H1 ATR | TP ", DoubleToString(TP_RR_Ratio, 1), ":1");
      Print("Scalp:  SL ", DoubleToString(ScalpSL_ATR_Mult, 1), "x M5 ATR | TP $", DoubleToString(ScalpProfitTarget, 2));
   }
   else
   {
      Print("With bias:    SL ", DoubleToString(SL_ATR_Mult, 2), "x ATR | TP ", DoubleToString(SL_ATR_Mult * TP_RR_Ratio, 2), "x ATR (", DoubleToString(TP_RR_Ratio, 1), ":1)");
      Print("Against bias: SL ", DoubleToString(SL_ATR_Against, 2), "x ATR | TP ", DoubleToString(TP_ATR_Against, 2), "x ATR");
   }
   Print("Risk: ", DoubleToString(RiskPerPosition, 1), "% per position | 3 positions per signal");
   Print("BE Lock: ", DoubleToString(BE_Lock_Pct, 1), "%");
   if(UseTrailing)
      Print("Trailing: ", DoubleToString(Trail_ATR_Mult, 1), "x H1 ATR | Activates at ", 
            DoubleToString(Trail_Activate_Pct * 100, 0), "% of TP");
   else
      Print("Trailing: OFF - let TP/SL play out");
   if(UseTimeFilter)
      Print("Time: ", TradeStartHour, ":00 - ", TradeEndHour, ":00 | Sunday: ", (SkipSunday ? "OFF" : "ON"));
   if(UseCooldown)
      Print("Cooldown: ", CooldownBars, " bars after ", CooldownAfterLosses, " losses");
   if(SkipAfterFirstLoss)
      Print("Skip after first loss: ON (symbol blocked for day)");
   Print("Stoch: BUY<=", Stoch_BuyLevel, " SELL>=", Stoch_SellLevel);
   Print("==============================");
   
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyResetDate = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleATR_M5 != INVALID_HANDLE) IndicatorRelease(handleATR_M5);
   if(handleStoch != INVALID_HANDLE)  IndicatorRelease(handleStoch);
   if(handleATR_H1 != INVALID_HANDLE) IndicatorRelease(handleATR_H1);
   if(handleD1_EMA_Fast != INVALID_HANDLE) IndicatorRelease(handleD1_EMA_Fast);
   if(handleD1_EMA_Mid != INVALID_HANDLE)  IndicatorRelease(handleD1_EMA_Mid);
   if(handleADX_H1 != INVALID_HANDLE)     IndicatorRelease(handleADX_H1);
   ObjectsDeleteAll(0, "RB_");
   Comment("");
   Print("RedBot v5.0 stopped. W:", winTrades, " L:", lossTrades);
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - Track wins/losses                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   
   long dealMagic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   long dealEntry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long dealReason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string dealSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   
   if(dealMagic != activeMagic || dealSymbol != _Symbol || dealEntry != DEAL_ENTRY_OUT) return;
   
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   
   if(dealReason == DEAL_REASON_SL)
   {
      lossTrades++;
      dailySymbolPnL += profit;
      consecutiveLosses++;
      
      // Skip after first loss
      if(SkipAfterFirstLoss)
      {
         symbolBlockedToday = true;
         Print("SYMBOL BLOCKED: ", _Symbol, " first loss today - no more trades until tomorrow");
      }
      
      // Cooldown
      if(UseCooldown && consecutiveLosses >= CooldownAfterLosses)
      {
         cooldownBarsLeft = CooldownBars;
         Print("COOLDOWN: ", CooldownBars, " bars after ", consecutiveLosses, " consecutive losses");
         consecutiveLosses = 0;
      }
      
      Print("X SL: $", DoubleToString(profit, 2), " DayPnL:", DoubleToString(dailySymbolPnL, 2));
      NotifyTrade(profit);
   }
   else if(dealReason == DEAL_REASON_TP)
   {
      winTrades++;
      dailySymbolPnL += profit;
      consecutiveLosses = 0;
      profitBELocked = false;
      Print("V TP: $", DoubleToString(profit, 2), " DayPnL:", DoubleToString(dailySymbolPnL, 2));
      NotifyTrade(profit);
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(ShowDashboard) UpdateDashboard();
   CheckDailyReset();
   if(UseBELock) CheckBELock();
   if(UseTrailing) ManageTrailingStop();
   if(UseHybridMode && currentMode == 1) CheckScalpProfitTarget();
   
   if(!IsNewBar()) return;
   if(!GetIndicatorData()) return;
   
   // Detect market mode via ADX
   if(UseHybridMode && ArraySize(adxH1) > 0)
   {
      double adx = adxH1[0];
      int prevMode = currentMode;
      if(adx >= ADX_Sniper_Thresh)
      {
         currentMode = 0;
         modeLabel = "SNIPER";
      }
      else if(adx <= ADX_Scalp_Thresh)
      {
         currentMode = 1;
         modeLabel = "SCALP";
      }
      // Between thresholds: keep current mode
      
      if(currentMode != prevMode)
         Print("MODE SWITCH: ", (currentMode == 0 ? "SNIPER" : "SCALP"), " (ADX:", DoubleToString(adx, 1), ")");
   }
   
   
   
   // Scan H1 zones every bar
   ScanH1Zones();
   
   // Log scan
   if(LogSignalScans) LogBarScan();
   
   // === ENTRY CHECKS ===
   
   // Already in a trade?
   if(CountOpenTrades() >= 3) return;
   
   // Min bars between trades
   barsSinceLastTrade++;
   if(barsSinceLastTrade < 3) return;
   
   // Symbol blocked after loss today?
   if(symbolBlockedToday) return;
   
   // Cooldown active?
   if(UseCooldown && cooldownBarsLeft > 0)
   {
      cooldownBarsLeft--;
      if(cooldownBarsLeft == 0)
         Print("COOLDOWN ended");
      return;
   }
   
   // Time filter
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(SkipSunday && dt.day_of_week == 0) return;
      if(dt.hour < TradeStartHour || dt.hour >= TradeEndHour) return;
   }
   
   // Daily symbol loss limit
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today != dailySymbolResetDate)
   {
      dailySymbolPnL = 0;
      dailySymbolResetDate = today;
      symbolBlockedToday = false;  // Reset daily block
   }
   if(UseDailySymbolLimit && dailySymbolPnL <= -MaxDailySymbolLoss) return;
   
   // Spread filter
   if(UseSpreadFilter)
   {
      double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(spread > atrM5[1] * MaxSpreadATR) return;
   }
   
   // === SIGNAL DETECTION ===
   int signal = GetH1ZoneSignal();
   
   if(signal == 1 && !isSellOnly)
      ExecuteTrade(ORDER_TYPE_BUY);
   else if(signal == -1 && !isBuyOnly)
      ExecuteTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Utility Functions                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t != lastBarTime) { lastBarTime = t; return true; }
   return false;
}

bool GetIndicatorData()
{
   if(CopyBuffer(handleATR_M5, 0, 0, 5, atrM5) < 5) return false;
   if(CopyBuffer(handleStoch, 0, 0, 5, stochMain) < 5) return false;
   if(CopyBuffer(handleStoch, 1, 0, 5, stochSignal) < 5) return false;
   if(CopyBuffer(handleATR_H1, 0, 0, 3, atrH1) < 3) return false;
   if(CopyBuffer(handleD1_EMA_Fast, 0, 0, 3, d1EmaFast) < 3) return false;
   if(CopyBuffer(handleD1_EMA_Mid, 0, 0, 3, d1EmaMid) < 3) return false;
   if(UseHybridMode)
   {
      if(CopyBuffer(handleADX_H1, 0, 0, 3, adxH1) < 3) return false;
   }
   return true;
}

int CountOpenTrades()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == activeMagic)
         c++;
   return c;
}

//+------------------------------------------------------------------+
//| D1 Trend Confirmation                                              |
//+------------------------------------------------------------------+
bool D1ConfirmsBuy()
{
   if(d1EmaFast[0] > d1EmaMid[0])
   {
      mtfD1Status = "BULL";
      return true;
   }
   mtfD1Status = "BEAR";
   return false;
}

bool D1ConfirmsSell()
{
   if(d1EmaFast[0] < d1EmaMid[0])
   {
      mtfD1Status = "BEAR";
      return true;
   }
   mtfD1Status = "BULL";
   return false;
}

//+------------------------------------------------------------------+
//| H1 Zone Scanner                                                    |
//+------------------------------------------------------------------+
void ScanH1Zones()
{
   // Reset zones
   for(int z = 0; z < h1TotalZones; z++)
      h1Zones[z].active = false;
   h1TotalZones = 0;
   
   if(ArraySize(atrH1) < 1 || atrH1[0] == 0) return;
   double atr = atrH1[0];
   
   int bars = Bars(_Symbol, PERIOD_H1);
   int look = MathMin(H1_ZoneLookback, bars - 1);
   if(look < H1_SwingStrength * 2 + 3) return;
   
   for(int i = H1_SwingStrength + 1; i < look - H1_SwingStrength; i++)
   {
      if(h1TotalZones >= h1MaxZones) break;
      
      double h = iHigh(_Symbol, PERIOD_H1, i);
      double l = iLow(_Symbol, PERIOD_H1, i);
      double o = iOpen(_Symbol, PERIOD_H1, i);
      double c = iClose(_Symbol, PERIOD_H1, i);
      
      // === SUPPLY ZONE (Swing High) ===
      bool isSwingHigh = true;
      for(int j = 1; j <= H1_SwingStrength; j++)
      {
         if(iHigh(_Symbol, PERIOD_H1, i - j) >= h || iHigh(_Symbol, PERIOD_H1, i + j) >= h)
         { isSwingHigh = false; break; }
      }
      if(isSwingHigh)
      {
         double zt = h;
         double zb = MathMax(o, c);
         if((zt - zb) < atr * 0.1) zb = zt - atr * 0.5;
         if(!H1ZoneExists(zt, zb, -1, atr))
            AddH1Zone(zt, zb, -1, i, atr);
      }
      
      // === DEMAND ZONE (Swing Low) ===
      bool isSwingLow = true;
      for(int j = 1; j <= H1_SwingStrength; j++)
      {
         if(iLow(_Symbol, PERIOD_H1, i - j) <= l || iLow(_Symbol, PERIOD_H1, i + j) <= l)
         { isSwingLow = false; break; }
      }
      if(isSwingLow)
      {
         double zb = l;
         double zt = MathMin(o, c);
         if((zt - zb) < atr * 0.1) zt = zb + atr * 0.5;
         if(!H1ZoneExists(zt, zb, 1, atr))
            AddH1Zone(zt, zb, 1, i, atr);
      }
   }
   
   // Also scan for H1 order blocks
   ScanH1OrderBlocks(atr, look);
   
   // Count zone touches and deactivate overused zones
   UpdateH1ZoneTouches(atr);
}

void ScanH1OrderBlocks(double atr, int look)
{
   for(int i = 3; i < look - 2; i++)
   {
      if(h1TotalZones >= h1MaxZones) break;
      
      double o = iOpen(_Symbol, PERIOD_H1, i);
      double c = iClose(_Symbol, PERIOD_H1, i);
      double h = iHigh(_Symbol, PERIOD_H1, i);
      double l = iLow(_Symbol, PERIOD_H1, i);
      double on = iOpen(_Symbol, PERIOD_H1, i - 1);
      double cn = iClose(_Symbol, PERIOD_H1, i - 1);
      
      // Bearish candle followed by strong bullish = demand OB
      if((c < o) && ((cn - on) > atr * 0.8))
      {
         double zt = MathMax(o, c);
         double zb = l;
         if(!H1ZoneExists(zt, zb, 1, atr))
            AddH1Zone(zt, zb, 1, i, atr);
      }
      // Bullish candle followed by strong bearish = supply OB
      if((c > o) && ((on - cn) > atr * 0.8))
      {
         double zt = h;
         double zb = MathMin(o, c);
         if(!H1ZoneExists(zt, zb, -1, atr))
            AddH1Zone(zt, zb, -1, i, atr);
      }
   }
}

bool H1ZoneExists(double t, double b, int type, double atr)
{
   double tol = atr * 0.3;
   for(int i = 0; i < h1TotalZones; i++)
   {
      if(!h1Zones[i].active || h1Zones[i].zoneType != type) continue;
      if(MathAbs(h1Zones[i].priceHigh - t) < tol && MathAbs(h1Zones[i].priceLow - b) < tol)
         return true;
   }
   return false;
}

void AddH1Zone(double t, double b, int type, int bar, double atr)
{
   if(h1TotalZones >= h1MaxZones) return;
   h1Zones[h1TotalZones].priceHigh = t;
   h1Zones[h1TotalZones].priceLow = b;
   h1Zones[h1TotalZones].timeFormed = iTime(_Symbol, PERIOD_H1, bar);
   h1Zones[h1TotalZones].barIndex = bar;
   h1Zones[h1TotalZones].touches = 0;
   h1Zones[h1TotalZones].zoneType = type;
   h1Zones[h1TotalZones].active = true;
   h1TotalZones++;
}

void UpdateH1ZoneTouches(double atr)
{
   double cl = iClose(_Symbol, PERIOD_H1, 0);
   for(int i = 0; i < h1TotalZones; i++)
   {
      if(!h1Zones[i].active) continue;
      if(cl >= (h1Zones[i].priceLow - atr * 0.1) && cl <= (h1Zones[i].priceHigh + atr * 0.1))
      {
         h1Zones[i].touches++;
         if(h1Zones[i].touches > H1_MaxZoneTouches)
            h1Zones[i].active = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Get Signal - H1 Zone + M5 Confirmation + D1 Trend                 |
//+------------------------------------------------------------------+
int GetH1ZoneSignal()
{
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double o2 = iOpen(_Symbol, PERIOD_CURRENT, 2);
   double atr = atrM5[1];
   double b1 = MathAbs(c1 - o1);
   double b2 = MathAbs(c2 - o2);
   bool bull = (c1 > o1);
   bool bear = (c1 < o1);
   double h1atr = (ArraySize(atrH1) > 0) ? atrH1[0] : atr;
   
   for(int z = 0; z < h1TotalZones; z++)
   {
      if(!h1Zones[z].active) continue;
      double zT = h1Zones[z].priceHigh;
      double zB = h1Zones[z].priceLow;
      
      // === BUY at H1 demand zone ===
      if(h1Zones[z].zoneType == 1 && !isSellOnly)
      {
         // Is price at the H1 zone?
         bool atZone = (l1 <= zT && l1 >= (zB - h1atr * H1_ZoneTolerance));
         if(!atZone) continue;
         
         // D1 trend must confirm
         if(!D1ConfirmsBuy())
         {
            Print("D1 BLOCK BUY: ", mtfD1Status);
            continue;
         }
         
         // Stochastic must confirm
         if(UseStochFilter && stochMain[1] > Stoch_BuyLevel) continue;
         
         // M5 candle confirmation
         bool sig = false;
         string et = "";
         
         if(UseEngulfing && bull && c2 < o2 && b1 > b2 * MinEngulfRatio && b1 > atr * MinCandleBodyATR)
         { sig = true; et = "Engulf"; }
         
         if(UsePinBar && !sig)
         {
            double lw = MathMin(o1, c1) - l1;
            double uw = h1 - MathMax(o1, c1);
            if(lw > b1 * MinPinWickRatio && lw > uw * 1.5 && b1 > atr * 0.05)
            { sig = true; et = "Pin"; }
         }
         
         if(UseOrderBlocks && !sig && l1 <= zT && c1 > zT && bull && b1 > atr * MinCandleBodyATR)
         { sig = true; et = "OB"; }
         
         if(sig)
         {
            lastSignalType = et + " @ H1 Demand";
            Print("H1 BUY SIGNAL: ", et, " at H1 demand zone [",
                  DoubleToString(zB, 2), "-", DoubleToString(zT, 2), "]",
                  " Stoch:", DoubleToString(stochMain[1], 1), " D1:", mtfD1Status);
            return 1;
         }
      }
      
      // === SELL at H1 supply zone ===
      if(h1Zones[z].zoneType == -1 && !isBuyOnly)
      {
         bool atZone = (h1 >= zB && h1 <= (zT + h1atr * H1_ZoneTolerance));
         if(!atZone) continue;
         
         if(!D1ConfirmsSell())
         {
            Print("D1 BLOCK SELL: ", mtfD1Status);
            continue;
         }
         
         if(UseStochFilter && stochMain[1] < Stoch_SellLevel) continue;
         
         bool sig = false;
         string et = "";
         
         if(UseEngulfing && bear && c2 > o2 && b1 > b2 * MinEngulfRatio && b1 > atr * MinCandleBodyATR)
         { sig = true; et = "Engulf"; }
         
         if(UsePinBar && !sig)
         {
            double uw = h1 - MathMax(o1, c1);
            double lw = MathMin(o1, c1) - l1;
            if(uw > b1 * MinPinWickRatio && uw > lw * 1.5 && b1 > atr * 0.05)
            { sig = true; et = "Pin"; }
         }
         
         if(UseOrderBlocks && !sig && h1 >= zB && c1 < zB && bear && b1 > atr * MinCandleBodyATR)
         { sig = true; et = "OB"; }
         
         if(sig)
         {
            lastSignalType = et + " @ H1 Supply";
            Print("H1 SELL SIGNAL: ", et, " at H1 supply zone [",
                  DoubleToString(zB, 2), "-", DoubleToString(zT, 2), "]",
                  " Stoch:", DoubleToString(stochMain[1], 1), " D1:", mtfD1Status);
            return -1;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Execute Trade - Sniper Mode (1 position, H1 ATR SL/TP)            |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double h1atr = atrH1[0];
   double entry = (orderType == ORDER_TYPE_BUY) ? ask : bid;
   
   // SL and TP based on current mode
   // Determine if trading with or against natural bias
   bool withBias = false;
   if(naturalBias == 1 && orderType == ORDER_TYPE_BUY) withBias = true;    // PainX BUY = with bias
   else if(naturalBias == -1 && orderType == ORDER_TYPE_SELL) withBias = true; // GainX SELL = with bias
   else if(naturalBias == 0) withBias = true;  // Unknown symbol = treat as with bias
   
   double sld, tpd;
   string tradeMode;
   
   if(UseHybridMode && currentMode == 1)
   {
      // SCALP MODE — M5 ATR for SL, profit target handles exit
      double m5atr = atrM5[1];
      sld = m5atr * ScalpSL_ATR_Mult;
      tpd = sld * 3.0;   // Wide TP as safety net, profit target closes earlier
      tradeMode = "SCALP";
      Print("SCALP MODE: M5 ATR=", DoubleToString(m5atr, 2), " SL:", DoubleToString(sld, 2), " (profit target $", DoubleToString(ScalpProfitTarget, 0), ")");
   }
   else
   {
      // SNIPER MODE — H1 ATR for SL/TP
      if(withBias)
      {
         sld = h1atr * SL_ATR_Mult;
         tpd = sld * TP_RR_Ratio;
      }
      else
      {
         sld = h1atr * SL_ATR_Against;
         tpd = h1atr * TP_ATR_Against;
      }
      tradeMode = "SNIPER";
      string biasLabel = withBias ? "WITH bias" : "AGAINST bias";
      Print("SNIPER MODE: ", biasLabel, " | SL:", DoubleToString(sld, 2), " TP:", DoubleToString(tpd, 2));
   }
   
   double slP, tpP;
   if(orderType == ORDER_TYPE_BUY)
   {
      slP = NormalizeDouble(entry - sld, digits);
      tpP = NormalizeDouble(entry + tpd, digits);
   }
   else
   {
      slP = NormalizeDouble(entry + sld, digits);
      tpP = NormalizeDouble(entry - tpd, digits);
   }
   
   // Broker minimum stops level
   double ms = stopsLevel * point;
   if(sld < ms)
   {
      sld = ms + 20 * point;
      slP = (orderType == ORDER_TYPE_BUY) ? NormalizeDouble(entry - sld, digits) : NormalizeDouble(entry + sld, digits);
      tpd = sld * TP_RR_Ratio;
      tpP = (orderType == ORDER_TYPE_BUY) ? NormalizeDouble(entry + tpd, digits) : NormalizeDouble(entry - tpd, digits);
   }
   
   // Calculate lot size
   double lot = CalculateLotSize(sld);
   if(lot <= 0) return;
   
   int positionsToOpen = 3;
   string ts = (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   Print("=== v5.0 SNIPER TRADE === ", ts, " | ", lastSignalType);
   Print("H1 ATR: ", DoubleToString(h1atr, 2), " SL: ", DoubleToString(sld, 2),
         "pts TP: ", DoubleToString(tpd, 2), "pts R:R 1:", DoubleToString(TP_RR_Ratio, 1));
   
   int opened = 0;
   ENUM_ORDER_TYPE_FILLING fills[] = {ORDER_FILLING_IOC, ORDER_FILLING_FOK, ORDER_FILLING_RETURN};
   
   for(int p = 0; p < positionsToOpen; p++)
   {
      // Refresh price for each position
      entry = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      MqlTradeRequest rq = {};
      MqlTradeResult rs = {};
      rq.action = TRADE_ACTION_DEAL;
      rq.symbol = _Symbol;
      rq.volume = lot;
      rq.type = orderType;
      rq.price = entry;
      rq.sl = slP;
      rq.tp = tpP;
      rq.deviation = 30;
      rq.magic = activeMagic;
      rq.comment = "RBv5 " + lastSignalType + " #" + IntegerToString(p + 1);
      
      bool ok = false;
      for(int f = 0; f < 3; f++)
      {
         rq.type_filling = fills[f];
         if(OrderSend(rq, rs)) { ok = true; break; }
      }
      
      if(ok)
      {
         opened++;
         Print("POS #", p + 1, " @", DoubleToString(entry, 2),
               " SL:", DoubleToString(slP, 2),
               " TP:", DoubleToString(tpP, 2),
               " Lot:", DoubleToString(lot, 2));
      }
      else
         Print("POS #", p + 1, " FAILED: ", rs.retcode);
      
      if(p < positionsToOpen - 1) Sleep(200);
   }
   
   if(opened > 0)
   {
      barsSinceLastTrade = 0;
      profitBELocked = false;
      Print("=== ", opened, "/", positionsToOpen, " opened ===");
      
      string msg = "RBv5 " + ts + " " + lastSignalType + " " + _Symbol +
                   " SL:" + DoubleToString(slP, 2) + " TP:" + DoubleToString(tpP, 2) +
                   " Lot:" + DoubleToString(lot, 2) + " x" + IntegerToString(opened);
      if(EnablePopupAlert) Alert(msg);
      if(EnablePushNotify) SendNotification(msg);
   }
}

//+------------------------------------------------------------------+
//| Lot Calculation                                                    |
//+------------------------------------------------------------------+
double CalculateLotSize(double sld)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskPerPos = bal * (RiskPerPosition / 100.0);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double ml = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(sld < stopsLevel * pt) sld = stopsLevel * pt;
   if(sld <= 0 || tv == 0 || ts == 0) return ml;
   
   double lots = riskPerPos / ((sld / ts) * tv);
   lots = MathFloor(lots / ls) * ls;
   lots = MathMax(lots, ml);
   lots = MathMin(lots, MathMin(mx, MaxLotSize));
   lots = MathMax(lots, MinLotSize);
   
   Print("LOT: Bal:", DoubleToString(bal, 0), " Risk:$", DoubleToString(riskPerPos, 2),
         " SLdist:", DoubleToString(sld, 2), " Lot:", DoubleToString(lots, 2));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Breakeven Lock                                                     |
//+------------------------------------------------------------------+
void CheckBELock()
{
   if(profitBELocked) return;
   
   double totalProfit = 0;
   int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      totalProfit += PositionGetDouble(POSITION_PROFIT);
      posCount++;
   }
   if(posCount == 0) return;
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double beLockTarget = bal * (BE_Lock_Pct / 100.0);
   
   if(totalProfit >= beLockTarget)
   {
      profitBELocked = true;
      int moved = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
         ulong ticket = PositionGetTicket(i);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         long posType = PositionGetInteger(POSITION_TYPE);
         
         bool needsMove = false;
         if(posType == POSITION_TYPE_BUY && currentSL < openPrice) needsMove = true;
         else if(posType == POSITION_TYPE_SELL && (currentSL > openPrice || currentSL == 0)) needsMove = true;
         
         if(needsMove)
         {
            MqlTradeRequest rq = {};
            MqlTradeResult rs = {};
            rq.action = TRADE_ACTION_SLTP;
            rq.position = ticket;
            rq.symbol = _Symbol;
            rq.sl = openPrice;
            rq.tp = currentTP;
            if(OrderSend(rq, rs)) moved++;
         }
      }
      Print("BE LOCK: $", DoubleToString(totalProfit, 2), " >= $", DoubleToString(beLockTarget, 2),
            " | SL moved to entry");
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop - 1x H1 ATR, activates at 50% of TP distance        |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(ArraySize(atrH1) < 1 || atrH1[0] == 0) return;
   double h1atr = atrH1[0];
   double trailDist = h1atr * Trail_ATR_Mult;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minStop = stopsLevel * point;
   if(trailDist < minStop) trailDist = minStop + 10 * point;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      
      ulong ticket = PositionGetTicket(i);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long posType = PositionGetInteger(POSITION_TYPE);
      
      // Calculate TP distance and activation threshold
      double tpDist = MathAbs(currentTP - openPrice);
      double activationDist = tpDist * Trail_Activate_Pct;  // 50% of TP
      
      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitDist = bid - openPrice;
         
         // Only trail after 50% of TP is reached
         if(profitDist < activationDist) continue;
         
         double newSL = NormalizeDouble(bid - trailDist, digits);
         
         // Only move SL up, never down
         if(newSL > currentSL && newSL > openPrice)
         {
            MqlTradeRequest rq = {};
            MqlTradeResult rs = {};
            rq.action = TRADE_ACTION_SLTP;
            rq.position = ticket;
            rq.symbol = _Symbol;
            rq.sl = newSL;
            rq.tp = currentTP;
            if(OrderSend(rq, rs))
               Print("TRAIL: #", ticket, " SL ", DoubleToString(currentSL, 2), " -> ", DoubleToString(newSL, 2),
                     " (profit:", DoubleToString(profitDist, 2), " trail:", DoubleToString(trailDist, 2), ")");
         }
      }
      else // SELL
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitDist = openPrice - ask;
         
         if(profitDist < activationDist) continue;
         
         double newSL = NormalizeDouble(ask + trailDist, digits);
         
         // Only move SL down, never up
         if((newSL < currentSL || currentSL == 0) && newSL < openPrice)
         {
            MqlTradeRequest rq = {};
            MqlTradeResult rs = {};
            rq.action = TRADE_ACTION_SLTP;
            rq.position = ticket;
            rq.symbol = _Symbol;
            rq.sl = newSL;
            rq.tp = currentTP;
            if(OrderSend(rq, rs))
               Print("TRAIL: #", ticket, " SL ", DoubleToString(currentSL, 2), " -> ", DoubleToString(newSL, 2),
                     " (profit:", DoubleToString(profitDist, 2), " trail:", DoubleToString(trailDist, 2), ")");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Scalp Profit Target — close all at $15 combined                    |
//+------------------------------------------------------------------+
void CheckScalpProfitTarget()
{
   double totalProfit = 0;
   int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      totalProfit += PositionGetDouble(POSITION_PROFIT);
      posCount++;
   }
   if(posCount == 0) return;
   
   if(totalProfit >= ScalpProfitTarget)
   {
      Print("SCALP TARGET HIT: $", DoubleToString(totalProfit, 2), " >= $", DoubleToString(ScalpProfitTarget, 2));
      // Close all positions
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
         ulong ticket = PositionGetTicket(i);
         long pt = PositionGetInteger(POSITION_TYPE);
         double vol = PositionGetDouble(POSITION_VOLUME);
         double ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double ml = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         vol = MathFloor(vol / ls) * ls;
         if(vol < ml) vol = ml;
         
         MqlTradeRequest rq = {};
         MqlTradeResult rs = {};
         rq.action = TRADE_ACTION_DEAL;
         rq.position = ticket;
         rq.symbol = _Symbol;
         rq.volume = vol;
         rq.deviation = 30;
         rq.magic = activeMagic;
         if(pt == POSITION_TYPE_BUY)
         { rq.type = ORDER_TYPE_SELL; rq.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
         else
         { rq.type = ORDER_TYPE_BUY; rq.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
         
         ENUM_ORDER_TYPE_FILLING fills[] = {ORDER_FILLING_IOC, ORDER_FILLING_FOK, ORDER_FILLING_RETURN};
         for(int f = 0; f < 3; f++)
         { rq.type_filling = fills[f]; if(OrderSend(rq, rs)) break; }
      }
      dailySymbolPnL += totalProfit;
      profitBELocked = false;
      string msg = "RBv5 SCALP TARGET $" + DoubleToString(totalProfit, 2) + " " + _Symbol;
      if(EnablePopupAlert) Alert(msg);
      if(EnablePushNotify) SendNotification(msg);
   }
}

//+------------------------------------------------------------------+
//| Daily Reset                                                        |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime td = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(td != dailyResetDate)
   {
      dailyResetDate = td;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      symbolBlockedToday = false;
   }
}

//+------------------------------------------------------------------+
//| Notifications                                                      |
//+------------------------------------------------------------------+
void NotifyTrade(double profit)
{
   string msg = "RBv5 " + (profit > 0 ? "WIN" : "LOSS") +
                " $" + DoubleToString(profit, 2) + " " + _Symbol;
   if(EnablePopupAlert) Alert(msg);
   if(EnablePushNotify) SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Logging                                                            |
//+------------------------------------------------------------------+
void LogBarScan()
{
   totalBarsScanned++;
   
   int dz = 0, sz = 0;
   for(int i = 0; i < h1TotalZones; i++)
   {
      if(!h1Zones[i].active) continue;
      if(h1Zones[i].zoneType == 1) dz++;
      else sz++;
   }
   
   // Update D1 status
   if(d1EmaFast[0] > d1EmaMid[0]) mtfD1Status = "BULL";
   else mtfD1Status = "BEAR";
   
   Print("SCAN #", totalBarsScanned,
         " ", modeLabel,
         " Stoch:", DoubleToString(stochMain[1], 1),
         " H1z D:", dz, " S:", sz,
         " D1:", mtfD1Status,
         " Open:", CountOpenTrades(),
         (symbolBlockedToday ? " BLOCKED" : ""),
         " Wait:", barsSinceLastTrade);
}

//+------------------------------------------------------------------+
//| Dashboard                                                          |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double h1atr = 0;
   if(CopyBuffer(handleATR_H1, 0, 0, 1, atrH1) >= 1) h1atr = atrH1[0];
   double sp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   
   double sm[];
   ArraySetAsSeries(sm, true);
   string si = "?";
   if(CopyBuffer(handleStoch, 0, 0, 1, sm) >= 1) si = DoubleToString(sm[0], 1);
   
   // D1 status
   double df[], dm[];
   ArraySetAsSeries(df, true);
   ArraySetAsSeries(dm, true);
   if(CopyBuffer(handleD1_EMA_Fast, 0, 0, 1, df) >= 1 && CopyBuffer(handleD1_EMA_Mid, 0, 0, 1, dm) >= 1)
      mtfD1Status = (df[0] > dm[0]) ? "BULL" : "BEAR";
   
   int dz = 0, sz = 0;
   for(int i = 0; i < h1TotalZones; i++)
   {
      if(!h1Zones[i].active) continue;
      if(h1Zones[i].zoneType == 1) dz++;
      else sz++;
   }
   
   // Get ADX for display
   string adxStr = "?";
   double adxArr[];
   ArraySetAsSeries(adxArr, true);
   if(UseHybridMode && CopyBuffer(handleADX_H1, 0, 0, 1, adxArr) >= 1)
      adxStr = DoubleToString(adxArr[0], 1);
   
   string NL = "\n";
   string info = "=== RedBot v5.0 HYBRID ===" + NL;
   info += "Mode: " + symbolType + NL;
   if(UseHybridMode)
      info += "Market: " + modeLabel + " (ADX:" + adxStr + ")" + NL;
   info += "Stoch: " + si + " | D1: " + mtfD1Status + NL;
   info += "H1 ATR: " + DoubleToString(h1atr, 2) + " Spread: " + DoubleToString(sp, 2) + NL;
   info += "H1 Zones: D:" + IntegerToString(dz) + " S:" + IntegerToString(sz) + NL;
   info += "Open: " + IntegerToString(CountOpenTrades()) + "/3" + NL;
   info += "Bal: $" + DoubleToString(bal, 2) + " Eq: $" + DoubleToString(eq, 2) + NL;
   info += "W:" + IntegerToString(winTrades) + " L:" + IntegerToString(lossTrades) + NL;
   info += "P/L: $" + DoubleToString(dailySymbolPnL, 2);
   if(symbolBlockedToday) info += " BLOCKED";
   info += NL;
   if(currentMode == 0)
      info += "SNIPER: SL " + DoubleToString(SL_ATR_Mult, 1) + "x H1 | TP " + DoubleToString(TP_RR_Ratio, 1) + ":1" + NL;
   else
      info += "SCALP: SL " + DoubleToString(ScalpSL_ATR_Mult, 1) + "x M5 | TP $" + DoubleToString(ScalpProfitTarget, 0) + NL;
   info += "=========================";
   Comment(info);
}
//+------------------------------------------------------------------+
