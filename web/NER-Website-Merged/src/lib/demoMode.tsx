import { createContext, useContext, useEffect, useMemo, useState } from 'react';

const STORAGE_KEY = 'ner-demo-data';

function loadDemoMode(): boolean {
  if (typeof window === 'undefined') return true;
  try {
    return window.localStorage.getItem(STORAGE_KEY) !== 'off';
  } catch {
    return true;
  }
}

interface DemoModeContextValue {
  demo: boolean;
  setDemo: (on: boolean) => void;
}

const DemoModeContext = createContext<DemoModeContextValue | null>(null);

export function DemoModeProvider({ children }: { children: React.ReactNode }) {
  const [demo, setDemo] = useState<boolean>(() => loadDemoMode());

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEY, demo ? 'on' : 'off');
    } catch {
      /* storage unavailable: the choice still applies for this page load */
    }
  }, [demo]);

  const value = useMemo(() => ({ demo, setDemo }), [demo]);
  return <DemoModeContext.Provider value={value}>{children}</DemoModeContext.Provider>;
}

export function useDemoMode(): DemoModeContextValue {
  const ctx = useContext(DemoModeContext);
  if (!ctx) throw new Error('useDemoMode must be used within a DemoModeProvider');
  return ctx;
}
