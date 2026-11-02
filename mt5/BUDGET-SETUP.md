# Adjustable risk app + EA v1.04

This version needs all three updated pieces: the published backend, rebuilt mobile app and `AGGRESSIVE_GOLD_SCALPER_BUDGET.mq5`. The original EA remains unchanged but is no longer allowed to Start on the updated backend: it cannot enforce the new daily budget. Older APKs do not expose the new inputs. The new EA refuses the old backend's AGS1 commands.

## What the three percentages mean

All three accept **0.1–10%**. Defaults remain entry 0.5%, daily risk budget 2%, daily-loss stop 2%. Higher limits permit higher exposure; none guarantees a maximum loss.

- **Per-entry risk:** fixed 0.05-lot FX entries must fit this percentage of current equity, with a 10% execution reserve. The EA skips rather than resizing lots. **Gold is one 0.01-lot order and bypasses this entry cap only.**
- **Daily risk budget:** the sum of each filled EA entry deal's estimated initial stop-loss risk, divided by the broker-day recorded baseline equity. Both gold and FX must fit the remaining budget before submission. Wins, closing trades and tightening stops do not refund used budget. Example: baseline equity 1,000 account-currency units and budget 2% means 20 units of cumulative initial stop-risk; entries using 5 units each spend approximately 0.5 percentage points each.
- **Daily-loss stop:** highest observed broker-day equity loss versus the recorded baseline, including unrealized/account-wide equity changes. It blocks new entries once reached, without closing positions. Equity recovery does not erase today's peak recorded loss.

The baseline is recorded when the EA first observes the broker day (or reused from the original EA's same-account/magic daily baseline). It is not reconstructed midnight equity if MT5 was offline. Both counters use broker-server dates, not the phone's date. The phone displays last-received MT5 data; the EA enforces locally.

## Ledger and execution limits

Entry deal history (`DEAL_SL`, initial entry price and volume) reconstructs risk across restarts. The first calculated risk estimate per deal and cumulative high-water total are persisted in MT5 terminal globals; budget closes/wins never replenish it. Same-day historical entries with the same magic are included when history and original SL are available, including entries made before upgrading. Missing initial SL/history causes a fail-closed ledger, not an assumed zero.

Before sending an order, the EA durably reserves its estimated stop-risk including the configured deviation allowance. On confirmed execution it reconciles actual filled deal volume/price/initial SL. Known rejections release the reservation. Unknown/time-out results keep risk reserved and block further entries until history reconciliation identifies the fill. Check Experts/Journal if `Ledger: BLOCKED`; do not delete terminal globals or change magic to bypass protection. If a broker rewrites the comment and no order identifier is available, manual investigation may be required.

Slippage/gaps, commissions and currency conversion can make actual losses or post-fill risk exceed estimates. A daily budget is an allocation guard, not a guaranteed monetary-loss ceiling. State lives in the same MT5 terminal; do not move terminals, clear globals or run multiple instances to reset it.

## Upgrade order

1. **Stop new entries** in the existing app. Stop does not close positions. Prefer upgrading flat; keep only one EA instance per account/magic.
2. Publish the updated backend using Runable's publishing UI. Its new downloads and AGS2 bridge must be live. Existing EA controllers may show ONLINE but Start is blocked until the matching EA is installed.
3. Update your GitHub source and rebuild the APK through your existing Expo website workflow. Keep your existing Expo project ID, matching slug, Android package and private environment values. The API URL must be your published backend: `https://aggress-fzvpmri.runable.site` (not the preview URL). Keep `packages/mobile/babel.config.js`, required for the Hermes/oRPC build fix. Do not copy a local `.env` or Expo token into GitHub.
4. MT5 → File → Open Data Folder → MQL5 → Experts. Copy the **new** `AGGRESSIVE_GOLD_SCALPER_BUDGET.mq5`, open it in MetaEditor and press **F7**. Require zero compiler errors. No EX5 is supplied and full native compilation has not been verified here.
5. Remove the previous EA and attach **one** budget EA to XAUUSD M1. Keep the original MagicNumber, MaxDeviationPoints and terminal PairingKey. Set `TesterMode=false` and `AllowLiveTrading=false` for demo. Set BridgeURL to `https://aggress-fzvpmri.runable.site/api/webhooks/mt5`.
6. Tools → Options → Expert Advisors: allow WebRequest origin `https://aggress-fzvpmri.runable.site`; enable terminal Algo Trading and EA permission. Check the chart reads **BUDGET 1.04** and **Ledger: READY**.
7. In the rebuilt app, Settings → enter the three percentages → **Save risk limits / stop entries**. Higher/increased limits require confirmation. Saving stops entries; it never clears today's recorded usage or loss. Wait for ONLINE and updated telemetry, then explicitly tap Start.

Increasing either daily limit after it has been reached can permit further entries today once settings sync and you deliberately Start again. Lowering a limit below current usage stops further entries. Avoid raising limits to chase losses.

## Strategy retained

Gold spread must be ≤20% of M1 ATR14 **and** ≤0.40 quoted-price units; configurable inputs permit tightening only. FX retains 12% ATR. Original EMA/ATR signals, broker-time 07:00–20:00 entry window, local stop/trailing management, lease, exposure and permission checks remain. Gold impulse signals can trigger one order, never a multi-order burst. Live remains opt-in through `AllowLiveTrading=true` plus the app's live Start confirmation.

## Testing

Inside Strategy Tester only, enable TesterMode, choose exact TesterSymbol, and set TesterEntryRiskPct / TesterDailyBudgetPct / TesterDailyLossPct (each 0.1–10%). They are ignored outside Tester; the app supplies runtime percentages. Backtest realistic ticks/costs and demo-forward-test. This update is not profitability-validated. No live orders were initiated during development.