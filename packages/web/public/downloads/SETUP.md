 # AGGRESSIVE GOLD SCALPER — MT5 setup

## What you receive

- An Expo mobile control app and a managed Hono backend.
- `AGGRESSIVE_GOLD_SCALPER.mq5`: an experimental MT5 Expert Advisor source file. It runs the trading logic in your own terminal. No MetaApi or paid trading API is used.
- Start/Stop controls, four instrument choices, shared-risk impulse entries, ATR trailing, account telemetry, recent exit deals, and a control log.

**Status:** TypeScript and app builds are tested separately. The EA source has not been compiled or executed in MetaEditor in this Linux environment. It must be compiled and tested in your own MT5 demo terminal before live use. There is no validated profitability claim, backtest result, or guarantee.

## Requirements

1. Windows MT5 desktop terminal logged into your broker account. The MT5 phone app cannot host EAs.
2. A continuously reachable HTTPS backend for this app. Use the platform's publishing controls; the preview URL is for testing and is not a 24/7 hosting guarantee. Keep the database configured and persistent.
3. Internet access and permission to trade this account. Use an MT5 **demo account first**.

The bridge itself has no API subscription. Hosting, electricity, trading spreads/commissions, and an optional VPS are not necessarily free. A sleeping/offline computer will not run the EA. If MT5 is closed, existing broker-side SL/TP remain, but trailing modifications cannot continue.

## Install and pair

1. Publish/run the backend and open the mobile app. For Android/iOS builds, use **Publish** in the mobile preview dashboard and connect your Expo account. No APK/IPA is included here.
2. Open **Bridge → Create free bridge**. Copy the private recovery key to a password manager. Never share it: possession grants control of this bot. The terminal-only key is separate. Native storage uses SecureStore; browser preview storage is limited to the current browser-tab session.
3. In MT5 choose **File → Open Data Folder**. Copy the `.mq5` file into `MQL5/Experts`. Open it in MetaEditor and press **F7**. Resolve any compiler errors before proceeding. The resulting `.ex5` appears in MT5 Navigator after refresh.
4. In **Tools → Options → Expert Advisors**, enable Algo Trading and allow WebRequest for the backend **origin**, for example `https://your-backend.example` (not just the heartbeat path).
5. Attach the EA to **ONE chart in ONE terminal per account**. Do not install copies on another computer/account session. The local lock only detects duplicate instances inside the same terminal; it cannot coordinate separate machines. Keep the default magic number and avoid other EAs with that number.
6. Set EA inputs:
   - `BridgeURL`: exact URL shown in the app, ending `/api/webhooks/mt5`.
   - `PairingKey`: the **terminal pairing key**, not the controller recovery key.
   - `AllowLiveTrading=false` for demo testing. Real accounts require this to be changed to `true` deliberately.
   - `TesterMode=false` for normal operation.
7. Enable the main MT5 **Algo Trading** button and permissions on the EA. Wait for **MT5 ONLINE** in the phone app (heartbeat about every five seconds).
8. Select one instrument. If the broker uses `XAUUSDm`, `GOLD.a`, etc., go to **Settings → Broker symbol mapping** and enter the exact Market Watch name. `GOLD` and `XAUUSD` are aliases: never trade both as independent exposures.
9. Press **Start scalper**. A real account requires a second explicit confirmation on the phone. The app first shows a start request; terminal acknowledgement follows a heartbeat. Start does not force an order—entries wait for the strategy filters.

## Strategy and risk behaviour

