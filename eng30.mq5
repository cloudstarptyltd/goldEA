//+------------------------------------------------------------------+
//|                                                   Engulfing EA.mq5 |
//|                                  https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "https://www.mql5.com"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Include necessary libraries
#include <Trade\Trade.mqh>

// --- Input parameters ---
input double BaseLotSize = 0.01;
input double TrailingStopPips = 30; // Trailing stop distance in points
input ulong MagicNumber = 12345; // Magic number for this EA

// --- Global variables ---
datetime last_trade_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Do not trade on every tick
    if(last_trade_time == TimeCurrent()) return;
    last_trade_time = TimeCurrent();

    // Check if there are open positions for this EA. If so, manage trailing stop and exit.
    if(CountPositions() > 0)
    {
        ManageTrailingStop();
        return;
    }

    // Find the engulfing candle and prepare to open a position.
    double lot_size = CalculateLotSize();
    if(lot_size == 0) return;

    CheckForEngulfing(lot_size);
}

//+------------------------------------------------------------------+
//| Function to count positions opened by this EA                   |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong position_ticket = PositionGetTicket(i);
        if(position_ticket == 0) continue;
        
        if(!PositionSelectByTicket(position_ticket)) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Function to manage trailing stop                                 |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    // This part of the code manages the trailing stop for existing positions.
    // It checks if the current price has moved in favor of the position
    // by a certain number of pips (TrailingStopPips) and adjusts the stop loss.

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong position_ticket = PositionGetTicket(i);
        if(position_ticket == 0) continue;
        
        // Select the position before accessing its data
        if(!PositionSelectByTicket(position_ticket)) continue;
        
        // Check if this position belongs to the current symbol and EA
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        long position_type = PositionGetInteger(POSITION_TYPE);
        double position_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double position_sl = PositionGetDouble(POSITION_SL);
        double current_price = 0;
        
        // Determine the current price based on the position type.
        if(position_type == POSITION_TYPE_BUY)
        {
            current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            if(current_price - position_price > TrailingStopPips * _Point)
            {
                // Move SL to trail the price
                double new_sl = current_price - TrailingStopPips * _Point;
                if(new_sl > position_sl || position_sl == 0)
                {
                    // Modify position
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    ZeroMemory(request);
                    request.action = TRADE_ACTION_SLTP;
                    request.position = position_ticket;
                    request.sl = new_sl;
                    
                    if(!OrderSend(request, result))
                    {
                        Print("Error modifying position #", position_ticket, ": ", result.retcode);
                    }
                }
            }
        }
        else if(position_type == POSITION_TYPE_SELL)
        {
            current_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            if(position_price - current_price > TrailingStopPips * _Point)
            {
                // Move SL to trail the price
                double new_sl = current_price + TrailingStopPips * _Point;
                if(new_sl < position_sl || position_sl == 0)
                {
                    // Modify position
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    ZeroMemory(request);
                    request.action = TRADE_ACTION_SLTP;
                    request.position = position_ticket;
                    request.sl = new_sl;
                    
                    if(!OrderSend(request, result))
                    {
                        Print("Error modifying position #", position_ticket, ": ", result.retcode);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Function to calculate lot size based on account history          |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    // This part of the code counts the number of losing trades and calculates the lot size.
    double total_profit = 0;
    int losing_deals = 0;

    HistorySelect(0, TimeCurrent()); // Select all history
    for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        if(deal_ticket == 0) continue;

        // Check if the deal is for the current symbol and is a closed position.
        if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) == Symbol() &&
           HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
        {
            double deal_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            total_profit += deal_profit;
            
            if(deal_profit < 0)
            {
                losing_deals++;
            }
        }
    }

    if(total_profit < 0)
    {
        return 0.03 * losing_deals;
    }
    else
    {
        return BaseLotSize;
    }
}

//+------------------------------------------------------------------+
//| Function to check for engulfing candle and open position         |
//+------------------------------------------------------------------+
void CheckForEngulfing(double lot_size)
{
    // Validate lot size
    if(lot_size <= 0)
    {
        Print("Invalid lot size: ", lot_size);
        return;
    }
    
    // Get candle data.
    MqlRates rates[3];
    if(CopyRates(Symbol(), Period(), 0, 3, rates) != 3)
    {
        Print("Error getting rates data");
        return;
    }

    double prev_high = rates[1].high;
    double prev_low = rates[1].low;
    double prev_open = rates[1].open;
    double prev_close = rates[1].close;

    double current_high = rates[0].high;
    double current_low = rates[0].low;
    double current_open = rates[0].open;
    double current_close = rates[0].close;

    // Bearish Engulfing:
    // 1. Previous candle is bullish (close > open)
    // 2. Current candle is bearish (close < open)
    // 3. Current candle's body engulfs the previous candle's body.
    // 4. Current candle's range engulfs the previous candle's range.
    if(prev_close > prev_open && current_close < current_open &&
       current_open > prev_close && current_close < prev_open &&
       current_high > prev_high && current_low < prev_low)
    {
        double sl_distance = MathAbs(current_high - current_low);
        double sl_price = current_high + 10 * _Point; // Add a small buffer for spread/slippage
        double tp_price = 0; // Take profit is managed by the trailing stop
        
        // Validate lot size against symbol limits
        double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
        double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        
        if(lot_size < min_lot || lot_size > max_lot)
        {
            Print("Lot size ", lot_size, " is outside allowed range [", min_lot, ", ", max_lot, "]");
            return;
        }
        
        // Normalize lot size to step
        lot_size = MathMax(min_lot, MathMin(max_lot, MathRound(lot_size / lot_step) * lot_step));

        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        request.action = TRADE_ACTION_DEAL;
        request.symbol = Symbol();
        request.volume = lot_size;
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        request.sl = sl_price;
        request.tp = 0; // Trailing stop manages TP
        request.deviation = 10;
        request.magic = MagicNumber;
        
        if(!OrderSend(request, result))
        {
            Print("Error opening sell position: ", result.retcode, " - ", result.comment);
        }
        else
        {
            Print("Sell position opened successfully. Ticket: ", result.order, " SL at: ", sl_price);
        }
        return;
    }

    // Bullish Engulfing:
    // 1. Previous candle is bearish (close < open)
    // 2. Current candle is bullish (close > open)
    // 3. Current candle's body engulfs the previous candle's body.
    // 4. Current candle's range engulfs the previous candle's range.
    if(prev_close < prev_open && current_close > current_open &&
       current_open < prev_close && current_close > prev_open &&
       current_high > prev_high && current_low < prev_low)
    {
        double sl_distance = MathAbs(current_high - current_low);
        double sl_price = current_low - 10 * _Point; // Add a small buffer
        double tp_price = 0; // Take profit is managed by the trailing stop

        // Validate lot size against symbol limits
        double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
        double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        
        if(lot_size < min_lot || lot_size > max_lot)
        {
            Print("Lot size ", lot_size, " is outside allowed range [", min_lot, ", ", max_lot, "]");
            return;
        }
        
        // Normalize lot size to step
        lot_size = MathMax(min_lot, MathMin(max_lot, MathRound(lot_size / lot_step) * lot_step));

        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        request.action = TRADE_ACTION_DEAL;
        request.symbol = Symbol();
        request.volume = lot_size;
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        request.sl = sl_price;
        request.tp = 0; // Trailing stop manages TP
        request.deviation = 10;
        request.magic = MagicNumber;

        if(!OrderSend(request, result))
        {
            Print("Error opening buy position: ", result.retcode, " - ", result.comment);
        }
        else
        {
            Print("Buy position opened successfully. Ticket: ", result.order, " SL at: ", sl_price);
        }
    }
}