import { z } from 'zod';

export const percent = z.number().finite().min(0.1).max(10);
export const configSchema = z.object({
  running: z.boolean(), pair: z.enum(['XAUUSD', 'GOLD', 'GBPUSD', 'AUDUSD']),
  risk: percent, dailyBudget: percent.default(2), dailyLoss: percent,
  impulse: z.boolean(), trailing: z.boolean(),
  brokerSymbol: z.string().max(30).regex(/^[A-Za-z0-9._-]*$/),
});
export const defaults = {
  running: false, pair: 'XAUUSD' as const, risk: 0.5, dailyBudget: 2,
  dailyLoss: 2, impulse: true, trailing: true, brokerSymbol: '',
};
type RiskTelemetry = {
  allowed: boolean; dailyLossPct: number; protocolVersion?: number;
  budgetReady?: boolean; dailyRiskUsedPct?: number;
};
export function startBlock(config: z.infer<typeof configSchema>, tel: RiskTelemetry | null, fresh: boolean): string | null {
  if (!tel || !fresh || !tel.allowed) return 'Connect a fresh, trading-enabled MT5 terminal before starting.';
  if (tel.protocolVersion !== 2) return 'Install and compile the budget-capable EA v1.04 or newer before starting.';
  if (!tel.budgetReady || tel.dailyRiskUsedPct === undefined) return 'MT5 daily-risk ledger is not ready. Check its Experts log.';
  if (tel.dailyLossPct >= config.dailyLoss) return 'Daily-loss stop reached. No new entries at the current limit.';
  if (tel.dailyRiskUsedPct >= config.dailyBudget) return 'Daily risk budget exhausted. No new entries at the current limit.';
  return null;
}

export function bridgeCommand(config: z.infer<typeof configSchema>, protocolVersion?: number): string {
  if (protocolVersion !== 2) {
    // Keep old terminals readable, never let them run without the new daily guard.
    return ['AGS1', 0, config.pair, Math.min(config.risk, 0.5), Math.max(0.5, Math.min(config.dailyLoss, 2)), config.impulse ? 1 : 0, config.trailing ? 1 : 0, config.brokerSymbol || config.pair].join('|');
  }
  return ['AGS2', config.running ? 1 : 0, config.pair, config.risk, config.dailyLoss, config.impulse ? 1 : 0, config.trailing ? 1 : 0, config.brokerSymbol || config.pair, config.dailyBudget].join('|');
}