- Gold: M5 EMA20/EMA50 bias; closed M1 bar EMA9 pullback or a directional body greater than 1.5 ATR14 breaking the preceding bar. Gold impulses can submit up to three sequential orders.
- GBPUSD/AUDUSD: closed M5 EMA9 pullback with M5 EMA20/50 bias; one order.
- Entries only from **07:00 to 20:00 broker server time**. No session optimisation or economic-news filter is included. Pause around news, illiquidity and broker maintenance.
- Spread filter: spread must be at most 12% of entry-timeframe ATR14. This can reject most entries on some brokers.
- Stop distance: at least 1.2 ATR and the broker minimum. Target: 1.5 times that distance. Broker tick size, lot step/min/max, margin, and trade return codes are checked.
- The configured 0.5% equity risk is the **total initial stop-risk budget for the entire basket**, not per order. A 10% execution reserve reduces calculated volume. It does not cover every commission, gap or slippage scenario. If minimum lot size exceeds budget, the EA skips. Partial/rejected burst orders are not retried automatically on that bar.
- Hedging accounts can show three tickets. Netting accounts combine executions into one position. Only one bot basket at a time; manual exposure on the selected symbol or recognised gold alias blocks new entries. Do not mix manual trading in the same netting symbol: ownership/protective management can become ambiguous.
- At approximately 1R favourable movement, trailing tries to protect break-even plus the current spread and trail by 1 ATR. Stops only tighten. Broker freezes/rejections are logged. Trailing uses the position's TP distance to infer initial R; manual TP edits distort that calculation.
- The daily guard measures the worst observed equity drop from the broker-day baseline, persisted in MT5 terminal global variables, including floating losses and all account activity. It blocks new entries until the next broker day once the configured threshold is reached. It does **not** force-close positions. On first installation mid-day the baseline is installation equity, not reconstructed midnight equity. Deposits/withdrawals distort this metric. Do not clear global variables to bypass limits.
- Risk controls limit requested exposure, not guaranteed losses. Gaps, execution costs, outages, other trades, partial fills, and broker behaviour can exceed limits.

## Stop, disconnect and recovery

**Stop** halts new entries after the next command sync. It does not close positions or cancel broker-side stops. Protective management stays local when trailing is enabled. There is no emergency close-all button in this version.

A heartbeat lease lasts 20 seconds. On loss of connectivity the EA disables entries; broker SL/TP persist, and local trailing continues while the terminal is running. On reconnect after a lease lapse the backend stops the requested run state. Start again manually. A daily stop and disabled trading permissions also clear the requested run state. Restarting the EA requires renewed remote Start/sync.

**Rotate terminal key / stop bot** invalidates the old terminal key. Re-enter the new key in EA inputs. A stolen controller recovery key still controls the app: terminal-key rotation does not revoke it. Keep both keys private, use HTTPS and trusted devices. A full user-login/administrative account system is not included; this is a single-owner capability-paired app.

## Backtesting and acceptance checks

MT5 WebRequest does not run in Strategy Tester. To test the local strategy, choose the EA in Strategy Tester, enable `TesterMode=true`, and set `TesterSymbol` to the exact broker symbol. This bypass is active **only inside Strategy Tester** and never enables live trading. Fixed default tester settings are 0.5% risk, 2% daily guard, trailing/impulse on. Use realistic ticks, spreads, commissions and execution conditions; then forward-test on demo.

Before live use, verify in your terminal:

- EA compiles with no errors and opens no trades before Start.
- Demo telemetry matches MT5 balance/equity/positions.
- Symbol suffix mapping works; an unavailable symbol fails closed.
- Loss budget and volume step are correct for your broker's gold contract.
- Three impulse orders share total risk; netting/hedging behaviour is understood.
- Every entry has broker-side SL and TP, and trailing never loosens SL.
- Stop pauses entries without closing positions.
- Disconnect for over 20 seconds blocks new entries and reconnect requires Start.
- Daily guard stays latched after equity recovers and survives EA restart.
- Market closed, large spread, margin shortage and minimum-lot violations reject entries safely.

No real terminal has been connected during development. Demo and live execution, broker-specific compilation/behaviour, mobile native builds and continuous deployment are not verified here.

## Data and references

Recent history displays up to 20 bot exit deals from the last seven days. Exit profit includes the exit deal's commission, swap and fee, but not necessarily entry-side commissions. It is not a complete performance report. Account equity/daily changes include non-bot activity.

- MT5 WebRequest: https://www.mql5.com/en/docs/network/webrequest
- CTrade Buy: https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradebuy
- CTrade PositionModify: https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionmodify