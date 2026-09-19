/* ────────────────────────────────────────────────────────────────
   DEMO rider dataset — single source of truth for the website.
   Organised as State → District → Rider. Every count, KPI, table
   row and map marker must be derived from DEMO_RIDERS; nothing
   about these riders may be duplicated elsewhere.
──────────────────────────────────────────────────────────────── */

import type { Severity } from '@/data/demo';
import type { LatLng } from '@/data/geo';

export type RiderStatus = 'Active' | 'Inactive';
export type RiderVehicleType = 'Bike' | 'Scooter';

export interface DemoRider {
  id: string;
  name: string;
  phone: string;
  state: string;
  district: string;
  vehicleType: RiderVehicleType;
  rating: number;
  status: RiderStatus;
  /** Reported delay, e.g. "+20m". Unset when the rider is on schedule. */
  delay?: string;
  /** Shipment risk. Unset when nothing is flagged. */
  risk?: Severity;
}

/**
 * RiderID,RiderName,Phone,State,District,VehicleType,Rating,Status
 */
export const DEMO_RIDERS: DemoRider[] = [
  { id: 'R001', name: 'Rohan Das', phone: '9876543210', state: 'Assam', district: 'Kamrup Metropolitan', vehicleType: 'Bike', rating: 4.8, status: 'Active' },
  { id: 'R002', name: 'Bidyut Konwar', phone: '9876543211', state: 'Assam', district: 'Dibrugarh', vehicleType: 'Scooter', rating: 4.5, status: 'Active' },
  { id: 'R003', name: 'Lalrinawma Ralte', phone: '9876543212', state: 'Mizoram', district: 'Aizawl', vehicleType: 'Bike', rating: 4.7, status: 'Active' },
  { id: 'R004', name: 'Kevichusa Angami', phone: '9876543213', state: 'Nagaland', district: 'Kohima', vehicleType: 'Bike', rating: 4.6, status: 'Inactive' },
  { id: 'R005', name: 'Ibemhal Singh', phone: '9876543214', state: 'Manipur', district: 'Imphal West', vehicleType: 'Scooter', rating: 4.9, status: 'Active' },
  { id: 'R006', name: 'Banlum Khonglah', phone: '9876543215', state: 'Meghalaya', district: 'East Khasi Hills', vehicleType: 'Bike', rating: 4.4, status: 'Active' },
  { id: 'R007', name: 'Subrata Debbarma', phone: '9876543216', state: 'Tripura', district: 'West Tripura', vehicleType: 'Bike', rating: 4.3, status: 'Active' },
];

/* ── Map geometry ───────────────────────────────────────────────
   One short district-level route per rider. Waypoints are named so
   the "Current Location" column can follow the rider as it moves.
   Only R002 carries a blocked segment and a detour. */

export interface RiderWaypoint {
  at: LatLng;
  label: string;
}

export interface RiderBlockedSection {
  /** Index of the waypoint where the blocked stretch begins. */
  from: number;
  /** Index of the waypoint where the road is passable again. */
  to: number;
  /** Alternate waypoints joining path[from] to path[to]. */
  detour: RiderWaypoint[];
  reason: string;
}

export interface RiderRoute {
  riderId: string;
  path: RiderWaypoint[];
  blocked?: RiderBlockedSection;
}

