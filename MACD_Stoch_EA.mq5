//+------------------------------------------------------------------+
//|                                                MACD_Stoch_EA.mq5 |
//|                                      Copyright 2024, Farid Zarie |
//|                                        https://github.com/Far-1d |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Farid Zarie"
#property link      "https://github.com/Far-1d"
#property version   "1.30"
#property description "این اکسپرت با بررسی دو مکدی مختلف یه گام و پولبک را تشخیص میدهد و به کمک اسنایپر کندل تریگر را انجام میدهد."
#property description "به منظور اطمینان از ادامه حرکت گام از استوکاستیک استفاده میشه و برای اعمال حد سود و ضرر از "
#property description "استفاده میشود atr"
#property description ""
#property description ""
#property description ""
#property description ""
#property description "added button to trader with alert"

//--- import library
#include <trade/trade.mqh>
CTrade trade;

#include <Controls/Dialog.mqh>
CAppDialog app;

#include <Controls/Button.mqh>
CButton btn;

#include <Controls/Label.mqh>
CLabel lbl;


//--- enum
enum yes_no{
   yes,     // Yes
   no       // No
};
enum p_res{
   yeah,    // Yes
   nope,    // No
   rfit,    // Use Risk Free 
};
enum smoothes {
   RMA,
   SMA,
   EMA,
   WMA
};

//--- input
input group "<<===      LEVEL 0 Setting     ===>>";
input ENUM_TIMEFRAMES tf_1             = PERIOD_H1;      // TimeFrame 1
input ENUM_TIMEFRAMES tf_2             = PERIOD_M30;     // TimeFrame 2
input string          start_time       = "08:00";        // Start Time
input string          end_time         = "20:00";        // End Time

input group "<<===       MACD Setting       ===>>";
input int         big_macd_Fast        = 48;       // 4x MACD Fast EMA
input int         big_macd_Slow        = 104;      // 4x MACD Slow EMA
input int         big_macd_Smooth      = 9;        // 4x MACD Smooth
input int         small_macd_Fast      = 12;       // 1x MACD Fast EMA
input int         small_macd_Slow      = 26;       // 1x MACD Slow EMA
input int         small_macd_Smooth    = 9;        // 1x MACD Smooth

input group "<<===       Stoch Setting       ===>>";
input int         stock_k              = 20;       // Stochastic %K
input int         stock_d              = 3;        // Stochastic %D
input int         stock_slow           = 3;        // Stochastic Slowing
input int         stock_upper          = 80;       // Stochastic Upper Band
input int         stock_lower          = 20;       // Stochastic Lower Band

input group "<<===        ATR Setting        ===>>";
input int         atr_length           = 14;       // Length
input smoothes    atr_smooth           = RMA;      // Smoothing
input double      atr_multi_1          = 1.5;      // Multiplier #1
input double      atr_multi_2          = 0;      // Multiplier #2 ( 0 = off )

input group "<<===      Postion Setting      ===>>";
input int         RR                   = 2;        // Risk to Reward
input double      lot_percent          = 1;        // Balance Used (%)
input yes_no      open_second_pos      = yes;      // Open Second Trade
input p_res       close_first_pos      = nope;     // Close First Trade in Lose
input int         Magic                = 11211;    // Magic

input group "<<===      Panel Setting      ===>>";
input color       bg_color             = clrGold;  // button bg color

