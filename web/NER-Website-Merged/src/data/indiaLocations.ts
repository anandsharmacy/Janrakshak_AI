import csv from "./india_districts.csv?raw";

// Region -> State -> District, built from india_districts.csv (columns: State,Region,District).
// Sets drop duplicate rows. ponytail: plain comma split, no quoted-field support; add a parser if a name ever contains a comma.
const TREE = new Map<string, Map<string, Set<string>>>();

for (const line of csv.split(/\r?\n/).slice(1)) {
  const [state, region, district] = line.split(",").map((cell) => cell.trim());
  if (!state || !region || !district) continue;
  if (!TREE.has(region)) TREE.set(region, new Map());
  const states = TREE.get(region)!;
  if (!states.has(state)) states.set(state, new Set());
  states.get(state)!.add(district);
}

const sorted = (values: Iterable<string>) => [...values].sort((a, b) => a.localeCompare(b));

export const REGIONS = sorted(TREE.keys());
export const statesOf = (region: string) => sorted(TREE.get(region)?.keys() ?? []);
export const districtsOf = (region: string, state: string) => sorted(TREE.get(region)?.get(state) ?? []);

/** True only for a real Region -> State (-> District) path in the CSV. */
export function isValidLocation(region: string, state: string, district?: string): boolean {
  const districts = TREE.get(region)?.get(state);
  return !!districts && (district === undefined || districts.has(district));
}
