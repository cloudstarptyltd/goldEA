//+------------------------------------------------------------------+
//|                                     WilliamsExternalCandle.mq5 |
//|                      Copyright 2024, Gemini |
//|                                                                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Gemini"
#property link      ""
#property version   "1.00"
#property description "Williams External Candle Trading Strategy"

//--- Input parameters
input double StopLossPips = 200; // Stop Loss in pips
input int    MagicNumber  = 12345;  // Magic number for orders
input double BaseLotSize = 0.01; // Base lot size for trading
input double LotIncrement = 0.01; // Lot size increment for losing days
input double MaxLotSize = 0.1; // Maximum lot size allowed
input bool   UseDailyPnL = true; // Enable daily profit/loss management
input bool   ShowDailyStatus = true; // Show daily profit/loss status
input bool   TradeOnlyOnTuesday = true; // Trade only on Tuesdays

//--- Global variables for daily P&L management
datetime g_last_check_date = 0;
double g_current_lot_size = 0.01;
double g_daily_profit = 0.0;
int g_daily_trades = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate input parameters
   if (StopLossPips <= 0)
   {
      Print("Error: Stop Loss must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (MagicNumber <= 0)
   {
      Print("Error: Magic Number must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (BaseLotSize <= 0)
   {
      Print("Error: Base Lot Size must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (LotIncrement <= 0)
   {
      Print("Error: Lot Increment must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (MaxLotSize < BaseLotSize)
   {
      Print("Error: Max Lot Size must be greater than or equal to Base Lot Size");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Initialize global variables
   g_current_lot_size = BaseLotSize;
   g_daily_profit = 0.0;
   g_daily_trades = 0;
   
   Print("Williams External Candle EA initialized successfully");
   Print("Symbol: ", _Symbol);
   Print("Period: ", EnumToString(_Period));
   Print("Stop Loss: ", StopLossPips, " pips");
   Print("Magic Number: ", MagicNumber);
   Print("Base Lot Size: ", BaseLotSize);
   Print("Lot Increment: ", LotIncrement);
   Print("Max Lot Size: ", MaxLotSize);
   Print("Daily P&L Management: ", UseDailyPnL ? "Enabled" : "Disabled");
   Print("Tuesday-Only Trading: ", TradeOnlyOnTuesday ? "Enabled" : "Disabled");
   
   // Show current day of week
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string day_names[] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
   Print("Current Day: ", day_names[dt.day_of_week]);
   
   if (TradeOnlyOnTuesday)
   {
      if (IsTuesday())
      {
         Print("Today is Tuesday - Trading is ACTIVE");
      }
      else
      {
         Print("Today is NOT Tuesday - Trading is DISABLED");
      }
   }
   
   // Check yesterday's status if enabled
   if (ShowDailyStatus)
   {
      CheckYesterdayStatus();
   }
   
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Williams External Candle EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Function to check yesterday's trading status                     |
//+------------------------------------------------------------------+
void CheckYesterdayStatus()
{
   datetime yesterday_start = StringToTime(TimeToString(TimeCurrent() - 86400, TIME_DATE));
   datetime yesterday_end = yesterday_start + 86400;
   
   double yesterday_profit = 0.0;
   int yesterday_trades = 0;
   double yesterday_volume = 0.0;
   
   // Check history for yesterday's trades
   if (HistorySelect(yesterday_start, yesterday_end))
   {
      int total_deals = HistoryDealsTotal();
      
      for (int i = 0; i < total_deals; i++)
      {
         ulong deal_ticket = HistoryDealGetTicket(i);
         if (deal_ticket > 0)
         {
            string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
            long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
            ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
            
            if (deal_symbol == _Symbol && deal_magic == MagicNumber)
            {
               if (deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
               {
                  yesterday_profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                  yesterday_volume += HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
                  yesterday_trades++;
               }
            }
         }
      }
   }
   
   string status = GetYesterdayStatusString(yesterday_profit, yesterday_trades, yesterday_volume);
   Print("Yesterday's Trading Status: ", status);
   
   // Update lot size based on yesterday's result
   if (UseDailyPnL)
   {
      UpdateLotSizeAndDailyStatus(yesterday_profit);
   }
}

//+------------------------------------------------------------------+
//| Function to get yesterday's status string                        |
//+------------------------------------------------------------------+
string GetYesterdayStatusString(double profit, int trades, double volume)
{
   string result = "";
   
   if (profit > 0)
   {
      result = "PROFIT: $" + DoubleToString(profit, 2);
   }
   else if (profit < 0)
   {
      result = "LOSS: $" + DoubleToString(MathAbs(profit), 2);
   }
   else
   {
      result = "BREAKEVEN: $0.00";
   }
   
   result += " | Trades: " + IntegerToString(trades);
   result += " | Volume: " + DoubleToString(volume, 2);
   
   return result;
}

//+------------------------------------------------------------------+
//| Function to update lot size based on daily P&L                   |
//+------------------------------------------------------------------+
void UpdateLotSizeAndDailyStatus(double yesterday_profit)
{
   if (yesterday_profit > 0)
   {
      // Profitable day - continue trading with base lot size
      g_current_lot_size = BaseLotSize; // Reset to base lot size
      Print("Yesterday was PROFITABLE ($", DoubleToString(yesterday_profit, 2), 
            "). Trading CONTINUES with base lot size: ", g_current_lot_size);
   }
   else if (yesterday_profit < 0)
   {
      // Losing day - increment lot size and continue trading
      g_current_lot_size = MathMin(g_current_lot_size + LotIncrement, MaxLotSize);
      Print("Yesterday was a LOSS ($", DoubleToString(MathAbs(yesterday_profit), 2), 
            "). Lot size INCREMENTED to: ", g_current_lot_size);
   }
   else
   {
      // Breakeven day - continue with current lot size
      Print("Yesterday was BREAKEVEN. Continuing with current lot size: ", g_current_lot_size);
   }
}

//+------------------------------------------------------------------+
//| Function to check if it's a new day                              |
//+------------------------------------------------------------------+
bool IsNewDay()
{
   datetime current_date = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   if (current_date != g_last_check_date)
   {
      g_last_check_date = current_date;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Function to check if today is Tuesday                            |
//+------------------------------------------------------------------+
bool IsTuesday()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Tuesday is day of week 2 (Sunday=0, Monday=1, Tuesday=2, etc.)
   return (dt.day_of_week == 2);
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if it's a new day and update daily status
   if (IsNewDay() && UseDailyPnL)
   {
      CheckYesterdayStatus();
   }
   
   // Check if Tuesday-only trading is enabled and today is not Tuesday
   if (TradeOnlyOnTuesday && !IsTuesday())
   {
      return; // Skip trading on non-Tuesday days
   }
   
   // Check if we have open positions with our magic number
   bool has_position = false;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetTicket(i) > 0)
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol && 
             PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            has_position = true;
            break;
         }
      }
   }
   
   if (has_position)
   {
      CheckAndClosePositions();
      return;
   }
   
   // We only need to check at the close of a candle
   if (!IsNewCandle())
   {
      return;
   }
   
   // Check for the trading signal
   int signal = GetTradingSignal();
   
   if (signal == 1) // Bullish signal
   {
      // Open a buy position with current lot size
      OpenPosition(ORDER_TYPE_BUY, StopLossPips, g_current_lot_size);
   }
   else if (signal == -1) // Bearish signal
   {
      // Open a sell position with current lot size
      OpenPosition(ORDER_TYPE_SELL, StopLossPips, g_current_lot_size);
   }
}
//+------------------------------------------------------------------+
//| Function to check for new candle                                 |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, _Period, 0);
   
   if (current_bar_time != last_bar_time)
   {
      last_bar_time = current_bar_time;
      return true;
   }
   
   return false;
}
//+------------------------------------------------------------------+
//| Function to get trading signal                                   |
//+------------------------------------------------------------------+
int GetTradingSignal()
{
   // Get price data for the last 3 candles
   double high[], low[], close[], open[];
   int count = 3; // We need 3 bars (0, 1, 2)
   
   ArrayResize(high, count);
   ArrayResize(low, count);
   ArrayResize(close, count);
   ArrayResize(open, count);
   
   if (CopyHigh(_Symbol, _Period, 0, count, high) < count ||
       CopyLow(_Symbol, _Period, 0, count, low) < count ||
       CopyClose(_Symbol, _Period, 0, count, close) < count ||
       CopyOpen(_Symbol, _Period, 0, count, open) < count)
   {
      Print("Failed to copy historical data");
      return 0;
   }
   
   // Check for a bullish signal (Bearish external candle)
   // An external candle has a high greater than the previous high and a low lower than the previous low
   // The signal candle must be a bearish candle (close[1] < open[1])
   // The close of the external candle must be below the low of the previous candle
   if (high[1] > high[2] && low[1] < low[2] && close[1] < open[1] && close[1] < low[2])
   {
      return 1; // Bullish signal
   }
   
   // Check for a bearish signal (Bullish external candle)
   // An external candle has a high greater than the previous high and a low lower than the previous low
   // The signal candle must be a bullish candle (close[1] > open[1])
   // The close of the external candle must be above the high of the previous candle
   if (high[1] > high[2] && low[1] < low[2] && close[1] > open[1] && close[1] > high[2])
   {
      return -1; // Bearish signal
   }
   
   return 0; // No signal
}
//+------------------------------------------------------------------+
//| Function to open a position                                      |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE order_type, double stop_loss_pips, double lot_size)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = lot_size;
   request.type   = order_type;
   request.type_filling = ORDER_FILLING_FOK;
   request.magic  = MagicNumber;
   
   double price;
   double stop_loss_price = 0;
   
   // Get current price
   MqlTick tick;
   if (!SymbolInfoTick(Symbol(), tick))
   {
      Print("Failed to get tick info");
      return;
   }
   
   if (order_type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      stop_loss_price = price - stop_loss_pips * _Point;
   }
   else
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      stop_loss_price = price + stop_loss_pips * _Point;
   }
   
   request.price = price;
   request.sl    = stop_loss_price;
   
   // Send the order
   if (!OrderSend(request, result))
   {
      Print("OrderSend failed, error code: ", GetLastError());
   }
   else
   {
      Print("Order placed successfully, ticket: ", result.deal);
   }
}
//+------------------------------------------------------------------+
//| Function to check and close positions                            |
//+------------------------------------------------------------------+
void CheckAndClosePositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetTicket(i) > 0)
      {
         string symbol_name = PositionGetString(POSITION_SYMBOL);
         long position_magic = PositionGetInteger(POSITION_MAGIC);
         
         if (symbol_name == _Symbol && position_magic == MagicNumber)
         {
            long position_ticket = PositionGetInteger(POSITION_TICKET);
            datetime position_time = (datetime)PositionGetInteger(POSITION_TIME);
            
            // Close positions at the beginning of the next session (next day)
            // Check if a new day has started since position was opened
            datetime current_time = TimeCurrent();
            if (current_time >= position_time + 86400) // 24 hours = 86400 seconds
         {
            ClosePosition(position_ticket);
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Function to close a position                                     |
//+------------------------------------------------------------------+
void ClosePosition(long position_ticket)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   
   request.action = TRADE_ACTION_DEAL;
   request.position = position_ticket;
   
   double price;
   ENUM_ORDER_TYPE order_type;
   
   if (PositionSelectByTicket(position_ticket))
   {
      order_type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
      request.volume = PositionGetDouble(POSITION_VOLUME);
      request.symbol = PositionGetString(POSITION_SYMBOL);
      
      if (order_type == POSITION_TYPE_BUY)
      {
         price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
         request.type = ORDER_TYPE_SELL;
      }
      else
      {
         price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
         request.type = ORDER_TYPE_BUY;
      }
      
      request.price = price;
      
      if (!OrderSend(request, result))
      {
         Print("Failed to close position ", position_ticket, ", error code: ", GetLastError());
      }
      else
      {
         Print("Position ", position_ticket, " closed successfully");
      }
   }
}
