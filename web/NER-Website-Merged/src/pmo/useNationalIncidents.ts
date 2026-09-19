import { useCallback, useEffect, useRef, useState } from 'react';
import { useDemoData } from '@/data/useDemoData';
import { useDemoMode } from '@/lib/demoMode';
import { demoNationalIncidents } from './demoIncidents';
import { fetchNationalIncidents, PmoAccessError } from './pmoApi';
import type { NationalIncident } from './types';

const REFRESH_MS = 60_000;

/** Live incidents from the database, or the site's demo dataset while demo mode is on. */
export function useNationalIncidents(onAccessDenied: () => void) {
  const { demo } = useDemoMode();
  const { incidents: demoList } = useDemoData();
  const [incidents, setIncidents] = useState<NationalIncident[]>([]);
  const [loading, setLoading] = useState(!demo);
  const [error, setError] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null);
  const latest = useRef(0);
  const denied = useRef(onAccessDenied);
  denied.current = onAccessDenied;

  const load = useCallback(async () => {
    const run = ++latest.current;
    setLoading(true);
    try {
      const rows = demo ? demoNationalIncidents(demoList) : await fetchNationalIncidents();
      if (run !== latest.current) return;
      setIncidents(rows);
      setError(null);
      setUpdatedAt(new Date());
    } catch (e) {
      if (run !== latest.current) return;
      if (e instanceof PmoAccessError) denied.current();
      setError(e instanceof Error ? e.message : 'Could not load incidents.');
    } finally {
      if (run === latest.current) setLoading(false);
    }
  }, [demo, demoList]);

  useEffect(() => {
    void load();
    if (demo) return;
    const timer = setInterval(() => void load(), REFRESH_MS);
    return () => clearInterval(timer);
  }, [load, demo]);

  return { incidents, loading, error, updatedAt, refresh: load, demo };
}
