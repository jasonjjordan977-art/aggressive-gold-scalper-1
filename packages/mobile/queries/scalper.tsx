import React, { createContext, useContext, useEffect, useState } from 'react';
import { Platform } from 'react-native';
import * as SecureStore from 'expo-secure-store';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { client, orpc } from '../lib/api';

const Session = createContext<{ token: string; ready: boolean; save: (value: string) => Promise<void> }>({ token: '', ready: false, save: async () => {} });
export function TradingProvider({ children }: { children: React.ReactNode }) {
  const [token, setToken] = useState('');
  const [ready, setReady] = useState(false);
  useEffect(() => { (async () => { try { const value = Platform.OS === 'web' ? sessionStorage.getItem('ags-controller') : await SecureStore.getItemAsync('ags-controller'); setToken(value || ''); } finally { setReady(true); } })(); }, []);
  async function save(value: string) {
    if (Platform.OS === 'web') sessionStorage.setItem('ags-controller', value);
    else await SecureStore.setItemAsync('ags-controller', value);
    setToken(value);
  }
  return <Session.Provider value={{ token, ready, save }}>{children}</Session.Provider>;
}
export function useTrading() {
  const session = useContext(Session);
  const qc = useQueryClient();
  const status = useQuery(orpc.scalper.status.queryOptions({ input: { token: session.token }, enabled: !!session.token, refetchInterval: 5000, retry: false }));
  const create = useMutation({ mutationFn: async () => { const result = await client.scalper.create(); await session.save(result.token); } });
  const configure = useMutation(orpc.scalper.configure.mutationOptions({ onSuccess: () => qc.invalidateQueries({ queryKey: orpc.scalper.key() }) }));
  const rotate = useMutation(orpc.scalper.rotate.mutationOptions({ onSuccess: () => qc.invalidateQueries({ queryKey: orpc.scalper.key() }) }));
  const error = configure.error?.message || create.error?.message || rotate.error?.message || status.error?.message || '';
  return { ...session, status, create, configure, rotate, error };
}