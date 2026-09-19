import csv from "./india_districts.csv?raw";

// Region -> State -> District, built from india_districts.csv (columns: State,Region,District).
// Sets drop duplicate rows. ponytail: plain comma split, no quoted-field support; add a parser if a name ever contains a comma.
const TREE = new Map<string, Map<string, Set<string>>>();
const REGION_OF_STATE = new Map<string, string>();

for (const line of csv.split(/\r?\n/).slice(1)) {
  const [state, region, district] = line.split(",").map((cell) => cell.trim());
  if (!state || !region || !district) continue;
  if (!TREE.has(region)) TREE.set(region, new Map());
  const states = TREE.get(region)!;
  if (!states.has(state)) states.set(state, new Set());
  states.get(state)!.add(district);
  REGION_OF_STATE.set(state, region);
}

const sorted = (values: Iterable<string>) => [...values].sort((a, b) => a.localeCompare(b));

export const REGIONS = sorted(TREE.keys());
export const STATES = sorted(REGION_OF_STATE.keys());
export const statesOf = (region: string) => sorted(TREE.get(region)?.keys() ?? []);
export const districtsOf = (region: string, state: string) => sorted(TREE.get(region)?.get(state) ?? []);
export const regionOfState = (state: string) => REGION_OF_STATE.get(state);

/** True only for a real Region -> State (-> District) path in the CSV. */
export function isValidLocation(region: string, state: string, district?: string): boolean {
  const districts = TREE.get(region)?.get(state);
  return !!districts && (district === undefined || districts.has(district));
}

/** Case- and punctuation-insensitive key, so "Jammu & Kashmir" equals "Jammu and Kashmir". */
export const nameKey = (name: string) =>
  name.toLowerCase().replace(/&/g, "and").replace(/\bdistrict\b/g, "").replace(/[^a-z0-9]/g, "");

const STATE_BY_KEY = new Map([...REGION_OF_STATE].map(([state, region]) => [nameKey(state), { state, region }]));

/** Canonical CSV state (and its region) for a free-text state name from any data source. */
export const resolveState = (name?: string | null) => (name ? STATE_BY_KEY.get(nameKey(name)) : undefined);

export interface LocationMatch {
  kind: "region" | "state" | "district";
  name: string;
  region: string;
  state?: string;
}

const SEARCH_INDEX = [
  ...REGIONS.map((name): LocationMatch => ({ kind: "region", name, region: name })),
  ...STATES.map((name): LocationMatch => ({ kind: "state", name, region: REGION_OF_STATE.get(name)! })),
  ...REGIONS.flatMap((region) =>
    statesOf(region).flatMap((state) =>
      districtsOf(region, state).map((name): LocationMatch => ({ kind: "district", name, region, state })),
    ),
  ),
].map((match) => ({ match, key: nameKey(match.name) }));

/** Regions, states and districts matching the text, best (prefix) matches first. */
export function searchLocations(query: string, limit = 8): LocationMatch[] {
  const q = nameKey(query);
  if (!q) return [];
  const prefix: LocationMatch[] = [];
  const inside: LocationMatch[] = [];
  for (const { match, key } of SEARCH_INDEX) {
    if (key.startsWith(q)) prefix.push(match);
    else if (key.includes(q)) inside.push(match);
  }
  return [...prefix, ...inside].slice(0, limit);
}
