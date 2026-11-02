import { z } from 'zod';
import { ORPCError } from '@orpc/server';
import { eq, desc } from 'drizzle-orm';
import { base } from '../__core/app';
import { db } from '../database';
import { terminals, tradeEvents } from '../database/schema';

const hex = (bytes: Uint8Array) => Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
const random = (n: number) => hex(crypto.getRandomValues(new Uint8Array(n)));
const hash = async (s: string) => hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))));
const key = z.object({ token: z.string().min(40).max(100) });
const configSchema = z.object({
  running: z.boolean(), pair: z.enum(['XAUUSD', 'GOLD', 'GBPUSD', 'AUDUSD']),
  risk: z.number().min(0.1).max(0.5), dailyLoss: z.number().min(0.5).max(2),
  impulse: z.boolean(), trailing: z.boolean(),
  brokerSymbol: z.string().max(30).regex(/^[A-Za-z0-9._-]*$/),
});
const defaults = { running: false, pair: 'XAUUSD' as const, risk: 0.5, dailyLoss: 2, impulse: true, trailing: true, brokerSymbol: '' };
const telemetrySchema = z.object({
  bootId: z.string().min(1).max(80),
  login: z.string().max(30), server: z.string().max(100), currency: z.string().max(10),
  balance: z.number().finite().nonnegative(), equity: z.number().finite().nonnegative(),
  dailyPnl: z.number().finite(), dailyLossPct: z.number().finite().nonnegative(),
  allowed: z.boolean(), live: z.boolean(), acknowledged: z.boolean(),
  symbol: z.string().max(30), bid: z.number().finite().nonnegative(), ask: z.number().finite().nonnegative(),
  status: z.string().max(200),
  positions: z.array(z.object({ ticket: z.string(), symbol: z.string(), side: z.string(), volume: z.number(), profit: z.number(), sl: z.number() })).max(100),
  deals: z.array(z.object({ ticket: z.string(), symbol: z.string(), profit: z.number(), time: z.number() })).max(30),
});
export type Telemetry = z.infer<typeof telemetrySchema>;
async function terminal(token: string) {
  const [t] = await db.select().from(terminals).where(eq(terminals.controlHash, await hash(token)));
  if (!t) throw new ORPCError('UNAUTHORIZED', { message: 'Pairing key not recognised. Create or restore your bridge.' });
  return t;
}
async function event(id: string, message: string) {
  await db.insert(tradeEvents).values({ id: random(16), terminalId: id, message, createdAt: Date.now() });
}
export const scalper = {
  create: base.handler(async () => {
    const token = random(32);
    const bridgeToken = random(32);
    const id = random(16);
    await db.insert(terminals).values({ id, controlHash: await hash(token), bridgeHash: await hash(bridgeToken), bridgeToken, config: JSON.stringify(defaults), createdAt: Date.now() });
    await event(id, 'Bridge created. Waiting for MT5 terminal.');
    return { token };
  }),
  status: base.input(key).handler(async ({ input }) => {
    const t = await terminal(input.token);
    const telemetry = t.telemetry ? telemetrySchema.parse(JSON.parse(t.telemetry)) : null;
    return { config: configSchema.parse(JSON.parse(t.config)), telemetry, connected: Date.now() - t.lastSeen < 20000, lastSeen: t.lastSeen,
      bridgeToken: t.bridgeToken, events: await db.select().from(tradeEvents).where(eq(tradeEvents.terminalId, t.id)).orderBy(desc(tradeEvents.createdAt)).limit(30) };
  }),
  configure: base.input(key.extend({ config: configSchema })).handler(async ({ input }) => {
    const t = await terminal(input.token);
    const old = configSchema.parse(JSON.parse(t.config));
    const tel = t.telemetry ? telemetrySchema.parse(JSON.parse(t.telemetry)) : null;
    if (input.config.running && (!tel || Date.now() - t.lastSeen > 20000 || !tel.allowed || tel.dailyLossPct >= input.config.dailyLoss))
      throw new ORPCError('BAD_REQUEST', { message: 'Start blocked: connect a fresh, trading-enabled MT5 terminal and check the daily loss limit.' });
    if (input.config.running && tel?.positions.length && (old.pair !== input.config.pair || old.brokerSymbol !== input.config.brokerSymbol))
      throw new ORPCError('BAD_REQUEST', { message: 'Stop the bot before changing instruments with positions open.' });
    await db.update(terminals).set({ config: JSON.stringify(input.config) }).where(eq(terminals.id, t.id));
    await event(t.id, old.running !== input.config.running ? input.config.running ? 'Start requested. Awaiting terminal acknowledgement.' : 'Stop requested. Existing positions keep protective stops.' : 'Strategy settings updated.');
    return { ok: true };
  }),
  rotate: base.input(key).handler(async ({ input }) => {
    const t = await terminal(input.token);
    const token = random(32);
    await db.update(terminals).set({ bridgeHash: await hash(token), bridgeToken: token, lastSeen: 0, config: JSON.stringify({ ...JSON.parse(t.config), running: false }) }).where(eq(terminals.id, t.id));
    await event(t.id, 'Terminal key rotated. Bot stopped; re-pair the EA.');
    return { ok: true };
  }),
};

// External MT5 heartbeat webhook. A separate terminal-only capability cannot access mobile controls.
export async function heartbeat(auth: string, body: unknown) {
  if (!auth.startsWith('Bearer ') || auth.length !== 71) return { code: 401, body: 'unauthorized' };
  const [t] = await db.select().from(terminals).where(eq(terminals.bridgeHash, await hash(auth.slice(7))));
  if (!t) return { code: 401, body: 'unauthorized' };
  const parsed = telemetrySchema.safeParse(body);
  if (!parsed.success) return { code: 400, body: 'invalid telemetry' };
  const c = configSchema.parse(JSON.parse(t.config));
  const stale = t.lastSeen > 0 && Date.now() - t.lastSeen > 20000;
  const restarted = t.telemetry && JSON.parse(t.telemetry).bootId !== parsed.data.bootId;
  if (stale || restarted || parsed.data.dailyLossPct >= c.dailyLoss || !parsed.data.allowed) c.running = false;
  await db.update(terminals).set({ telemetry: JSON.stringify(parsed.data), lastSeen: Date.now(), config: JSON.stringify(c) }).where(eq(terminals.id, t.id));
  if (stale) await event(t.id, 'Connection lease expired. Start again manually after reconnecting.');
  if (restarted) await event(t.id, 'EA restarted. Start again manually after reconnecting.');
  return { code: 200, body: ['AGS1', c.running ? 1 : 0, c.pair, c.risk, c.dailyLoss, c.impulse ? 1 : 0, c.trailing ? 1 : 0, c.brokerSymbol || c.pair].join('|') };
}