export const DEMO_RIDER_ROUTES: Record<string, RiderRoute> = {
  // Assam · Kamrup Metropolitan — GS Road, Guwahati
  R001: {
    riderId: 'R001',
    path: [
      { at: [26.1445, 91.7362], label: 'Paltan Bazaar, Guwahati' },
      { at: [26.1520, 91.7690], label: 'Ganeshguri, Guwahati' },
      { at: [26.1400, 91.7900], label: 'Dispur, Guwahati' },
      { at: [26.1210, 91.8130], label: 'Basistha Chariali, Guwahati' },
    ],
  },
  // Assam · Dibrugarh — AT Road towards Mohanbari (blocked at Bogibeel Road crossing)
  R002: {
    riderId: 'R002',
    path: [
      { at: [27.4728, 94.9120], label: 'Thana Chariali, Dibrugarh' },
      { at: [27.4760, 94.9450], label: 'Jalan Nagar, Dibrugarh' },
      { at: [27.4790, 94.9750], label: 'Mohanbari Road, Dibrugarh' },
      { at: [27.4830, 95.0170], label: 'Mohanbari, Dibrugarh' },
    ],
    blocked: {
      from: 1,
      to: 2,
      reason: 'Waterlogged stretch on AT Road near Jalan Nagar',
      detour: [
        { at: [27.4640, 94.9480], label: 'Chowkidinghee bypass, Dibrugarh' },
        { at: [27.4660, 94.9780], label: 'Lahoal bypass, Dibrugarh' },
      ],
    },
  },
  // Mizoram · Aizawl — Aizawl to Durtlang
  R003: {
    riderId: 'R003',
    path: [
      { at: [23.7271, 92.7176], label: 'Treasury Square, Aizawl' },
      { at: [23.7400, 92.7240], label: 'Chanmari, Aizawl' },
      { at: [23.7560, 92.7300], label: 'Durtlang, Aizawl' },
    ],
  },
  // Nagaland · Kohima — inactive rider parked at Kohima town
  R004: {
    riderId: 'R004',
    path: [
      { at: [25.6751, 94.1086], label: 'Kohima Town, Kohima' },
    ],
  },
  // Manipur · Imphal West — Imphal to Lamphelpat
  R005: {
    riderId: 'R005',
    path: [
      { at: [24.8170, 93.9368], label: 'Kangla, Imphal West' },
      { at: [24.8080, 93.9240], label: 'Uripok, Imphal West' },
      { at: [24.7920, 93.9120], label: 'Lamphelpat, Imphal West' },
    ],
  },
  // Meghalaya · East Khasi Hills — Shillong to Nongthymmai
  R006: {
    riderId: 'R006',
    path: [
      { at: [25.5788, 91.8933], label: 'Police Bazar, Shillong' },
      { at: [25.5700, 91.8830], label: 'Laitumkhrah, Shillong' },
      { at: [25.5590, 91.8720], label: 'Nongthymmai, Shillong' },
    ],
  },
  // Tripura · West Tripura — Agartala to Khayerpur
  R007: {
    riderId: 'R007',
    path: [
      { at: [23.8315, 91.2868], label: 'Battala, Agartala' },
      { at: [23.8460, 91.3010], label: 'Kunjaban, Agartala' },
      { at: [23.8610, 91.3170], label: 'Khayerpur, Agartala' },
    ],
  },
};

/* ── Derived views (State → District → Rider) ─────────────────── */

export interface DistrictRiders<T extends DemoRider = DemoRider> {
  district: string;
  state: string;
  riders: T[];
}

export interface StateRiders<T extends DemoRider = DemoRider> {
  state: string;
  districts: DistrictRiders<T>[];
  riders: T[];
}

/** Groups riders as State → District → Rider, preserving dataset order. */
export function groupRidersByState<T extends DemoRider>(riders: T[]): StateRiders<T>[] {
  const states: StateRiders<T>[] = [];
  riders.forEach(rider => {
    let state = states.find(s => s.state === rider.state);
    if (!state) {
      state = { state: rider.state, riders: [], districts: [] };
      states.push(state);
    }
    state.riders.push(rider);
    let district = state.districts.find(d => d.district === rider.district);
    if (!district) {
      district = { district: rider.district, state: rider.state, riders: [] };
      state.districts.push(district);
    }
    district.riders.push(rider);
  });
  return states;
}

export interface RiderCounts {
  riders: number;
  active: number;
  inactive: number;
}

function countRiders(riders: DemoRider[]): RiderCounts {
  return {
    riders: riders.length,
    active: riders.filter(r => r.status === 'Active').length,
    inactive: riders.filter(r => r.status === 'Inactive').length,
  };
}

/** Per-state rider counts, derived from the rider list. */
export function stateRiderCounts(riders: DemoRider[]): ({ state: string } & RiderCounts)[] {
  return groupRidersByState(riders).map(group => ({ state: group.state, ...countRiders(group.riders) }));
}

/** Per-district rider counts, derived from the rider list. */
export function districtRiderCounts(riders: DemoRider[]): ({ district: string; state: string } & RiderCounts)[] {
  return groupRidersByState(riders).flatMap(group =>
    group.districts.map(district => ({ district: district.district, state: district.state, ...countRiders(district.riders) })),
  );
}

/** State → District → Rider filter. Omit district for a whole state; omit both for everyone. */
export function filterRiders<T extends DemoRider>(riders: T[], state?: string | null, district?: string | null): T[] {
  return riders.filter(r => (!state || r.state === state) && (!district || r.district === district));
}

/** Logistics KPI values, derived from the rider list. */
export function riderKpis(riders: DemoRider[]) {
  return {
    active: riders.filter(r => r.status === 'Active').length,
    delayed: riders.filter(r => Boolean(r.delay)).length,
    atRisk: riders.filter(r => r.risk === 'CRITICAL' || r.risk === 'HIGH').length,
    inactive: riders.filter(r => r.status === 'Inactive').length,
  };
}

export function riderRoute(riderId: string): RiderRoute | null {
  return DEMO_RIDER_ROUTES[riderId] ?? null;
}
