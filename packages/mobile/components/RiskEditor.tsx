import React, { useEffect, useState } from 'react';
import { View, Text, TextInput, Pressable, StyleSheet } from 'react-native';

type Limits = { risk: number; dailyBudget: number; dailyLoss: number };
const fields = [
  { key: 'risk', label: 'Per-entry risk', help: 'FX percentage cap with an execution reserve. Gold stays one 0.01 lot and bypasses this cap.' },
  { key: 'dailyBudget', label: 'Daily risk budget', help: 'Cumulative initial stop-risk of filled EA entries / broker-day starting equity. Wins and closes do not refill it.' },
  { key: 'dailyLoss', label: 'Daily-loss stop', help: 'Highest recorded broker-day equity loss. Stops new entries; does not close positions or guarantee a maximum loss.' },
] as const;
export function RiskEditor({ limits, busy, onSave }: { limits: Limits; busy: boolean; onSave: (limits: Limits) => Promise<void> }) {
  const [draft, setDraft] = useState({ risk: String(limits.risk), dailyBudget: String(limits.dailyBudget), dailyLoss: String(limits.dailyLoss) });
  const [error, setError] = useState('');
  const [confirmation, setConfirmation] = useState<Limits | null>(null);
  useEffect(() => {
    setDraft({ risk: String(limits.risk), dailyBudget: String(limits.dailyBudget), dailyLoss: String(limits.dailyLoss) });
    setConfirmation(null);
  }, [limits.risk, limits.dailyBudget, limits.dailyLoss]);
  async function commit(values: Limits) {
    setError('');
    try { await onSave(values); setConfirmation(null); }
    catch (e) { setError(e instanceof Error ? e.message : 'Settings could not be saved.'); }
  }
  function save() {
    const values = {} as Limits;
    for (const f of fields) {
      const text = draft[f.key].trim().replace(',', '.');
      const value = Number(text);
      if (!/^\d*(\.\d*)?$/.test(text) || !text || !Number.isFinite(value) || value < 0.1 || value > 10) {
        setError(`${f.label}: enter a percentage from 0.1 to 10.`); return;
      }
      values[f.key] = value;
    }
    setError('');
    if (fields.some(f => values[f.key] > limits[f.key]) || values.risk > 0.5 || values.dailyBudget > 2 || values.dailyLoss > 2) setConfirmation(values);
    else void commit(values);
  }
  return <View style={s.container}>
    {fields.map(f => <View key={f.key} style={s.field}>
      <Text style={s.title}>{f.label}</Text><Text style={s.help}>{f.help}</Text>
      <View style={s.inputRow}><TextInput accessibilityLabel={`${f.label} percentage`} value={draft[f.key]} onChangeText={text => { setDraft(p => ({ ...p, [f.key]: text })); setError(''); setConfirmation(null); }} editable={!busy} keyboardType="decimal-pad" maxLength={12} placeholder="0.1–10" placeholderTextColor="#79858A" style={s.input}/><Text style={s.percent}>%</Text></View>
      <Text style={s.help}>Allowed: 0.1–10% · Saved: {limits[f.key]}%</Text>
    </View>)}
    <Text style={s.warning}>Gold bypasses per-entry risk ONLY. Its 0.01-lot order must still fit the daily budget and pass the daily-loss stop. A smaller lot is not a guaranteed low-risk trade.</Text>
    {Boolean(error) && <Text accessibilityRole="alert" style={s.error}>{error}</Text>}
    {confirmation ? <View style={s.confirm}>
      <Text style={s.warning}>Confirm entry {confirmation.risk}%, daily budget {confirmation.dailyBudget}% and daily-loss stop {confirmation.dailyLoss}%. Higher limits permit more exposure. Raising a reached daily limit can allow more trades today. Saving stops entries; Start is a separate action.</Text>
      <Pressable accessibilityRole="button" disabled={busy} onPress={() => void commit(confirmation)} style={s.button}><Text style={s.buttonText}>{busy ? 'Saving…' : 'Confirm risk limits'}</Text></Pressable>
      <Pressable accessibilityRole="button" disabled={busy} onPress={() => setConfirmation(null)}><Text style={s.cancel}>Cancel</Text></Pressable>
    </View> : <Pressable accessibilityRole="button" disabled={busy} onPress={save} style={s.button}><Text style={s.buttonText}>{busy ? 'Saving…' : 'Save risk limits / stop entries'}</Text></Pressable>}
    <Text style={s.help}>Defaults: 0.5% entry · 2% daily budget · 2% daily-loss stop. Settings do not reset today’s counters. Use the matching v1.04 EA.</Text>
  </View>;
}
const s = StyleSheet.create({
  container: { gap: 16 }, field: { gap: 7 }, title: { fontFamily: 'Manrope_600SemiBold', color: '#F3F1E9', fontSize: 13 },
  help: { fontFamily: 'Manrope_400Regular', color: '#79858A', fontSize: 11, lineHeight: 18 },
  inputRow: { flexDirection: 'row', alignItems: 'center', gap: 10 }, input: { flex: 1, backgroundColor: '#090C0D', borderWidth: 1, borderColor: '#263033', borderRadius: 9, padding: 13, fontFamily: 'Manrope_600SemiBold', fontSize: 17, color: '#F3F1E9' },
  percent: { fontFamily: 'Manrope_600SemiBold', color: '#D7B66C', fontSize: 18 }, warning: { fontFamily: 'Manrope_400Regular', fontSize: 11, lineHeight: 19, color: '#D7B66C' },
  error: { fontFamily: 'Manrope_400Regular', color: '#F28585', fontSize: 12 }, confirm: { gap: 12, padding: 13, backgroundColor: '#252116', borderRadius: 10 },
  button: { backgroundColor: '#D7B66C', borderRadius: 10, padding: 15, alignItems: 'center' }, buttonText: { fontFamily: 'Manrope_800ExtraBold', fontSize: 13, color: '#090C0D' },
  cancel: { fontFamily: 'Manrope_600SemiBold', color: '#F3F1E9', textAlign: 'center', padding: 8 },
});