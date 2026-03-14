//+------------------------------------------------------------------+
//|                                           RedBot_GainX_v40.mq5    |
//|                                                    Red Bot v4.0   |
//|     Price Action + Stochastic + 3 EMA + Multi-Timeframe           |
//+------------------------------------------------------------------+
#property copyright "RedBot"
#property version   "4.00"
#property description "v4.0 Sniper MTF"

input group "=== Risk Management ==="
input double RiskPercent       = 2.5;
input double MaxLotSize        = 0.50;
input double MinLotSize        = 0.01;
input int    MaxOpenTrades     = 3;
input int    PositionsPerSignal = 3;
input bool   UseTrailingStop   = true;
input double TrailATR_Mult     = 1.5;
input double TrailActivation   = 1.0;
input double BreakevenATR      = 0.5;
input double MinTrailStep      = 0.3;

input group "=== Profit Target ==="
input bool   UseProfitTarget   = true;
input double ProfitTargetUSD   = 7.0;      // Close all when floating P&L hits this

input group "=== Staggered SL/TP ==="
input double Pos1_SL_Pct       = 1.0;
input double Pos1_TP_Pct       = 1.0;
input double Pos2_SL_Pct       = 1.0;
input double Pos2_TP_Pct       = 1.0;
input double Pos3_SL_Pct       = 1.0;
input double Pos3_TP_Pct       = 1.0;
input double Pos4_SL_Pct       = 1.0;
input double Pos4_TP_Pct       = 1.0;

input group "=== Time Filter ==="
input bool   UseTimeFilter     = true;
input int    TradeStartHour    = 8;
input int    TradeStartMin     = 0;
input int    TradeEndHour      = 20;
input int    TradeEndMin       = 0;
input bool   SkipSunday        = true;

input group "=== Cooldown ==="
input bool   UseCooldown       = true;
input int    CooldownAfterLosses = 2;
input int    CooldownBars      = 40;
input bool   UseDailySymbolLimit = true;
input double MaxDailySymbolLoss = 20.0;

input group "=== Minimum SL (ATR) ==="
input bool   UseMinSL          = true;
input int    ATR_Period         = 14;
input double MinSL_ATR_Mult    = 2.0;     // Minimum SL = ATR * this multiplier
input double MaxSL_ATR_Mult    = 3.0;     // Skip trade if SL would exceed this

input group "=== Multi-Timeframe ==="
input bool   UseMTF            = true;
input bool   UseH1_Zones       = true;
input bool   RequireH1Zone     = true;
input bool   UseSwingStructure = true;    // DFS swing structure (replaces H4 EMA)
input int    SwingLookback     = 5;       // Bars left/right for swing detection
input int    MinSwingDepth     = 3;       // Min swing sequence for bias
input bool   UseH4_Trend       = false;   // H4 EMA trend (disabled - replaced by swing)
input bool   UseD1_Trend       = true;
input bool   UseW1_GainX       = false;
input int    MTF_ZoneLookback  = 50;
input int    MTF_SwingStrength = 3;

input group "=== Zone Detection ==="
input int    ZoneLookback      = 50;
input int    SwingStrength     = 3;
input double ZoneTouchTolerance = 0.5;
input int    MinZoneAge        = 5;
input int    MaxZoneTouches    = 3;
input bool   DrawZones         = true;

input group "=== Entry Settings ==="
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
input double Stoch_SellLevel   = 70.0;
input double Stoch_BuyLevel    = 30.0;

input group "=== 3 EMA Crossover ==="
input bool   UseEMACross       = false;
input int    EMA_Fast          = 7;
input int    EMA_Mid           = 21;
input int    EMA_Slow          = 200;

input group "=== ATR Settings ==="
input double SL_ATR_Mult      = 1.2;
input double MinRR_Ratio      = 1.5;
input double MaxSL_ATR        = 3.0;

input group "=== GainX/PainX ==="
input bool   AutoDetectBias    = true;
input bool   ManualBuyOnly     = false;
input bool   ManualSellOnly    = false;
input bool   UseSpreadFilter   = true;
input double MaxSpreadATR      = 0.3;

input group "=== Alerts ==="
input bool   EnableSoundAlerts = true;
input bool   EnablePushNotify  = true;
input bool   EnablePopupAlert  = true;
input bool   LogSignalScans    = true;
input color  BuyArrowColor     = clrLime;
input color  SellArrowColor    = clrRed;
input color  DemandZoneColor   = clrDodgerBlue;
input color  SupplyZoneColor   = clrCrimson;

input group "=== General ==="
input int    MagicNumber       = 234567;
input bool   ShowDashboard     = true;

input group "=== Profit Management ==="
input bool   UseDailyProfitTarget = false;
input double DailyProfitTarget    = 50.0;
input bool   UseDailyLossLimit    = false;
input double DailyLossLimit       = 100.0;
input bool   UseSessionProfitClose = false;
input double SessionProfitClose    = 10.0;
input bool   UseDailyTradeLimit    = false;
input int    MaxDailyTrades        = 10;


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
   int      zoneType;
   bool     active;
   string   name;
};

// Chart TF indicator handles
int handleEMA_Fast, handleEMA_Mid, handleEMA_Slow, handleATR, handleStoch;
double emaFastBuf[], emaMidBuf[], emaSlowBuf[], atrBuffer[];
double stochMainBuf[], stochSignalBuf[];

// MTF indicator handles
int handleH1_EMA_Fast, handleH1_EMA_Mid, handleH1_ATR;
int handleH4_EMA_Fast, handleH4_EMA_Mid;
int handleD1_EMA_Fast, handleD1_EMA_Mid;
int handleW1_EMA_Fast, handleW1_EMA_Mid;
double h1EmaFast[], h1EmaMid[], h1ATR[];
double h4EmaFast[], h4EmaMid[];
double d1EmaFast[], d1EmaMid[];
double w1EmaFast[], w1EmaMid[];

// H1 zones for MTF
PriceZone h1Zones[];
int h1TotalZones = 0;
int h1MaxZones = 20;

// Chart TF zones
PriceZone zones[];
int totalZones = 0;
int maxZones = 20;

datetime lastBarTime = 0;
int stopsLevel = 0;
int activeMagic = 0;
bool isBuyOnly = false;
bool isSellOnly = false;
bool isGainX600 = false;
bool isScalpOnly = false;
string symbolType = "UNKNOWN";

int totalTrades = 0;
int winTrades = 0;
int lossTrades = 0;
int barsSinceLastTrade = 0;
int totalBarsScanned = 0;
int arrowCounter = 0;
string lastSignalType = "";
double signalSL = 0;
double signalTP = 0;
int lastTradeZoneIndex = -1;
int consecutiveLosses = 0;
int cooldownBarsLeft = 0;
bool firstTPHit = false;
double dailySymbolPnL = 0;
datetime dailySymbolResetDate = 0;

// DFS Swing Structure
struct SwingNode
{
   datetime time;
   double   price;
   int      type;    // 1 = high, -1 = low
};
SwingNode swingNodes[];
int swingNodeCount = 0;
int structuralBias = 0;  // 1=bullish, -1=bearish, 0=neutral
string structureStatus = "?";

string mtfH1Status = "?";
string mtfH4Status = "?";
string mtfD1Status = "?";
string mtfW1Status = "?";

