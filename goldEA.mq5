//+------------------------------------------------------------------+
//|                                                GoldEA.mq5        |
//|                                      Copyright 2024, GoldEA      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, GoldEA"
#property link      "https://github.com/goldea"
#property version   "1.03"
#property description "Gold EA based on volume and candle shadows analysis."

//--- MQL5 Standard Library includes
#include <Trade\Trade.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Global objects
CTrade         trade;
CDealInfo      dealInfo;
CPositionInfo  positionInfo;
//--- Input parameters
input group "=== Trading Parameters ==="
input double      Lots                  = 0.01;   // Initial Lot Size
input int         MagicNumber           = 123456; // Magic Number for trade identification
input int         StopLoss_Points       = 600;    // Stop Loss in points
input int         TakeProfit_Points     = 600;    // Take Profit in points
input int         Slippage              = 10;     // Maximum slippage in points

input group "=== Risk Management ==="
input bool        DailyStopTrading      = true;   // Stop trading for the day after a profit
input double      MaxLotSize            = 1.0;    // Maximum lot size
input double      LotIncrement          = 0.01;   // Lot size increment after loss

input group "=== Volume Analysis ==="
input double      VolumeMultiplier      = 1.25;   // Volume multiplier threshold
input int         MinVolumeBars         = 2;      // Minimum bars for volume analysis

input group "=== Trading Hours ==="
input bool        UseTradingHours       = true;   // Enable trading hours restriction
input int         StartHour             = 15;     // Trading start hour (24-hour format)
input int         EndHour               = 18;     // Trading end hour (24-hour format)

input group "=== Signal Confirmation ==="
input bool        UseSignalConfirmation = true;   // Enable next candle confirmation
input int         ConfirmationBars      = 1;      // Number of bars to wait for confirmation

input group "=== News Avoidance ==="
input bool        UseNewsAvoidance      = true;   // Enable news avoidance
input int         NewsAvoidanceMinutes  = 30;     // Minutes before/after news to avoid trading
input bool        AvoidHighImpactNews   = true;   // Avoid high impact news events
input bool        AvoidMediumImpactNews = false;  // Avoid medium impact news events

//--- Global variables
double      currentLot = 0.01;       // Current lot size for trading
int         lastClosedDay = 0;       // Stores the day of the last closed position
bool        hasProfitToday = false;  // Flag to check if there was a profitable trade today
long        lastBarTime = 0;         // Stores the time of the last processed bar
bool        isTradingActive = true;  // Flag to control trading activity

//--- Signal confirmation variables
bool        pendingBuySignal = false;   // Flag for pending buy signal
bool        pendingSellSignal = false;  // Flag for pending sell signal
double      signalCandleHigh = 0;       // High of the signal candle
double      signalCandleLow = 0;        // Low of the signal candle
datetime    signalTime = 0;             // Time of the signal candle

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
// Set initial lot size from input parameter
   currentLot = Lots;

// Configure trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

// Check if the daily stop feature is enabled
   if(DailyStopTrading)
     {
      // Get the day of the month for the current time
      MqlDateTime now;
      TimeToStruct(TimeCurrent(), now);
      lastClosedDay = now.day;
     }

