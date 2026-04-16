"""
RedBot Trade Relay Server
=========================
Runs on the DEMO VPS. Receives trade commands from the live VPS signal copier
and executes them on the demo MT5 account.

Setup:
  1. Install on demo VPS: pip install flask MetaTrader5 --break-system-packages
  2. Update RELAY_SECRET below (must match live copier)
  3. Run: python trade_relay.py

The live copier sends POST requests to this server whenever a VIP signal is confirmed.
"""

from flask import Flask, request, jsonify
import MetaTrader5 as mt5
import logging
from datetime import datetime

# ─── CONFIG ───
RELAY_PORT = 5555
RELAY_SECRET = "redbot_relay_2026"  # Must match live copier
RISK_PER_POSITION = 2.0
POSITIONS_PER_SIGNAL = 3
SL_POINTS = 50
MAGIC_BASE = 555555
PROFIT_TARGET = 15.0

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
log = logging.getLogger("TradeRelay")

app = Flask(__name__)


def compute_magic(symbol):
    magic = MAGIC_BASE
    for i, ch in enumerate(symbol):
        magic += ord(ch) * (i + 1)
    return magic


def connect_mt5():
    if not mt5.initialize():
        log.error(f"MT5 init failed: {mt5.last_error()}")
        return False
    info = mt5.account_info()
    if info:
        log.info(f"MT5 Connected: #{info.login} | Balance: ${info.balance:.2f}")
    return True


def calculate_lot(symbol, sl_distance):
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
    lots = int(lots / vol_step) * vol_step
    lots = max(lots, vol_min)
    lots = min(lots, vol_max)
    
    return round(lots, 2)


def execute_trade(symbol, direction, tp_price=None):
    """Execute trade on demo MT5"""
    if not mt5.symbol_select(symbol, True):
        return {"success": False, "error": f"Failed to select {symbol}"}
    
    info = mt5.symbol_info(symbol)
    if info is None:
        return {"success": False, "error": f"Symbol {symbol} not found"}
    
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return {"success": False, "error": f"No tick data for {symbol}"}
    
    if direction == "BUY":
        entry = tick.ask
        order_type = mt5.ORDER_TYPE_BUY
    else:
        entry = tick.bid
        order_type = mt5.ORDER_TYPE_SELL
    
    sl_distance = SL_POINTS
    
    if direction == "BUY":
        sl_price = round(entry - sl_distance, info.digits)
        tp = round(tp_price, info.digits) if tp_price else round(entry + sl_distance * 2, info.digits)
    else:
        sl_price = round(entry + sl_distance, info.digits)
        tp = round(tp_price, info.digits) if tp_price else round(entry - sl_distance * 2, info.digits)
    
    lot = calculate_lot(symbol, sl_distance)
    magic = compute_magic(symbol)
    max_loss = mt5.account_info().balance * (RISK_PER_POSITION / 100.0)
    
    opened = 0
    for i in range(POSITIONS_PER_SIGNAL):
        tick = mt5.symbol_info_tick(symbol)
        price = tick.ask if direction == "BUY" else tick.bid
        
        req = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": lot,
            "type": order_type,
            "price": price,
            "sl": sl_price,
            "tp": tp,
            "deviation": 30,
            "magic": magic,
            "comment": "VIP Relay",
            "type_time": mt5.ORDER_TIME_GTC,
        }
        
        for filling in [mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_RETURN]:
            req["type_filling"] = filling
            result = mt5.order_send(req)
            if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                opened += 1
                break
    
    return {
        "success": True,
        "opened": opened,
        "total": POSITIONS_PER_SIGNAL,
        "symbol": symbol,
        "direction": direction,
        "entry": entry,
        "sl": sl_price,
        "tp": tp,
        "lot": lot,
        "max_loss_per_pos": max_loss,
    }


@app.route('/trade', methods=['POST'])
def receive_trade():
    """Receive trade command from live copier"""
    data = request.json
    
    # Auth check
    if data.get('secret') != RELAY_SECRET:
        return jsonify({"success": False, "error": "Unauthorized"}), 401
    
    symbol = data.get('symbol')
    direction = data.get('direction')
    tp_price = data.get('tp')
    
    if not symbol or not direction:
        return jsonify({"success": False, "error": "Missing symbol or direction"}), 400
    
    log.info(f"RELAY RECEIVED: {direction} {symbol} TP:{tp_price}")
    
    # Ensure MT5 is connected
    if not mt5.terminal_info():
        if not connect_mt5():
            return jsonify({"success": False, "error": "MT5 not connected"}), 500
    
    result = execute_trade(symbol, direction, tp_price)
    
    if result['success']:
        log.info(f"RELAY EXECUTED: {result['opened']}/{result['total']} {direction} {symbol} @{result['entry']}")
    else:
        log.error(f"RELAY FAILED: {result['error']}")
    
    return jsonify(result)


@app.route('/status', methods=['GET'])
def status():
    """Account status endpoint"""
    secret = request.args.get('secret', '')
    if secret != RELAY_SECRET:
        return jsonify({"error": "Unauthorized"}), 401
    
    if not mt5.terminal_info():
        connect_mt5()
    
    info = mt5.account_info()
    positions = mt5.positions_get()
    
    vip_count = 0
    vip_profit = 0
    bot_count = 0
    bot_profit = 0
    
    if positions:
        for p in positions:
            if p.magic >= MAGIC_BASE:
                vip_count += 1
                vip_profit += p.profit
            elif p.magic > 0:
                bot_count += 1
                bot_profit += p.profit
    
    return jsonify({
        "account": info.login,
        "balance": info.balance,
        "equity": info.equity,
        "vip_positions": vip_count,
        "vip_floating": round(vip_profit, 2),
        "bot_positions": bot_count,
        "bot_floating": round(bot_profit, 2),
        "server_time": datetime.now().isoformat(),
    })


@app.route('/close', methods=['POST'])
def close_positions():
    """Close VIP positions"""
    data = request.json
    if data.get('secret') != RELAY_SECRET:
        return jsonify({"error": "Unauthorized"}), 401
    
    symbol = data.get('symbol')
    close_all = data.get('close_all', False)
    
    if not mt5.terminal_info():
        connect_mt5()
    
    positions = mt5.positions_get()
    closed = 0
    
    if positions:
        for p in positions:
            if p.magic < MAGIC_BASE:
                continue
            if not close_all and symbol and p.symbol != symbol:
                continue
            
            close_type = mt5.ORDER_TYPE_SELL if p.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
            price = mt5.symbol_info_tick(p.symbol).bid if p.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(p.symbol).ask
            
            req = {
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
            result = mt5.order_send(req)
            if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                closed += 1
    
    return jsonify({"closed": closed})


if __name__ == '__main__':
    log.info("Starting Trade Relay Server...")
    
    if not connect_mt5():
        log.error("Cannot start without MT5")
        exit(1)
    
    log.info(f"Relay ready on port {RELAY_PORT}")
    log.info(f"Settings: {POSITIONS_PER_SIGNAL} positions, {RISK_PER_POSITION}% risk/pos, SL={SL_POINTS}pts")
    
    app.run(host='0.0.0.0', port=RELAY_PORT)
