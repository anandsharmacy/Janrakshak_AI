import 'models.dart';

const fieldOfficer = Officer(
  name: 'A. Sangma',
  officerId: 'NER-FO-4471',
  role: AppRole.field,
  roleLabel: 'Field Officer',
  department: 'Janrakshak AI Division',
  region: 'Ri Bhoi District, Meghalaya',
  phone: '+91 94365 00471',
  email: 'a.sangma@ner.gov.in',
  lastLogin: 'Today, 09:38 IST',
);

const districtOfficer = Officer(
  name: 'R. Borah',
  officerId: 'NER-DO-2281',
  role: AppRole.district,
  roleLabel: 'District Officer',
  department: 'Kamrup Metro District Administration',
  region: 'Kamrup Metro, Assam',
  phone: '+91 98641 02281',
  email: 'r.borah@kamrup.gov.in',
  lastLogin: 'Today, 09:41 IST',
);

const controlOfficer = Officer(
  name: 'S. Khongsdier',
  officerId: 'NER-CO-0012',
  role: AppRole.control,
  roleLabel: 'Control Room Operator',
  department: 'NER Regional Command Center',
  region: 'North Eastern Region (8 States)',
  phone: '+91 98000 10012',
  email: 's.khongsdier@ner.gov.in',
  lastLogin: 'Today, 09:41 IST',
);

const riderOfficer = Officer(
  name: 'P. Lyngdoh',
  officerId: 'NER-RD-1184',
  role: AppRole.rider,
  roleLabel: 'Logistics Rider',
  department: 'Janrakshak AI Division',
  region: 'Ri Bhoi District, Meghalaya',
  phone: '+91 94365 01184',
  email: 'p.lyngdoh@ner.gov.in',
  lastLogin: 'Today, 09:39 IST',
);

const activeTrip = TripInfo(
  tripId: 'TRP-2291',
  consignment: 'P1 medical',
  destination: 'Sonapur',
  origin: 'Guwahati Depot',
);
