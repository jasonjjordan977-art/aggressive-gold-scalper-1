// AGGRESSIVE GOLD SCALPER — HFM fixed-lot spread-test candidate, not HFM endorsed.
// Experimental, no profitability guarantee. Compile in MetaEditor 5.
// Attach ONE instance per account. Demo-test first. Live remains opt-in.
// User-approved exception: ONE 0.01 gold order may exceed the percentage-risk cap.
// Gold still obeys the cumulative DAILY risk budget and DAILY loss stop.
// All settings 0.1–10%. Requires updated AGS2 backend/app. Demo-test first.
#property strict
#property version "1.04"
#include <Trade/Trade.mqh>
input string BridgeURL="https://aggress-fzvpmri.runable.site/api/webhooks/mt5";
input string PairingKey="";
input bool AllowLiveTrading=false;
input ulong MagicNumber=2601102;
input int MaxDeviationPoints=20;
// Gold price differences, NOT points or account-currency amounts.
// Defaults are demo-test candidates; inputs can tighten but not widen these caps.
input double MaxGoldSpreadAtrFraction=0.20;
input double MaxGoldSpreadPrice=0.40;
// Offline backtesting deliberately bypasses remote controls ONLY in Strategy Tester.
input bool TesterMode=false;
input string TesterSymbol="XAUUSD";
input double TesterEntryRiskPct=0.5;
input double TesterDailyBudgetPct=2.0;
input double TesterDailyLossPct=2.0;

// Fixed requested volume PER ORDER; never rounded up or automatically resized.
const double GOLD_ORDER_LOTS=0.01;
const double FX_ORDER_LOTS=0.05;

CTrade trade;
bool running=false,impulse=true,trailing=true;
double riskPct=0.5,dailyLimit=2.0,dailyBudgetPct=2.0,dayEquity=0;
double dailyRiskMoney=0,pendingRisk=0;
bool budgetReady=false;
datetime lastRiskRefresh=0;
string riskLedgerKey="";
string activeSymbol="XAUUSD",pair="XAUUSD",state="Waiting for mobile Start",dayKey="",lockKey="",bootId="";
string spreadInfo="Spread check pending (last entry evaluation)";
string riskInfo="Gold: 0.01 lot, entry cap bypassed ONLY. Daily budget enforced.";
datetime lastContact=0,lastSend=0,lastBar=0;
bool ownsLock=false;

string Escape(string value){StringReplace(value,"\\","\\\\");StringReplace(value,"\"","\\\"");StringReplace(value,"\n"," ");StringReplace(value,"\r"," ");return value;}
string Num(double n,int digits=2){return DoubleToString(n,digits);}
bool IsTester(){return MQLInfoInteger(MQL_TESTER)&&TesterMode;}
bool Permission(){if(IsTester())return true;return TerminalInfoInteger(TERMINAL_CONNECTED)&&TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)&&MQLInfoInteger(MQL_TRADE_ALLOWED)&&AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)&&AccountInfoInteger(ACCOUNT_TRADE_EXPERT)&&(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_REAL||AllowLiveTrading);}
bool Lease(){return IsTester()||(lastContact>0&&TimeLocal()-lastContact<=20);}

void DailyBaseline(){
  MqlDateTime d;TimeToStruct(TimeCurrent(),d);
  string key=StringFormat("AGS_DAY_%I64d_%I64u_%04d%02d%02d",AccountInfoInteger(ACCOUNT_LOGIN),MagicNumber,d.year,d.mon,d.day);
  if(dayKey!=key){dayKey=key;if(!GlobalVariableCheck(key))GlobalVariableSet(key,AccountInfoDouble(ACCOUNT_EQUITY));dayEquity=GlobalVariableGet(key);}
}
double DailyLoss(){
  DailyBaseline();if(dayEquity<=0)return 100;
  double loss=MathMax(0,(dayEquity-AccountInfoDouble(ACCOUNT_EQUITY))/dayEquity*100);
  string lossKey=dayKey+"_LOSS";
  if(GlobalVariableCheck(lossKey))loss=MathMax(loss,GlobalVariableGet(lossKey));
  GlobalVariableSet(lossKey,loss);return loss;
}

