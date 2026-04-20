"""
RedBot VIP Signal Copier
========================
Telegram bot that receives forwarded VIP signals and executes them on MT5.

Setup:
  1. Create a Telegram bot via @BotFather → get your BOT_TOKEN
  2. pip install python-telegram-bot MetaTrader5
  3. Update BOT_TOKEN and ALLOWED_USERS below
  4. Run: python signal_copier.py

Usage:
  Forward any VIP signal to your Telegram bot. It parses:
    Gain 400
    Sell
    TP: 103225.55
  
  And executes 3 SELL positions on GainX 400 with ATR-based SL.
"""

import MetaTrader5 as mt5
import asyncio
import re
import requests
import logging
from datetime import datetime

# ─── TELEGRAM CONFIG ───
BOT_TOKEN = "8734403363:AAGxh6Gnqb42jzQwpbuxJknNstLU-0g_RAI"  # Get from @BotFather
ALLOWED_USERS = [7718901010]  # Your Telegram user IDs. Empty = allow all. Find yours via @userinfobot

# ─── MT5 CONFIG ───
RISK_PER_POSITION = 2.0  # Max loss per position as % of balance
POSITIONS_PER_SIGNAL = 3
SL_POINTS = 50           # Fixed SL distance in points
MAGIC_BASE = 555555      # Different magic from main bot to avoid conflicts
PROFIT_TARGET = 15.0     # Close all at $15 combined profit ($5 per position)

# ─── DEMO RELAY CONFIG ───
RELAY_ENABLED = False
RELAY_URL = "http://DEMO_VPS_IP:5555"  # Replace with demo VPS IP
RELAY_SECRET = "redbot_relay_2026"

# ─── SYMBOL MAPPING ───
SYMBOL_MAP = {
    # GainX / PainX
    "gain 400": "GainX 400",
    "gain 600": "GainX 600", 
    "gain 800": "GainX 800",
    "gain 999": "GainX 999",
    "gain 1200": "GainX 1200",
    "pain 400": "PainX 400",
    "pain 600": "PainX 600",
    "pain 800": "PainX 800",
    "pain 999": "PainX 999",
    "pain 1200": "PainX 1200",
    "gainx 400": "GainX 400",
    "gainx 600": "GainX 600",
    "gainx 800": "GainX 800",
    "gainx 999": "GainX 999",
    "gainx 1200": "GainX 1200",
    "painx 400": "PainX 400",
    "painx 600": "PainX 600",
    "painx 800": "PainX 800",
    "painx 999": "PainX 999",
    "painx 1200": "PainX 1200",
    # FX Volatility indices
    "fx vol 20": "FX Vol 20",
    "fx vol 40": "FX Vol 40",
    "fx vol 60": "FX Vol 60",
    "fx vol 80": "FX Vol 80",
    "fx vol 99": "FX Vol 99",
    "fxvol 20": "FX Vol 20",
    "fxvol 40": "FX Vol 40",
    "fxvol 60": "FX Vol 60",
    "fxvol 80": "FX Vol 80",
    "fxvol 99": "FX Vol 99",
    "fx 20": "FX Vol 20",
    "fx 40": "FX Vol 40",
    "fx 60": "FX Vol 60",
    "fx 80": "FX Vol 80",
    "fx 99": "FX Vol 99",
    # SFX Volatility indices
    "sfx vol 20": "SFX Vol 20",
    "sfx vol 40": "SFX Vol 40",
    "sfx vol 60": "SFX Vol 60",
    "sfx vol 80": "SFX Vol 80",
    "sfx vol 99": "SFX Vol 99",
    "sfxvol 20": "SFX Vol 20",
    "sfxvol 40": "SFX Vol 40",
    "sfxvol 60": "SFX Vol 60",
    "sfxvol 80": "SFX Vol 80",
    "sfxvol 99": "SFX Vol 99",
    "sfx 20": "SFX Vol 20",
    "sfx 40": "SFX Vol 40",
    "sfx 60": "SFX Vol 60",
    "sfx 80": "SFX Vol 80",
    "sfx 99": "SFX Vol 99",
    # Break indices
    "break 600": "BreakX 600",
    "break x 600": "BreakX 600",
    "breakx 600": "BreakX 600",
    "break 1200": "BreakX 1200",
    "break x 1200": "BreakX 1200",
    "breakx 1200": "BreakX 1200",
    "break 1800": "BreakX 1800",
    "break x 1800": "BreakX 1800",
    "breakx 1800": "BreakX 1800",
}

# Direction defaults based on symbol type
# GainX = SELL, PainX = BUY, everything else = MUST specify in signal
DEFAULT_DIRECTION = {
    "GainX": "SELL",
    "PainX": "BUY",
}

# Symbols that switch direction - direction MUST be in signal
SWITCHING_SYMBOLS = ["FX Vol", "SFX Vol", "BreakX"]

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
log = logging.getLogger("SignalCopier")

# Global reference for sending messages from background tasks
telegram_app = None
chat_id_store = set()

# Track open VIP positions for P&L reporting
open_vip_tickets = set()


def compute_magic(symbol):
    magic = MAGIC_BASE
    for i, ch in enumerate(symbol):
        magic += ord(ch) * (i + 1)
    return magic


def relay_to_demo(symbol, direction, tp_price=None):
    """Relay trade to demo VPS"""
    if not RELAY_ENABLED:
        return
    try:
        resp = requests.post(
            f"{RELAY_URL}/trade",
            json={
                "secret": RELAY_SECRET,
                "symbol": symbol,
                "direction": direction,
                "tp": tp_price,
            },
            timeout=10
        )
        data = resp.json()
        if data.get('success'):
            log.info(f"RELAY OK: {data['opened']}/{data['total']} {direction} {symbol} on demo")
        else:
            log.warning(f"RELAY FAIL: {data.get('error')}")
    except Exception as e:
        log.warning(f"RELAY ERROR: {e}")


def connect_mt5():
    if not mt5.initialize():
        log.error(f"MT5 init failed: {mt5.last_error()}")
        return False
    info = mt5.account_info()
    if info:
        log.info(f"MT5 Connected: #{info.login} | Balance: ${info.balance:.2f}")
    return True


def calculate_lot(symbol, sl_distance):
    """Calculate lot size based on fixed risk per position"""
    balance = mt5.account_info().balance
    risk_amount = balance * (RISK_PER_POSITION / 100.0)
    
    tick_value = mt5.symbol_info(symbol).trade_tick_value
    tick_size = mt5.symbol_info(symbol).trade_tick_size
    vol_step = mt5.symbol_info(symbol).volume_step
    vol_min = mt5.symbol_info(symbol).volume_min
    vol_max = mt5.symbol_info(symbol).volume_max
    
    if tick_value == 0 or tick_size == 0 or sl_distance == 0:
        return vol_min
    
    lots = risk_amount / ((sl_distance / tick_size) * tick_value)
    
    # Round to volume step
    lots = int(lots / vol_step) * vol_step
    lots = max(lots, vol_min)
    lots = min(lots, vol_max)
    
    return round(lots, 2)


def parse_signal(text):
    """Parse VIP signal text into trade parameters"""
    text = text.strip()
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    
    if not lines:
        return None
    
    signal = {
        'symbol': None,
        'direction': None,
        'tp': None,
        'raw': text,
    }
    
    for line in lines:
        lower = line.lower()
        
        # Check for symbol
        for key, mapped in SYMBOL_MAP.items():
            if key in lower:
                signal['symbol'] = mapped
                break
        
        # Check for direction
        if lower in ['buy', 'sell']:
            signal['direction'] = lower.upper()
        elif lower.startswith('buy'):
            signal['direction'] = 'BUY'
        elif lower.startswith('sell'):
            signal['direction'] = 'SELL'
        
        # Check for TP
        tp_match = re.search(r'tp[:\s]*([0-9]+\.?[0-9]*)', lower)
        if tp_match:
            signal['tp'] = float(tp_match.group(1))
    
    if not signal['symbol']:
        return None
    
    # Default direction based on symbol type
    if not signal['direction']:
        # Check if this is a switching symbol (needs explicit direction)
        is_switching = any(s in signal['symbol'] for s in SWITCHING_SYMBOLS)
        if is_switching:
            signal['direction'] = None  # Will be caught below
        else:
            for prefix, default_dir in DEFAULT_DIRECTION.items():
                if prefix in signal['symbol']:
                    signal['direction'] = default_dir
                    break
    
    # If still no direction, signal is incomplete
    if not signal['direction']:
        signal['needs_direction'] = True
    else:
        signal['needs_direction'] = False
    
    return signal


