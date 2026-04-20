"""
RedBot v4.0 - Market Analysis Agent
====================================
Connects to MT5 on your VPS, pulls trade history and market data,
then generates actionable insights per symbol.

Setup:
  pip install MetaTrader5 pandas tabulate

Usage:
  python redbot_analyst.py              # Last 7 days
  python redbot_analyst.py --days 30    # Last 30 days
  python redbot_analyst.py --live       # Continuous monitoring mode
"""

import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime, timedelta
import argparse
import time
import json
import os

# ─── CONFIG ───
MAGIC_BASE = 234567  # Base magic number from EA
VIP_MAGIC_BASE = 555555  # Base magic for VIP signal copier
SYMBOLS = [
    "GainX 400", "GainX 600", "GainX 800", "GainX 999", "GainX 1200",
    "PainX 400", "PainX 600", "PainX 800", "PainX 999", "PainX 1200",
    "FX Vol 20", "FX Vol 40", "FX Vol 60", "FX Vol 80", "FX Vol 99",
    "SFX Vol 20", "SFX Vol 40", "SFX Vol 60", "SFX Vol 80", "SFX Vol 99",
    "BreakX 600", "BreakX 1200", "BreakX 1800",
]

def compute_magic(symbol, base=MAGIC_BASE):
    """Replicate the EA's magic number calculation: base + sum of char*pos"""
    magic = base
    for i, ch in enumerate(symbol):
        magic += ord(ch) * (i + 1)
    return magic

# Pre-compute all valid magic numbers (both RedBot and VIP)
VALID_MAGICS = set()
REDBOT_MAGICS = set()
VIP_MAGICS = set()
for s in SYMBOLS:
    rm = compute_magic(s, MAGIC_BASE)
    vm = compute_magic(s, VIP_MAGIC_BASE)
    REDBOT_MAGICS.add(rm)
    VIP_MAGICS.add(vm)
    VALID_MAGICS.add(rm)
    VALID_MAGICS.add(vm)

REPORT_FILE = "redbot_analysis.json"


def connect():
    """Connect to MT5 terminal"""
    if not mt5.initialize():
        print(f"MT5 init failed: {mt5.last_error()}")
        return False
    info = mt5.account_info()
    if info:
        print(f"Connected: #{info.login} | Balance: ${info.balance:.2f} | Equity: ${info.equity:.2f}")
    return True


def get_trade_history(days=7):
    """Pull closed trades from MT5 history"""
    now = datetime.now()
    start = now - timedelta(days=days)
    
    deals = mt5.history_deals_get(start, now)
    if deals is None or len(deals) == 0:
        print("No deals found in history")
        return pd.DataFrame()
    
    df = pd.DataFrame(list(deals), columns=deals[0]._asdict().keys())
    
    # Filter to our EA's trades (entry out = closed trades)
    df = df[(df['magic'].isin(VALID_MAGICS)) & (df['entry'] == 1)]  # DEAL_ENTRY_OUT
    
    if df.empty:
        print(f"No RedBot trades found. Valid magics: {VALID_MAGICS}")
        return df
    
    df['time'] = pd.to_datetime(df['time'], unit='s')
    df['date'] = df['time'].dt.date
    df['hour'] = df['time'].dt.hour
    df['day_of_week'] = df['time'].dt.day_name()
    df['win'] = df['profit'] > 0
    df['loss'] = df['profit'] < 0
    df['source'] = df['magic'].apply(lambda m: 'VIP' if m in VIP_MAGICS else 'RedBot')
    
    return df