//--- Globals
int macd_4x_handle, macd_1x_handle, stock_handle, atr_handle; 
int change_bar = 10;
bool allow_pass = true;
bool pass_to_lvl_3_buy = false;
bool pass_to_lvl_3_sell = false;
int history_total;
bool main_position_open_buy = false;
bool main_position_open_sell = false;
string dataArray[];
bool traded_current_macd = false;
bool trade_1_closed = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(Magic);
   history_total = HistoryDealsTotal();
   
   macd_4x_handle = iMACD(_Symbol, PERIOD_CURRENT, big_macd_Fast, big_macd_Slow, big_macd_Smooth, PRICE_CLOSE);
   macd_1x_handle = iMACD(_Symbol, PERIOD_CURRENT, small_macd_Fast, small_macd_Slow, small_macd_Smooth, PRICE_CLOSE);
   stock_handle   = iStochastic(_Symbol, PERIOD_CURRENT, stock_k, stock_d, stock_slow, MODE_EMA,STO_LOWHIGH);
   atr_handle     = iCustom(_Symbol, PERIOD_CURRENT, "market/ATR Stop Loss Finder", atr_length, atr_smooth, atr_multi_1, atr_multi_2);
   
   if (macd_4x_handle == INVALID_HANDLE || macd_1x_handle == INVALID_HANDLE || stock_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
   {
      Print("indicator error");
      return (INIT_FAILED);
   }
   // check initially if macd changed fase priorly
   check_current_macd();
   
   app.Create(0, "", 0, 30,30, 200, 130);
   btn.Create(0, "button", 0, 0, 0, 162, 35);
   btn.ColorBackground(bg_color);
   btn.Text("enable");
   app.Add(btn);
   
   lbl.Create(0, "label", 0, 50, 40, 112, 30);
   lbl.Text("deactive");
   lbl.Color(clrTomato);
   app.Add(lbl);
   app.Run();
   
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   IndicatorRelease(macd_4x_handle);
   IndicatorRelease(macd_1x_handle);
   IndicatorRelease(stock_handle);
   IndicatorRelease(atr_handle);
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static int total_bars = iBars(_Symbol, PERIOD_CURRENT);
   int bars = iBars(_Symbol,PERIOD_CURRENT);
   
   if (total_bars != bars)
   {
      datetime
         start = StringToTime(start_time),
         end = StringToTime(end_time);
      
      if (TimeCurrent() >= start && TimeCurrent()<=end)
      { 
         int level0_res = check_level_0();
         int level1_res = check_macd();
         if ( (level0_res == 1 && level1_res == 1 && !traded_current_macd) || pass_to_lvl_3_buy)
         { Print("----- lvl 1 2 3 passed -----");
            if (pass_to_lvl_3_buy) check_macd_size("BUY");
            if (check_sniper_candle("BUY"))
            { Print("----- lvl 4 passed -----");
               if (check_macd_size("BUY"))
               {Print("-----  lvl 5 passed -----");
                  if (check_stoch("BUY"))
                  {
                     Alert("Signal is 100% ok for Buy");
                     open_position("BUY");
                  }
                  else
                  {
                     Alert("medium buy signal");
                     draw_objects(clrSeaGreen);
                  }
               }
            }
         }
         else if ((level0_res == -1 && level1_res == -1 && !traded_current_macd) || pass_to_lvl_3_sell)
         { Print("----- lvl 1 2 3 passed -----");
            if (pass_to_lvl_3_sell) check_macd_size("SELL");
            if (check_sniper_candle("SELL"))
            { Print("----- lvl 4 passed -----");
               if (check_macd_size("SELL"))
               { Print("-----  lvl 5 passed -----");
                  if (check_stoch("SELL"))
                  {
                     Alert("Signal is 100% ok for Sell");
                     open_position("SELL");
                  }
                  else
                  {
                     Alert("medium sell signal");
                     draw_objects(clrSienna);
                  }
               }
            }
         }
      }
      
      total_bars = bars;
   }
   
   if (PositionsTotal()==1 && open_second_pos==yes)
   {
      check_retrace();
   }
   
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   ENUM_TRADE_TRANSACTION_TYPE type=(ENUM_TRADE_TRANSACTION_TYPE)trans.type; 
   if(type == TRADE_TRANSACTION_DEAL_ADD) 
   {
      int pos = CheckMatch((string)trans.position);
      if (pos == -1)
      {
         add_to_array((string)trans.position);
      }
      else
      {
         ulong tikt = trans.deal;
         HistoryDealSelect(tikt);
         double profit     = HistoryDealGetDouble(tikt, DEAL_PROFIT);
         long   p_type      = HistoryDealGetInteger(tikt, DEAL_TYPE);
         
         if (profit <0) 
         {
            if (trade_1_closed) trade_1_closed = false;
            else
            {
               if (p_type == DEAL_TYPE_SELL && allow_pass) 
               {
                  Print("pass to level 3 buy activated");
                  pass_to_lvl_3_buy = true;
               }
               if (p_type == DEAL_TYPE_BUY && allow_pass) 
               {
                  pass_to_lvl_3_sell = true;
                  Print("pass to level 3 sell activated");
               }
            }
         }
      }
   }
}