SKIP_SUNDAY = True         # Block trades on Sunday
MAX_SPREAD_POINTS = 5.0    # Skip if spread is too wide

def execute_signal(signal):
    """Execute parsed signal on MT5"""
    symbol = signal['symbol']
    direction = signal['direction']
    tp_price = signal['tp']
    
    # Sunday check
    if SKIP_SUNDAY and datetime.now().weekday() == 6:
        return "BLOCKED: No trading on Sunday. Spreads are too wide."
    
    # Ensure symbol is available
    if not mt5.symbol_select(symbol, True):
        return f"Failed to select {symbol}"
    
    info = mt5.symbol_info(symbol)
    if info is None:
        return f"Symbol {symbol} not found"
    
    # Get current price
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return f"No tick data for {symbol}"
    
    if direction == "BUY":
        entry = tick.ask
        order_type = mt5.ORDER_TYPE_BUY
    else:
        entry = tick.bid
        order_type = mt5.ORDER_TYPE_SELL
    
    # Fixed SL distance
    sl_distance = SL_POINTS
    
    if direction == "BUY":
        sl_price = round(entry - sl_distance, info.digits)
        if tp_price:
            tp = round(tp_price, info.digits)
        else:
            tp = round(entry + sl_distance * 2, info.digits)
    else:
        sl_price = round(entry + sl_distance, info.digits)
        if tp_price:
            tp = round(tp_price, info.digits)
        else:
            tp = round(entry - sl_distance * 2, info.digits)
    
    # Calculate lot size - risk per position
    lot = calculate_lot(symbol, sl_distance)
    max_loss = mt5.account_info().balance * (RISK_PER_POSITION / 100.0)
    magic = compute_magic(symbol)
    
    # Open positions
    opened = 0
    results = []
    
    for i in range(POSITIONS_PER_SIGNAL):
        # Refresh price for each position
        tick = mt5.symbol_info_tick(symbol)
        if direction == "BUY":
            price = tick.ask
        else:
            price = tick.bid
        
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": lot,
            "type": order_type,
            "price": price,
            "sl": sl_price,
            "tp": tp,
            "deviation": 30,
            "magic": magic,
            "comment": "VIP Signal",
            "type_time": mt5.ORDER_TIME_GTC,
        }
        
        # Try different filling modes
        for filling in [mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_RETURN]:
            request["type_filling"] = filling
            result = mt5.order_send(request)
            if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                opened += 1
                results.append(f"POS #{i+1} @{price} SL:{sl_price} TP:{tp} Lot:{lot}")
                break
    
    summary = (
        f"VIP SIGNAL EXECUTED: {direction} {symbol}\n"
        f"Positions: {opened}/{POSITIONS_PER_SIGNAL}\n"
        f"Entry: ~{entry} | SL: {sl_price} | TP: {tp}\n"
        f"Lot: {lot} x {opened} | SL: {SL_POINTS} pts\n"
        f"Max loss/pos: ${max_loss:.2f} ({RISK_PER_POSITION}%)"
    )
    
    for r in results:
        log.info(r)
    
    return summary


