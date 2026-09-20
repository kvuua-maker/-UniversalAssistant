#!/usr/bin/env python3
"""Generate the bounded runtime fuel-POI asset from a developer-time OSM extract.

Input is Overpass JSON or equivalent prefiltered OSM JSON. Runtime never calls
Overpass/Nominatim. Output contains no user data and retains ODbL attribution.
"""
import argparse, datetime, json
from pathlib import Path

FUEL_KEYS = {
    "fuel:octane_92": "octane92", "fuel:octane_95": "octane95",
    "fuel:octane_98": "octane98", "fuel:octane_100": "octane100",
    "fuel:diesel": "diesel", "fuel:lpg": "lpg", "fuel:cng": "cng",
}
UKRAINE_BOUNDS = (22.13, 44.38, 40.23, 52.38)

def truthy(value):
    return str(value or "").lower() in {"yes", "true", "1", "designated"}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--source", default="https://download.geofabrik.de/europe/ukraine.html")
    args = parser.parse_args()
    root = json.loads(args.input.read_text())
    stations = []
    for element in root.get("elements", []):
        tags = element.get("tags", {})
        if tags.get("amenity") != "fuel":
            continue
        center = element.get("center", element)
        lat, lon = center.get("lat"), center.get("lon")
        if lat is None or lon is None:
            continue
        west, south, east, north = UKRAINE_BOUNDS
        if not (west <= lon <= east and south <= lat <= north):
            continue
        address = " ".join(filter(None, [tags.get("addr:street"), tags.get("addr:housenumber"), tags.get("addr:city")])) or None
        stations.append({
            "id": f"{element.get('type', 'node')}/{element['id']}",
            "name": tags.get("name"), "operatorName": tags.get("operator") or tags.get("brand"),
            "latitude": lat, "longitude": lon, "address": address,
            "phone": tags.get("contact:phone") or tags.get("phone"),
            "website": tags.get("contact:website") or tags.get("website"),
            "openingHours": tags.get("opening_hours"),
            "fuels": sorted(value for key, value in FUEL_KEYS.items() if truthy(tags.get(key))),
        })
    output = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
        "sourceURL": args.source, "license": "© OpenStreetMap contributors · ODbL 1.0",
        "stations": stations,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {len(stations)} stations to {args.output}")

if __name__ == "__main__": main()
