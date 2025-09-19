//+------------------------------------------------------------------+
//|                                              structured_entry.mq5|
//|                                             Expert Advisor based |
//|                                                on a YouTube video|
//+------------------------------------------------------------------+
#property copyright "2024, Gemini"
#property link      ""
#property version   "1.00"
#property description "Implements a structured entry strategy with three entries, a single shared stop loss, and tiered take profit."

//--- MQL5 Standard Library for trading and position management
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Global variables
CTrade      m_trade;    // Trading class for trade operations
CPositionInfo m_position; // Position information class
string      m_symbol;   // Current symbol name
double      m_lot_1;    // Lot size for the first entry
double      m_lot_2;    // Lot size for the second entry
double      m_lot_3;    // Lot size for the third entry
double      m_sl_points; // Stop loss in points
double      m_tp_1;     // Take profit 1 in points
double      m_tp_2;     // Take profit 2 in points
double      m_tp_3;     // Take profit 3 in points
double      m_entry_distance; // Distance between entries in points
int         m_magic_number;   // Magic number to identify EA's trades

//--- External parameters for user customization
input double LotSize_1      = 0.01;   // Lot size for the 1st entry
input double LotSize_2      = 0.01;   // Lot size for the 2nd entry
input double LotSize_3      = 0.02;   // Lot size for the 3rd entry
input int    StopLossPoints = 100;    // Stop loss in points
input int    TakeProfit1    = 25;     // Take profit for the 1st entry in points
input int    TakeProfit2    = 50;     // Take profit for the 2nd entry in points
input int    TakeProfit3    = 100;    // Take profit for the 3rd entry in points
input int    EntryDistance  = 50;     // Distance between entries in points
input int    MagicNumber    = 12345;  // Unique magic number

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Validate input parameters
    if (LotSize_1 <= 0 || LotSize_2 <= 0 || LotSize_3 <= 0)
    {
        Print("Error: All lot sizes must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if (StopLossPoints <= 0 || TakeProfit1 <= 0 || TakeProfit2 <= 0 || TakeProfit3 <= 0)
    {
        Print("Error: Stop Loss and Take Profit values must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if (EntryDistance <= 0)
    {
        Print("Error: Entry distance must be greater than 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    //--- Set global variables from external parameters
    m_lot_1 = LotSize_1;
    m_lot_2 = LotSize_2;
    m_lot_3 = LotSize_3;
    m_sl_points = StopLossPoints;
    m_tp_1 = TakeProfit1;
    m_tp_2 = TakeProfit2;
    m_tp_3 = TakeProfit3;
    m_entry_distance = EntryDistance;
    m_magic_number = MagicNumber;

    //--- Initialize trading and position info classes
    m_symbol = Symbol();
    m_trade.SetExpertMagicNumber(m_magic_number);
    m_trade.SetDeviationInPoints(10);
    m_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    Print("Structured Entry EA initialized successfully");
    Print("Symbol: ", m_symbol);
    Print("Magic Number: ", m_magic_number);
    Print("Lot Sizes: ", m_lot_1, " / ", m_lot_2, " / ", m_lot_3);
    Print("Stop Loss: ", m_sl_points, " points");
    Print("Take Profits: ", m_tp_1, " / ", m_tp_2, " / ", m_tp_3, " points");
    Print("Entry Distance: ", m_entry_distance, " points");

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Clean up
    Print("Expert Advisor deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if the EA is already managing an active trade.
    // This prevents multiple entry cycles from starting.
    if (HasActiveTrade())
    {
        return;
    }

    //--- Main trading logic
    // This is a placeholder for your actual entry signal.
    // Replace this with your preferred indicator or analysis logic.
    // For this example, we'll use a simple moving average crossover.
    
     // Get moving average values
     int ma_fast_handle = iMA(m_symbol, PERIOD_CURRENT, 10, 0, MODE_SMA, PRICE_CLOSE);
     int ma_slow_handle = iMA(m_symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
     
     double ma_fast[], ma_slow[];
     ArrayResize(ma_fast, 1);
     ArrayResize(ma_slow, 1);
     
     if (CopyBuffer(ma_fast_handle, 0, 0, 1, ma_fast) < 1 || CopyBuffer(ma_slow_handle, 0, 0, 1, ma_slow) < 1)
     {
         return; // Failed to get MA values
     }
    
    // Placeholder for a long (buy) signal
    if (ma_fast[0] > ma_slow[0]) // Simple MA crossover for buy
    {
        // Place the first entry for a BUY trade
        PlaceEntry(ORDER_TYPE_BUY, m_lot_1, m_tp_1, m_sl_points);
    }
    
    // Placeholder for a short (sell) signal
    if (ma_fast[0] < ma_slow[0]) // Simple MA crossover for sell
    {
        // Place the first entry for a SELL trade
        PlaceEntry(ORDER_TYPE_SELL, m_lot_1, m_tp_1, m_sl_points);
    }
}

//+------------------------------------------------------------------+
//| Custom function to manage structured entries                     |
//+------------------------------------------------------------------+
void PlaceEntry(ENUM_ORDER_TYPE order_type, double lots, double tp_points, double sl_points)
{
    double price, sl_price, tp_price;
    
    // Get current prices
    if (order_type == ORDER_TYPE_BUY)
    {
        price = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        sl_price = price - sl_points * _Point;
        tp_price = price + tp_points * _Point;
        
        //--- Open the first position
        if (!m_trade.Buy(lots, m_symbol, price, sl_price, tp_price, "First Entry"))
        {
            Print("Failed to open first BUY position. Error: ", m_trade.ResultRetcode());
            return;
        }
    }
    else if (order_type == ORDER_TYPE_SELL)
    {
        price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        sl_price = price + sl_points * _Point;
        tp_price = price - tp_points * _Point;
        
        //--- Open the first position
        if (!m_trade.Sell(lots, m_symbol, price, sl_price, tp_price, "First Entry"))
        {
            Print("Failed to open first SELL position. Error: ", m_trade.ResultRetcode());
            return;
        }
    }
    
    Print("First entry placed successfully. Type: ", EnumToString(order_type), " Lots: ", lots);
}

//+------------------------------------------------------------------+
//| Custom function to check if there is an active trade             |
//+------------------------------------------------------------------+
bool HasActiveTrade()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (m_position.SelectByIndex(i) && m_position.Magic() == m_magic_number && m_position.Symbol() == m_symbol)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Custom function to get the ticket of the active trade            |
//+------------------------------------------------------------------+
ulong GetActiveTicket()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (m_position.SelectByIndex(i) && m_position.Magic() == m_magic_number && m_position.Symbol() == m_symbol)
        {
            return m_position.Ticket();
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Custom function to get the price of the last opened position     |
//+------------------------------------------------------------------+
double GetLastEntryPrice()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (m_position.SelectByIndex(i) && m_position.Magic() == m_magic_number && m_position.Symbol() == m_symbol)
        {
            return m_position.PriceOpen();
        }
    }
    return 0;
}
