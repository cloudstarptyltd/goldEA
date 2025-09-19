//+------------------------------------------------------------------+
//|                                     MACD_200EMA_EA.mq5           |
//|                                    https://www.mql5.com          |
//|                                                                  |
//| This Expert Advisor is based on a trading strategy combining     |
//| the MACD indicator and a 200-period Exponential Moving Average.  |
//|                                                                  |
//| Strategy Rules:                                                  |
//| - For a Buy trade: MACD crosses up below the zero line AND the   |
//|   price is above the 200 EMA.                                    |
//| - For a Sell trade: MACD crosses down above the zero line AND    |
//|   the price is below the 200 EMA.                                |
//| - Stop Loss is set below the 200 EMA for buy trades and above    |
//|   the 200 EMA for sell trades.                                   |
//| - Take Profit is set at 1.5 times the Stop Loss distance.        |
//| - Only one trade can be open at a time.                          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini"
#property link      "https://gemini.google.com"
#property version   "1.00"

// Include necessary libraries
#include <Trade\Trade.mqh>

//--- Input parameters
input double  LotSize              = 0.01;      // Trade Lot Size
input int     MagicNumber          = 12345;     // Magic Number
input int     MACD_Fast_Period     = 12;        // MACD Fast EMA Period
input int     MACD_Slow_Period     = 26;        // MACD Slow EMA Period
input int     MACD_Signal_Period   = 9;         // MACD Signal EMA Period
input int     EMA_200_Period       = 200;       // 200 EMA Period
input double  TP_Ratio             = 1.5;       // Take Profit to Stop Loss Ratio

//--- Global variables
CTrade         m_trade;           // Trading object
int            m_macd_handle;     // MACD indicator handle
int            m_ema_handle;      // EMA indicator handle
long           m_position_ticket  = 0; // Current position ticket
bool           m_new_bar_created  = false; // Flag to check for new bar
long           m_last_bar_time    = 0;     // Time of the last bar

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate input parameters
   if (LotSize <= 0) {
      Print("Error: Lot size must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (MACD_Fast_Period >= MACD_Slow_Period) {
      Print("Error: MACD Fast Period must be less than Slow Period");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (TP_Ratio <= 0) {
      Print("Error: Take Profit ratio must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Set up MACD indicator
   m_macd_handle = iMACD(_Symbol, _Period, MACD_Fast_Period, MACD_Slow_Period, MACD_Signal_Period, PRICE_CLOSE);
   if (m_macd_handle == INVALID_HANDLE) {
      Print("Failed to create MACD indicator handle. Error: ", GetLastError());
      return INIT_FAILED;
   }

   // Set up 200 EMA indicator
   m_ema_handle = iMA(_Symbol, _Period, EMA_200_Period, 0, MODE_EMA, PRICE_CLOSE);
   if (m_ema_handle == INVALID_HANDLE) {
      Print("Failed to create EMA indicator handle. Error: ", GetLastError());
      return INIT_FAILED;
   }
   
   // Set Expert Advisor properties
   m_trade.SetExpertMagicNumber(MagicNumber);
   m_trade.SetDeviationInPoints(10);
   m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Check for last bar time to avoid multiple trades on start
   m_last_bar_time = iTime(_Symbol, _Period, 0);
   
   Print("MACD+200EMA EA initialized successfully");
   Print("Symbol: ", _Symbol);
   Print("Period: ", EnumToString(_Period));
   Print("Lot Size: ", LotSize);
   Print("Magic Number: ", MagicNumber);
   Print("MACD Parameters: Fast=", MACD_Fast_Period, " Slow=", MACD_Slow_Period, " Signal=", MACD_Signal_Period);
   Print("EMA Period: ", EMA_200_Period);
   Print("TP Ratio: ", TP_Ratio);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if (m_macd_handle != INVALID_HANDLE) {
      IndicatorRelease(m_macd_handle);
   }
   if (m_ema_handle != INVALID_HANDLE) {
      IndicatorRelease(m_ema_handle);
   }
   Print("MACD+200EMA EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if a new bar has formed
   if (m_last_bar_time != iTime(_Symbol, _Period, 0)) {
      m_new_bar_created = true;
      m_last_bar_time = iTime(_Symbol, _Period, 0);
   }

   // Only check for new signals on a new bar and if no open positions
   if (m_new_bar_created && !IsPositionOpen()) {
      
      // Get indicator values
      double macd_main[], macd_signal[];
      double ema_values[];
      
      // Resize arrays
      ArrayResize(macd_main, 2);
      ArrayResize(macd_signal, 2);
      ArrayResize(ema_values, 1);
      
      // Copy indicator data
      if (CopyBuffer(m_macd_handle, 0, 0, 2, macd_main) < 2 ||
          CopyBuffer(m_macd_handle, 1, 0, 2, macd_signal) < 2 ||
          CopyBuffer(m_ema_handle, 0, 0, 1, ema_values) < 1) {
         Print("Failed to copy indicator data");
         return;
      }
      
      double macd_main_0 = macd_main[0];
      double macd_signal_0 = macd_signal[0];
      double macd_main_1 = macd_main[1];
      double macd_signal_1 = macd_signal[1];
      
      double ema_200_0 = ema_values[0];
      
      double price_open_0 = iOpen(_Symbol, _Period, 0);
      double price_close_0 = iClose(_Symbol, _Period, 0);

      //--- Check for Buy signal
      // MACD cross up below zero line
      bool macd_cross_up = (macd_main_1 <= macd_signal_1) && (macd_main_0 > macd_signal_0) && (macd_main_0 < 0);
      // Price is above 200 EMA
      bool price_above_ema = (price_close_0 > ema_200_0);
      
      if (macd_cross_up && price_above_ema) {
         // Calculate Stop Loss and Take Profit levels
         double ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double stop_loss = NormalizeDouble(ema_200_0 - 5 * _Point, _Digits); // 5 points below EMA
         double take_profit = NormalizeDouble(ask_price + (ask_price - stop_loss) * TP_Ratio, _Digits);
         
         // Send Buy order
         if (m_trade.Buy(LotSize, _Symbol, ask_price, stop_loss, take_profit, "MACD+200EMA Buy")) {
            Print("BUY order sent successfully at price: ", ask_price);
         } else {
            Print("BUY order failed. Error: ", m_trade.ResultRetcode(), " - ", m_trade.ResultComment());
         }
      }

      //--- Check for Sell signal
      // MACD cross down above zero line
      bool macd_cross_down = (macd_main_1 >= macd_signal_1) && (macd_main_0 < macd_signal_0) && (macd_main_0 > 0);
      // Price is below 200 EMA
      bool price_below_ema = (price_close_0 < ema_200_0);
      
      if (macd_cross_down && price_below_ema) {
         // Calculate Stop Loss and Take Profit levels
         double bid_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double stop_loss = NormalizeDouble(ema_200_0 + 5 * _Point, _Digits); // 5 points above EMA
         double take_profit = NormalizeDouble(bid_price - (stop_loss - bid_price) * TP_Ratio, _Digits);
         
         // Send Sell order
         if (m_trade.Sell(LotSize, _Symbol, bid_price, stop_loss, take_profit, "MACD+200EMA Sell")) {
            Print("SELL order sent successfully at price: ", bid_price);
         } else {
            Print("SELL order failed. Error: ", m_trade.ResultRetcode(), " - ", m_trade.ResultComment());
         }
      }
      
      // Reset the new bar flag
      m_new_bar_created = false;
   }
}

//+------------------------------------------------------------------+
//| Checks if there is an open position                              |
//+------------------------------------------------------------------+
bool IsPositionOpen()
{
   return PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber;
}