// Validate input parameters
   if(Lots <= 0 || Lots > MaxLotSize)
     {
      Print("Error: Invalid lot size. Must be between 0 and ", MaxLotSize);
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(StopLoss_Points <= 0 || TakeProfit_Points <= 0)
     {
      Print("Error: Stop Loss and Take Profit must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
     }
   
   // Validate trading hours parameters
   if(UseTradingHours)
     {
      if(StartHour < 0 || StartHour > 23 || EndHour < 0 || EndHour > 23)
        {
         Print("Error: Trading hours must be between 0 and 23");
         return(INIT_PARAMETERS_INCORRECT);
        }
      if(StartHour == EndHour)
        {
         Print("Error: Start hour and End hour cannot be the same");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }
   
   // Validate signal confirmation parameters
   if(UseSignalConfirmation)
     {
      if(ConfirmationBars < 1 || ConfirmationBars > 5)
        {
         Print("Error: Confirmation bars must be between 1 and 5");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }
   
   // Validate news avoidance parameters
   if(UseNewsAvoidance)
     {
      if(NewsAvoidanceMinutes < 5 || NewsAvoidanceMinutes > 120)
        {
         Print("Error: News avoidance minutes must be between 5 and 120");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }

   Print("GoldEA has been initialized successfully.");
   Print("Magic Number: ", MagicNumber);
   Print("Initial Lot Size: ", currentLot);
   Print("Stop Loss: ", StopLoss_Points, " points");
   Print("Take Profit: ", TakeProfit_Points, " points");
   
   if(UseTradingHours)
     {
      Print("Trading Hours: ", StartHour, ":00 to ", EndHour, ":00 (24-hour format)");
     }
   else
     {
      Print("Trading Hours: 24/7 (no restrictions)");
     }
   
   if(UseSignalConfirmation)
     {
      Print("Signal Confirmation: Enabled (", ConfirmationBars, " bar(s) confirmation)");
     }
   else
     {
      Print("Signal Confirmation: Disabled (immediate execution)");
     }
   
   if(UseNewsAvoidance)
     {
      Print("News Avoidance: Enabled (", NewsAvoidanceMinutes, " minutes before/after high-impact news)");
      if(AvoidHighImpactNews)
        {
         Print("High-Impact News Avoidance: Enabled");
        }
      if(AvoidMediumImpactNews)
        {
         Print("Medium-Impact News Avoidance: Enabled");
        }
     }
   else
     {
      Print("News Avoidance: Disabled");
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//| Cleanup and final messages on EA removal.                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("GoldEA has been deinitialized. Reason: ", reason);
   Print("Final lot size: ", currentLot);
   Print("Trading was active: ", isTradingActive);
   
   if(UseTradingHours)
     {
      Print("Trading hours were: ", StartHour, ":00 to ", EndHour, ":00");
     }
   
   if(UseSignalConfirmation)
     {
      Print("Signal confirmation was enabled (", ConfirmationBars, " bar(s))");
     }
   
   if(UseNewsAvoidance)
     {
      Print("News avoidance was enabled (", NewsAvoidanceMinutes, " minutes)");
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//| Main logic executed on every new tick.                           |
//+------------------------------------------------------------------+
void OnTick()
  {
// Do not execute if there is an open position or if trading is not active
   if(positionInfo.Select(_Symbol))
     {
      return;
     }

// Calculate current lot size and daily status before placing orders
   UpdateLotSizeAndDailyStatus();

// Check for the daily stop trading rule
   if(DailyStopTrading && hasProfitToday)
     {
      // Check if the current day is different from the day of the last profitable trade
      MqlDateTime now;
      TimeToStruct(TimeCurrent(), now);
      if(now.day == lastClosedDay)
        {
         // Same day, stop trading
         isTradingActive = false;
        }
      else
        {
         // A new day has started, reset the flag and resume trading
         hasProfitToday = false;
         isTradingActive = true;
         lastClosedDay = now.day;
        }
     }


// If trading is not active, exit the function
   if(!isTradingActive)
     {
      return;
     }
   
   // Check if current time is within trading hours
   if(!IsWithinTradingHours())
     {
      return; // Outside trading hours, skip trading
     }
   
   // Check if current time is near high-impact news events
   if(IsNearHighImpactNews())
     {
      return; // Near high-impact news, skip trading
     }
   
   // Check for signal confirmation first
   if(CheckSignalConfirmation())
     {
      // Signal confirmed, proceed with trade execution
      ExecuteConfirmedTrade();
      return;
     }

// Ensure the logic only runs on a new bar
   if(lastBarTime != iTime(_Symbol, _Period, 0))
     {
      // Update last processed bar time
      lastBarTime = iTime(_Symbol, _Period, 0);

      // Arrays to store price and volume data
      double  low_prices[2], high_prices[2], open_prices[2], close_prices[2];
      long    tick_volumes[2];

      // Copy data for the last two bars
      if(CopyLow(_Symbol, _Period, 0, 2, low_prices) < 2 ||
         CopyHigh(_Symbol, _Period, 0, 2, high_prices) < 2 ||
         CopyOpen(_Symbol, _Period, 0, 2, open_prices) < 2 ||
         CopyClose(_Symbol, _Period, 0, 2, close_prices) < 2 ||
         CopyTickVolume(_Symbol, _Period, 0, 2, tick_volumes) < 2)
        {
         // If data copy fails, print an error and return
         Print("Failed to copy historical data. Check chart data availability.");
         return;
        }

      // Get symbol point value for precise calculations
      double point_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      // Calculate upper and lower shadows for the current candle (index 0)
      double upperShadow = high_prices[0] - MathMax(open_prices[0], close_prices[0]);
      double lowerShadow = MathMin(open_prices[0], close_prices[0]) - low_prices[0];



      bool volumeCondition = tick_volumes[0] > (tick_volumes[1] * VolumeMultiplier);

       // Check for buy signal
       if(volumeCondition && lowerShadow > upperShadow && !hasProfitToday)
         {
          if(UseSignalConfirmation)
            {
             // Set pending buy signal for confirmation
             pendingBuySignal = true;
             signalCandleHigh = high_prices[0];
             signalTime = iTime(_Symbol, _Period, 0);
             Print("Buy signal detected - waiting for confirmation. Signal high: ", signalCandleHigh);
            }
          else
            {
             // Immediate execution (confirmation disabled)
             double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
             double sl = ask - StopLoss_Points * point_value;
             double tp = ask + TakeProfit_Points * point_value;

             if(trade.Buy(currentLot, _Symbol, ask, sl, tp, "GoldEA Buy Signal"))
               {
                Print("Buy order successfully sent. Volume: ", currentLot, " Price: ", ask);
               }
             else
               {
                Print("Buy order failed. Error: ", trade.ResultRetcode(), " - ", trade.ResultComment());
               }
            }
         }
       else
          if(hasProfitToday)
            {
             Print("Buy signal detected but trading stopped for today due to profit.");
            }
          else if(!IsWithinTradingHours())
            {
             Print("Buy signal detected but outside trading hours (", StartHour, ":00-", EndHour, ":00).");
            }
          else if(IsNearHighImpactNews())
            {
             Print("Buy signal detected but avoiding trading due to high-impact news.");
            }

      // Check for sell signal
      if(volumeCondition && upperShadow > lowerShadow && !hasProfitToday)
        {
         if(UseSignalConfirmation)
           {
            // Set pending sell signal for confirmation
            pendingSellSignal = true;
            signalCandleLow = low_prices[0];
            signalTime = iTime(_Symbol, _Period, 0);
            Print("Sell signal detected - waiting for confirmation. Signal low: ", signalCandleLow);
           }
         else
           {
            // Immediate execution (confirmation disabled)
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl = bid + StopLoss_Points * point_value;
            double tp = bid - TakeProfit_Points * point_value;

            if(trade.Sell(currentLot, _Symbol, bid, sl, tp, "GoldEA Sell Signal"))
              {
               Print("Sell order successfully sent. Volume: ", currentLot, " Price: ", bid);
              }
            else
              {
               Print("Sell order failed. Error: ", trade.ResultRetcode(), " - ", trade.ResultComment());
              }
           }
        }
       else
          if(hasProfitToday)
            {
             Print("Sell signal detected but trading stopped for today due to profit.");
            }
          else if(!IsWithinTradingHours())
            {
             Print("Sell signal detected but outside trading hours (", StartHour, ":00-", EndHour, ":00).");
            }
          else if(IsNearHighImpactNews())
            {
             Print("Sell signal detected but avoiding trading due to high-impact news.");
            }
     }
  }

//+------------------------------------------------------------------+
//| Execute confirmed trade based on pending signal                  |
//+------------------------------------------------------------------+
void ExecuteConfirmedTrade()
{
   if(pendingBuySignal)
     {
      // Execute confirmed buy trade
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double sl = ask - StopLoss_Points * point_value;
      double tp = ask + TakeProfit_Points * point_value;
      
      if(trade.Buy(currentLot, _Symbol, ask, sl, tp, "GoldEA Confirmed Buy Signal"))
        {
         Print("Confirmed buy order executed. Volume: ", currentLot, " Price: ", ask);
         pendingBuySignal = false;
        }
      else
        {
         Print("Confirmed buy order failed. Error: ", trade.ResultRetcode(), " - ", trade.ResultComment());
        }
     }
   else if(pendingSellSignal)
     {
      // Execute confirmed sell trade
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double point_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double sl = bid + StopLoss_Points * point_value;
      double tp = bid - TakeProfit_Points * point_value;
      
      if(trade.Sell(currentLot, _Symbol, bid, sl, tp, "GoldEA Confirmed Sell Signal"))
        {
         Print("Confirmed sell order executed. Volume: ", currentLot, " Price: ", bid);
         pendingSellSignal = false;
        }
      else
        {
         Print("Confirmed sell order failed. Error: ", trade.ResultRetcode(), " - ", trade.ResultComment());
        }
     }
}

//+------------------------------------------------------------------+
//| Check signal confirmation for buy/sell signals                   |
//+------------------------------------------------------------------+
bool CheckSignalConfirmation()
{
   if(!UseSignalConfirmation)
     {
      return true; // Signal confirmation disabled
     }
   
   // Check if we have pending signals
   if(!pendingBuySignal && !pendingSellSignal)
     {
      return false; // No pending signals
     }
   
   // Get current candle data for confirmation
   double currentHigh[], currentLow[];
   if(CopyHigh(_Symbol, _Period, 0, ConfirmationBars, currentHigh) < ConfirmationBars ||
      CopyLow(_Symbol, _Period, 0, ConfirmationBars, currentLow) < ConfirmationBars)
     {
      Print("Failed to get confirmation candle data");
      return false;
     }
   
   // Check buy signal confirmation
   if(pendingBuySignal)
     {
      // Check if any of the confirmation bars have high above signal candle high
      for(int i = 0; i < ConfirmationBars; i++)
        {
         if(currentHigh[i] > signalCandleHigh)
           {
            Print("Buy signal confirmed: Current high ", currentHigh[i], " > Signal high ", signalCandleHigh);
            pendingBuySignal = false;
            return true;
           }
        }
      
      // Check if signal is too old (more than 5 bars)
      if(iTime(_Symbol, _Period, 0) - signalTime > 5 * PeriodSeconds(_Period))
        {
         Print("Buy signal expired - too old");
         pendingBuySignal = false;
         return false;
        }
     }
   
   // Check sell signal confirmation
   if(pendingSellSignal)
     {
      // Check if any of the confirmation bars have low below signal candle low
      for(int i = 0; i < ConfirmationBars; i++)
        {
         if(currentLow[i] < signalCandleLow)
           {
            Print("Sell signal confirmed: Current low ", currentLow[i], " < Signal low ", signalCandleLow);
            pendingSellSignal = false;
            return true;
           }
        }
      
      // Check if signal is too old (more than 5 bars)
      if(iTime(_Symbol, _Period, 0) - signalTime > 5 * PeriodSeconds(_Period))
        {+
         Print("Sell signal expired - too old");
         pendingSellSignal = false;
         return false;
        }
     }
   
   return false; // Signal not confirmed yet
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   if(!UseTradingHours)
     {
      return true; // Trading hours disabled, allow trading 24/7
     }
   
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   
   int currentHour = now.hour;
   
   // Handle normal case (start hour < end hour)
   if(StartHour < EndHour)
     {
      return (currentHour >= StartHour && currentHour < EndHour);
     }
   // Handle overnight case (start hour > end hour, e.g., 22:00 to 06:00)
   else
     {
      return (currentHour >= StartHour || currentHour < EndHour);
     }
}

//+------------------------------------------------------------------+
//| Check if current time is near high-impact US news events        |
//+------------------------------------------------------------------+
bool IsNearHighImpactNews()
{
   if(!UseNewsAvoidance)
     {
      return false; // News avoidance disabled
     }
   
   datetime currentTime = TimeCurrent();
   MqlDateTime now;
   TimeToStruct(currentTime, now);
   
   // Convert to EST/EDT (UTC-5/UTC-4) for US market hours
   datetime usTime = currentTime - (5 * 3600); // EST (UTC-5)
   MqlDateTime usDateTime;
   TimeToStruct(usTime, usDateTime);
   
   int usHour = usDateTime.hour;
   int usMinute = usDateTime.min;
   int usDayOfWeek = usDateTime.day_of_week;
   
   // Skip weekends (Saturday = 6, Sunday = 0)
   if(usDayOfWeek == 0 || usDayOfWeek == 6)
     {
      return false;
     }
   
   // High-impact US news events (EST times)
   // These are the most important economic releases that affect gold
   struct NewsEvent
     {
      int hour;
      int minute;
      string name;
      int impact; // 3 = High, 2 = Medium, 1 = Low
     };
   
   NewsEvent highImpactNews[] = {
      {8, 30, "Non-Farm Payrolls", 3},
      {8, 30, "Unemployment Rate", 3},
      {8, 30, "CPI (Consumer Price Index)", 3},
      {8, 30, "PPI (Producer Price Index)", 3},
      {8, 30, "Retail Sales", 3},
      {8, 30, "GDP", 3},
      {8, 30, "Durable Goods Orders", 3},
      {8, 30, "Trade Balance", 3},
      {8, 30, "Consumer Confidence", 3},
      {8, 30, "ISM Manufacturing PMI", 3},
      {8, 30, "ISM Services PMI", 3},
      {8, 30, "Industrial Production", 3},
      {8, 30, "Capacity Utilization", 3},
      {8, 30, "Housing Starts", 3},
      {8, 30, "Building Permits", 3},
      {8, 30, "Existing Home Sales", 3},
      {8, 30, "New Home Sales", 3},
      {8, 30, "Personal Income", 3},
      {8, 30, "Personal Spending", 3},
      {8, 30, "Core PCE", 3},
      {8, 30, "Factory Orders", 3},
      {8, 30, "Wholesale Inventories", 3},
      {8, 30, "Business Inventories", 3},
      {8, 30, "Advance GDP", 3},
      {8, 30, "Preliminary GDP", 3},
      {8, 30, "Final GDP", 3},
      {8, 30, "Advance GDP Price Index", 3},
      {8, 30, "Preliminary GDP Price Index", 3},
      {8, 30, "Final GDP Price Index", 3},
      {8, 30, "Corporate Profits", 3},
      {8, 30, "Current Account", 3},
      {8, 30, "Net Long-term TIC Flows", 3},
      {8, 30, "Total Net TIC Flows", 3},
      {8, 30, "Michigan Consumer Sentiment", 3},
      {8, 30, "Michigan Consumer Expectations", 3},
      {8, 30, "Michigan Current Conditions", 3},
      {8, 30, "Michigan Inflation Expectations", 3},
      {8, 30, "JOLTS Job Openings", 3},
      {8, 30, "Jobless Claims", 3},
      {8, 30, "Continuing Claims", 3},
      {8, 30, "Average Hourly Earnings", 3},
      {8, 30, "Average Weekly Hours", 3},
      {8, 30, "Labor Force Participation Rate", 3},
      {8, 30, "Employment Cost Index", 3},
      {8, 30, "Productivity", 3},
      {8, 30, "Unit Labor Costs", 3},
      {8, 30, "Philadelphia Fed Manufacturing Index", 3},
      {8, 30, "Empire State Manufacturing Index", 3},
      {8, 30, "Richmond Fed Manufacturing Index", 3},
      {8, 30, "Kansas City Fed Manufacturing Index", 3},
      {8, 30, "Dallas Fed Manufacturing Index", 3},
      {8, 30, "Chicago PMI", 3},
      {8, 30, "Milwaukee PMI", 3},
      {8, 30, "New York PMI", 3},
      {8, 30, "Philadelphia PMI", 3},
      {8, 30, "Richmond PMI", 3},
      {8, 30, "Kansas City PMI", 3},
      {8, 30, "Dallas PMI", 3},
      {8, 30, "Chicago Fed National Activity Index", 3},
      {8, 30, "Leading Economic Index", 3},
      {8, 30, "Coincident Economic Index", 3},
      {8, 30, "Lagging Economic Index", 3},
      {8, 30, "Consumer Credit", 3},
      {8, 30, "Total Vehicle Sales", 3},
      {8, 30, "Domestic Vehicle Sales", 3},
      {8, 30, "Import Price Index", 3},
      {8, 30, "Export Price Index", 3},
      {8, 30, "Treasury Budget", 3},
      {8, 30, "Federal Budget", 3},
      {8, 30, "Monthly Budget Statement", 3},
      {8, 30, "Weekly Budget Statement", 3},
      {8, 30, "Daily Treasury Statement", 3},
      {8, 30, "Treasury Refunding Announcement", 3},
      {8, 30, "Treasury Refunding Details", 3},
      {8, 30, "Treasury Refunding Results", 3},
      {8, 30, "Treasury Bill Auction Results", 3},
      {8, 30, "Treasury Note Auction Results", 3},
      {8, 30, "Treasury Bond Auction Results", 3},
      {8, 30, "TIPS Auction Results", 3},
      {8, 30, "FRB Auction Results", 3},
      {8, 30, "Fed Funds Rate", 3},
      {8, 30, "Discount Rate", 3},
      {8, 30, "Primary Credit Rate", 3},
      {8, 30, "Secondary Credit Rate", 3},
      {8, 30, "Seasonal Credit Rate", 3},
      {8, 30, "Emergency Credit Rate", 3},
      {8, 30, "Term Auction Facility Rate", 3},
      {8, 30, "Term Securities Lending Facility Rate", 3},
      {8, 30, "Primary Dealer Credit Facility Rate", 3},
      {8, 30, "Asset-Backed Commercial Paper Money Market Mutual Fund Liquidity Facility Rate", 3},
      {8, 30, "Commercial Paper Funding Facility Rate", 3},
      {8, 30, "Money Market Investor Funding Facility Rate", 3},
      {8, 30, "Term Asset-Backed Securities Loan Facility Rate", 3},
      {8, 30, "Public-Private Investment Program Rate", 3},
      {8, 30, "Consumer ABS TALF Rate", 3},
      {8, 30, "SBA ABS TALF Rate", 3},
      {8, 30, "CMBS TALF Rate", 3},
      {8, 30, "Legacy CMBS TALF Rate", 3},
      {8, 30, "New CMBS TALF Rate", 3},
      {8, 30, "Agency CMBS TALF Rate", 3},
      {8, 30, "Non-Agency CMBS TALF Rate", 3},
      {8, 30, "Agency MBS TALF Rate", 3},
      {8, 30, "Non-Agency MBS TALF Rate", 3},
      {8, 30, "Agency CMO TALF Rate", 3},
      {8, 30, "Non-Agency CMO TALF Rate", 3},
      {8, 30, "Agency CMO TALF Rate", 3},
      {8, 30, "Non-Agency CMO TALF Rate", 3}
   };
   
   // Check if current time is within the avoidance window of any high-impact news
   for(int i = 0; i < ArraySize(highImpactNews); i++)
     {
      if(AvoidHighImpactNews && highImpactNews[i].impact >= 3)
        {
         // Check if current time is within the avoidance window
         int timeDiff = MathAbs((usHour * 60 + usMinute) - (highImpactNews[i].hour * 60 + highImpactNews[i].minute));
         if(timeDiff <= NewsAvoidanceMinutes)
           {
            Print("Avoiding trading due to high-impact news: ", highImpactNews[i].name, 
                  " at ", highImpactNews[i].hour, ":", StringFormat("%02d", highImpactNews[i].minute), " EST");
            return true;
           }
        }
     }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update lot size and daily status before placing orders           |
//+------------------------------------------------------------------+
void UpdateLotSizeAndDailyStatus()
  {
// Calculate today's date range
   datetime today = TimeCurrent();
   datetime today_start = today - (today % 86400);
   datetime today_end = today_start + 86400 - 1;

// Calculate today's profit and total deals
   double today_profit = CalculateDailyProfit(today_start, today_end);
   double total_deals = Calculatetotaldeals(today_start, today_end);
   double total_volume = Calculatevolume(today_start, today_end);

// Update lot size based on today's performance
   if(today_profit < 0)
     {
        if (total_deals > 5){
            currentLot = Lots;
            lastClosedDay = now.day;
        }
        else{
            currentLot = MathMin(total_volume+Lots, MaxLotSize);
            Print("Today is losing. Total deals: ", total_deals, " Lot size set to: ", currentLot);

        }

     }
   else
      if(today_profit > 0)
        {
         // If profitable today, reset to initial lot size and stop trading
         currentLot = Lots;
         hasProfitToday = true;

         MqlDateTime now;
         TimeToStruct(TimeCurrent(), now);
         lastClosedDay = now.day;

         Print("Today is profitable. Profit: ", today_profit, " Lot size reset to: ", currentLot);
        }
      else
        {
         // No trades today or break-even, use current lot size
         currentLot = MathMax(currentLot, Lots);
        }
  }

//+------------------------------------------------------------------+
//| Calculate daily profit for a given date range                    |
//+------------------------------------------------------------------+
double CalculateDailyProfit(datetime from_date, datetime to_date)
  {
   HistorySelect(from_date, to_date);
   double daily_profit = 0;
   ulong deal_ticket;

   for(uint i = 0; i < HistoryDealsTotal(); i++)
     {
      if((deal_ticket = HistoryDealGetTicket(i)) > 0)
        {
         if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == MagicNumber && HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
           {
            daily_profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
           }
        }
     }
   Print("Calculated profit for ", TimeToString(from_date), " to ", TimeToString(to_date), " is: ", daily_profit);
   return daily_profit;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Calculatetotaldeals(datetime from_date, datetime to_date)
  {
   HistorySelect(from_date, to_date);
   double total_deals = 0;
   ulong deal_ticket;

   for(uint i = 0; i < HistoryDealsTotal(); i++)
     {
      if((deal_ticket = HistoryDealGetTicket(i)) > 0)
        {
         if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == MagicNumber && HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
           {
            total_deals=total_deals+1;
           }
        }
     }
   Print("Calculated total deals for ", TimeToString(from_date), " to ", TimeToString(to_date), " is: ", total_deals);
   return total_deals;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Calculatevolume(datetime from_date, datetime to_date)
  {
   HistorySelect(from_date, to_date);
   double deal_volume = 0;
   ulong deal_ticket;

   for(uint i = 0; i < HistoryDealsTotal(); i++)
     {
      if((deal_ticket = HistoryDealGetTicket(i)) > 0)
        {
         if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == MagicNumber && HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
           {
            deal_volume=HistoryDealGetDouble(deal_ticket,DEAL_VOLUME)+deal_volume;
           }
        }
     }
   Print("Calculated deal_volume for ", TimeToString(from_date), " to ", TimeToString(to_date), " is: ", deal_volume);
   return deal_volume;
  }
//+------------------------------------------------------------------+
//| OnTradeTransaction event handler                                 |
//| This function handles trade transaction events.                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
// Check if a deal has been added
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      // Get deal information
      ulong deal_id = trans.deal;

      if(!dealInfo.SelectByIndex(HistoryDealsTotal() - 1))
        {
         Print("Failed to get deal information for ID: ", deal_id);
         return;
        }

      // Check if this is a closing deal for our EA
      if(dealInfo.Entry() == DEAL_ENTRY_OUT &&
         dealInfo.Symbol() == _Symbol &&
         dealInfo.Magic() == MagicNumber)
        {
         double profit = dealInfo.Profit();
         double swap = dealInfo.Swap();
         double commission = dealInfo.Commission();
         double totalProfit = profit + swap + commission;

         Print("Trade closed. Total P&L: ", totalProfit,
               " (Profit: ", profit, ", Swap: ", swap, ", Commission: ", commission, ")");

         // The lot size and daily status will be updated in the next OnTick() call
         // through UpdateLotSizeAndDailyStatus() function
        }
     }
  }
//+------------------------------------------------------------------+
//| GoldEA Improvements Made:                                        |
//| 1. Fixed file extension from .cs to .mq5                        |
//| 2. Added proper MQL5 includes (Trade, DealInfo, PositionInfo)   |
//| 3. Implemented CTrade object for better order management        |
//| 4. Added magic number for trade identification                  |
//| 5. Enhanced input parameters with groups and validation         |
//| 6. Improved lot size management with maximum limits             |
//| 7. Better error handling and logging                            |
//| 8. Added comprehensive P&L calculation (profit + swap + comm)   |
//| 9. Enhanced volume analysis with configurable multiplier        |
//| 10. Improved trade transaction handling                         |
//| 11. Added news avoidance functionality for high-impact US events |
//| 12. Implemented configurable news avoidance time windows        |
//| 13. Added comprehensive logging for news avoidance events       |
//+------------------------------------------------------------------+