def symbol_profiler(df):
    """Per-symbol performance breakdown"""
    print("\n" + "=" * 70)
    print("  PER-SYMBOL PERFORMANCE PROFILER")
    print("=" * 70)
    
    results = []
    
    for symbol in df['symbol'].unique():
        sdf = df[df['symbol'] == symbol]
        wins = sdf[sdf['win']]
        losses = sdf[sdf['loss']]
        
        total_trades = len(sdf)
        win_count = len(wins)
        loss_count = len(losses)
        win_rate = (win_count / total_trades * 100) if total_trades > 0 else 0
        
        total_profit = sdf['profit'].sum()
        avg_win = wins['profit'].mean() if len(wins) > 0 else 0
        avg_loss = losses['profit'].mean() if len(losses) > 0 else 0
        
        # Profit factor
        gross_profit = wins['profit'].sum() if len(wins) > 0 else 0
        gross_loss = abs(losses['profit'].sum()) if len(losses) > 0 else 0.01
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else 999
        
        # Max consecutive losses
        max_consec_loss = 0
        current_streak = 0
        for p in sdf['profit'].values:
            if p < 0:
                current_streak += 1
                max_consec_loss = max(max_consec_loss, current_streak)
            else:
                current_streak = 0
        
        # Max drawdown in a single trade set
        worst_trade = sdf['profit'].min()
        best_trade = sdf['profit'].max()
        
        result = {
            'symbol': symbol,
            'trades': total_trades,
            'wins': win_count,
            'losses': loss_count,
            'win_rate': win_rate,
            'net_pnl': total_profit,
            'avg_win': avg_win,
            'avg_loss': avg_loss,
            'profit_factor': profit_factor,
            'max_consec_loss': max_consec_loss,
            'worst_trade': worst_trade,
            'best_trade': best_trade,
        }
        results.append(result)
    
    # Sort by net P&L
    results.sort(key=lambda x: x['net_pnl'], reverse=True)
    
    for r in results:
        status = "PROFITABLE" if r['net_pnl'] > 0 else "BLEEDING"
        color_indicator = "+" if r['net_pnl'] > 0 else ""
        
        print(f"\n  {r['symbol']} — {status}")
        print(f"  {'─' * 50}")
        print(f"  Trades: {r['trades']}  |  Wins: {r['wins']}  |  Losses: {r['losses']}")
        print(f"  Win Rate: {r['win_rate']:.1f}%  |  Profit Factor: {r['profit_factor']:.2f}")
        print(f"  Net P&L: {color_indicator}${r['net_pnl']:.2f}")
        print(f"  Avg Win: ${r['avg_win']:.2f}  |  Avg Loss: ${r['avg_loss']:.2f}")
        print(f"  Best: ${r['best_trade']:.2f}  |  Worst: ${r['worst_trade']:.2f}")
        print(f"  Max Consecutive Losses: {r['max_consec_loss']}")
    
    return results


def source_analysis(df):
    """Breakdown by RedBot vs VIP signals"""
    print("\n" + "=" * 70)
    print("  REDBOT vs VIP SIGNAL PERFORMANCE")
    print("=" * 70)
    
    for source in ['RedBot', 'VIP']:
        sdf = df[df['source'] == source]
        if len(sdf) == 0:
            print(f"\n  {source}: No trades")
            continue
        
        total = len(sdf)
        wins = sdf['win'].sum()
        losses = sdf['loss'].sum()
        wr = (wins / total * 100) if total > 0 else 0
        net = sdf['profit'].sum()
        avg_win = sdf[sdf['win']]['profit'].mean() if wins > 0 else 0
        avg_loss = sdf[sdf['loss']]['profit'].mean() if losses > 0 else 0
        
        gross_win = sdf[sdf['win']]['profit'].sum() if wins > 0 else 0
        gross_loss = abs(sdf[sdf['loss']]['profit'].sum()) if losses > 0 else 0.01
        pf = gross_win / gross_loss if gross_loss > 0 else 999
        
        indicator = "+" if net > 0 else ""
        print(f"\n  {source}:")
        print(f"  {'─' * 50}")
        print(f"  Trades: {total}  |  Wins: {int(wins)}  |  Losses: {int(losses)}")
        print(f"  Win Rate: {wr:.1f}%  |  Profit Factor: {pf:.2f}")
        print(f"  Net P&L: {indicator}${net:.2f}")
        print(f"  Avg Win: ${avg_win:.2f}  |  Avg Loss: ${avg_loss:.2f}")
        
        # Per-symbol breakdown for this source
        if len(sdf['symbol'].unique()) > 1:
            print(f"\n  {source} by symbol:")
            for sym in sdf['symbol'].unique():
                ssdf = sdf[sdf['symbol'] == sym]
                s_net = ssdf['profit'].sum()
                s_wr = ssdf['win'].mean() * 100
                s_ind = "+" if s_net > 0 else ""
                print(f"    {sym:<15} {len(ssdf)} trades  WR:{s_wr:.0f}%  {s_ind}${s_net:.2f}")


