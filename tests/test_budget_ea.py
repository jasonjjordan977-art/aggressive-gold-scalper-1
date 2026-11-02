"""Extract and execute exact MQL helper bodies with fake MT5 APIs in C++.
Not a full MQL5 compile, Strategy Tester, or broker execution test.
"""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / 'mt5/AGGRESSIVE_GOLD_SCALPER_BUDGET.mq5').read_text()
base = (root / 'tests/fixtures/gold-single-v1.03.mq5').read_text()

def function(text, name):
    start = text.index(name + '(')
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

for name in ['Permission', 'Lease', 'DailyBaseline', 'DailyLoss', 'HasExposure', 'ManageStops', 'EntrySpreadAllowed', 'FixedVolumeAllowed', 'EntryOrderCount']:
    assert function(source, name) == function(base, name), name
assert 'double budget=equity*riskPct/100*0.9;' in source
assert '?3:1' not in function(source, 'Evaluate')
assert 'int count=1;' in function(source, 'Evaluate')
assert 'parts[0]!="AGS2"' in source
assert 'ReserveDailyRisk(MathAbs(loss),orderComment)' in source
assert 'TRADE_RETCODE_TIMEOUT' not in function(source, 'DefinitiveRejection')
assert len('AGS_R2_'+'4294967295'+'_'+'4294967295'+'_D'+'18446744073709551615') <= 63

cpp = r'''
#include <cmath>
#include <cassert>
#include <string>
#include <vector>
#include <unordered_map>
#include <limits>
#include <iostream>
#include <algorithm>
using string=std::string;
using datetime=long;
enum ENUM_ORDER_TYPE{ORDER_TYPE_BUY,ORDER_TYPE_SELL};
enum {DEAL_MAGIC,DEAL_ENTRY,DEAL_TYPE,DEAL_ENTRY_IN,DEAL_ENTRY_INOUT,DEAL_TYPE_BUY,DEAL_TYPE_SELL,DEAL_VOLUME,DEAL_PRICE,DEAL_SL,DEAL_SYMBOL,DEAL_ORDER,DEAL_COMMENT,ACCOUNT_SERVER};
struct MqlDateTime{int hour,min,sec;};
struct Deal{ulong ticket,order;double volume,open,sl;long magic,entry,type,time;string comment;};
std::unordered_map<string,double> globals;
std::vector<Deal> deals,selected;
double dayEquity=1000,dailyBudgetPct=2,dailyRiskMoney=0,pendingRisk=0;
bool budgetReady=false,historyReady=true;
datetime lastRiskRefresh=0,now=100000;
ulong MagicNumber=2601102;
string dayKey="DAY1",riskLedgerKey="",state="";
bool MathIsValidNumber(double v){return std::isfinite(v);}
double MathAbs(double v){return std::abs(v);}
double MathMax(double a,double b){return std::max(a,b);}
string IntegerToString(long x){return std::to_string(x);}
int StringLen(string x){return x.size();}
int StringGetCharacter(string x,int i){return (unsigned char)x[i];}
string AccountInfoString(int){return "TEST_SERVER";}
void DailyBaseline(){}
long TimeLocal(){return now;}
long TimeCurrent(){return now;}
long GetTickCount64(){return 12345;}
void TimeToStruct(long,MqlDateTime &d){d={0,0,0};}
long StructToTime(MqlDateTime){return now-(now%86400);}
bool HistorySelect(long start,long end){selected.clear();for(auto d:deals)if(d.time>=start&&d.time<=end)selected.push_back(d);return historyReady;}
int HistoryDealsTotal(){return selected.size();}
ulong HistoryDealGetTicket(int i){return selected.at(i).ticket;}
Deal &get(ulong t){for(auto &d:selected)if(d.ticket==t)return d;throw std::runtime_error("missing deal");}
long HistoryDealGetInteger(ulong t,int p){auto &d=get(t);if(p==DEAL_MAGIC)return d.magic;if(p==DEAL_ENTRY)return d.entry;if(p==DEAL_TYPE)return d.type;if(p==DEAL_ORDER)return d.order;return 0;}
double HistoryDealGetDouble(ulong t,int p){auto &d=get(t);if(p==DEAL_VOLUME)return d.volume;if(p==DEAL_PRICE)return d.open;if(p==DEAL_SL)return d.sl;return 0;}
string HistoryDealGetString(ulong t,int p){return p==DEAL_COMMENT?get(t).comment:"XAUUSD";}
bool OrderCalcProfit(ENUM_ORDER_TYPE side,string,double vol,double open,double sl,double &loss){loss=(side==ORDER_TYPE_BUY?sl-open:open-sl)*100*vol;return true;}
bool GlobalVariableCheck(string k){return globals.count(k);}
double GlobalVariableGet(string k){return globals[k];}
long GlobalVariableSet(string k,double v){globals[k]=v;return now;}
void GlobalVariableDel(string k){globals.erase(k);}
void GlobalVariablesFlush(){}
'''
for result, name in [('bool','ValidPercent'),('bool','FitsDailyRisk'),('string','ScopedRiskKey'),('void','RefreshDailyRisk'),('double','DailyRiskUsedPct'),('bool','ReserveDailyRisk'),('void','ReleaseRejectedRisk')]:
    cpp += result + ' ' + function(source, name) + '\n'
