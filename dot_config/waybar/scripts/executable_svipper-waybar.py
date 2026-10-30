#!/usr/bin/env python3
"""Waybar custom module showing upcoming bus departures from Svipper/Entur."""

import argparse
import json
import sys
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

API_URL = "https://api.entur.io/journey-planner/v3/graphql"
GEOCODER_URL = "https://api.entur.io/geocoder/v1/autocomplete"
CLIENT_NAME = "svipper-waybar"
CACHE_FILE = Path.home() / ".cache" / "svipper-waybar" / "stops.json"

QUERY = """
query ($id: String!, $count: Int!) {
  %s(id: $id) {
    name
    estimatedCalls(numberOfDepartures: $count, timeRange: 86400) {
      expectedDepartureTime
      realtime
      cancellation
      destinationDisplay { frontText }
      serviceJourney {
        directionType
        journeyPattern { line { publicCode } }
      }
    }
  }
}
"""


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stop", required=True,
                   help="stop name, e.g. Postterminalen, "
                        "or an id: NSR:Quay:<id> (one platform) / NSR:StopPlace:<id>")
    p.add_argument("--city", help="city or county the stop is in, e.g. Tromsø")
    p.add_argument("--line", help="route number, e.g. 40")
    p.add_argument("--direction",
                   help="'inbound', 'outbound', or text matched against the destination, e.g. Slettaelva")
    p.add_argument("--count", type=int, default=5, help="departures listed in the tooltip")
    p.add_argument("--icon", default="󰃧")
    return p.parse_args()


def http_json(req):
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)


def lookup_stop(name, city):
    params = urllib.parse.urlencode({"text": name, "layers": "venue", "size": 20})
    req = urllib.request.Request(f"{GEOCODER_URL}?{params}", headers={"ET-Client-Name": CLIENT_NAME})
    for f in http_json(req)["features"]:
        props = f["properties"]
        areas = [(props.get(k) or "").lower() for k in ("locality", "county")]
        if props["name"].lower() == name.lower() and (not city or city.lower() in areas):
            return props["id"]
    raise RuntimeError(f"no stop named '{name}'" + (f" in {city}" if city else ""))


def resolve_stop(stop, city):
    if stop.startswith("NSR:"):
        return stop
    key = f"{stop}|{city or ''}"
    try:
        cache = json.loads(CACHE_FILE.read_text())
    except (OSError, ValueError):
        cache = {}
    if key not in cache:
        cache[key] = lookup_stop(stop, city)
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        CACHE_FILE.write_text(json.dumps(cache, ensure_ascii=False, indent=2))
    return cache[key]


def fetch_calls(stop_id):
    kind = "stopPlace" if "StopPlace" in stop_id else "quay"
    body = json.dumps({"query": QUERY % kind, "variables": {"id": stop_id, "count": 100}})
    req = urllib.request.Request(API_URL, data=body.encode(), headers={
        "Content-Type": "application/json",
        "ET-Client-Name": CLIENT_NAME,
    })
    data = http_json(req)
    if data.get("errors"):
        raise RuntimeError(data["errors"][0].get("message", "API error"))
    stop = data["data"][kind]
    if stop is None:
        raise RuntimeError(f"unknown stop {stop_id}")
    return stop["name"], stop["estimatedCalls"]


def matches(call, line, direction):
    journey = call["serviceJourney"]
    if line and journey["journeyPattern"]["line"]["publicCode"] != line:
        return False
    if direction:
        d = direction.lower()
        if d in ("inbound", "outbound"):
            return journey["directionType"] == d
        return d in call["destinationDisplay"]["frontText"].lower()
    return True


def describe(call, now):
    t = datetime.fromisoformat(call["expectedDepartureTime"]).astimezone()
    minutes = max(0, int((t - now).total_seconds() // 60))
    return t, minutes


def main():
    args = parse_args()
    now = datetime.now().astimezone()
    try:
        stop_name, calls = fetch_calls(resolve_stop(args.stop, args.city))
    except Exception as e:
        print(json.dumps({"text": f"{args.icon} –", "tooltip": f"Svipper error: {e}", "class": "error"}))
        return

    calls = [c for c in calls if not c["cancellation"] and matches(c, args.line, args.direction)]
    if not calls:
        print(json.dumps({"text": f"{args.icon} –", "tooltip": f"{stop_name}: no departures", "class": "none"}))
        return

    t, minutes = describe(calls[0], now)
    label = f"{args.line} " if args.line else ""
    text = f"{args.icon} {label}{t:%H:%M} ({minutes} min)"

    dest = calls[0]["destinationDisplay"]["frontText"]
    lines = [f"<b>{stop_name} → {dest}</b>"]
    for c in calls[: args.count]:
        ct, cm = describe(c, now)
        code = c["serviceJourney"]["journeyPattern"]["line"]["publicCode"]
        live = "" if c["realtime"] else " *"
        lines.append(f"<tt>{code:>3}  {ct:%H:%M}  {cm:>3} min{live}</tt>")

    cls = "soon" if minutes <= 5 else "normal"
    print(json.dumps({"text": text, "tooltip": "\n".join(lines), "class": cls}))


if __name__ == "__main__":
    sys.exit(main())
