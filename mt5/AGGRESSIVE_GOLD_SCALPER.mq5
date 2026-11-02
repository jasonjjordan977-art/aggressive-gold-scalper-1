// AGGRESSIVE GOLD SCALPER — experimental, no profitability guarantee.
// Compile in MetaEditor 5. Attach ONE instance per account. Test on demo first.
#property strict
#property version "1.00"
#include <Trade/Trade.mqh>
input string BridgeURL="https://YOUR-PUBLISHED-BACKEND/api/webhooks/mt5";
input string PairingKey="";
input bool AllowLiveTrading=false;
input ulong MagicNumber=2601102;
input int MaxDeviationPoints=20;
// Offline backtesting deliberately bypasses remote controls ONLY in Strategy Tester.
input bool TesterMode=false;
input string TesterSymbol="XAUUSD";

CTrade trade;
bool running=false,impulse=true,trailing=true;
double riskPct=0.5,dailyLimit=2.0,dayEquity=0;
string activeSymbol="XAUUSD",pair="XAUUSD",state="Waiting for mobile Start",dayKey="",lockKey="",bootId="";
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
  if(tick.ask-tick.bid>atr*0.12){state="Spread filter: entry skipped";return;}
  bool up=fast>slow,down=fast<slow;
  bool impulseBuy=up&&bars[1].close>bars[1].open&&(bars[1].close-bars[1].open)>1.5*atr&&bars[1].close>bars[2].high;
  bool impulseSell=down&&bars[1].close<bars[1].open&&(bars[1].open-bars[1].close)>1.5*atr&&bars[1].close<bars[2].low;
  bool pullBuy=up&&bars[1].low<=ema&&bars[1].close>ema&&bars[1].close>bars[1].open;
  bool pullSell=down&&bars[1].high>=ema&&bars[1].close<ema&&bars[1].close<bars[1].open;
  bool gold=tf==PERIOD_M1;
  bool buy=pullBuy||(gold&&impulse&&impulseBuy),sell=pullSell||(gold&&impulse&&impulseSell);
  if(!buy&&!sell){state="Scanning: trend + pullback / impulse filter";return;}
  int count=gold&&impulse&&(impulseBuy||impulseSell)?3:1;
  double price=buy?tick.ask:tick.bid,point=SymbolInfoDouble(activeSymbol,SYMBOL_POINT);
  double stops=(SymbolInfoInteger(activeSymbol,SYMBOL_TRADE_STOPS_LEVEL)+2)*point;
  double distance=MathMax(1.2*atr,stops+(tick.ask-tick.bid));
  double sl=RoundPrice(activeSymbol,buy?price-distance:price+distance,!buy);
  double tp=RoundPrice(activeSymbol,buy?price+1.5*distance:price-1.5*distance,buy);
  if(sl<=0||tp<=0)return;
  ENUM_ORDER_TYPE type=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
  double loss=0,worstPrice=buy?price+MaxDeviationPoints*point:price-MaxDeviationPoints*point;
  if(!OrderCalcProfit(type,activeSymbol,1.0,worstPrice,sl,loss)||MathAbs(loss)<=0){state="Cannot calculate symbol risk";return;}
  double step=SymbolInfoDouble(activeSymbol,SYMBOL_VOLUME_STEP),minLot=SymbolInfoDouble(activeSymbol,SYMBOL_VOLUME_MIN),maxLot=SymbolInfoDouble(activeSymbol,SYMBOL_VOLUME_MAX);
  if(step<=0||minLot<=0||maxLot<=0)return;
  // 10% execution reserve; slippage, commissions and gaps can still exceed planned risk.
  double budget=AccountInfoDouble(ACCOUNT_EQUITY)*MathMin(riskPct,0.5)/100*0.9;
  double total=MathFloor(budget/MathAbs(loss)/step)*step;
  if(total<count*minLot)count=1;
  double lots=NormalizeDouble(MathFloor(MathMin(total/count,maxLot)/step)*step,8);
  if(lots<minLot){state="Minimum broker lot exceeds risk budget; skipped";return;}
  double margin=0;if(!OrderCalcMargin(type,activeSymbol,lots*count,price,margin)||margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.8){state="Insufficient free margin";return;}
  trade.SetTypeFillingBySymbol(activeSymbol);
  int filled=0;
  for(int n=0;n<count;n++){
    if(!Lease()||!Permission()||DailyLoss()>=dailyLimit)break;
    MqlTick fresh;if(!SymbolInfoTick(activeSymbol,fresh))break;
    double current=buy?fresh.ask:fresh.bid;
    // Abort a burst if price has moved beyond the reserved slippage allowance.
    if(MathAbs(current-price)>MaxDeviationPoints*point)break;
    bool sent=buy?trade.Buy(lots,activeSymbol,0,sl,tp,"AGS risk basket"):trade.Sell(lots,activeSymbol,0,sl,tp,"AGS risk basket");
    uint code=trade.ResultRetcode();
    if(!sent||!(code==TRADE_RETCODE_DONE||code==TRADE_RETCODE_DONE_PARTIAL)){state="Order rejected: "+trade.ResultRetcodeDescription();Print(state);break;}
    filled++;
  }
  if(filled>0)state=StringFormat("Opened %d order(s); basket risk shared",filled);
}