//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| check level 0: 1h or 30min candle                                |
//+------------------------------------------------------------------+
int check_level_0(){
   double
      close_0_1  = iClose(_Symbol, tf_1, 1),
      open_1_1   = iOpen(_Symbol, tf_1, 2),
      close_1_1  = iClose(_Symbol, tf_1, 2),
      high_1_1   = iHigh(_Symbol, tf_1, 2),
      low_1_1    = iLow(_Symbol, tf_1, 2),
      
      close_0_2  = iClose(_Symbol, tf_2, 1),
      open_1_2   = iOpen(_Symbol, tf_2, 2),
      close_1_2  = iClose(_Symbol, tf_2, 2),
      high_1_2   = iHigh(_Symbol, tf_2, 2),
      low_1_2    = iLow(_Symbol, tf_2, 2);
   
   if (close_0_1 >= high_1_1) return 1;
   else if (close_0_1 <= low_1_1) return -1;
   
   if (close_0_2 >= high_1_2) return 1;
   else if (close_0_2 <= low_1_2) return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| check level 1 and 2 : macd values                                |
//+------------------------------------------------------------------+
int check_macd(){
   double big_macd_histo[], small_macd_histo[];
   ArraySetAsSeries(big_macd_histo, true);
   ArraySetAsSeries(small_macd_histo, true);
   
   CopyBuffer(macd_4x_handle, MAIN_LINE, 1, 2, big_macd_histo);
   CopyBuffer(macd_1x_handle, MAIN_LINE, 1, 2, small_macd_histo);
   
   if ((big_macd_histo[1]>=0 && big_macd_histo[0]<0)  || (big_macd_histo[1]<=0 && big_macd_histo[0]>0))
   {
      Print("current macd FALSE");
      traded_current_macd = false;
      allow_pass = true;
   }
   if (!traded_current_macd)
   {
      if (big_macd_histo[0] > 0 && small_macd_histo[1]<=0 && small_macd_histo[0]>0 ) traded_current_macd=true;
      if (big_macd_histo[0] < 0 && small_macd_histo[1]>=0 && small_macd_histo[0]<0 ) traded_current_macd=true;
   }
   
   if (big_macd_histo[0] > 0 && small_macd_histo[0] < 0 )  return 1;
   else if (big_macd_histo[0] < 0 && small_macd_histo[0] > 0 )  return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| check lvl 3 : sniper candle                                      |
//+------------------------------------------------------------------+
bool check_sniper_candle(string type){
   double close_0  = iClose(_Symbol, PERIOD_CURRENT, 1);
      
   if (type == "BUY")
   {
      for (int i=2; i<10; i++){
         double
            close  = iClose(_Symbol, PERIOD_CURRENT, i),
            open   = iOpen(_Symbol, PERIOD_CURRENT, i),
            high   = iHigh(_Symbol, PERIOD_CURRENT, i);
         
         if (close < open && high <= close_0) // bearish with next candle covering it
         {
            return true;
         }
      }
   }
   
   else 
   {
      for (int i=2; i<10; i++){
         double
            close  = iClose(_Symbol, PERIOD_CURRENT, i),
            open   = iOpen(_Symbol, PERIOD_CURRENT, i),
            low    = iLow(_Symbol, PERIOD_CURRENT, i);
         if (close > open && low >= close_0)
         {
            return true;
         }
      }
   }
   
   return false;
}


//+------------------------------------------------------------------+
//| check level 4 : macd histo size comparison                       |
//+------------------------------------------------------------------+
bool check_macd_size(string type){
   double big_macd_histo[], small_macd_histo[];
   ArraySetAsSeries(big_macd_histo, true);
   ArraySetAsSeries(small_macd_histo, true);
   
   CopyBuffer(macd_4x_handle, MAIN_LINE, 1, 50, big_macd_histo);
   CopyBuffer(macd_1x_handle, MAIN_LINE, 1, 50, small_macd_histo);
   
   double large_histo_value=0;
   
   if (fabs(big_macd_histo[0]) < fabs(small_macd_histo[0]))
   {
      allow_pass = false;
      if (pass_to_lvl_3_buy || pass_to_lvl_3_sell) Print("pass to level 3 cancelled");
      pass_to_lvl_3_buy = false;
      pass_to_lvl_3_sell = false;
   }
   
   if (type == "BUY")
   {      
      for (int i=0; i<20; i++){
         if (small_macd_histo[i]<0)
         {
            if (small_macd_histo[i] < large_histo_value)
            {
               large_histo_value = small_macd_histo[i];
            }
         } else break;
      }
      if (fabs(big_macd_histo[0]) >= fabs(large_histo_value)) return true;
   }
   else
   {
      for (int i=0; i<20; i++){
         if (small_macd_histo[i]>0)
         {
            if (small_macd_histo[i] > large_histo_value)
            {
               large_histo_value = small_macd_histo[i];
            }
         } else break;
      }
      if (fabs(big_macd_histo[0]) >= fabs(large_histo_value)) return true;
   }
   
   return false;
}


//+------------------------------------------------------------------+
//| check level 5 : stock d value must be saturated                  |
//+------------------------------------------------------------------+
bool check_stoch(string type){
   double stock_array[], small_macd_histo[];
   
   ArraySetAsSeries(stock_array, true);
   ArraySetAsSeries(small_macd_histo, true);

   CopyBuffer(stock_handle, SIGNAL_LINE, 1, 10, stock_array);
   CopyBuffer(macd_1x_handle, MAIN_LINE, 1, 10, small_macd_histo);
   
   if (type == "BUY")
   {
      //--- find where macd changed sign
      for (int i=0; i<10; i++){
         if (small_macd_histo[i]>0)
         {
            change_bar = i;
            break;
         }
      }
      
      for(int i=0;i<change_bar; i++){
         if (stock_array[i] <=stock_lower) return true;
      }
   }
   else
   {
      //--- find where macd changed sign
      for (int i=0; i<10; i++){
         if (small_macd_histo[i]<0)
         {
            change_bar = i;
            break;
         }
      }
      
      for(int i=0;i<change_bar; i++){
         if (stock_array[i] >=stock_upper) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void open_position(string type){
   double
      ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
      bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID),
      sl    = find_sl(type),
      tp    = type=="BUY" ? ((ask-sl)*RR)+ask : bid-((sl-bid)*RR);
   
   int sl_distance = type=="BUY" ? (int)((ask-sl)/_Point) : (int)((sl-bid)/_Point);
   double lot_size = calculate_lot(sl_distance);
   
   if (type == "BUY")
   {
      trade.Buy(lot_size, _Symbol, 0, sl, tp);
      Alert("Trade Buy  @",SymbolInfoDouble(_Symbol, SYMBOL_ASK), "  sl=",sl, "    tp=",tp);
      pass_to_lvl_3_buy = false;
      main_position_open_buy=true;
      traded_current_macd = true;
   }
   else
   {
      trade.Sell(lot_size, _Symbol, 0, sl, tp);
      Alert("Trade Sell  @",SymbolInfoDouble(_Symbol, SYMBOL_BID), "  sl=",sl, "    tp=",tp);
      pass_to_lvl_3_sell=false;
      main_position_open_sell=true;
      traded_current_macd = true;
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double find_sl(string type){
   double atr_array_buy[], atr_array_sell[];
   ArraySetAsSeries(atr_array_buy, true);
   ArraySetAsSeries(atr_array_sell, true);
   
   CopyBuffer(atr_handle, 0, 1, 20, atr_array_buy); // buy sl
   CopyBuffer(atr_handle, 1, 1, 20, atr_array_sell); // sell sl
   
   double sl=type=="BUY" ? atr_array_buy[0] : atr_array_sell[0];
   
   int last = MathMin(10, MathMax(5, change_bar)); 
   for (int i=0; i<last; i++){
      
      int counter=0;
      if (type=="BUY")
      {
         if (atr_array_buy[i]<sl) 
         {
            sl=atr_array_buy[i];
         }
      }
      else
      {
         if (atr_array_sell[i]>sl) 
         {
            sl=atr_array_sell[i];
         }
      }
      
      counter ++;
   }
   
   return sl;
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double calculate_lot(int sl_distance){
   double balance       = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxRisk       = balance*lot_percent/100;
   
   string base_symbol = StringSubstr(_Symbol, 0, 3);
   StringToUpper(base_symbol);
   double _multiplier = 1;                   // since for some symbols point value is wrong there must be a multiplier to fix it
   if (base_symbol == "XAU") _multiplier = 1;
   
   double tickValue     = _multiplier * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double contractSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double max_lot       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double min_lot       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   double lots = NormalizeDouble(maxRisk / (sl_distance * tickValue), 2);
   return MathMax(min_lot, MathMin(max_lot, lots));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void draw_objects(color clr){
   string name = "V_LINE_"+TimeToString(TimeCurrent());
   ObjectCreate(0, name, OBJ_VLINE, 0, TimeCurrent(), 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void check_retrace(){
   ulong tikt = PositionGetTicket(0);
   ENUM_POSITION_TYPE p_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   datetime p_time = (datetime)PositionGetInteger(POSITION_TIME);
   double 
      p_start     = PositionGetDouble(POSITION_PRICE_OPEN),
      p_current   = PositionGetDouble(POSITION_PRICE_CURRENT),
      p_sl        = PositionGetDouble(POSITION_SL),
      p_tp        = PositionGetDouble(POSITION_TP);
   
   int candle = iBarShift(_Symbol, PERIOD_CURRENT, p_time)+1;
   double
      high = iHigh(_Symbol, PERIOD_CURRENT, candle),
      low = iLow(_Symbol,PERIOD_CURRENT, candle);
   
   if (p_type == POSITION_TYPE_BUY && main_position_open_buy)
   {
      if ( p_current < (high+low)/2 )
      {
         Print("----------  should buy back  ------------");
         double lot_size = calculate_lot((int)((p_current-p_sl)/_Point));
         if (trade.Buy(lot_size, _Symbol, 0, p_sl, p_tp))
         {
            Alert("Trade Second Buy  @",SymbolInfoDouble(_Symbol, SYMBOL_ASK), "  sl=",p_sl, "    tp=",p_tp);
            main_position_open_buy = false;
            
            if (close_first_pos==yeah)
            {
               trade_1_closed = true;
               trade.PositionClose(tikt);
            }
            else if (close_first_pos==rfit)
            {
               trade.PositionModify(tikt, p_sl, p_start+(_Point*5));
            }
         }
      }
   }
   else if (p_type == POSITION_TYPE_SELL && main_position_open_sell)
   {
      if ( p_current > (high+low)/2 )
      {
         Print("-------------  should sell back  --------------");
         double lot_size = calculate_lot((int)((p_sl-p_current)/_Point));
         if(trade.Sell(lot_size, _Symbol, 0, p_sl, p_tp))
         {
            Alert("Trade Second Sell  @",SymbolInfoDouble(_Symbol, SYMBOL_BID), "  sl=",p_sl, "    tp=",p_tp);
            main_position_open_sell=false;
            
            if (close_first_pos==yeah)
            {
               trade_1_closed = true;
               trade.PositionClose(tikt);
            }
            else if (close_first_pos==rfit)
            {
               trade.PositionModify(tikt, p_sl, p_start-(_Point*5));
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CheckMatch(string tikt){
   int size = ( int )ArraySize(dataArray);
   for (int i=0; i<size; i++)
   {
      if (dataArray[i] == tikt)
      {
         return i;
      }
   }
   return -1;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void add_to_array(string tikt){
   int size = ( int )ArraySize(dataArray);
   ArrayResize(dataArray, size+1);
   dataArray[size] = tikt;
}

//+--------------------------------------------------------------------------+
//| checks macd history on init to see if a prior trade could have happened  |
//+--------------------------------------------------------------------------+
void check_current_macd(){
   double big_histo[], small_histo[];
   ArraySetAsSeries(big_histo, true);
   ArraySetAsSeries(small_histo, true);
   
   CopyBuffer(macd_4x_handle, MAIN_LINE, 1, 100, big_histo);
   CopyBuffer(macd_1x_handle, MAIN_LINE, 1, 101, small_histo);
   
   int change_candle = 100;
   for (int i=0; i<100; i++){
      if (big_histo[0] > 0){
         if (big_histo[i]<0) 
         {
            change_candle = i; 
            break;
         }
      }
      if (big_histo[0] < 0){
         if (big_histo[i]>0)
         {
            change_candle = i; 
            break;
         }
      }
   }
   
   for (int i=0; i<change_candle; i++){
      if (big_histo[0]>0){
         if (small_histo[i]>0 && small_histo[i+1]<=0) traded_current_macd = true;
      }
      if (big_histo[0]<0){
         if (small_histo[i]<0 && small_histo[i+1]>=0) traded_current_macd = true;
      }
   }
   Print("last macd sign change was ",change_candle," candles ago and ", traded_current_macd?" smaller macd changed sign during this time":" smaller macd didn't change sign this time");

}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long& lparam,const double& dparam,const string& sparam)
{
   app.ChartEvent(id, lparam, dparam, sparam);
   if (id == CHARTEVENT_OBJECT_CLICK)
   {
      if (sparam == btn.Name() && lbl.Text() == "deactive")
      {
         double big_macd_histo[];
         ArraySetAsSeries(big_macd_histo, true);
         CopyBuffer(macd_4x_handle, MAIN_LINE, 1, 1, big_macd_histo);
         
         if (big_macd_histo[0]>0) 
         {
            pass_to_lvl_3_buy = true;
            pass_to_lvl_3_sell = false;
         }else 
         {
            pass_to_lvl_3_sell = true;
            pass_to_lvl_3_buy = false;
         }
         lbl.Text("active");
         lbl.Color(clrSeaGreen);
      }
      else if (sparam == btn.Name() && lbl.Text() == "active")
      {
         pass_to_lvl_3_buy = false;
         pass_to_lvl_3_sell = false;
         
         lbl.Text("deactive");
         lbl.Color(clrTomato);
      }
   }
}