def time_analysis(df):
    """Analyze performance by time of day"""
    print("\n" + "=" * 70)
    print("  TIME-OF-DAY PERFORMANCE")
    print("=" * 70)
    
    # Group by hour
    hourly = df.groupby('hour').agg(
        trades=('profit', 'count'),
        net_pnl=('profit', 'sum'),
        win_rate=('win', 'mean'),
        avg_profit=('profit', 'mean')
    ).round(2)
    
    print(f"\n  {'Hour':<8} {'Trades':<10} {'Net P&L':<12} {'Win Rate':<12} {'Avg P&L':<10}")
    print(f"  {'─' * 52}")
    
    for hour, row in hourly.iterrows():
        indicator = "+" if row['net_pnl'] > 0 else ""
        wr = f"{row['win_rate']*100:.0f}%"
        print(f"  {hour:02d}:00   {int(row['trades']):<10} {indicator}${row['net_pnl']:<11.2f} {wr:<12} ${row['avg_profit']:.2f}")
    
    # Best and worst hours
    if not hourly.empty:
        best_hour = hourly['net_pnl'].idxmax()
        worst_hour = hourly['net_pnl'].idxmin()
        print(f"\n  BEST HOUR:  {best_hour:02d}:00 (+${hourly.loc[best_hour, 'net_pnl']:.2f})")
        print(f"  WORST HOUR: {worst_hour:02d}:00 (${hourly.loc[worst_hour, 'net_pnl']:.2f})")


def day_of_week_analysis(df):
    """Performance by day of week"""
    print("\n" + "=" * 70)
    print("  DAY-OF-WEEK PERFORMANCE")
    print("=" * 70)
    
    day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    daily = df.groupby('day_of_week').agg(
        trades=('profit', 'count'),
        net_pnl=('profit', 'sum'),
        win_rate=('win', 'mean'),
    ).round(2)
    
    # Reindex by day order
    daily = daily.reindex([d for d in day_order if d in daily.index])
    
    print(f"\n  {'Day':<12} {'Trades':<10} {'Net P&L':<12} {'Win Rate':<10}")
    print(f"  {'─' * 44}")
    
    for day, row in daily.iterrows():
        indicator = "+" if row['net_pnl'] > 0 else ""
        wr = f"{row['win_rate']*100:.0f}%"
        print(f"  {day:<12} {int(row['trades']):<10} {indicator}${row['net_pnl']:<11.2f} {wr}")


def daily_pnl_analysis(df):
    """Daily P&L breakdown"""
    print("\n" + "=" * 70)
    print("  DAILY P&L BREAKDOWN")
    print("=" * 70)
    
    daily = df.groupby('date').agg(
        trades=('profit', 'count'),
        net_pnl=('profit', 'sum'),
        wins=('win', 'sum'),
        losses=('loss', 'sum'),
    ).round(2)
    
    print(f"\n  {'Date':<14} {'Trades':<8} {'Wins':<7} {'Losses':<8} {'Net P&L':<10}")
    print(f"  {'─' * 47}")
    
    running_total = 0
    for date, row in daily.iterrows():
        running_total += row['net_pnl']
        indicator = "+" if row['net_pnl'] > 0 else ""
        print(f"  {str(date):<14} {int(row['trades']):<8} {int(row['wins']):<7} {int(row['losses']):<8} {indicator}${row['net_pnl']:.2f}")
    
    print(f"  {'─' * 47}")
    indicator = "+" if running_total > 0 else ""
    print(f"  {'TOTAL':<14} {int(daily['trades'].sum()):<8} {int(daily['wins'].sum()):<7} {int(daily['losses'].sum()):<8} {indicator}${running_total:.2f}")
    
    # Stats
    if len(daily) > 0:
        winning_days = (daily['net_pnl'] > 0).sum()
        losing_days = (daily['net_pnl'] < 0).sum()
        avg_day = daily['net_pnl'].mean()
        best_day = daily['net_pnl'].max()
        worst_day = daily['net_pnl'].min()
        
        print(f"\n  Winning Days: {winning_days}  |  Losing Days: {losing_days}")
        print(f"  Average Day: ${avg_day:.2f}")
        print(f"  Best Day: +${best_day:.2f}  |  Worst Day: ${worst_day:.2f}")