double dailyStartBalance = 0;
datetime dailyResetDate = 0;
int dailyTradeCount = 0;
bool dailyTargetReached = false;
bool dailyLossReached = false;

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   handleEMA_Fast = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Mid  = iMA(_Symbol, PERIOD_CURRENT, EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handleATR      = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   handleStoch    = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);

   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Mid == INVALID_HANDLE ||
      handleEMA_Slow == INVALID_HANDLE || handleATR == INVALID_HANDLE ||
      handleStoch == INVALID_HANDLE)
   {
      Print("ERROR: Chart indicators failed!");
      return(INIT_FAILED);
   }

   if(UseMTF)
   {
      handleH1_EMA_Fast = iMA(_Symbol, PERIOD_H1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      handleH1_EMA_Mid  = iMA(_Symbol, PERIOD_H1, EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
      handleH1_ATR      = iATR(_Symbol, PERIOD_H1, ATR_Period);
      handleH4_EMA_Fast = iMA(_Symbol, PERIOD_H4, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      handleH4_EMA_Mid  = iMA(_Symbol, PERIOD_H4, EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
      handleD1_EMA_Fast = iMA(_Symbol, PERIOD_D1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      handleD1_EMA_Mid  = iMA(_Symbol, PERIOD_D1, EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);

      if(handleH1_EMA_Fast == INVALID_HANDLE || handleH1_EMA_Mid == INVALID_HANDLE ||
         handleH1_ATR == INVALID_HANDLE ||
         handleH4_EMA_Fast == INVALID_HANDLE || handleH4_EMA_Mid == INVALID_HANDLE ||
         handleD1_EMA_Fast == INVALID_HANDLE || handleD1_EMA_Mid == INVALID_HANDLE)
      {
         Print("ERROR: MTF indicators failed!");
         return(INIT_FAILED);
      }

      if(UseW1_GainX)
      {
         handleW1_EMA_Fast = iMA(_Symbol, PERIOD_W1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
         handleW1_EMA_Mid  = iMA(_Symbol, PERIOD_W1, EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
         if(handleW1_EMA_Fast == INVALID_HANDLE || handleW1_EMA_Mid == INVALID_HANDLE)
         {
            Print("ERROR: W1 indicators failed!");
            return(INIT_FAILED);
         }
         ArraySetAsSeries(w1EmaFast, true);
         ArraySetAsSeries(w1EmaMid, true);
      }

      ArraySetAsSeries(h1EmaFast, true);
      ArraySetAsSeries(h1EmaMid, true);
      ArraySetAsSeries(h1ATR, true);
      ArraySetAsSeries(h4EmaFast, true);
      ArraySetAsSeries(h4EmaMid, true);
      ArraySetAsSeries(d1EmaFast, true);
      ArraySetAsSeries(d1EmaMid, true);
      ArrayResize(h1Zones, h1MaxZones);
   }

   ArraySetAsSeries(emaFastBuf, true);
   ArraySetAsSeries(emaMidBuf, true);
   ArraySetAsSeries(emaSlowBuf, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(stochMainBuf, true);
   ArraySetAsSeries(stochSignalBuf, true);
   ArrayResize(zones, maxZones);
   stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   if(AutoDetectBias)
   {
      string sn = _Symbol;
      StringToUpper(sn);
      if(StringFind(sn, "GAINX") >= 0 || StringFind(sn, "GAIN_X") >= 0)
      {
         isSellOnly = true;
         isBuyOnly = false;
         symbolType = "GainX (SELL)";
         if(StringFind(sn, "600") >= 0)
            isGainX600 = true;
         if(StringFind(sn, "400") >= 0)
            isScalpOnly = true;
      }
      else if(StringFind(sn, "PAINX") >= 0 || StringFind(sn, "PAIN_X") >= 0)
      {
         isBuyOnly = true;
         isSellOnly = false;
         symbolType = "PainX (BUY)";
         if(StringFind(sn, "400") >= 0)
            isScalpOnly = true;
      }
      else
      {
         symbolType = "Unknown (BOTH)";
      }
   }
   else
   {
      isBuyOnly = ManualBuyOnly;
      isSellOnly = ManualSellOnly;
      if(isBuyOnly) symbolType = "Manual BUY";
      else if(isSellOnly) symbolType = "Manual SELL";
      else symbolType = "Manual BOTH";
   }

   activeMagic = MagicNumber;
   for(int i = 0; i < StringLen(_Symbol); i++)
      activeMagic += StringGetCharacter(_Symbol, i) * (i + 1);

   Print("=== RedBot v4.0 (Sniper MTF) ===");
   Print("Symbol: ", _Symbol, " | TF: ", EnumToString(Period()));
   Print("Mode: ", symbolType, " | MTF: ", UseMTF ? "ON" : "OFF");
   Print("Stoch(", Stoch_K, ",", Stoch_D, ",", Stoch_Slowing, ") EMA(", EMA_Fast, ",", EMA_Mid, ",", EMA_Slow, ")");
   Print("Risk: ", RiskPercent, "% | Positions: ", PositionsPerSignal);
   Print("TP Split: #1=", Pos1_TP_Pct*100, "% #2=", Pos2_TP_Pct*100, "% #3=", Pos3_TP_Pct*100, "% #4=", Pos4_TP_Pct*100, "%");
   if(UseTimeFilter)
      Print("Time Filter: ", TradeStartHour, ":", (TradeStartMin < 10 ? "0" : ""), TradeStartMin, " - ", TradeEndHour, ":", (TradeEndMin < 10 ? "0" : ""), TradeEndMin, (SkipSunday ? " | Sunday: OFF" : ""));
   else
      Print("Time Filter: OFF");
   if(UseCooldown)
      Print("Cooldown: ", CooldownBars, " bars after ", CooldownAfterLosses, " consecutive losses");
   if(UseDailySymbolLimit)
      Print("Daily Symbol Limit: -$", DoubleToString(MaxDailySymbolLoss, 2), " per symbol");
   Print("Trailing: Runners only (TP > 1.2x SL)");
   Print("H1 Zone: ", (RequireH1Zone ? "REQUIRED" : "Optional"));
   if(UseSwingStructure)
      Print("Swing Structure: ON (Lookback:", SwingLookback, " MinDepth:", MinSwingDepth, ") - replaces H4 EMA");
   else if(UseH4_Trend)
      Print("H4 EMA: ON (informational)");
   if(UseProfitTarget)
      Print("Profit Target: $", DoubleToString(ProfitTargetUSD, 2), " per trade set");
   Print("Stoch: BUY<=", Stoch_BuyLevel, " SELL>=", Stoch_SellLevel);
   if(isScalpOnly)
      Print("SCALP ONLY MODE: All positions at 100% TP");
   Print("BE on TP: Move remaining SLs to breakeven after first TP hit");
   if(UseMinSL)
      Print("Min SL: ATR(", ATR_Period, ") x ", DoubleToString(MinSL_ATR_Mult, 1), " | Max SL: ATR x ", DoubleToString(MaxSL_ATR_Mult, 1));
   
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyResetDate = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA_Fast != INVALID_HANDLE) IndicatorRelease(handleEMA_Fast);
   if(handleEMA_Mid != INVALID_HANDLE)  IndicatorRelease(handleEMA_Mid);
   if(handleEMA_Slow != INVALID_HANDLE) IndicatorRelease(handleEMA_Slow);
   if(handleATR != INVALID_HANDLE)      IndicatorRelease(handleATR);
   if(handleStoch != INVALID_HANDLE)    IndicatorRelease(handleStoch);
   if(UseMTF)
   {
      if(handleH1_EMA_Fast != INVALID_HANDLE) IndicatorRelease(handleH1_EMA_Fast);
      if(handleH1_EMA_Mid != INVALID_HANDLE)  IndicatorRelease(handleH1_EMA_Mid);
      if(handleH1_ATR != INVALID_HANDLE)      IndicatorRelease(handleH1_ATR);
      if(handleH4_EMA_Fast != INVALID_HANDLE) IndicatorRelease(handleH4_EMA_Fast);
      if(handleH4_EMA_Mid != INVALID_HANDLE)  IndicatorRelease(handleH4_EMA_Mid);
      if(handleD1_EMA_Fast != INVALID_HANDLE) IndicatorRelease(handleD1_EMA_Fast);
      if(handleD1_EMA_Mid != INVALID_HANDLE)  IndicatorRelease(handleD1_EMA_Mid);
      if(handleW1_EMA_Fast != INVALID_HANDLE) IndicatorRelease(handleW1_EMA_Fast);
      if(handleW1_EMA_Mid != INVALID_HANDLE)  IndicatorRelease(handleW1_EMA_Mid);
   }
   ObjectsDeleteAll(0, "RB_");
   Comment("");
   Print("RedBot v4.0 stopped. W:", winTrades, " L:", lossTrades);
}

//+------------------------------------------------------------------+
//| OnTradeTransaction                                                 |
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
      Print("X SL: $", DoubleToString(profit, 2), " DayPnL:", DoubleToString(dailySymbolPnL, 2));
      NotifyTradeClosed(profit);
      if(lastTradeZoneIndex >= 0 && lastTradeZoneIndex < totalZones && zones[lastTradeZoneIndex].active)
      {
         zones[lastTradeZoneIndex].active = false;
         Print("DEAD ZONE killed");
      }
      // Cooldown tracking - only count when no more positions open
      if(CountOpenTrades() == 0)
      {
         consecutiveLosses++;
         if(UseCooldown && consecutiveLosses >= CooldownAfterLosses)
         {
            cooldownBarsLeft = CooldownBars;
            Print("COOLDOWN activated: ", CooldownBars, " bars after ", consecutiveLosses, " consecutive losses");
            consecutiveLosses = 0;
         }
      }
   }
   else if(dealReason == DEAL_REASON_TP)
   {
      winTrades++;
      dailySymbolPnL += profit;
      Print("V TP: $", DoubleToString(profit, 2), " DayPnL:", DoubleToString(dailySymbolPnL, 2));
      NotifyTradeClosed(profit);
      consecutiveLosses = 0;
      
      // Move remaining positions to breakeven after first TP hit
      if(!firstTPHit)
      {
         firstTPHit = true;
         MoveRemainingToBE();
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(ShowDashboard) UpdateDashboard();
   CheckDailyReset();
   if(UseSessionProfitClose) CheckSessionProfitClose();
   if(UseProfitTarget) CheckProfitTarget();
   if(UseTrailingStop && GetIndicatorData()) ManageBreakeven();
   
   if(!IsNewBar()) return;
   if(!GetIndicatorData()) { Print("FAIL: GetIndicatorData"); return; }
   if(UseMTF && !GetMTFData()) { Print("FAIL: GetMTFData"); return; }
   if(UseSwingStructure) DetectSwings();
   if(UseTrailingStop) ManageTrailingStop();
   
   ScanForZones();
   UpdateZoneTouches();
   if(DrawZones) DrawZonesOnChart();
   if(UseMTF && UseH1_Zones) ScanH1Zones();
   
   LogBarScan();
   CheckExitSignals();
   
   if(dailyTargetReached || dailyLossReached) return;
   if(UseDailyProfitTarget && GetDailyPL() >= DailyProfitTarget)
   {
      dailyTargetReached = true;
      CloseAllPositions();
      SendNotification("Redbot TARGET " + _Symbol);
      return;
   }
   if(UseDailyLossLimit && GetDailyPL() <= -DailyLossLimit)
   {
      dailyLossReached = true;
      CloseAllPositions();
      SendNotification("Redbot LOSS " + _Symbol);
      return;
   }
   if(UseDailyTradeLimit && dailyTradeCount >= MaxDailyTrades) return;
   if(CountOpenTrades() >= MaxOpenTrades) return;
   if(barsSinceLastTrade < 2) return;
   
   // Cooldown after consecutive losses
   if(UseCooldown && cooldownBarsLeft > 0)
   {
      cooldownBarsLeft--;
      if(cooldownBarsLeft == 0)
         Print("COOLDOWN ended - resuming trading");
      else
         return;
   }
   
   // Time filter
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(SkipSunday && dt.day_of_week == 0) return;
      int nowMins = dt.hour * 60 + dt.min;
      int startMins = TradeStartHour * 60 + TradeStartMin;
      int endMins = TradeEndHour * 60 + TradeEndMin;
      if(nowMins < startMins || nowMins >= endMins) return;
   }
   
   // Reset daily symbol P&L at midnight
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today != dailySymbolResetDate)
   {
      dailySymbolPnL = 0;
      dailySymbolResetDate = today;
   }
   
   // Daily symbol loss limit
   if(UseDailySymbolLimit && dailySymbolPnL <= -MaxDailySymbolLoss)
   {
      static datetime lastSymLimitMsg = 0;
      if(TimeCurrent() - lastSymLimitMsg > 300)
      {
         Print("SYMBOL DAILY LIMIT: ", _Symbol, " P&L=$", DoubleToString(dailySymbolPnL, 2), " (max -$", DoubleToString(MaxDailySymbolLoss, 2), ")");
         lastSymLimitMsg = TimeCurrent();
      }
      return;
   }
   
   if(!PassesFilters()) return;
   
   int signal = GetZoneSignal();
   if(signal == 1 && !isSellOnly)
      ExecuteTrade(ORDER_TYPE_BUY);
   else if(signal == -1 && !isBuyOnly)
      ExecuteTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Utility functions                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

bool GetIndicatorData()
{
   if(CopyBuffer(handleEMA_Fast, 0, 0, 5, emaFastBuf) < 5) return false;
   if(CopyBuffer(handleEMA_Mid, 0, 0, 5, emaMidBuf) < 5)   return false;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 5, emaSlowBuf) < 5) return false;
   if(CopyBuffer(handleATR, 0, 0, 5, atrBuffer) < 5)        return false;
   if(CopyBuffer(handleStoch, 0, 0, 5, stochMainBuf) < 5)   return false;
   if(CopyBuffer(handleStoch, 1, 0, 5, stochSignalBuf) < 5) return false;
   return true;
}

bool GetMTFData()
{
   if(UseH1_Zones)
   {
      if(CopyBuffer(handleH1_EMA_Fast, 0, 0, 3, h1EmaFast) < 3) return false;
      if(CopyBuffer(handleH1_EMA_Mid, 0, 0, 3, h1EmaMid) < 3)   return false;
      if(CopyBuffer(handleH1_ATR, 0, 0, 3, h1ATR) < 3)           return false;
   }
   if(UseH4_Trend)
   {
      if(CopyBuffer(handleH4_EMA_Fast, 0, 0, 3, h4EmaFast) < 3) return false;
      if(CopyBuffer(handleH4_EMA_Mid, 0, 0, 3, h4EmaMid) < 3)   return false;
   }
   if(UseD1_Trend)
   {
      if(CopyBuffer(handleD1_EMA_Fast, 0, 0, 3, d1EmaFast) < 3) return false;
      if(CopyBuffer(handleD1_EMA_Mid, 0, 0, 3, d1EmaMid) < 3)   return false;
   }
   if(UseW1_GainX)
   {
      if(CopyBuffer(handleW1_EMA_Fast, 0, 0, 3, w1EmaFast) < 3) return false;
      if(CopyBuffer(handleW1_EMA_Mid, 0, 0, 3, w1EmaMid) < 3)   return false;
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

bool PassesFilters()
{
   double atr = atrBuffer[1];
   if(UseSpreadFilter)
   {
      double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(spread > atr * MaxSpreadATR) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Confirmations: Stochastic, EMA, MTF                                |
//+------------------------------------------------------------------+
bool StochConfirmsBuy()
{
   if(!UseStochFilter) return true;
   return (stochMainBuf[1] <= Stoch_BuyLevel);
}

bool StochConfirmsSell()
{
   if(!UseStochFilter) return true;
   return (stochMainBuf[1] >= Stoch_SellLevel);
}

bool EMAConfirmsBuy()
{
   if(!UseEMACross) return true;
   return (emaFastBuf[1] > emaMidBuf[1]);
}

bool EMAConfirmsSell()
{
   if(!UseEMACross) return true;
   return (emaFastBuf[1] < emaMidBuf[1]);
}

//+------------------------------------------------------------------+
//| DFS Swing Structure Detection                                      |
//+------------------------------------------------------------------+
void DetectSwings()
{
   if(!UseSwingStructure) return;
   
   double h[], l[];
   datetime t[];
   int bars = SwingLookback * 2 + 10;
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(t, true);
   if(CopyHigh(_Symbol, PERIOD_H1, 0, bars, h) < bars) return;
   if(CopyLow(_Symbol, PERIOD_H1, 0, bars, l) < bars) return;
   if(CopyTime(_Symbol, PERIOD_H1, 0, bars, t) < bars) return;
   
   // Clear and rebuild swings
   swingNodeCount = 0;
   ArrayResize(swingNodes, 0, 50);
   
   for(int i = SwingLookback; i < bars - SwingLookback; i++)
   {
      // Check swing high
      bool isHigh = true;
      for(int j = 1; j <= SwingLookback; j++)
      {
         if(h[i] <= h[i-j] || h[i] <= h[i+j]) { isHigh = false; break; }
      }
      if(isHigh)
      {
         ArrayResize(swingNodes, swingNodeCount + 1, 50);
         swingNodes[swingNodeCount].time = t[i];
         swingNodes[swingNodeCount].price = h[i];
         swingNodes[swingNodeCount].type = 1;
         swingNodeCount++;
      }
      
      // Check swing low
      bool isLow = true;
      for(int j = 1; j <= SwingLookback; j++)
      {
         if(l[i] >= l[i-j] || l[i] >= l[i+j]) { isLow = false; break; }
      }
      if(isLow)
      {
         ArrayResize(swingNodes, swingNodeCount + 1, 50);
         swingNodes[swingNodeCount].time = t[i];
         swingNodes[swingNodeCount].price = l[i];
         swingNodes[swingNodeCount].type = -1;
         swingNodeCount++;
      }
   }
   
   // Sort by time (most recent last) - they come reversed from CopyHigh
   // Reverse the array
   for(int i = 0; i < swingNodeCount / 2; i++)
   {
      SwingNode tmp = swingNodes[i];
      swingNodes[i] = swingNodes[swingNodeCount - 1 - i];
      swingNodes[swingNodeCount - 1 - i] = tmp;
   }
   
   // Determine structural bias using DFS path logic
   DetermineStructuralBias();
}

void DetermineStructuralBias()
{
   structuralBias = 0;
   structureStatus = "NEUTRAL";
   
   if(swingNodeCount < MinSwingDepth) return;
   
   // Get the last N swing nodes
   int start = MathMax(0, swingNodeCount - 8);
   
   // Count higher highs / higher lows vs lower lows / lower highs
   int bullishCount = 0;
   int bearishCount = 0;
   
   double lastHigh = 0, lastLow = 0;
   bool firstHigh = true, firstLow = true;
   
   for(int i = start; i < swingNodeCount; i++)
   {
      if(swingNodes[i].type == 1) // Swing high
      {
         if(!firstHigh)
         {
            if(swingNodes[i].price > lastHigh) bullishCount++;
            else if(swingNodes[i].price < lastHigh) bearishCount++;
         }
         lastHigh = swingNodes[i].price;
         firstHigh = false;
      }
      else // Swing low
      {
         if(!firstLow)
         {
            if(swingNodes[i].price > lastLow) bullishCount++;
            else if(swingNodes[i].price < lastLow) bearishCount++;
         }
         lastLow = swingNodes[i].price;
         firstLow = false;
      }
   }
   
   if(bullishCount >= MinSwingDepth && bullishCount > bearishCount)
   {
      structuralBias = 1;
      structureStatus = "BULL(" + IntegerToString(bullishCount) + ")";
   }
   else if(bearishCount >= MinSwingDepth && bearishCount > bullishCount)
   {
      structuralBias = -1;
      structureStatus = "BEAR(" + IntegerToString(bearishCount) + ")";
   }
   else
   {
      structureStatus = "CHOP(" + IntegerToString(bullishCount) + "/" + IntegerToString(bearishCount) + ")";
   }
}

bool MTFConfirmsBuy()
{
   if(!UseMTF) return true;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(UseH1_Zones)
   {
      bool atZ = false;
      double h1a = (ArraySize(h1ATR) > 0) ? h1ATR[0] : 0;
      if(h1a > 0)
      {
         for(int i = 0; i < h1TotalZones; i++)
         {
            if(!h1Zones[i].active || h1Zones[i].zoneType != 1) continue;
            if(price >= (h1Zones[i].priceLow - h1a * 0.3) && price <= (h1Zones[i].priceHigh + h1a * 0.3))
            {
               atZ = true;
               break;
            }
         }
      }
      mtfH1Status = atZ ? "DEMAND" : "-";
      if(RequireH1Zone && !atZ) return false;
   }

   if(UseH4_Trend)
   {
      if(h4EmaFast[0] <= h4EmaMid[0])
         mtfH4Status = "BEAR";
      else
         mtfH4Status = "BULL";
      // H4 is informational only - does not block trades
   }

   // DFS Swing Structure - replaces H4 blocking
   if(UseSwingStructure)
   {
      if(structuralBias == -1)
      {
         mtfH4Status = structureStatus;
         return false;
      }
      mtfH4Status = structureStatus;
   }

   if(UseD1_Trend)
   {
      if(d1EmaFast[0] <= d1EmaMid[0])
      {
         mtfD1Status = "BEAR";
         return false;
      }
      mtfD1Status = "BULL";
   }
   return true;
}

bool MTFConfirmsSell()
{
   if(!UseMTF) return true;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(UseH1_Zones)
   {
      bool atZ = false;
      double h1a = (ArraySize(h1ATR) > 0) ? h1ATR[0] : 0;
      if(h1a > 0)
      {
         for(int i = 0; i < h1TotalZones; i++)
         {
            if(!h1Zones[i].active || h1Zones[i].zoneType != -1) continue;
            if(price >= (h1Zones[i].priceLow - h1a * 0.3) && price <= (h1Zones[i].priceHigh + h1a * 0.3))
            {
               atZ = true;
               break;
            }
         }
      }
      mtfH1Status = atZ ? "SUPPLY" : "-";
      if(RequireH1Zone && !atZ) return false;
   }

   if(UseH4_Trend)
   {
      if(h4EmaFast[0] >= h4EmaMid[0])
         mtfH4Status = "BULL";
      else
         mtfH4Status = "BEAR";
      // H4 is informational only - does not block trades
   }

   // DFS Swing Structure - replaces H4 blocking
   if(UseSwingStructure)
   {
      if(structuralBias == 1)
      {
         mtfH4Status = structureStatus;
         return false;
      }
      mtfH4Status = structureStatus;
   }

   if(UseD1_Trend)
   {
      if(d1EmaFast[0] >= d1EmaMid[0])
      {
         mtfD1Status = "BULL";
         return false;
      }
      mtfD1Status = "BEAR";
   }

   if(UseW1_GainX && isGainX600)
   {
      if(w1EmaFast[0] >= w1EmaMid[0])
      {
         mtfW1Status = "BULL(skip)";
         return false;
      }
      mtfW1Status = "BEAR(ok)";
   }
   return true;
}

//+------------------------------------------------------------------+
//| H1 Zone Scanning for MTF                                           |
//+------------------------------------------------------------------+
void ScanH1Zones()
{
   for(int z = 0; z < h1TotalZones; z++)
      h1Zones[z].active = false;
   h1TotalZones = 0;

   double atr = (ArraySize(h1ATR) > 0) ? h1ATR[0] : 0;
   if(atr == 0) return;

   int bars = Bars(_Symbol, PERIOD_H1);
   int look = MathMin(MTF_ZoneLookback, bars - 1);
   if(look < MTF_SwingStrength * 2 + 3) return;

   for(int i = MTF_SwingStrength + 1; i < look - MTF_SwingStrength; i++)
   {
      if(h1TotalZones >= h1MaxZones) break;

      double h = iHigh(_Symbol, PERIOD_H1, i);
      double l = iLow(_Symbol, PERIOD_H1, i);
      double o = iOpen(_Symbol, PERIOD_H1, i);
      double c = iClose(_Symbol, PERIOD_H1, i);

      // Swing high = supply zone
      bool swH = true;
      for(int j = 1; j <= MTF_SwingStrength; j++)
      {
         if(iHigh(_Symbol, PERIOD_H1, i - j) >= h || iHigh(_Symbol, PERIOD_H1, i + j) >= h)
         {
            swH = false;
            break;
         }
      }
      if(swH)
      {
         double zt = h;
         double zb = MathMax(o, c);
         if((zt - zb) < atr * 0.1) zb = zt - atr * 0.5;
         bool ex = false;
         for(int k = 0; k < h1TotalZones; k++)
         {
            if(h1Zones[k].active && h1Zones[k].zoneType == -1 && MathAbs(h1Zones[k].priceHigh - zt) < atr * 0.3)
            {
               ex = true;
               break;
            }
         }
         if(!ex)
         {
            h1Zones[h1TotalZones].priceHigh = zt;
            h1Zones[h1TotalZones].priceLow = zb;
            h1Zones[h1TotalZones].zoneType = -1;
            h1Zones[h1TotalZones].active = true;
            h1Zones[h1TotalZones].barIndex = i;
            h1Zones[h1TotalZones].touches = 0;
            h1TotalZones++;
         }
      }

      // Swing low = demand zone
      bool swL = true;
      for(int j = 1; j <= MTF_SwingStrength; j++)
      {
         if(iLow(_Symbol, PERIOD_H1, i - j) <= l || iLow(_Symbol, PERIOD_H1, i + j) <= l)
         {
            swL = false;
            break;
         }
      }
      if(swL)
      {
         double zb = l;
         double zt = MathMin(o, c);
         if((zt - zb) < atr * 0.1) zt = zb + atr * 0.5;
         bool ex = false;
         for(int k = 0; k < h1TotalZones; k++)
         {
            if(h1Zones[k].active && h1Zones[k].zoneType == 1 && MathAbs(h1Zones[k].priceLow - zb) < atr * 0.3)
            {
               ex = true;
               break;
            }
         }
         if(!ex)
         {
            h1Zones[h1TotalZones].priceHigh = zt;
            h1Zones[h1TotalZones].priceLow = zb;
            h1Zones[h1TotalZones].zoneType = 1;
            h1Zones[h1TotalZones].active = true;
            h1Zones[h1TotalZones].barIndex = i;
            h1Zones[h1TotalZones].touches = 0;
            h1TotalZones++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Chart TF Zone Scanning                                             |
//+------------------------------------------------------------------+
void ScanForZones()
{
   for(int z = 0; z < totalZones; z++)
      zones[z].active = false;
   totalZones = 0;

   if(ArraySize(atrBuffer) < 2) return;
   double atr = atrBuffer[1];
   if(atr == 0) return;

   int look = MathMin(ZoneLookback, Bars(_Symbol, PERIOD_CURRENT) - 1);
   if(look < SwingStrength * 2 + 3) return;

   for(int i = SwingStrength + 1; i < look - SwingStrength; i++)
   {
      if(totalZones >= maxZones) break;
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      double o = iOpen(_Symbol, PERIOD_CURRENT, i);
      double c = iClose(_Symbol, PERIOD_CURRENT, i);

      if(IsSwingHigh(i))
      {
         double zt = h;
         double zb = MathMax(o, c);
         if((zt - zb) < atr * 0.1) zb = zt - atr * ZoneTouchTolerance;
         if(!ZoneExists(zt, zb, -1)) AddZone(zt, zb, -1, i);
      }
      if(IsSwingLow(i))
      {
         double zb = l;
         double zt = MathMin(o, c);
         if((zt - zb) < atr * 0.1) zt = zb + atr * ZoneTouchTolerance;
         if(!ZoneExists(zt, zb, 1)) AddZone(zt, zb, 1, i);
      }
   }
   if(UseOrderBlocks) ScanOrderBlocks();
}

bool IsSwingHigh(int idx)
{
   double h = iHigh(_Symbol, PERIOD_CURRENT, idx);
   for(int i = 1; i <= SwingStrength; i++)
   {
      if(iHigh(_Symbol, PERIOD_CURRENT, idx - i) >= h) return false;
      if(iHigh(_Symbol, PERIOD_CURRENT, idx + i) >= h) return false;
   }
   return true;
}

bool IsSwingLow(int idx)
{
   double l = iLow(_Symbol, PERIOD_CURRENT, idx);
   for(int i = 1; i <= SwingStrength; i++)
   {
      if(iLow(_Symbol, PERIOD_CURRENT, idx - i) <= l) return false;
      if(iLow(_Symbol, PERIOD_CURRENT, idx + i) <= l) return false;
   }
   return true;
}

void ScanOrderBlocks()
{
   double atr = atrBuffer[1];
   if(atr == 0) return;
   int look = MathMin(ZoneLookback, Bars(_Symbol, PERIOD_CURRENT) - 1);
   for(int i = 3; i < look - 2; i++)
   {
      if(totalZones >= maxZones) break;
      double o = iOpen(_Symbol, PERIOD_CURRENT, i);
      double c = iClose(_Symbol, PERIOD_CURRENT, i);
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      double on = iOpen(_Symbol, PERIOD_CURRENT, i - 1);
      double cn = iClose(_Symbol, PERIOD_CURRENT, i - 1);
      if((c < o) && ((cn - on) > atr * 0.8))
      {
         double zt = MathMax(o, c);
         double zb = l;
         if(!ZoneExists(zt, zb, 1)) AddZone(zt, zb, 1, i);
      }
      if((c > o) && ((on - cn) > atr * 0.8))
      {
         double zt = h;
         double zb = MathMin(o, c);
         if(!ZoneExists(zt, zb, -1)) AddZone(zt, zb, -1, i);
      }
   }
}

void AddZone(double t, double b, int type, int bar)
{
   if(totalZones >= maxZones) return;
   zones[totalZones].priceHigh = t;
   zones[totalZones].priceLow = b;
   zones[totalZones].timeFormed = iTime(_Symbol, PERIOD_CURRENT, bar);
   zones[totalZones].barIndex = bar;
   zones[totalZones].touches = 0;
   zones[totalZones].zoneType = type;
   zones[totalZones].active = true;
   zones[totalZones].name = "RB_Z_" + IntegerToString(totalZones);
   totalZones++;
}

bool ZoneExists(double t, double b, int type)
{
   double tol = atrBuffer[1] * 0.3;
   for(int i = 0; i < totalZones; i++)
   {
      if(!zones[i].active || zones[i].zoneType != type) continue;
      if(MathAbs(zones[i].priceHigh - t) < tol && MathAbs(zones[i].priceLow - b) < tol)
         return true;
   }
   return false;
}

void UpdateZoneTouches()
{
   if(ArraySize(atrBuffer) < 2) return;
   double cl = iClose(_Symbol, PERIOD_CURRENT, 1);
   double atr = atrBuffer[1];
   for(int i = 0; i < totalZones; i++)
   {
      if(!zones[i].active) continue;
      if(cl >= (zones[i].priceLow - atr * 0.1) && cl <= (zones[i].priceHigh + atr * 0.1))
      {
         zones[i].touches++;
         if(zones[i].touches > MaxZoneTouches)
            zones[i].active = false;
      }
   }
}

//+------------------------------------------------------------------+
//| GetZoneSignal - with Stoch + EMA + MTF                             |
//+------------------------------------------------------------------+
int GetZoneSignal()
{
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double o2 = iOpen(_Symbol, PERIOD_CURRENT, 2);
   double h2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
   double l2 = iLow(_Symbol, PERIOD_CURRENT, 2);
   double atr = atrBuffer[1];
   double b1 = MathAbs(c1 - o1);
   double b2 = MathAbs(c2 - o2);
   bool bull = (c1 > o1);
   bool bear = (c1 < o1);

   for(int z = 0; z < totalZones; z++)
   {
      if(!zones[z].active || zones[z].barIndex < MinZoneAge) continue;
      double zT = zones[z].priceHigh;
      double zB = zones[z].priceLow;

      // === BUY at demand ===
      if(zones[z].zoneType == 1 && !isSellOnly)
      {
         bool inZ = (l1 <= zT && l1 >= (zB - atr * 0.2)) || (l2 <= zT && l2 >= (zB - atr * 0.2));
         if(!inZ) continue;
         if(!StochConfirmsBuy() || !EMAConfirmsBuy()) continue;
         if(!MTFConfirmsBuy())
         {
            Print("MTF BLOCK BUY H1:", mtfH1Status, " H4:", mtfH4Status, " D1:", mtfD1Status);
            continue;
         }

         bool sig = false;
         string et = "";
         if(UseEngulfing && bull && c2 < o2 && b1 > b2 * MinEngulfRatio && b1 > atr * MinCandleBodyATR)
         {
            sig = true;
            et = "Engulf";
         }
         if(UsePinBar && !sig)
         {
            double lw = MathMin(o1, c1) - l1;
            double uw = h1 - MathMax(o1, c1);
            if(lw > b1 * MinPinWickRatio && lw > uw * 1.5 && b1 > atr * 0.05)
            {
               sig = true;
               et = "Pin";
            }
         }
         if(UseOrderBlocks && !sig && l1 <= zT && c1 > zT && bull && b1 > atr * MinCandleBodyATR)
         {
            sig = true;
            et = "OB";
         }

         if(sig)
         {
            double sl = zB - atr * 0.3;
            double sld = c1 - sl;
            if(sld > atr * MaxSL_ATR || sld <= 0) continue;
            double ztp = FindOppositeZone(c1, 1);
            double atp = c1 + sld * 2.5;
            double tp = (ztp > 0 && (ztp - c1) >= sld * MinRR_Ratio) ? ztp : atp;
            lastSignalType = et + " @ Demand";
            signalSL = sl;
            signalTP = tp;
            lastTradeZoneIndex = z;
            Print("BUY: ", et, " R:R=1:", DoubleToString((tp - c1) / sld, 1),
                  " Stoch:", DoubleToString(stochMainBuf[1], 1),
                  " MTF H1:", mtfH1Status, " H4:", mtfH4Status, " D1:", mtfD1Status);
            return 1;
         }
      }

      // === SELL at supply ===
      if(zones[z].zoneType == -1 && !isBuyOnly)
      {
         bool inZ = (h1 >= zB && h1 <= (zT + atr * 0.2)) || (h2 >= zB && h2 <= (zT + atr * 0.2));
         if(!inZ) continue;
         if(!StochConfirmsSell() || !EMAConfirmsSell()) continue;
         if(!MTFConfirmsSell())
         {
            Print("MTF BLOCK SELL H1:", mtfH1Status, " H4:", mtfH4Status, " D1:", mtfD1Status, " W1:", mtfW1Status);
            continue;
         }

         bool sig = false;
         string et = "";
         if(UseEngulfing && bear && c2 > o2 && b1 > b2 * MinEngulfRatio && b1 > atr * MinCandleBodyATR)
         {
            sig = true;
            et = "Engulf";
         }
         if(UsePinBar && !sig)
         {
            double uw = h1 - MathMax(o1, c1);
            double lw = MathMin(o1, c1) - l1;
            if(uw > b1 * MinPinWickRatio && uw > lw * 1.5 && b1 > atr * 0.05)
            {
               sig = true;
               et = "Pin";
            }
         }
         if(UseOrderBlocks && !sig && h1 >= zB && c1 < zB && bear && b1 > atr * MinCandleBodyATR)
         {
            sig = true;
            et = "OB";
         }

         if(sig)
         {
            double sl = zT + atr * 0.3;
            double sld = sl - c1;
            if(sld > atr * MaxSL_ATR || sld <= 0) continue;
            double ztp = FindOppositeZone(c1, -1);
            double atp = c1 - sld * 2.5;
            double tp = (ztp > 0 && (c1 - ztp) >= sld * MinRR_Ratio) ? ztp : atp;
            lastSignalType = et + " @ Supply";
            signalSL = sl;
            signalTP = tp;
            lastTradeZoneIndex = z;
            Print("SELL: ", et, " R:R=1:", DoubleToString((c1 - tp) / sld, 1),
                  " Stoch:", DoubleToString(stochMainBuf[1], 1),
                  " MTF H1:", mtfH1Status, " H4:", mtfH4Status, " D1:", mtfD1Status);
            return -1;
         }
      }
   }
   return 0;
}

double FindOppositeZone(double price, int dir)
{
   double near = 0;
   double minD = 999999;
   for(int i = 0; i < totalZones; i++)
   {
      if(!zones[i].active) continue;
      if(dir == 1 && zones[i].zoneType == -1)
      {
         double d = zones[i].priceLow - price;
         if(d > 0 && d < minD) { minD = d; near = zones[i].priceLow; }
      }
      if(dir == -1 && zones[i].zoneType == 1)
      {
         double d = price - zones[i].priceHigh;
         if(d > 0 && d < minD) { minD = d; near = zones[i].priceHigh; }
      }
   }
   return near;
}

//+------------------------------------------------------------------+
//| Exit signals & partial close                                       |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   double cl = iClose(_Symbol, PERIOD_CURRENT, 1);
   int pc = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == activeMagic)
         pc++;
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      ulong tk = PositionGetInteger(POSITION_TICKET);
      long pt = PositionGetInteger(POSITION_TYPE);
      double po = PositionGetDouble(POSITION_PRICE_OPEN);
      string cm = PositionGetString(POSITION_COMMENT);
      bool az = false;

      if(pt == POSITION_TYPE_BUY)
      {
         for(int z = 0; z < totalZones; z++)
         {
            if(zones[z].active && zones[z].zoneType == -1 && cl >= zones[z].priceLow && cl > po)
            { az = true; break; }
         }
         if(az)
         {
            if(pc > 1 && StringFind(cm, "#1") >= 0) { ClosePosition(tk); MoveToBreakeven_All(); pc--; }
            else if(pc == 1) { ClosePosition(tk); pc--; }
         }
      }
      else
      {
         for(int z = 0; z < totalZones; z++)
         {
            if(zones[z].active && zones[z].zoneType == 1 && cl <= zones[z].priceHigh && cl < po)
            { az = true; break; }
         }
         if(az)
         {
            if(pc > 1 && StringFind(cm, "#1") >= 0) { ClosePosition(tk); MoveToBreakeven_All(); pc--; }
            else if(pc == 1) { ClosePosition(tk); pc--; }
         }
      }
   }
}

void MoveToBreakeven_All()
{
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      ulong tk = PositionGetInteger(POSITION_TICKET);
      long tp = PositionGetInteger(POSITION_TYPE);
      double po = PositionGetDouble(POSITION_PRICE_OPEN);
      double ps = PositionGetDouble(POSITION_SL);
      double pp = PositionGetDouble(POSITION_TP);
      double ns = (tp == POSITION_TYPE_BUY) ? NormalizeDouble(po + 5 * pt, dg) : NormalizeDouble(po - 5 * pt, dg);
      bool mv = (tp == POSITION_TYPE_BUY && ns > ps) || (tp == POSITION_TYPE_SELL && ns < ps);
      if(mv)
      {
         MqlTradeRequest r = {};
         MqlTradeResult s = {};
         r.action = TRADE_ACTION_SLTP;
         r.position = tk;
         r.symbol = _Symbol;
         r.sl = ns;
         r.tp = pp;
         if(!OrderSend(r, s)) Print("OrderSend failed: ", GetLastError());
      }
   }
}

void ClosePosition(ulong ticket)
{
   MqlTradeRequest rq = {};
   MqlTradeResult rs = {};
   if(!PositionSelectByTicket(ticket)) return;
   long pt = PositionGetInteger(POSITION_TYPE);
   double vol = PositionGetDouble(POSITION_VOLUME);
   double pf = PositionGetDouble(POSITION_PROFIT);
   double ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double ml = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   vol = MathFloor(vol / ls) * ls;
   if(vol < ml) vol = ml;

   rq.action = TRADE_ACTION_DEAL;
   rq.position = ticket;
   rq.symbol = _Symbol;
   rq.volume = vol;
   rq.deviation = 30;
   rq.magic = activeMagic;
   if(pt == POSITION_TYPE_BUY)
   {
      rq.type = ORDER_TYPE_SELL;
      rq.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      rq.type = ORDER_TYPE_BUY;
      rq.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   ENUM_ORDER_TYPE_FILLING fills[] = {ORDER_FILLING_IOC, ORDER_FILLING_FOK, ORDER_FILLING_RETURN};
   bool ok = false;
   for(int f = 0; f < 3; f++)
   {
      rq.type_filling = fills[f];
      if(OrderSend(rq, rs)) { ok = true; break; }
   }
   if(ok)
   {
      if(pf > 0)
      {
         winTrades++;
         consecutiveLosses = 0;
         if(!firstTPHit)
         {
            firstTPHit = true;
            MoveRemainingToBE();
         }
      }
      else lossTrades++;
      dailySymbolPnL += pf;
      Print("CLOSED: $", DoubleToString(pf, 2), " DayPnL:", DoubleToString(dailySymbolPnL, 2));
      NotifyTradeClosed(pf);
   }
}

//+------------------------------------------------------------------+
//| ExecuteTrade with staggered SL/TP                                  |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double atr = atrBuffer[1];
   double entry = (orderType == ORDER_TYPE_BUY) ? ask : bid;
   double slP = NormalizeDouble(signalSL, digits);
   double tpP = NormalizeDouble(signalTP, digits);

   double sld, tpd;
   if(orderType == ORDER_TYPE_BUY)
   {
      sld = entry - slP;
      tpd = tpP - entry;
   }
   else
   {
      sld = slP - entry;
      tpd = entry - tpP;
   }

   // ATR-based minimum SL
   if(UseMinSL)
   {
      double minSL = atr * MinSL_ATR_Mult;
      double maxSL = atr * MaxSL_ATR_Mult;
      
      Print("ATR CHECK: sld=", DoubleToString(sld, 2), " ATR=", DoubleToString(atr, 2),
            " min=", DoubleToString(minSL, 2), " max=", DoubleToString(maxSL, 2));
      
      if(sld > maxSL)
      {
         Print("SKIP: SL too wide ", DoubleToString(sld, 2), " > ATR max ", DoubleToString(maxSL, 2));
         return;
      }
      if(sld < minSL)
      {
         Print("SL WIDEN: ", DoubleToString(sld, 2), " -> ", DoubleToString(minSL, 2), " (ATR:", DoubleToString(atr, 2), ")");
         sld = minSL;
         slP = (orderType == ORDER_TYPE_BUY) ? NormalizeDouble(entry - sld, digits) : NormalizeDouble(entry + sld, digits);
      }
   }
   if(tpd < sld * MinRR_Ratio)
   {
      tpd = sld * 2.5;
      tpP = (orderType == ORDER_TYPE_BUY) ? NormalizeDouble(entry + tpd, digits) : NormalizeDouble(entry - tpd, digits);
   }

   double ms = stopsLevel * point;
   if(sld < ms)
   {
      sld = ms + 20 * point;
      slP = (orderType == ORDER_TYPE_BUY) ? NormalizeDouble(entry - sld, digits) : NormalizeDouble(entry + sld, digits);
   }
   if(tpd < ms)
   {
      tpd = ms + 20 * point;
      tpP = (orderType == ORDER_TYPE_BUY) ? NormalizeDouble(entry + tpd, digits) : NormalizeDouble(entry - tpd, digits);
   }

   double tLot = CalculateLotSize(sld);
   if(tLot <= 0) return;
   int pc = MathMin(PositionsPerSignal, MaxOpenTrades - CountOpenTrades());
   if(pc <= 0) return;
   double ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double ml = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double pl = MathFloor((tLot / pc) / ls) * ls;
   if(pl < ml) pl = ml;

   double slPcts[];
   double tpPcts[];
   ArrayResize(slPcts, pc);
   ArrayResize(tpPcts, pc);
   if(pc >= 1) { slPcts[0] = Pos1_SL_Pct; tpPcts[0] = Pos1_TP_Pct; }
   if(pc >= 2) { slPcts[1] = Pos2_SL_Pct; tpPcts[1] = Pos2_TP_Pct; }
   if(pc >= 3) { slPcts[2] = Pos3_SL_Pct; tpPcts[2] = Pos3_TP_Pct; }
   if(pc >= 4) { slPcts[3] = Pos4_SL_Pct; tpPcts[3] = Pos4_TP_Pct; }
   for(int p = 4; p < pc; p++) { slPcts[p] = 1.0; tpPcts[p] = 1.0; }
   
   // Scalp-only symbols: force all TPs to 100%
   if(isScalpOnly)
   {
      for(int p = 0; p < pc; p++) tpPcts[p] = 1.0;
   }

   string ts = (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   Print("=== v4.0 MTF TRADE === ", ts, " | ", lastSignalType,
         " Stoch:", DoubleToString(stochMainBuf[1], 1),
         " MTF H1:", mtfH1Status, " H4:", mtfH4Status, " D1:", mtfD1Status);

   int opened = 0;
   for(int p = 0; p < pc; p++)
   {
      entry = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double tsd = sld * slPcts[p];
      double ttd = tpd * tpPcts[p];
      if(tsd < ms) tsd = ms + 20 * point;
      if(ttd < ms) ttd = ms + 20 * point;

      double tsl, ttp;
      if(orderType == ORDER_TYPE_BUY)
      {
         tsl = NormalizeDouble(entry - tsd, digits);
         ttp = NormalizeDouble(entry + ttd, digits);
      }
      else
      {
         tsl = NormalizeDouble(entry + tsd, digits);
         ttp = NormalizeDouble(entry - ttd, digits);
      }

      MqlTradeRequest rq = {};
      MqlTradeResult rs = {};
      rq.action = TRADE_ACTION_DEAL;
      rq.symbol = _Symbol;
      rq.volume = pl;
      rq.type = orderType;
      rq.price = entry;
      rq.sl = tsl;
      rq.tp = ttp;
      rq.deviation = 30;
      rq.magic = activeMagic;
      rq.comment = "Redbot " + lastSignalType + " #" + IntegerToString(p + 1);
      rq.type_filling = ORDER_FILLING_IOC;

      bool ok = OrderSend(rq, rs);
      if(!ok) { rq.type_filling = ORDER_FILLING_FOK; ok = OrderSend(rq, rs); }
      if(!ok) { rq.type_filling = ORDER_FILLING_RETURN; ok = OrderSend(rq, rs); }
      if(!ok) { Print("POS #", p + 1, " FAILED: ", rs.retcode); continue; }

      opened++;
      totalTrades++;
      dailyTradeCount++;
      Print("POS #", p + 1, " @", DoubleToString(entry, 2),
            " SL:", DoubleToString(tsl, 2), "(", DoubleToString(slPcts[p] * 100, 0), "%)",
            " TP:", DoubleToString(ttp, 2), "(", DoubleToString(tpPcts[p] * 100, 0), "%)",
            " Lot:", pl);
      if(p < pc - 1) Sleep(200);
   }

   barsSinceLastTrade = 0;
   firstTPHit = false;
   Print("=== ", opened, "/", pc, " opened ===");
   NotifyTradeOpened(ts, entry, slP, tpP, pl * opened);

   arrowCounter++;
   string an = "RB_A_" + IntegerToString(arrowCounter);
   if(orderType == ORDER_TYPE_BUY)
   {
      ObjectCreate(0, an, OBJ_ARROW_BUY, 0, TimeCurrent(), entry);
      ObjectSetInteger(0, an, OBJPROP_COLOR, BuyArrowColor);
   }
   else
   {
      ObjectCreate(0, an, OBJ_ARROW_SELL, 0, TimeCurrent(), entry);
      ObjectSetInteger(0, an, OBJPROP_COLOR, SellArrowColor);
   }
   ObjectSetInteger(0, an, OBJPROP_WIDTH, 2);
}

double CalculateLotSize(double sld)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * (RiskPercent / 100.0);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double ml = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double atr = atrBuffer[1];
   if(sld < atr * 0.5) sld = atr * 0.5;
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(sld < stopsLevel * pt) sld = stopsLevel * pt;
   if(tv == 0 || ts == 0 || sld == 0) return ml;
   double lots = risk / ((sld / ts) * tv);
   lots = MathFloor(lots / ls) * ls;
   lots = MathMax(lots, ml);
   lots = MathMin(lots, MathMin(mx, MaxLotSize));
   lots = MathMax(lots, MinLotSize);
   Print("LOT: Bal:", DoubleToString(bal, 0), " Risk$:", DoubleToString(risk, 2), " Lot:", DoubleToString(lots, 2));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Breakeven & Trailing Stop                                          |
//+------------------------------------------------------------------+
void MoveRemainingToBE()
{
   Sleep(500);  // Let the closing order settle
   int moved = 0;
   int found = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      found++;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long posType = PositionGetInteger(POSITION_TYPE);
      
      Print("BE CHECK #", ticket, " type:", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
            " open:", DoubleToString(openPrice, 2), " SL:", DoubleToString(currentSL, 2));
      
      // Always attempt to move SL to entry - force it regardless of current SL reading
      MqlTradeRequest rq = {};
      MqlTradeResult rs = {};
      rq.action = TRADE_ACTION_SLTP;
      rq.position = ticket;
      rq.symbol = _Symbol;
      rq.sl = openPrice;
      rq.tp = currentTP;
      ResetLastError();
      if(OrderSend(rq, rs))
      {
         moved++;
         Print("BE MOVED #", ticket, " SL -> ", DoubleToString(openPrice, 2));
      }
      else
         Print("BE FAILED #", ticket, " err:", GetLastError(), " retcode:", rs.retcode);
   }
   Print("BE PROTECT: Found ", found, " remaining, moved ", moved, " to breakeven");
}

void ManageBreakeven()
{
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double atr = atrBuffer[1];
   double bd = atr * BreakevenATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      ulong tk = PositionGetInteger(POSITION_TICKET);
      double ps = PositionGetDouble(POSITION_SL);
      double pp = PositionGetDouble(POSITION_TP);
      double po = PositionGetDouble(POSITION_PRICE_OPEN);
      long tp = PositionGetInteger(POSITION_TYPE);
      
      // Skip scalp positions - only trail runners (TP > 1.2x SL distance)
      double tpDist = MathAbs(pp - po);
      double slDist = MathAbs(po - ps);
      if(slDist > 0 && tpDist / slDist < 1.2) continue;

      if(tp == POSITION_TYPE_BUY)
      {
         double b = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((b - po) >= bd && ps < po)
         {
            double ns = NormalizeDouble(po + 5 * pt, dg);
            MqlTradeRequest r = {};
            MqlTradeResult s = {};
            r.action = TRADE_ACTION_SLTP;
            r.position = tk;
            r.symbol = _Symbol;
            r.sl = ns;
            r.tp = pp;
            if(!OrderSend(r, s)) Print("OrderSend failed: ", GetLastError());
         }
      }
      else
      {
         double a = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((po - a) >= bd && ps > po)
         {
            double ns = NormalizeDouble(po - 5 * pt, dg);
            MqlTradeRequest r = {};
            MqlTradeResult s = {};
            r.action = TRADE_ACTION_SLTP;
            r.position = tk;
            r.symbol = _Symbol;
            r.sl = ns;
            r.tp = pp;
            if(!OrderSend(r, s)) Print("OrderSend failed: ", GetLastError());
         }
      }
   }
}

void ManageTrailingStop()
{
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double atr = atrBuffer[1];
   double td = atr * TrailATR_Mult;
   double ad = atr * TrailActivation;
   double mst = atr * MinTrailStep;
   double msp = stopsLevel * pt;
   if(td < msp) td = msp + 10 * pt;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      ulong tk = PositionGetInteger(POSITION_TICKET);
      double ps = PositionGetDouble(POSITION_SL);
      double pp = PositionGetDouble(POSITION_TP);
      double po = PositionGetDouble(POSITION_PRICE_OPEN);
      long tp = PositionGetInteger(POSITION_TYPE);
      
      // Skip scalp positions - only trail runners (TP > 1.2x SL distance)
      double tpDist = MathAbs(pp - po);
      double slDist = MathAbs(po - ps);
      if(slDist > 0 && tpDist / slDist < 1.2) continue;

      if(tp == POSITION_TYPE_BUY)
      {
         double b = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((b - po) < ad) continue;
         double ns = NormalizeDouble(b - td, dg);
         if(ns > ps && ns > po && (ns - ps) >= mst)
         {
            MqlTradeRequest r = {};
            MqlTradeResult s = {};
            r.action = TRADE_ACTION_SLTP;
            r.position = tk;
            r.symbol = _Symbol;
            r.sl = ns;
            r.tp = pp;
            if(!OrderSend(r, s)) Print("OrderSend failed: ", GetLastError());
         }
      }
      else
      {
         double a = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((po - a) < ad) continue;
         double ns = NormalizeDouble(a + td, dg);
         if((ns < ps || ps == 0) && ns < po && (ps - ns) >= mst)
         {
            MqlTradeRequest r = {};
            MqlTradeResult s = {};
            r.action = TRADE_ACTION_SLTP;
            r.position = tk;
            r.symbol = _Symbol;
            r.sl = ns;
            r.tp = pp;
            if(!OrderSend(r, s)) Print("OrderSend failed: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Notifications                                                      |
//+------------------------------------------------------------------+
void NotifyTradeOpened(string t, double e, double sl, double tp, double lot)
{
   string msg = "Redbot v4 " + t + " " + lastSignalType + " " + _Symbol +
                " SL:" + DoubleToString(sl, 2) +
                " TP:" + DoubleToString(tp, 2) +
                " Lot:" + DoubleToString(lot, 2);
   if(EnablePopupAlert)  Alert(msg);
   if(EnablePushNotify)  SendNotification(msg);
   if(EnableSoundAlerts) PlaySound("alert.wav");
}

void NotifyTradeClosed(double profit)
{
   string msg = "Redbot v4 " + (profit > 0 ? "WIN" : "LOSS") +
                " $" + DoubleToString(profit, 2) + " " + _Symbol;
   if(EnablePopupAlert)  Alert(msg);
   if(EnablePushNotify)  SendNotification(msg);
   if(EnableSoundAlerts) PlaySound(profit > 0 ? "ok.wav" : "alert2.wav");
}

//+------------------------------------------------------------------+
//| Daily P&L Management                                               |
//+------------------------------------------------------------------+
double GetDailyPL()
{
   return (AccountInfoDouble(ACCOUNT_BALANCE) - dailyStartBalance) +
          (AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE));
}

void CheckDailyReset()
{
   datetime td = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(td != dailyResetDate)
   {
      dailyResetDate = td;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dailyTradeCount = 0;
      dailyTargetReached = false;
      dailyLossReached = false;
   }
}

void CheckProfitTarget()
{
   double totalProfit = 0;
   int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      totalProfit += PositionGetDouble(POSITION_PROFIT);
      posCount++;
   }
   if(posCount > 0 && totalProfit >= ProfitTargetUSD)
   {
      Print("PROFIT TARGET HIT: $", DoubleToString(totalProfit, 2), " >= $", DoubleToString(ProfitTargetUSD, 2));
      CloseAllPositions();
      dailySymbolPnL += totalProfit;
      SendNotification("Redbot v4 TARGET $" + DoubleToString(totalProfit, 2) + " " + _Symbol);
   }
}

void CheckSessionProfitClose()
{
   double tp = 0;
   int pc = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      tp += PositionGetDouble(POSITION_PROFIT);
      pc++;
   }
   if(pc > 0 && tp >= SessionProfitClose)
   {
      CloseAllPositions();
      SendNotification("Redbot SESSION $" + DoubleToString(tp, 2) + " " + _Symbol);
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != activeMagic) continue;
      ClosePosition(PositionGetInteger(POSITION_TICKET));
   }
}

//+------------------------------------------------------------------+
//| Logging & Visuals                                                  |
//+------------------------------------------------------------------+
void LogBarScan()
{
   if(!LogSignalScans) return;
   totalBarsScanned++;
   barsSinceLastTrade++;
   string tr = (emaFastBuf[1] > emaMidBuf[1]) ? "UP" : "DN";
   int dz = 0, sz = 0;
   for(int i = 0; i < totalZones; i++)
   {
      if(!zones[i].active) continue;
      if(zones[i].zoneType == 1) dz++;
      else sz++;
   }
   Print("SCAN #", totalBarsScanned, " ", tr,
         " Stoch:", DoubleToString(stochMainBuf[1], 1),
         " D:", dz, " S:", sz, " H1z:", h1TotalZones,
         " MTF H4:", mtfH4Status, " D1:", mtfD1Status,
         " Wait:", barsSinceLastTrade);
}

void DrawZonesOnChart()
{
   ObjectsDeleteAll(0, "RB_Z_");
   for(int i = 0; i < totalZones; i++)
   {
      if(!zones[i].active) continue;
      string nr = "RB_Z_" + IntegerToString(i) + "r";
      string nl = "RB_Z_" + IntegerToString(i) + "l";
      color zc = (zones[i].zoneType == 1) ? DemandZoneColor : SupplyZoneColor;

      ObjectCreate(0, nr, OBJ_RECTANGLE, 0, zones[i].timeFormed, zones[i].priceHigh,
                   TimeCurrent() + PeriodSeconds() * 10, zones[i].priceLow);
      ObjectSetInteger(0, nr, OBJPROP_COLOR, zc);
      ObjectSetInteger(0, nr, OBJPROP_FILL, true);
      ObjectSetInteger(0, nr, OBJPROP_BACK, true);
      ObjectSetInteger(0, nr, OBJPROP_SELECTABLE, false);

      ObjectCreate(0, nl, OBJ_TEXT, 0, zones[i].timeFormed, zones[i].priceHigh);
      ObjectSetString(0, nl, OBJPROP_TEXT, (zones[i].zoneType == 1 ? "D" : "S") + " T:" + IntegerToString(zones[i].touches));
      ObjectSetInteger(0, nl, OBJPROP_COLOR, zc);
      ObjectSetInteger(0, nl, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nl, OBJPROP_SELECTABLE, false);
   }
   ChartRedraw(0);
}

void UpdateDashboard()
{
   if(!ShowDashboard) return;
   double atr = 0;
   if(CopyBuffer(handleATR, 0, 0, 1, atrBuffer) >= 1) atr = atrBuffer[0];
   double sp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   string tr = "?";
   double mf[], mm[];
   ArraySetAsSeries(mf, true);
   ArraySetAsSeries(mm, true);
   if(CopyBuffer(handleEMA_Fast, 0, 0, 1, mf) >= 1 && CopyBuffer(handleEMA_Mid, 0, 0, 1, mm) >= 1)
      tr = (mf[0] > mm[0]) ? "UP" : "DN";

   double sm[];
   ArraySetAsSeries(sm, true);
   string si = "?";
   if(CopyBuffer(handleStoch, 0, 0, 1, sm) >= 1) si = DoubleToString(sm[0], 1);

   int dz = 0, sz = 0;
   for(int i = 0; i < totalZones; i++)
   {
      if(!zones[i].active) continue;
      if(zones[i].zoneType == 1) dz++;
      else sz++;
   }

   string NL = "\n";
   // Update MTF status for dashboard display
   if(UseMTF)
   {
      if(UseH4_Trend && ArraySize(h4EmaFast) > 0 && ArraySize(h4EmaMid) > 0)
         mtfH4Status = (h4EmaFast[0] > h4EmaMid[0]) ? "BULL" : "BEAR";
      if(UseD1_Trend && ArraySize(d1EmaFast) > 0 && ArraySize(d1EmaMid) > 0)
         mtfD1Status = (d1EmaFast[0] > d1EmaMid[0]) ? "BULL" : "BEAR";
      if(UseW1_GainX && ArraySize(w1EmaFast) > 0 && ArraySize(w1EmaMid) > 0)
         mtfW1Status = (w1EmaFast[0] > w1EmaMid[0]) ? "BULL" : "BEAR";
      if(UseH1_Zones)
         mtfH1Status = IntegerToString(h1TotalZones) + "z";
   }
   string info = "=== RedBot v4.0 MTF ===" + NL;
   info += "Mode: " + symbolType + NL;
   info += "Trend: " + tr + " | Stoch: " + si + NL;
   info += "ATR: " + DoubleToString(atr, 2) + " Spread: " + DoubleToString(sp, 2) + NL;
   info += "Zones: D:" + IntegerToString(dz) + " S:" + IntegerToString(sz) + " H1z:" + IntegerToString(h1TotalZones) + NL;
   info += "Open: " + IntegerToString(CountOpenTrades()) + "/" + IntegerToString(MaxOpenTrades) + NL;
   info += "Bal: $" + DoubleToString(bal, 2) + " Eq: $" + DoubleToString(eq, 2) + NL;
   info += "W:" + IntegerToString(winTrades) + " L:" + IntegerToString(lossTrades) + NL;
   info += "P/L: $" + DoubleToString(GetDailyPL(), 2);
   if(dailyTargetReached) info += " TARGET";
   if(dailyLossReached) info += " LIMIT";
   info += NL;
   if(UseMTF)
      info += "MTF H1:" + mtfH1Status + " H4:" + mtfH4Status + " D1:" + mtfD1Status + " W1:" + mtfW1Status + NL;
   info += "Stag: #1=" + DoubleToString(Pos1_SL_Pct * 100, 0) + "% #2=" + DoubleToString(Pos2_SL_Pct * 100, 0) + "% #3=" + DoubleToString(Pos3_SL_Pct * 100, 0) + "%" + NL;
   info += "=======================";
   Comment(info);
}

//+------------------------------------------------------------------+
