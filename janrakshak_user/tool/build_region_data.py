"""Build-time: tool/india_districts.csv -> assets/region_data.json. Run: python3 tool/build_region_data.py"""
import csv, json

REGIONS = {
    "South": ["Andhra Pradesh", "Karnataka", "Kerala", "Tamil Nadu", "Telangana", "Andaman & Nicobar Islands", "Lakshadweep", "Puducherry"],
    "East": ["Bihar", "Jharkhand", "Odisha", "West Bengal"],
    "Northeast": ["Arunachal Pradesh", "Assam", "Manipur", "Meghalaya", "Mizoram", "Nagaland", "Sikkim", "Tripura"],
    "Central": ["Chhattisgarh", "Madhya Pradesh", "Uttar Pradesh", "Uttarakhand"],
    "West": ["Goa", "Gujarat", "Maharashtra", "Dadra & Nagar Haveli and Daman & Diu"],
    "North": ["Haryana", "Himachal Pradesh", "Punjab", "Rajasthan", "Chandigarh", "Delhi", "Jammu & Kashmir", "Ladakh"],
}
RENAME = {  # CSV spelling -> spec spelling
    "Andaman and Nicobar Islands": "Andaman & Nicobar Islands",
    "Jammu and Kashmir": "Jammu & Kashmir",
    "Dadra and Nagar Haveli and Daman and Diu": "Dadra & Nagar Haveli and Daman & Diu",
}

districts = {}
with open("tool/india_districts.csv", encoding="utf-8-sig") as f:
    for r in csv.DictReader(f):
        st = RENAME.get(r["State"].strip(), r["State"].strip())
        districts.setdefault(st, []).append(r["District"].strip())

listed = {s for v in REGIONS.values() for s in v}
assert listed == set(districts), (listed ^ set(districts))  # every state in exactly the spec's regions
out = {
    "regionToStates": REGIONS,
    "stateToDistricts": {s: sorted(set(d)) for s, d in sorted(districts.items())},
}
json.dump(out, open("assets/region_data.json", "w"), ensure_ascii=False, separators=(",", ":"))
print(len(REGIONS), "regions,", len(districts), "states,", sum(len(v) for v in districts.values()), "districts")