def win_loss_pattern_analysis(df):
    """Analyze patterns in wins and losses"""
    print("\n" + "=" * 70)
    print("  WIN/LOSS PATTERN ANALYSIS")
    print("=" * 70)
    
    # Pattern: what happens after a win vs after a loss
    for symbol in df['symbol'].unique():
        sdf = df[df['symbol'] == symbol].reset_index(drop=True)
        if len(sdf) < 5:
            continue
        
        after_win = []
        after_loss = []
        
        for i in range(1, len(sdf)):
            if sdf.loc[i-1, 'win']:
                after_win.append(sdf.loc[i, 'profit'])
            elif sdf.loc[i-1, 'loss']:
                after_loss.append(sdf.loc[i, 'profit'])
        
        print(f"\n  {symbol}:")
        if after_win:
            aw_wr = sum(1 for x in after_win if x > 0) / len(after_win) * 100
            print(f"    After a WIN  → Next trade win rate: {aw_wr:.0f}% (n={len(after_win)}), avg: ${sum(after_win)/len(after_win):.2f}")
        if after_loss:
            al_wr = sum(1 for x in after_loss if x > 0) / len(after_loss) * 100
            print(f"    After a LOSS → Next trade win rate: {al_wr:.0f}% (n={len(after_loss)}), avg: ${sum(after_loss)/len(after_loss):.2f}")


def entry_type_analysis(df):
    """Analyze performance by entry type if comment contains info"""
    print("\n" + "=" * 70)
    print("  ENTRY TYPE ANALYSIS")
    print("=" * 70)
    
    # Check if comments have useful info
    if 'comment' not in df.columns:
        print("  No comment data available")
        return
    
    for entry_type in ['OB', 'Engulf', 'Pin']:
        typed = df[df['comment'].str.contains(entry_type, na=False)]
        if len(typed) > 0:
            wr = typed['win'].mean() * 100
            net = typed['profit'].sum()
            indicator = "+" if net > 0 else ""
            print(f"  {entry_type:<10} Trades: {len(typed):<6} Win Rate: {wr:.0f}%  Net: {indicator}${net:.2f}")


def generate_recommendations(symbol_results, df):
    """Generate actionable recommendations"""
    print("\n" + "=" * 70)
    print("  RECOMMENDATIONS")
    print("=" * 70)
    
    recommendations = []
    
    for r in symbol_results:
        # Flag symbols with < 40% win rate
        if r['win_rate'] < 40 and r['trades'] >= 5:
            recommendations.append(
                f"CONSIDER DISABLING {r['symbol']}: Win rate {r['win_rate']:.0f}% with {r['trades']} trades. "
                f"Net loss: ${r['net_pnl']:.2f}"
            )
        
        # Flag symbols with high consecutive losses
        if r['max_consec_loss'] >= 4:
            recommendations.append(
                f"INCREASE COOLDOWN for {r['symbol']}: {r['max_consec_loss']} consecutive losses detected. "
                f"Current cooldown may be too short."
            )
        
        # Flag symbols with good win rate but negative P&L (avg loss > avg win)
        if r['win_rate'] > 50 and r['net_pnl'] < 0:
            recommendations.append(
                f"FIX RISK:REWARD on {r['symbol']}: Winning {r['win_rate']:.0f}% but still losing money. "
                f"Avg win ${r['avg_win']:.2f} vs avg loss ${r['avg_loss']:.2f}. "
                f"Losses are too large relative to wins."
            )
        
        # Highlight best performers
        if r['profit_factor'] > 1.5 and r['trades'] >= 5:
            recommendations.append(
                f"STRONG: {r['symbol']} has {r['profit_factor']:.1f}x profit factor. "
                f"Consider increasing position size or priority."
            )
    
    # Time-based recommendations
    hourly = df.groupby('hour')['profit'].sum()
    worst_hours = hourly[hourly < -5].index.tolist()
    if worst_hours:
        hours_str = ", ".join([f"{h:02d}:00" for h in worst_hours])
        recommendations.append(
            f"AVOID HOURS: Negative performance at {hours_str}. "
            f"Consider tightening time filter."
        )
    
    if not recommendations:
        print("\n  No critical issues detected. Keep monitoring.")
    else:
        for i, rec in enumerate(recommendations, 1):
            print(f"\n  {i}. {rec}")
    
    return recommendations


