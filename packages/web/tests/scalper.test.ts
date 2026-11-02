import { expect, test } from 'bun:test';
import { createORPCClient } from '@orpc/client';
import { RPCLink } from '@orpc/client/fetch';
import type { AppRouterClient } from '../src/api';
import { db } from '../src/api/database';
import { terminals, tradeEvents } from '../src/api/database/schema';
import { eq } from 'drizzle-orm';
const client: AppRouterClient = createORPCClient(new RPCLink({url:'http://localhost:4200/api/rpc'}));
test('pairing, control isolation, permission gates, stop, daily guard, restart and lease expiry', async()=>{
 const {token}=await client.scalper.create();
 let id='';
 try {
  let d=await client.scalper.status({token});
  id=d.events[0]!.terminalId;
  expect(d.connected).toBe(false);expect(d.config.running).toBe(false);
  await expect(client.scalper.configure({token,config:{...d.config,running:true}})).rejects.toThrow();
  await expect(client.scalper.status({token:d.bridgeToken})).rejects.toThrow();
  const config=d.config; const bridgeToken=d.bridgeToken;
  const tel={bootId:'test-boot',login:'TEST-ONLY',server:'SYNTHETIC / NOT MT5',currency:'USD',balance:10000,equity:10000,dailyPnl:0,dailyLossPct:0,allowed:true,live:false,acknowledged:false,symbol:'XAUUSD',bid:2000,ask:2000.1,status:'Synthetic integration test',positions:[],deals:[]};
  const post=async (body:unknown,auth=bridgeToken)=>fetch('http://localhost:4200/api/webhooks/mt5',{method:'POST',headers:{'content-type':'application/json',authorization:`Bearer ${auth}`},body:JSON.stringify(body)});
  expect((await post(tel,token)).status).toBe(401);
  expect((await post({})).status).toBe(400);
  expect((await post(tel)).status).toBe(200);
  d=await client.scalper.status({token});expect(d.connected).toBe(true);
  await client.scalper.configure({token,config:{...config,running:true}});
  expect(await (await post(tel)).text()).toContain('AGS1|1|XAUUSD|0.5|2|1|1|XAUUSD');
  await client.scalper.configure({token,config:{...config,running:false}});
  expect(await (await post(tel)).text()).toContain('AGS1|0|');
  await client.scalper.configure({token,config:{...config,running:true}});
  expect(await (await post({...tel,dailyLossPct:2.1})).text()).toContain('AGS1|0|');
  await expect(client.scalper.configure({token,config:{...config,running:true}})).rejects.toThrow();
  await post(tel);await client.scalper.configure({token,config:{...config,running:true}});
  expect(await (await post({...tel,bootId:'new-boot'})).text()).toContain('AGS1|0|');
  await post(tel);await client.scalper.configure({token,config:{...config,running:true}});
  await db.update(terminals).set({lastSeen:Date.now()-30000}).where(eq(terminals.id,id));
  expect(await (await post(tel)).text()).toContain('AGS1|0|');
  await client.scalper.rotate({token});
  expect((await post(tel)).status).toBe(401);
 } finally {
  if(id){await db.delete(tradeEvents).where(eq(tradeEvents.terminalId,id));await db.delete(terminals).where(eq(terminals.id,id));}
 }
});
