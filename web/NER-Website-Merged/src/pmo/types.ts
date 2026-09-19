export interface NationalIncident {
  id: string;
  reference: string | null;
  /** Reporting channel: 'field_report', 'disaster_feed' or 'demo'. */
  source: string;
  typeId: string;
  rawType: string;
  title: string;
  description: string;
  severity: string | null;
  /** pending | active | escalated | resolved */
  status: string;
  /** Canonical spelling from india_districts.csv when the state could be resolved. */
  state: string | null;
  district: string | null;
  /** Derived from `state` via the CSV; never stored. */
  region: string | null;
  lat: number | null;
  lng: number | null;
  /** ISO timestamp from the database; demo data carries display text instead. */
  reportedAt: string | null;
  reporter: string | null;
}

export type RequestStatus = 'pending' | 'approved' | 'rejected';

export interface ControlRoomRequest {
  id: string;
  userId: string;
  fullName: string;
  email: string;
  requestedRegion: string | null;
  requestedState: string;
  reason: string;
  status: RequestStatus;
  createdAt: string;
  decidedAt: string | null;
  decidedByName: string | null;
}