def save_report(symbol_results, recommendations):
    """Save analysis to JSON for the EA to potentially read"""
    report = {
        'timestamp': datetime.now().isoformat(),
        'symbols': symbol_results,
        'recommendations': recommendations,
    }
    with open(REPORT_FILE, 'w') as f:
        json.dump(report, f, indent=2, default=str)
    print(f"\n  Report saved to {REPORT_FILE}")


def run_analysis(days=7):
    """Run full analysis"""
    print(f"\n{'=' * 70}")
    print(f"  REDBOT v4.0 MARKET ANALYSIS AGENT")
    print(f"  Analyzing last {days} days of trading")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'=' * 70}")
    
    if not connect():
        return
    
    df = get_trade_history(days)
    
    if df.empty:
        print("\nNo trade data to analyze.")
        mt5.shutdown()
        return
    
    print(f"\n  Found {len(df)} closed trades across {df['symbol'].nunique()} symbols")
    
    # Run all analyses
    symbol_results = symbol_profiler(df)
    source_analysis(df)
    time_analysis(df)
    day_of_week_analysis(df)
    daily_pnl_analysis(df)
    win_loss_pattern_analysis(df)
    entry_type_analysis(df)
    recommendations = generate_recommendations(symbol_results, df)
    
    # Save report
    save_report(symbol_results, recommendations)
    
    mt5.shutdown()
    print(f"\n{'=' * 70}")
    print(f"  Analysis complete.")
    print(f"{'=' * 70}\n")


def live_monitor(interval=300):
    """Run analysis every N seconds"""
    print(f"Live monitoring mode - updating every {interval}s")
    print("Press Ctrl+C to stop\n")
    
    while True:
        try:
            run_analysis(days=1)
            print(f"\nNext update in {interval}s...")
            time.sleep(interval)
        except KeyboardInterrupt:
            print("\nMonitoring stopped.")
            break


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="RedBot v4.0 Market Analysis Agent")
    parser.add_argument('--days', type=int, default=7, help='Days of history to analyze')
    parser.add_argument('--live', action='store_true', help='Continuous monitoring mode')
    parser.add_argument('--interval', type=int, default=300, help='Seconds between updates in live mode')
    parser.add_argument('--magic', type=int, default=MAGIC_BASE, help='EA base magic number')
    
    args = parser.parse_args()
    MAGIC_BASE = args.magic
    
    # Recompute magics if base changed
    VALID_MAGICS.clear()
    REDBOT_MAGICS.clear()
    VIP_MAGICS.clear()
    for s in SYMBOLS:
        rm = compute_magic(s, MAGIC_BASE)
        vm = compute_magic(s, VIP_MAGIC_BASE)
        REDBOT_MAGICS.add(rm)
        VIP_MAGICS.add(vm)
        VALID_MAGICS.add(rm)
        VALID_MAGICS.add(vm)
    
    if args.live:
        live_monitor(args.interval)
    else:
        run_analysis(args.days)