cpp += r'''
void restart(){riskLedgerKey="";dailyRiskMoney=0;pendingRisk=0;budgetReady=false;lastRiskRefresh=0;}
int main(){
assert(ValidPercent(0.1)&&ValidPercent(10)&&!ValidPercent(10.01));
assert(FitsDailyRisk(15,5,1000,2));
assert(!FitsDailyRisk(15,5.01,1000,2));
assert(!FitsDailyRisk(0,30,1000,2));
assert(!FitsDailyRisk(0,1,0,2));
RefreshDailyRisk(true);assert(budgetReady&&dailyRiskMoney==0);
string comment;assert(ReserveDailyRisk(5,comment));assert(!budgetReady&&pendingRisk==5);
restart();RefreshDailyRisk(true);assert(!budgetReady&&pendingRisk==5);
assert(!ReserveDailyRisk(5,comment));
deals.push_back({1,101,0.01,2000,1995,(long)MagicNumber,DEAL_ENTRY_IN,DEAL_TYPE_BUY,now,comment});
RefreshDailyRisk(true);assert(budgetReady&&pendingRisk==0&&dailyRiskMoney==5);
restart();RefreshDailyRisk(true);assert(budgetReady&&dailyRiskMoney==5);
// Closing a trade/winning does not replenish initial risk.
deals.push_back({2,102,0.01,2005,2000,(long)MagicNumber,999,DEAL_TYPE_SELL,now,"exit"});
RefreshDailyRisk(true);assert(dailyRiskMoney==5);
// Cached initial risk doesn't change when subsequent history properties drift.
deals[0].sl=1998;RefreshDailyRisk(true);assert(dailyRiskMoney==5);
assert(ReserveDailyRisk(5,comment));
deals.push_back({3,103,0.005,2000,1995,(long)MagicNumber,DEAL_ENTRY_IN,DEAL_TYPE_BUY,now,comment});
RefreshDailyRisk(true);assert(budgetReady&&dailyRiskMoney==7.5);
// Delayed second partial fill is added, not ignored or counted twice.
deals.push_back({4,103,0.005,2000,1995,(long)MagicNumber,DEAL_ENTRY_IN,DEAL_TYPE_BUY,now,comment});
RefreshDailyRisk(true);RefreshDailyRisk(true);assert(dailyRiskMoney==10);
assert(!ReserveDailyRisk(11,comment));
// A changed broker comment can reconcile through the order id.
assert(ReserveDailyRisk(5,comment));GlobalVariableSet(riskLedgerKey+"_O",104);
deals.push_back({5,104,0.01,2000,1995,(long)MagicNumber,DEAL_ENTRY_IN,DEAL_TYPE_BUY,now,"broker-rewritten"});
RefreshDailyRisk(true);assert(budgetReady&&dailyRiskMoney==15);
assert(ReserveDailyRisk(5,comment));ReleaseRejectedRisk();assert(budgetReady&&pendingRisk==0&&dailyRiskMoney==15);
assert(ReserveDailyRisk(5,comment));restart();RefreshDailyRisk(true);assert(!budgetReady&&pendingRisk==5);
ReleaseRejectedRisk();
historyReady=false;RefreshDailyRisk(true);assert(!budgetReady);historyReady=true;
deals.push_back({6,105,0.01,2000,0,(long)MagicNumber,DEAL_ENTRY_IN,DEAL_TYPE_BUY,now,"missing-SL"});
RefreshDailyRisk(true);assert(!budgetReady);deals.pop_back();
// Temporarily incomplete history never lowers persisted high-water usage.
auto saved=deals;deals.clear();RefreshDailyRisk(true);assert(budgetReady&&dailyRiskMoney==15);deals=saved;
// Other magic numbers are not allocated to this bot's daily budget.
deals.push_back({7,106,0.01,2000,1900,42,DEAL_ENTRY_IN,DEAL_TYPE_BUY,now,"manual"});
RefreshDailyRisk(true);assert(dailyRiskMoney==15);
// Broker-day rollover creates a fresh ledger; previous-day entries excluded.
now+=86400;dayKey="DAY2";RefreshDailyRisk(true);assert(budgetReady&&dailyRiskMoney==0);
assert(FitsDailyRisk(0,30,1000,10));
std::cout << "Isolated daily-budget helper assertions passed\n";
}
'''
out=Path('/tmp/gold-budget-ledger-test.cpp');out.write_text(cpp)
subprocess.run(['g++','-std=c++17','-Wall','-Wextra',str(out),'-o','/tmp/gold-budget-ledger-test'],check=True)
subprocess.run(['/tmp/gold-budget-ledger-test'],check=True)
print(f'{cpp.count("assert(")} isolated C++ assertions; 9 original safeguard/helper functions unchanged.')
print('Full MetaEditor compilation, MT5 runtime and broker execution NOT verified.')