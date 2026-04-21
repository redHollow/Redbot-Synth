# RedBot v4.0 — Synthetic Index Trading System

Automated trading system for Deriv synthetic indices (GainX/PainX/BreakX/FX Vol/SFX Vol) running on MetaTrader 5.

## Components

**RedBot EA** (`RedBot_GainX_v40.mq5`)
MQL5 Expert Advisor — M5 scalper using supply/demand zones, stochastic filter, and multi-timeframe trend alignment (D1 EMA). Manages risk with ATR-based SL/TP, percentage-based profit targets, and breakeven protection.

**VIP Signal Copier** (`signal_copier.py`)
Telegram bot that receives forwarded VIP group signals and executes them on MT5. Supports GainX, PainX, FX Vol, SFX Vol, and BreakX symbols. Features auto-direction detection, switching symbol prompts (BUY/SELL), scaled profit targets, and daily loss blocking per symbol.

**Market Analyst** (`redbot_analyst.py`)
Python tool that pulls MT5 trade history and generates performance reports — per-symbol profiling, RedBot vs VIP breakdown, time-of-day analysis, win/loss patterns, and recommendations.

## Supported Symbols

| Type | Symbols |
|------|---------|
| GainX | 400, 600, 800, 999, 1200 |
| PainX | 400, 600, 800, 999, 1200 |
| FX Vol | 20, 40, 60, 80, 99 |
| SFX Vol | 20, 40, 60, 80, 99 |
| BreakX | 600, 1200, 1800 |

## Setup

### EA
1. Copy `RedBot_GainX_v40.mq5` to MT5 `Experts` folder
2. Compile in MetaEditor
3. Attach to any supported symbol chart (M5 timeframe)
4. EA auto-detects GainX (SELL) / PainX (BUY) bias

### Signal Copier
```bash
pip install python-telegram-bot MetaTrader5 requests
python signal_copier.py
```

### Analyst
```bash
pip install MetaTrader5 pandas
python redbot_analyst.py --days 7
```

## Risk Management

- ATR-based SL/TP (1.5x ATR stop, 2.25x ATR target)
- 2% risk per position, 3 positions per signal
- Percentage-based profit target (scales with balance)
- Breakeven lock after 1% combined profit
- Cooldown after 2 consecutive losses (40 bars)
- Daily symbol loss limit
- Sunday trading blocked

## Architecture

```
VIP WhatsApp Group
        │
        ▼ (manual forward)
  Telegram Bot ──────► MT5 (Live)
        │
        ▼ (relay)
  Trade Relay ───────► MT5 (Demo)

  RedBot EA ─────────► MT5 (auto trades)
  
  Analyst ◄──────────── MT5 (trade history)
```

## Status

Active development. Live trading since Feb 2026.
