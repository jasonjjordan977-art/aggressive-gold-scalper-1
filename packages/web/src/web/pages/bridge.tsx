import { useState } from 'react';
import { Zap, Download, ShieldCheck, Smartphone, ArrowUpRight, Copy, Link2 } from 'lucide-react';
import { usePing } from '../queries/ping';

export default function BridgeSetup() {
  const ping = usePing();
  const [copied, setCopied] = useState(false);
  const endpoint = `${window.location.origin}/api/webhooks/mt5`;
  return <main className="bridge-page">
    <header className="bridge-nav"><a className="bridge-brand" href="/"><span className="bridge-mark"><Zap size={22}/></span><span><small>AGGRESSIVE</small><strong>GOLD SCALPER</strong></span></a><span className="backend-status"><i/>{ping.isLoading?'Checking backend…':ping.isError?'Backend unavailable':'Backend responding'}</span></header>
    <section className="bridge-hero"><div><p className="eyebrow">THE FREE MT5 CONNECTION</p><h1>Your terminal.<br/><em>Your engine.</em></h1><p className="bridge-lead">Your mobile app handles the controls. Your MetaTrader 5 terminal handles the trades. No MetaApi. No paid trading API.</p><a className="bridge-primary" href="/downloads/AGGRESSIVE_GOLD_SCALPER.mq5" download><Download size={18}/>Download MT5 Expert Advisor</a><a className="bridge-guide" href="/downloads/SETUP.md" target="_blank" rel="noreferrer">Read the full installation guide <ArrowUpRight size={15}/></a><div className="bridge-warning"><ShieldCheck size={20}/><p>Experimental strategy. Compile and forward-test on an MT5 demo account before considering real money.</p></div></div>
    <aside className="bridge-install"><p className="eyebrow">PAIR ONCE. CONTROL FROM YOUR PHONE.</p>{[
      {icon:Smartphone,title:'Create your private bridge',text:'Open the mobile app → Bridge → Create free bridge. Keep the controller recovery key private.'},
      {icon:Download,title:'Install the EA in MT5',text:'Copy the source into MQL5/Experts and compile with MetaEditor. Attach one instance to one chart.'},
      {icon:Link2,title:'Pair, then press Start',text:'Allow HTTPS WebRequest, enter your terminal pairing key, enable Algo Trading, and wait for ONLINE in the app.'},
    ].map((step,i)=><div className="bridge-step" key={step.title}><span className="bridge-step-no">0{i+1}</span><div><step.icon size={19}/><h2>{step.title}</h2><p>{step.text}</p></div></div>)}<div className="bridge-endpoint"><p className="eyebrow">BACKEND HEARTBEAT URL</p><code>{endpoint}</code><button onClick={async()=>{await navigator.clipboard.writeText(endpoint);setCopied(true);}}><Copy size={14}/>{copied?'Copied':'Copy URL'}</button></div></aside></section>
    <footer className="bridge-bottom"><span>MT5 DESKTOP MUST REMAIN OPEN</span><span>0.5% basket risk · 2% daily entry stop · Up to 3 impulse orders</span><p>No trading API fee does not mean zero running costs. Hosting or an optional VPS may cost money. Losses can exceed planned risk. The EA has not been compiled or traded in this environment.</p></footer>
  </main>;
}