def check_profit_target():
    """Check if any symbol's VIP positions hit profit target"""
    positions = mt5.positions_get()
    if positions is None:
        return
    
    # Group by symbol
    symbol_profits = {}
    for pos in positions:
        if pos.magic < MAGIC_BASE:  # Not our VIP positions
            continue
        sym = pos.symbol
        if sym not in symbol_profits:
            symbol_profits[sym] = {'profit': 0, 'tickets': []}
        symbol_profits[sym]['profit'] += pos.profit
        symbol_profits[sym]['tickets'].append(pos.ticket)
    
    for sym, data in symbol_profits.items():
        signal_sets = max(1, len(data['tickets']) // POSITIONS_PER_SIGNAL)
        scaled_target = PROFIT_TARGET * signal_sets
        if data['profit'] >= scaled_target:
            log.info(f"VIP PROFIT TARGET: {sym} +${data['profit']:.2f} (target ${scaled_target:.2f} for {signal_sets} sets)")
            for ticket in data['tickets']:
                pos = mt5.positions_get(ticket=ticket)
                if pos and len(pos) > 0:
                    p = pos[0]
                    close_type = mt5.ORDER_TYPE_SELL if p.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
                    price = mt5.symbol_info_tick(sym).bid if p.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(sym).ask
                    
                    request = {
                        "action": mt5.TRADE_ACTION_DEAL,
                        "symbol": sym,
                        "volume": p.volume,
                        "type": close_type,
                        "position": ticket,
                        "price": price,
                        "deviation": 30,
                        "magic": p.magic,
                        "comment": "VIP TP Hit",
                    }
                    for filling in [mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_RETURN]:
                        request["type_filling"] = filling
                        result = mt5.order_send(request)
                        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                            break
            return sym, data['profit']
    return None


async def handle_message(update, context):
    """Handle incoming Telegram messages"""
    user_id = update.effective_user.id
    username = update.effective_user.username or "Unknown"
    
    # Check authorization
    if ALLOWED_USERS and user_id not in ALLOWED_USERS:
        await update.message.reply_text("Unauthorized. Add your user ID to ALLOWED_USERS.")
        return
    
    text = update.message.text
    if not text:
        return
    
    log.info(f"Message from @{username} ({user_id}): {text}")
    chat_id_store.add(update.effective_chat.id)
    
    # Check for commands
    if text.startswith('/'):
        await handle_command(update, context, text)
        return
    
    # Parse signal
    signal = parse_signal(text)
    
    if signal is None:
        await update.message.reply_text(
            "Could not parse signal. Expected format:\n"
            "Gain 400\nSell\nTP: 103225.55"
        )
        return
    
    # If direction is missing for switching symbol, ask for it
    if signal.get('needs_direction', False):
        context.user_data['pending_signal_no_dir'] = signal
        await update.message.reply_text(
            f"Symbol: {signal['symbol']}\n"
            f"TP: {signal['tp'] if signal['tp'] else 'N/A'}\n\n"
            f"This symbol switches direction.\n"
            f"Reply BUY or SELL to set direction."
        )
        return
    
    # Confirm before executing
    confirm_msg = (
        f"Signal detected:\n"
        f"Symbol: {signal['symbol']}\n"
        f"Direction: {signal['direction']}\n"
        f"TP: {signal['tp'] if signal['tp'] else 'ATR-based'}\n\n"
        f"Positions: {POSITIONS_PER_SIGNAL} @ {RISK_PER_POSITION}% risk/pos\n\n"
        f"Send 'YES' to execute or 'NO' to cancel."
    )
    
    # Store pending signal
    context.user_data['pending_signal'] = signal
    await update.message.reply_text(confirm_msg)


async def handle_confirmation(update, context):
    """Handle YES/NO confirmation"""
    text = update.message.text.strip().upper()
    
    if text == 'YES' and 'pending_signal' in context.user_data:
        signal = context.user_data.pop('pending_signal')
        
        await update.message.reply_text(f"Executing {signal['direction']} {signal['symbol']}...")
        
        # Ensure MT5 is connected
        if not mt5.terminal_info():
            if not connect_mt5():
                await update.message.reply_text("MT5 connection failed!")
                return
        
        result = execute_signal(signal)
        await update.message.reply_text(result)
        
        # Relay to demo VPS
        relay_to_demo(signal['symbol'], signal['direction'], signal.get('tp'))
        if RELAY_ENABLED:
            await update.message.reply_text("Relayed to demo account.")
        
    elif text == 'NO':
        context.user_data.pop('pending_signal', None)
        await update.message.reply_text("Signal cancelled.")


async def handle_command(update, context, text):
    """Handle bot commands"""
    cmd = text.split()[0].lower()
    
    if cmd == '/status':
        if not mt5.terminal_info():
            connect_mt5()
        info = mt5.account_info()
        positions = mt5.positions_get()
        vip_count = 0
        vip_profit = 0
        if positions:
            for p in positions:
                if p.magic >= MAGIC_BASE:
                    vip_count += 1
                    vip_profit += p.profit
        
        msg = (
            f"MT5 Status:\n"
            f"Balance: ${info.balance:.2f}\n"
            f"Equity: ${info.equity:.2f}\n"
            f"VIP Positions: {vip_count}\n"
            f"VIP Floating P&L: ${vip_profit:.2f}"
        )
        await update.message.reply_text(msg)
    
    elif cmd == '/close':
        parts = text.split()
        if len(parts) < 2:
            await update.message.reply_text("Usage: /close GainX 400")
            return
        symbol = ' '.join(parts[1:])
        # Map shorthand
        mapped = SYMBOL_MAP.get(symbol.lower(), symbol)
        
        positions = mt5.positions_get(symbol=mapped)
        closed = 0
        if positions:
            for p in positions:
                if p.magic >= MAGIC_BASE:
                    close_type = mt5.ORDER_TYPE_SELL if p.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
                    price = mt5.symbol_info_tick(mapped).bid if p.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(mapped).ask
                    request = {
                        "action": mt5.TRADE_ACTION_DEAL,
                        "symbol": mapped,
                        "volume": p.volume,
                        "type": close_type,
                        "position": p.ticket,
                        "price": price,
                        "deviation": 30,
                        "magic": p.magic,
                        "type_filling": mt5.ORDER_FILLING_IOC,
                    }
                    result = mt5.order_send(request)
                    if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                        closed += 1
        await update.message.reply_text(f"Closed {closed} VIP positions on {mapped}")
    
    elif cmd == '/closeall':
        positions = mt5.positions_get()
        closed = 0
        if positions:
            for p in positions:
                if p.magic >= MAGIC_BASE:
                    close_type = mt5.ORDER_TYPE_SELL if p.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
                    price = mt5.symbol_info_tick(p.symbol).bid if p.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(p.symbol).ask
                    request = {
                        "action": mt5.TRADE_ACTION_DEAL,
                        "symbol": p.symbol,
                        "volume": p.volume,
                        "type": close_type,
                        "position": p.ticket,
                        "price": price,
                        "deviation": 30,
                        "magic": p.magic,
                        "type_filling": mt5.ORDER_FILLING_IOC,
                    }
                    result = mt5.order_send(request)
                    if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                        closed += 1
        await update.message.reply_text(f"Closed {closed} VIP positions total")
    
    elif cmd == '/help':
        msg = (
            "RedBot VIP Signal Copier\n\n"
            "Forward a VIP signal → confirm with YES\n\n"
            "Commands:\n"
            "/status - Account & position info\n"
            "/close GainX 400 - Close VIP positions on symbol\n"
            "/closeall - Close all VIP positions\n"
            "/help - This message"
        )
        await update.message.reply_text(msg)


async def profit_monitor():
    """Background task to check profit targets and report closed trades"""
    global open_vip_tickets
    
    while True:
        try:
            if mt5.terminal_info():
                # Get current VIP positions
                positions = mt5.positions_get()
                current_tickets = set()
                symbol_profits = {}
                
                if positions:
                    for pos in positions:
                        if pos.magic >= MAGIC_BASE:
                            current_tickets.add(pos.ticket)
                            sym = pos.symbol
                            if sym not in symbol_profits:
                                symbol_profits[sym] = {'profit': 0, 'tickets': [], 'count': 0}
                            symbol_profits[sym]['profit'] += pos.profit
                            symbol_profits[sym]['tickets'].append(pos.ticket)
                            symbol_profits[sym]['count'] += 1
                
                # Check for closed positions (were open, now gone)
                closed_tickets = open_vip_tickets - current_tickets
                if closed_tickets and chat_id_store:
                    # Check history for these tickets
                    from datetime import timedelta
                    now = datetime.now()
                    deals = mt5.history_deals_get(now - timedelta(minutes=5), now)
                    if deals:
                        for deal in deals:
                            if deal.magic >= MAGIC_BASE and deal.entry == 1:  # DEAL_ENTRY_OUT
                                profit = deal.profit
                                sym = deal.symbol
                                result = "WIN" if profit > 0 else "LOSS"
                                msg = f"VIP {result}: ${profit:+.2f} on {sym}"
                                log.info(msg)
                                for cid in chat_id_store:
                                    try:
                                        await telegram_app.bot.send_message(cid, msg)
                                    except:
                                        pass
                
                open_vip_tickets = current_tickets
                
                # Check profit target per symbol - scales with number of signal sets
                for sym, data in symbol_profits.items():
                    signal_sets = max(1, data['count'] // POSITIONS_PER_SIGNAL)
                    scaled_target = PROFIT_TARGET * signal_sets
                    if data['profit'] >= scaled_target:
                        log.info(f"VIP PROFIT TARGET: {sym} +${data['profit']:.2f} (target ${scaled_target:.2f} for {signal_sets} sets)")
                        
                        # Close all positions for this symbol
                        for ticket in data['tickets']:
                            pos_list = mt5.positions_get(ticket=ticket)
                            if pos_list and len(pos_list) > 0:
                                p = pos_list[0]
                                close_type = mt5.ORDER_TYPE_SELL if p.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
                                price = mt5.symbol_info_tick(sym).bid if p.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(sym).ask
                                request = {
                                    "action": mt5.TRADE_ACTION_DEAL,
                                    "symbol": sym,
                                    "volume": p.volume,
                                    "type": close_type,
                                    "position": ticket,
                                    "price": price,
                                    "deviation": 30,
                                    "magic": p.magic,
                                    "comment": "VIP TP Hit",
                                }
                                for filling in [mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_RETURN]:
                                    request["type_filling"] = filling
                                    result = mt5.order_send(request)
                                    if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                                        break
                        
                        # Notify
                        msg = f"VIP TARGET HIT: +${data['profit']:.2f} on {sym} ({data['count']} positions closed)"
                        log.info(msg)
                        for cid in chat_id_store:
                            try:
                                await telegram_app.bot.send_message(cid, msg)
                            except:
                                pass
                                
        except Exception as e:
            log.error(f"Profit monitor error: {e}")
        await asyncio.sleep(2)


def main():
    from telegram.ext import ApplicationBuilder, MessageHandler, filters
    
    log.info("Starting RedBot VIP Signal Copier...")
    
    # Connect to MT5
    if not connect_mt5():
        log.error("Cannot start without MT5 connection")
        return
    
    # Build Telegram bot
    global telegram_app
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    telegram_app = app
    
    # Message handler - routes to signal parser or confirmation
    async def router(update, context):
        text = update.message.text
        if not text:
            return
        upper = text.strip().upper()
        
        # Handle BUY/SELL response for switching symbols
        if upper in ['BUY', 'SELL'] and 'pending_signal_no_dir' in context.user_data:
            signal = context.user_data.pop('pending_signal_no_dir')
            signal['direction'] = upper
            signal['needs_direction'] = False
            context.user_data['pending_signal'] = signal
            await update.message.reply_text(
                f"Direction set: {upper} {signal['symbol']}\n"
                f"TP: {signal['tp'] if signal['tp'] else 'ATR-based'}\n\n"
                f"Send 'YES' to execute or 'NO' to cancel."
            )
        elif upper in ['YES', 'NO'] and 'pending_signal' in context.user_data:
            await handle_confirmation(update, context)
        else:
            await handle_message(update, context)
    
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, router))
    app.add_handler(MessageHandler(filters.COMMAND, lambda u, c: handle_message(u, c)))
    
    log.info("Bot ready. Forward VIP signals to execute trades.")
    log.info(f"Settings: {POSITIONS_PER_SIGNAL} positions, {RISK_PER_POSITION}% risk/pos, SL={SL_POINTS}pts, TP=${PROFIT_TARGET}")
    
    # Run bot
    # Add profit monitor as background task
    async def post_init(application):
        asyncio.create_task(profit_monitor())
    
    app.post_init = post_init
    app.run_polling()


if __name__ == "__main__":
    main()