bool ValidPercent(double value){return MathIsValidNumber(value)&&value>=0.1&&value<=10.0;}
bool FitsDailyRisk(double used,double added,double baseline,double capPct){
  return MathIsValidNumber(used)&&MathIsValidNumber(added)&&MathIsValidNumber(baseline)&&used>=0&&added>0&&baseline>0&&ValidPercent(capPct)&&(used+added<=baseline*capPct/100.0+1e-9);
}

string ScopedRiskKey(){
  // Short dual hash keeps every MT5 global name below its 63-character limit.
  string scope=AccountInfoString(ACCOUNT_SERVER)+"|"+dayKey;
  uint a=2166136261,b=5381;
  for(int i=0;i<StringLen(scope);i++){uint c=(uint)StringGetCharacter(scope,i);a=(a^c)*16777619;b=b*33+c;}
  return "AGS_R2_"+IntegerToString((long)a)+"_"+IntegerToString((long)b);
}

// Reconstruct each entry deal's INITIAL stop-risk, never today's P/L or trailing SL.
// DEAL_SL on entry deals is the original order's SL. Cache first estimate per deal.
// Both broker history and durable globals survive EA restarts on this terminal.
void RefreshDailyRisk(bool force=false){
  DailyBaseline();
  string key=ScopedRiskKey();
  if(key!=riskLedgerKey){riskLedgerKey=key;dailyRiskMoney=0;pendingRisk=0;lastRiskRefresh=0;force=true;}
  if(!force&&lastRiskRefresh==TimeLocal())return;
  lastRiskRefresh=TimeLocal();budgetReady=false;
  if(dayEquity<=0||!MathIsValidNumber(dayEquity))return;
  MqlDateTime d;TimeToStruct(TimeCurrent(),d);d.hour=0;d.min=0;d.sec=0;
  if(!HistorySelect(StructToTime(d),TimeCurrent()))return;
  string pendingKey=key+"_P",nonceKey=key+"_N",orderKey=key+"_O";
  pendingRisk=GlobalVariableCheck(pendingKey)?GlobalVariableGet(pendingKey):0;
  double nonce=GlobalVariableCheck(nonceKey)?GlobalVariableGet(nonceKey):0;
  // Order ticket is a double global; nonce/comment is a second matching route.
  ulong pendingOrder=GlobalVariableCheck(orderKey)?(ulong)GlobalVariableGet(orderKey):0;
  bool matched=false;double historyTotal=0;
  for(int i=0;i<HistoryDealsTotal();i++){
    ulong ticket=HistoryDealGetTicket(i);if(ticket==0)continue;
    if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=MagicNumber)continue;
    long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY),type=HistoryDealGetInteger(ticket,DEAL_TYPE);
    if(entry!=DEAL_ENTRY_IN&&entry!=DEAL_ENTRY_INOUT)continue;
    if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL)continue;
    string dealKey=key+"_D"+IntegerToString((long)ticket);
    double cost=0;
    if(GlobalVariableCheck(dealKey))cost=GlobalVariableGet(dealKey);
    else{
      double volume=HistoryDealGetDouble(ticket,DEAL_VOLUME),open=HistoryDealGetDouble(ticket,DEAL_PRICE),sl=HistoryDealGetDouble(ticket,DEAL_SL),loss=0;
      string symbol=HistoryDealGetString(ticket,DEAL_SYMBOL);
      ENUM_ORDER_TYPE side=type==DEAL_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(sl<=0||volume<=0||!OrderCalcProfit(side,symbol,volume,open,sl,loss)||!MathIsValidNumber(loss)||loss>=0){state="Daily risk history missing initial SL/risk; entries blocked";return;}
      cost=MathAbs(loss);if(GlobalVariableSet(dealKey,cost)==0)return;
    }
    if(!MathIsValidNumber(cost)||cost<=0)return;
    historyTotal+=cost;
    ulong order=(ulong)HistoryDealGetInteger(ticket,DEAL_ORDER);
    string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
    if(pendingRisk>0&&((pendingOrder>0&&order==pendingOrder)||(nonce>0&&comment=="AGS2:"+IntegerToString((long)nonce))))matched=true;
  }
  double previous=GlobalVariableCheck(key)?GlobalVariableGet(key):0;
  if(!MathIsValidNumber(previous)||previous<0||!MathIsValidNumber(historyTotal)||!MathIsValidNumber(pendingRisk)||pendingRisk<0)return;
  dailyRiskMoney=MathMax(previous,historyTotal);
  if(GlobalVariableSet(key,dailyRiskMoney)==0)return;
  // Retain a reservation on unknown outcomes. Never silently assume a timeout failed.
  if(matched){GlobalVariableDel(pendingKey);GlobalVariableDel(nonceKey);GlobalVariableDel(orderKey);pendingRisk=0;}
  GlobalVariablesFlush();
  budgetReady=pendingRisk==0;
}
double DailyRiskUsedPct(){return dayEquity>0?(dailyRiskMoney+pendingRisk)/dayEquity*100.0:100.0;}
bool ReserveDailyRisk(double amount,string &comment){
  RefreshDailyRisk(true);
  if(!budgetReady||!FitsDailyRisk(dailyRiskMoney,amount,dayEquity,dailyBudgetPct))return false;
  string sequenceKey=riskLedgerKey+"_SEQ";
  double previousNonce=GlobalVariableCheck(sequenceKey)?GlobalVariableGet(sequenceKey):0;
  if(!MathIsValidNumber(previousNonce)||previousNonce<0)return false;
  long nonce=(long)MathMax(previousNonce+1,(double)((long)TimeLocal()*1000+(long)(GetTickCount64()%1000)));
  if(GlobalVariableSet(sequenceKey,(double)nonce)==0)return false;
  if(GlobalVariableSet(riskLedgerKey+"_N",(double)nonce)==0)return false;
  if(GlobalVariableSet(riskLedgerKey+"_P",amount)==0)return false;
  GlobalVariableDel(riskLedgerKey+"_O");GlobalVariablesFlush();
  pendingRisk=amount;budgetReady=false;comment="AGS2:"+IntegerToString(nonce);return true;
}
bool DefinitiveRejection(uint code){
  return code==TRADE_RETCODE_REJECT||code==TRADE_RETCODE_CANCEL||code==TRADE_RETCODE_REQUOTE||code==TRADE_RETCODE_INVALID||code==TRADE_RETCODE_INVALID_VOLUME||code==TRADE_RETCODE_INVALID_PRICE||code==TRADE_RETCODE_INVALID_STOPS||code==TRADE_RETCODE_TRADE_DISABLED||code==TRADE_RETCODE_MARKET_CLOSED||code==TRADE_RETCODE_NO_MONEY||code==TRADE_RETCODE_PRICE_CHANGED||code==TRADE_RETCODE_PRICE_OFF||code==TRADE_RETCODE_INVALID_FILL;
}
void ReleaseRejectedRisk(){
  GlobalVariableDel(riskLedgerKey+"_P");GlobalVariableDel(riskLedgerKey+"_N");GlobalVariableDel(riskLedgerKey+"_O");GlobalVariablesFlush();pendingRisk=0;RefreshDailyRisk(true);
}
bool BotPosition(int i){ulong ticket=PositionGetTicket(i);return ticket>0&&(ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber;}
bool HasExposure(string symbol){
  for(int i=0;i<PositionsTotal();i++){
    if(PositionGetTicket(i)==0)continue;
    if((ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber||PositionGetString(POSITION_SYMBOL)==symbol)return true;
    // Never stack a gold alias on an existing manual gold exposure.
    string s=PositionGetString(POSITION_SYMBOL);StringToUpper(s);
    if((pair=="XAUUSD"||pair=="GOLD")&&(StringFind(s,"XAU")>=0||StringFind(s,"GOLD")>=0))return true;
  }
  for(int i=0;i<OrdersTotal();i++){
    if(OrderGetTicket(i)==0)continue;
    if((ulong)OrderGetInteger(ORDER_MAGIC)==MagicNumber||OrderGetString(ORDER_SYMBOL)==symbol)return true;
  }
  return false;
}
double Indicator(string symbol,ENUM_TIMEFRAMES tf,int period,bool atr,int shift=1){
  int handle=atr?iATR(symbol,tf,period):iMA(symbol,tf,period,0,MODE_EMA,PRICE_CLOSE);
  if(handle==INVALID_HANDLE)return 0;
  double buffer[1];int count=CopyBuffer(handle,0,shift,1,buffer);IndicatorRelease(handle);
  return count==1?buffer[0]:0;
}
double RoundPrice(string symbol,double value,bool up){
  double step=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);if(step<=0)return 0;
  return NormalizeDouble((up?MathCeil(value/step):MathFloor(value/step))*step,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
}
ENUM_TIMEFRAMES EntryTF(string symbol){string v=symbol;StringToUpper(v);return StringFind(v,"XAU")>=0||StringFind(v,"GOLD")>=0?PERIOD_M1:PERIOD_M5;}

bool FixedVolumeAllowed(double lots,double minimum,double maximum,double step){
  if(!MathIsValidNumber(lots)||!MathIsValidNumber(minimum)||!MathIsValidNumber(maximum)||!MathIsValidNumber(step)||lots<=0||minimum<=0||maximum<minimum||step<=0)return false;
  if(lots<minimum-1e-9||lots>maximum+1e-9)return false;
  return MathAbs(lots-MathRound(lots/step)*step)<=1e-9;
}

int AffordableOrderCount(int requested,double lossPerOrder,double budget){
  if(requested<1||!MathIsValidNumber(lossPerOrder)||!MathIsValidNumber(budget)||lossPerOrder<=0||budget<=0)return 0;
  // Reduce the number of orders, NEVER increase risk or alter the fixed lot size.
  while(requested>0&&lossPerOrder*requested>budget)requested--;
  return requested;
}

int EntryOrderCount(bool gold,int requested,double lossPerOrder,double budget){
  if(requested<1||!MathIsValidNumber(lossPerOrder)||!MathIsValidNumber(budget)||lossPerOrder<=0||budget<=0)return 0;
  // Explicit gold-only exception; never opens a multi-order gold burst.
  if(gold)return 1;
  return AffordableOrderCount(requested,lossPerOrder,budget);
}

bool EntrySpreadAllowed(ENUM_TIMEFRAMES tf,double atr,double bid,double ask){
  if(!MathIsValidNumber(atr)||!MathIsValidNumber(bid)||!MathIsValidNumber(ask)||atr<=0||bid<=0||ask<=bid){spreadInfo="Invalid ATR / quote; spread check blocked";return false;}
  double spread=ask-bid;
  double limit=tf==PERIOD_M1?MathMin(atr*MaxGoldSpreadAtrFraction,MaxGoldSpreadPrice):atr*0.12;
  spreadInfo=StringFormat("Last check: spread %.4f | ATR %.4f | cap %.4f | %.1f%% ATR",spread,atr,limit,atr>0?spread/atr*100.0:0.0);
  // Tolerance only for binary floating-point subtraction, not extra spread room.
  return spread<=limit+1e-9;
}

// Protective management remains local and runs even when remote entries are stopped/offline.
void ManageStops(){
  if(!trailing)return;
  for(int i=PositionsTotal()-1;i>=0;i--){
    if(!BotPosition(i))continue;
    ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
    string symbol=PositionGetString(POSITION_SYMBOL);
    bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
    double open=PositionGetDouble(POSITION_PRICE_OPEN),old=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
    MqlTick tick;if(!SymbolInfoTick(symbol,tick)||old<=0||tp<=0)continue;
    double atr=Indicator(symbol,EntryTF(symbol),14,true);if(atr<=0)continue;
    double initialR=MathAbs(tp-open)/1.5,price=buy?tick.bid:tick.ask;
    if(initialR<=0||(buy?price-open:open-price)<initialR)continue;
    double point=SymbolInfoDouble(symbol,SYMBOL_POINT),spread=tick.ask-tick.bid;
    double floorDistance=(MathMax(SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))+2)*point;
    double target=buy?MathMax(open+spread,price-atr):MathMin(open-spread,price+atr);
    target=buy?MathMin(target,tick.bid-floorDistance):MathMax(target,tick.ask+floorDistance);
    target=RoundPrice(symbol,target,!buy);
    if(target<=0||(buy?target<=old+point:target>=old-point))continue;
    if(!trade.PositionModify(ticket,target,tp)||!(trade.ResultRetcode()==TRADE_RETCODE_DONE||trade.ResultRetcode()==TRADE_RETCODE_NO_CHANGES))Print("Trailing stop rejected: ",trade.ResultRetcodeDescription());
  }
}

void Evaluate(){
  if(!running||!Lease()){if(running&&!Lease()){running=false;state="Offline lease expired. Entries stopped.";}return;}
  if(!Permission()){state="Trading permission disabled or live trading not authorised";return;}
  if(DailyLoss()>=dailyLimit){running=false;state="Daily loss stop hit. No new entries.";return;}
  RefreshDailyRisk();
  if(!budgetReady){running=false;state="Daily risk ledger/pending execution unresolved; entries stopped";return;}
  if(DailyRiskUsedPct()>=dailyBudgetPct){running=false;state="Daily risk budget exhausted. No new entries.";return;}
  if(!SymbolSelect(activeSymbol,true)){state="Broker symbol missing. Set exact symbol mapping.";return;}
  if(HasExposure(activeSymbol)){state="Managing existing exposure; no additional basket";return;}
  MqlDateTime now;TimeToStruct(TimeCurrent(),now);
  if(now.hour<7||now.hour>=20){state="Outside 07:00–20:00 broker-time entry window";return;}
  ENUM_TIMEFRAMES tf=EntryTF(activeSymbol);
  MqlRates bars[];ArraySetAsSeries(bars,true);
  if(CopyRates(activeSymbol,tf,0,4,bars)!=4){state="Waiting for market history";return;}
  if(bars[1].time==lastBar)return;
  double atr=Indicator(activeSymbol,tf,14,true),ema=Indicator(activeSymbol,tf,9,false);
  double fast=Indicator(activeSymbol,PERIOD_M5,20,false),slow=Indicator(activeSymbol,PERIOD_M5,50,false);
  if(atr<=0||ema<=0||fast<=0||slow<=0){state="Waiting for EMA / ATR history";return;}
  MqlTick tick;if(!SymbolInfoTick(activeSymbol,tick)||tick.bid<=0||tick.ask<=tick.bid||TimeCurrent()-tick.time>10){state="No fresh quote";return;}
  lastBar=bars[1].time;
  if(!EntrySpreadAllowed(tf,atr,tick.bid,tick.ask)){state="Spread filter: entry skipped. "+spreadInfo;Print(state);return;}
  bool up=fast>slow,down=fast<slow;
  bool impulseBuy=up&&bars[1].close>bars[1].open&&(bars[1].close-bars[1].open)>1.5*atr&&bars[1].close>bars[2].high;
  bool impulseSell=down&&bars[1].close<bars[1].open&&(bars[1].open-bars[1].close)>1.5*atr&&bars[1].close<bars[2].low;
  bool pullBuy=up&&bars[1].low<=ema&&bars[1].close>ema&&bars[1].close>bars[1].open;
  bool pullSell=down&&bars[1].high>=ema&&bars[1].close<ema&&bars[1].close<bars[1].open;
  bool gold=tf==PERIOD_M1;
  bool buy=pullBuy||(gold&&impulse&&impulseBuy),sell=pullSell||(gold&&impulse&&impulseSell);
  if(!buy&&!sell){state="Scanning: trend + pullback / impulse filter";return;}
  // Impulse signals may still trigger, but ALL entries use at most one order.
  int count=1;
  double price=buy?tick.ask:tick.bid,point=SymbolInfoDouble(activeSymbol,SYMBOL_POINT);
  double stops=(SymbolInfoInteger(activeSymbol,SYMBOL_TRADE_STOPS_LEVEL)+2)*point;
  double distance=MathMax(1.2*atr,stops+(tick.ask-tick.bid));
  double sl=RoundPrice(activeSymbol,buy?price-distance:price+distance,!buy);
  double tp=RoundPrice(activeSymbol,buy?price+1.5*distance:price-1.5*distance,buy);
  if(sl<=0||tp<=0)return;
  ENUM_ORDER_TYPE type=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
  double lots=gold?GOLD_ORDER_LOTS:FX_ORDER_LOTS;
  double step=SymbolInfoDouble(activeSymbol,SYMBOL_VOLUME_STEP),minLot=SymbolInfoDouble(activeSymbol,SYMBOL_VOLUME_MIN),maxLot=SymbolInfoDouble(activeSymbol,SYMBOL_VOLUME_MAX);
  if(!FixedVolumeAllowed(lots,minLot,maxLot,step)){state=StringFormat("Fixed %.2f lot unsupported by broker min/max/step; skipped",lots);Print(state);return;}
  double loss=0,worstPrice=buy?price+MaxDeviationPoints*point:price-MaxDeviationPoints*point;
  if(!OrderCalcProfit(type,activeSymbol,lots,worstPrice,sl,loss)||!MathIsValidNumber(loss)||loss>=0){state="Cannot calculate fixed-lot stop risk";return;}
  double equity=AccountInfoDouble(ACCOUNT_EQUITY);
  if(!MathIsValidNumber(equity)||equity<=0){state="Invalid account equity; skipped";return;}
  // FX retains its 10% execution reserve. Gold's cap is diagnostic ONLY.
  // Slippage, commissions and gaps can exceed the calculated stop loss.
  double budget=equity*riskPct/100*0.9;
  count=EntryOrderCount(gold,count,MathAbs(loss),budget);
  if(count==0){state=StringFormat("Fixed %.2f lot exceeds risk budget; skipped",lots);Print(state);return;}
  if(!FitsDailyRisk(dailyRiskMoney,MathAbs(loss),dayEquity,dailyBudgetPct)){state="Next fixed-lot entry would exceed daily risk budget; skipped";Print(state);return;}
  double plannedRiskPct=MathAbs(loss)/equity*100.0;
  riskInfo=StringFormat("Last signal: stop-risk estimate %.2f %s (%.2f%% equity) | %s",MathAbs(loss),AccountInfoString(ACCOUNT_CURRENCY),plannedRiskPct,gold?"GOLD percentage cap BYPASSED; max 1 order":"FX percentage cap enforced");
  double margin=0;if(!OrderCalcMargin(type,activeSymbol,lots,price,margin)||!MathIsValidNumber(margin)||margin<0||margin*count>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.8){state="Insufficient free margin";return;}
  trade.SetTypeFillingBySymbol(activeSymbol);
  int filled=0;
  for(int n=0;n<count;n++){
    if(!Lease()||!Permission()||DailyLoss()>=dailyLimit)break;
    MqlTick fresh;if(!SymbolInfoTick(activeSymbol,fresh))break;
    // Recheck the same spread cap before each order in an impulse burst.
    if(!EntrySpreadAllowed(tf,atr,fresh.bid,fresh.ask)){state="Spread widened: burst stopped. "+spreadInfo;Print(state);break;}
    double current=buy?fresh.ask:fresh.bid;
    // Abort a burst if price has moved beyond the reserved slippage allowance.
    if(MathAbs(current-price)>MaxDeviationPoints*point)break;
    if(gold)Print("Gold fixed-lot exception: ",riskInfo,". DAILY budget and daily-loss stop still enforced.");
    string orderComment;
    if(!ReserveDailyRisk(MathAbs(loss),orderComment)){state="Daily risk reservation failed / budget insufficient; entry blocked";Print(state);break;}
    bool sent=buy?trade.Buy(lots,activeSymbol,0,sl,tp,orderComment):trade.Sell(lots,activeSymbol,0,sl,tp,orderComment);
    uint code=trade.ResultRetcode();
    ulong orderTicket=trade.ResultOrder();if(orderTicket>0){GlobalVariableSet(riskLedgerKey+"_O",(double)orderTicket);GlobalVariablesFlush();}
    if(!sent||!(code==TRADE_RETCODE_DONE||code==TRADE_RETCODE_DONE_PARTIAL)){
      if(DefinitiveRejection(code))ReleaseRejectedRisk();
      else{running=false;state="Execution outcome uncertain; risk reserved, entries stopped";Print(state);}
      state="Order result: "+trade.ResultRetcodeDescription()+"; pending outcomes remain reserved";Print(state);break;
    }
    RefreshDailyRisk(true);
    filled++;
  }
  if(filled>0)state=StringFormat("Opened %d order(s) x %.2f lot; estimated stop risk %.2f%%; %s",filled,lots,plannedRiskPct,gold?"gold percentage cap bypassed":"FX risk cap enforced");
}

string Telemetry(){
  DailyBaseline();RefreshDailyRisk(true);MqlTick tick;ZeroMemory(tick);SymbolInfoTick(activeSymbol,tick);
  string positions="",deals="";int count=0;
  for(int i=0;i<PositionsTotal()&&count<100;i++){
    if(!BotPosition(i))continue;if(count++>0)positions+=",";
    positions+="{\"ticket\":\""+IntegerToString(PositionGetInteger(POSITION_TICKET))+"\",\"symbol\":\""+Escape(PositionGetString(POSITION_SYMBOL))+"\",\"side\":\""+(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL")+"\",\"volume\":"+Num(PositionGetDouble(POSITION_VOLUME),8)+",\"profit\":"+Num(PositionGetDouble(POSITION_PROFIT))+",\"sl\":"+Num(PositionGetDouble(POSITION_SL),8)+"}";
  }
  count=0;if(HistorySelect(TimeCurrent()-7*86400,TimeCurrent())){
    for(int i=HistoryDealsTotal()-1;i>=0&&count<20;i--){
      ulong ticket=HistoryDealGetTicket(i);if(ticket==0||(ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=MagicNumber)continue;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);if(entry!=DEAL_ENTRY_OUT&&entry!=DEAL_ENTRY_OUT_BY)continue;
      if(count++>0)deals+=",";
      double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
      deals+="{\"ticket\":\""+IntegerToString((long)ticket)+"\",\"symbol\":\""+Escape(HistoryDealGetString(ticket,DEAL_SYMBOL))+"\",\"profit\":"+Num(profit)+",\"time\":"+IntegerToString(HistoryDealGetInteger(ticket,DEAL_TIME))+"}";
    }
  }
  string budgetFields="\"protocolVersion\":2,\"budgetReady\":"+(budgetReady?"true":"false")+",\"dailyRiskUsedPct\":"+Num(DailyRiskUsedPct(),8)+",\"dailyRiskUsed\":"+Num(dailyRiskMoney+pendingRisk,8)+",\"dayEquity\":"+Num(dayEquity,8)+",";
  return "{"+budgetFields+"\"bootId\":\""+bootId+"\",\"login\":\""+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"\",\"server\":\""+Escape(AccountInfoString(ACCOUNT_SERVER))+"\",\"currency\":\""+Escape(AccountInfoString(ACCOUNT_CURRENCY))+"\",\"balance\":"+Num(AccountInfoDouble(ACCOUNT_BALANCE))+",\"equity\":"+Num(AccountInfoDouble(ACCOUNT_EQUITY))+",\"dailyPnl\":"+Num(AccountInfoDouble(ACCOUNT_EQUITY)-dayEquity)+",\"dailyLossPct\":"+Num(DailyLoss(),4)+",\"allowed\":"+(Permission()?"true":"false")+",\"live\":"+(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL?"true":"false")+",\"acknowledged\":"+(running&&Lease()&&Permission()&&budgetReady&&DailyRiskUsedPct()<dailyBudgetPct?"true":"false")+",\"symbol\":\""+Escape(activeSymbol)+"\",\"bid\":"+Num(tick.bid,8)+",\"ask\":"+Num(tick.ask,8)+",\"status\":\""+Escape(state)+"\",\"positions\":["+positions+"],\"deals\":["+deals+"]}";
}
void Sync(){
  if(IsTester())return;
  char data[],result[];string headers;
  int len=StringToCharArray(Telemetry(),data,0,WHOLE_ARRAY,CP_UTF8);ArrayResize(data,len-1);
  int code=WebRequest("POST",BridgeURL,"Content-Type: application/json\r\nAuthorization: Bearer "+PairingKey+"\r\n",4000,data,result,headers);
  if(code>=400&&code<500){running=false;lastContact=0;state="Bridge rejected request. Recheck pairing and setup.";return;}
  if(code!=200){if(!Lease()){running=false;state="Bridge offline / unauthorised. Check WebRequest URL and pairing key.";}return;}
  string response=CharArrayToString(result,0,-1,CP_UTF8),parts[];
  if(StringSplit(response,'|',parts)!=9||parts[0]!="AGS2"){running=false;lastContact=0;state="Update backend: this EA requires AGS2 daily-budget commands";return;}
  double r=StringToDouble(parts[3]),d=StringToDouble(parts[4]),b=StringToDouble(parts[8]);
  if(!ValidPercent(r)||!ValidPercent(d)||!ValidPercent(b)){running=false;state="Risk percentages must be 0.1 to 10";return;}
  if(parts[2]!="XAUUSD"&&parts[2]!="GOLD"&&parts[2]!="GBPUSD"&&parts[2]!="AUDUSD"){running=false;return;}
  if(activeSymbol!=parts[7]){lastBar=0;spreadInfo="Spread check pending (symbol changed)";riskInfo="Gold: 0.01 lot, entry cap bypassed ONLY. Daily budget enforced.";}
  pair=parts[2];activeSymbol=parts[7];riskPct=r;dailyLimit=d;dailyBudgetPct=b;impulse=parts[5]=="1";trailing=parts[6]=="1";lastContact=TimeLocal();
  RefreshDailyRisk(true);
  running=parts[1]=="1"&&Permission()&&DailyLoss()<dailyLimit&&budgetReady&&DailyRiskUsedPct()<dailyBudgetPct;
  if(!running)state=DailyLoss()>=dailyLimit?"Daily loss stop hit":!budgetReady?"Daily risk ledger not ready; entries stopped":DailyRiskUsedPct()>=dailyBudgetPct?"Daily risk budget exhausted":"Stopped. Protective management remains local.";
}
int OnInit(){
  bootId=IntegerToString((long)TimeLocal())+"-"+IntegerToString((long)GetMicrosecondCount());
  if(!MathIsValidNumber(MaxGoldSpreadAtrFraction)||MaxGoldSpreadAtrFraction<=0||MaxGoldSpreadAtrFraction>0.20||!MathIsValidNumber(MaxGoldSpreadPrice)||MaxGoldSpreadPrice<=0||MaxGoldSpreadPrice>0.40){Print("Gold spread limits must be positive, at most 0.20 ATR and 0.40 price units.");return INIT_PARAMETERS_INCORRECT;}
  if(MaxDeviationPoints<0){Print("Deviation must be nonnegative.");return INIT_PARAMETERS_INCORRECT;}
  if(IsTester()&&(!ValidPercent(TesterEntryRiskPct)||!ValidPercent(TesterDailyBudgetPct)||!ValidPercent(TesterDailyLossPct))){Print("Tester percentages must be 0.1 to 10.");return INIT_PARAMETERS_INCORRECT;}
  if(!IsTester()&&(StringLen(PairingKey)!=64||StringFind(BridgeURL,"https://")!=0)){Print("Configure HTTPS BridgeURL and 64-character PairingKey first.");return INIT_PARAMETERS_INCORRECT;}
  Print("BUDGET 1.04: gold ONE 0.01 lot bypasses entry cap ONLY. All entries obey daily budget/loss stop. FX 0.05 lot obeys entry cap. Requires AGS2 backend.");
  lockKey=StringFormat("AGS_LOCK_%I64d_%I64u",AccountInfoInteger(ACCOUNT_LOGIN),MagicNumber);
  if(!IsTester()){
    if(!GlobalVariableCheck(lockKey))GlobalVariableSet(lockKey,0);
    double previous=GlobalVariableGet(lockKey);
    if(TimeLocal()-previous<30||!GlobalVariableSetOnCondition(lockKey,(double)TimeLocal(),previous)){Print("Only ONE EA instance per account/magic is allowed.");return INIT_FAILED;}
    ownsLock=true;
  }
  trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(MathMax(0,MaxDeviationPoints));trade.SetAsyncMode(false);
  DailyBaseline();
  if(IsTester()){activeSymbol=TesterSymbol;pair=TesterSymbol;riskPct=TesterEntryRiskPct;dailyBudgetPct=TesterDailyBudgetPct;dailyLimit=TesterDailyLossPct;running=true;}
  RefreshDailyRisk(true);
  EventSetTimer(1);return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){EventKillTimer();if(ownsLock)GlobalVariableDel(lockKey);Comment("");}
void OnTimer(){
  if(ownsLock)GlobalVariableSet(lockKey,(double)TimeLocal());
  if(!Lease()&&!IsTester())running=false;
  ManageStops();
  if(TimeLocal()-lastSend>=5){lastSend=TimeLocal();Sync();}
  Evaluate();Comment("AGGRESSIVE GOLD SCALPER - BUDGET 1.04\n",state,"\nSymbol: ",activeSymbol," | Daily loss: ",Num(DailyLoss())," / ",Num(dailyLimit),"%\nDaily risk used: ",Num(DailyRiskUsedPct())," / ",Num(dailyBudgetPct),"% | Ledger: ",budgetReady?"READY":"BLOCKED","\nEntries: ",running?"ON":"OFF"," | FX entry cap: ",Num(riskPct),"%\nFixed lot/order: gold 0.01 | FX 0.05\n",spreadInfo,"\n",riskInfo);
}
void OnTick(){ManageStops();if(IsTester())Evaluate();}