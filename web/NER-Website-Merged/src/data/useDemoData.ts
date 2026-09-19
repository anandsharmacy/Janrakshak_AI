import { DEMO_AI_INSIGHTS, DEMO_INCIDENTS, DEMO_ROUTES, DEMO_VEHICLES, NO_AI_INSIGHTS } from '@/data/demo';
import type { AiInsights, Incident, Route, Vehicle } from '@/data/demo';
import { DEMO_RIDERS } from '@/data/demoRiders';
import type { DemoRider } from '@/data/demoRiders';
import { useDemoMode } from '@/lib/demoMode';

interface DemoData {
  incidents: Incident[];
  routes: Route[];
  vehicles: Vehicle[];
  riders: DemoRider[];
  aiInsights: AiInsights;
}

const ON: DemoData = {
  incidents: DEMO_INCIDENTS,
  routes: DEMO_ROUTES,
  vehicles: DEMO_VEHICLES,
  riders: DEMO_RIDERS,
  aiInsights: DEMO_AI_INSIGHTS,
};

const OFF: DemoData = { incidents: [], routes: [], vehicles: [], riders: [], aiInsights: NO_AI_INSIGHTS };

/** The demo datasets while demo mode is on, empty lists while it is off. Both objects are module constants, so the references are stable across renders. */
export function useDemoData(): DemoData {
  return useDemoMode().demo ? ON : OFF;
}