string Telemetry(){
  DailyBaseline();MqlTick tick;ZeroMemory(tick);SymbolInfoTick(activeSymbol,tick);
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
  return "{\"bootId\":\""+bootId+"\",\"login\":\""+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"\",\"server\":\""+Escape(AccountInfoString(ACCOUNT_SERVER))+"\",\"currency\":\""+Escape(AccountInfoString(ACCOUNT_CURRENCY))+"\",\"balance\":"+Num(AccountInfoDouble(ACCOUNT_BALANCE))+",\"equity\":"+Num(AccountInfoDouble(ACCOUNT_EQUITY))+",\"dailyPnl\":"+Num(AccountInfoDouble(ACCOUNT_EQUITY)-dayEquity)+",\"dailyLossPct\":"+Num(DailyLoss(),4)+",\"allowed\":"+(Permission()?"true":"false")+",\"live\":"+(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL?"true":"false")+",\"acknowledged\":"+(running&&Lease()&&Permission()?"true":"false")+",\"symbol\":\""+Escape(activeSymbol)+"\",\"bid\":"+Num(tick.bid,8)+",\"ask\":"+Num(tick.ask,8)+",\"status\":\""+Escape(state)+"\",\"positions\":["+positions+"],\"deals\":["+deals+"]}";
}
void Sync(){
  if(IsTester())return;
  char data[],result[];string headers;
  int len=StringToCharArray(Telemetry(),data,0,WHOLE_ARRAY,CP_UTF8);ArrayResize(data,len-1);
  int code=WebRequest("POST",BridgeURL,"Content-Type: application/json\r\nAuthorization: Bearer "+PairingKey+"\r\n",4000,data,result,headers);
  if(code>=400&&code<500){running=false;lastContact=0;state="Bridge rejected request. Recheck pairing and setup.";return;}
  if(code!=200){if(!Lease()){running=false;state="Bridge offline / unauthorised. Check WebRequest URL and pairing key.";}return;}
  string response=CharArrayToString(result,0,-1,CP_UTF8),parts[];
  if(StringSplit(response,'|',parts)!=8||parts[0]!="AGS1"){running=false;state="Invalid bridge command";return;}
  double r=StringToDouble(parts[3]),d=StringToDouble(parts[4]);
  if(r<0.1||r>0.5||d<0.5||d>2){running=false;state="Invalid risk configuration";return;}
  if(parts[2]!="XAUUSD"&&parts[2]!="GOLD"&&parts[2]!="GBPUSD"&&parts[2]!="AUDUSD"){running=false;return;}
  if(activeSymbol!=parts[7])lastBar=0;
  pair=parts[2];activeSymbol=parts[7];riskPct=r;dailyLimit=d;impulse=parts[5]=="1";trailing=parts[6]=="1";lastContact=TimeLocal();
  running=parts[1]=="1"&&Permission()&&DailyLoss()<dailyLimit;
  if(!running)state=DailyLoss()>=dailyLimit?"Daily loss stop hit":"Stopped. Protective management remains local.";
}
int OnInit(){
  bootId=IntegerToString((long)TimeLocal())+"-"+IntegerToString((long)GetMicrosecondCount());
  if(MaxDeviationPoints<0){Print("Deviation must be nonnegative.");return INIT_PARAMETERS_INCORRECT;}
  if(!IsTester()&&(StringLen(PairingKey)!=64||StringFind(BridgeURL,"https://")!=0)){Print("Configure HTTPS BridgeURL and 64-character PairingKey first.");return INIT_PARAMETERS_INCORRECT;}
  lockKey=StringFormat("AGS_LOCK_%I64d_%I64u",AccountInfoInteger(ACCOUNT_LOGIN),MagicNumber);
  if(!IsTester()){
    if(!GlobalVariableCheck(lockKey))GlobalVariableSet(lockKey,0);
    double previous=GlobalVariableGet(lockKey);
    if(TimeLocal()-previous<30||!GlobalVariableSetOnCondition(lockKey,(double)TimeLocal(),previous)){Print("Only ONE EA instance per account/magic is allowed.");return INIT_FAILED;}
    ownsLock=true;
  }
  trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(MathMax(0,MaxDeviationPoints));trade.SetAsyncMode(false);
  DailyBaseline();
  if(IsTester()){activeSymbol=TesterSymbol;pair=TesterSymbol;running=true;}
  EventSetTimer(1);return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){EventKillTimer();if(ownsLock)GlobalVariableDel(lockKey);Comment("");}
void OnTimer(){
  if(ownsLock)GlobalVariableSet(lockKey,(double)TimeLocal());
  if(!Lease()&&!IsTester())running=false;
  ManageStops();
  if(TimeLocal()-lastSend>=5){lastSend=TimeLocal();Sync();}
  Evaluate();Comment("AGGRESSIVE GOLD SCALPER\n",state,"\nSymbol: ",activeSymbol," | Daily loss: ",Num(DailyLoss()),"%\nEntries: ",running?"ON":"OFF");
}
void OnTick(){ManageStops();if(IsTester())Evaluate();}