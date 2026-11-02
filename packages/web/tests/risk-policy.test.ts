import { describe, expect, test } from 'bun:test';
import { configSchema, defaults, startBlock, bridgeCommand } from '../src/api/lib/risk-policy';

const tel = { allowed: true, protocolVersion: 2, budgetReady: true, dailyRiskUsedPct: 0.4, dailyLossPct: 0.2 };
describe('adjustable risk policy', () => {
  test('all three percentages accept 0.1 through 10', () => {
    for (const field of ['risk', 'dailyBudget', 'dailyLoss']) {
      for (const value of [0.1, 0.125, 0.5, 2, 9.5, 10]) expect(configSchema.safeParse({ ...defaults, [field]: value }).success).toBe(true);
      for (const value of [0, 0.09, 10.01, NaN, Infinity, '2']) expect(configSchema.safeParse({ ...defaults, [field]: value }).success).toBe(false);
    }
  });
  test('old JSON configurations acquire a daily budget without DB migration', () => {
    const { dailyBudget: _missing, ...legacy } = defaults;
    expect(configSchema.parse(legacy).dailyBudget).toBe(2);
  });
  test('ledger capability and connectivity fail closed', () => {
    expect(startBlock(defaults, tel, true)).toBeNull();
    expect(startBlock(defaults, null, true)).toBeTruthy();
    expect(startBlock(defaults, tel, false)).toBeTruthy();
    expect(startBlock(defaults, { ...tel, allowed: false }, true)).toBeTruthy();
    expect(startBlock(defaults, { ...tel, protocolVersion: undefined }, true)).toContain('v1.04');
    expect(startBlock(defaults, { ...tel, budgetReady: false }, true)).toContain('ledger');
    expect(startBlock(defaults, { ...tel, dailyRiskUsedPct: undefined }, true)).toContain('ledger');
  });
  test('both daily stops are independent; raising a limit does not erase usage', () => {
    expect(startBlock(defaults, { ...tel, dailyLossPct: 2 }, true)).toContain('Daily-loss');
    expect(startBlock(defaults, { ...tel, dailyRiskUsedPct: 2 }, true)).toContain('budget');
    expect(startBlock({ ...defaults, dailyBudget: 3 }, { ...tel, dailyRiskUsedPct: 2 }, true)).toBeNull();
    expect(startBlock({ ...defaults, dailyBudget: 3 }, { ...tel, dailyRiskUsedPct: 2, dailyLossPct: 2 }, true)).toContain('Daily-loss');
  });
  test('AGS2 has nine fields and all three settings; legacy never runs', () => {
    expect(bridgeCommand({ ...defaults, running: true, risk: 10, dailyLoss: 9, dailyBudget: 8 }, 2)).toBe('AGS2|1|XAUUSD|10|9|1|1|XAUUSD|8');
    expect(bridgeCommand({ ...defaults, running: true, risk: 10, dailyLoss: 10 }).split('|')).toEqual(['AGS1', '0', 'XAUUSD', '0.5', '2', '1', '1', 'XAUUSD']);
  });
});