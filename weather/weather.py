# weather/weather.py
# A minimal MCP server that exposes two tools using NOAA/NWS public APIs
# Tools:
#   - get_alerts(state: str)
#   - get_forecast(latitude: float, longitude: float)
#
# Run (suggested):
#   uv venv && source .venv/bin/activate
#   uv add "mcp[cli]" httpx
#   uv run weather.py
#
# Or with pip:
#   python -m venv .venv && source .venv/bin/activate
#   pip install "mcp[cli]" httpx
#   python weather.py

from typing import Any, Dict, Optional, List
import httpx
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("weather")
NWS_API_BASE = "https://api.weather.gov"
USER_AGENT = "mcp-weather/1.0 (example)"

async def _get_json(url: str) -> Optional[Dict[str, Any]]:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/geo+json"
    }
    async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
        try:
            r = await client.get(url, headers=headers)
            r.raise_for_status()
            return r.json()
        except Exception:
            return None

def _format_alert(feature: Dict[str, Any]) -> str:
    props = feature.get("properties", {})
    return (
        f"Event: {props.get('event', 'Unknown')}\n"
        f"Area: {props.get('areaDesc', 'Unknown')}\n"
        f"Severity: {props.get('severity', 'Unknown')}\n"
        f"Description: {props.get('description', 'No description available')}\n"
        f"Instructions: {props.get('instruction', 'No specific instructions provided')}"
    )

@mcp.tool()
async def get_alerts(state: str) -> str:
    """Get active weather alerts for a US state (e.g., CA, NY)."""
    if not state or len(state) not in (2,):
        return "Please provide a 2-letter US state/territory code (e.g., CA, NY)."
    url = f"{NWS_API_BASE}/alerts/active/area/{state.upper()}"
    data = await _get_json(url)
    if not data or "features" not in data:
        return "Unable to fetch alerts or invalid response."
    feats = data.get("features", [])
    if not feats:
        return "No active alerts for this state."
    return "\n\n---\n\n".join(_format_alert(f) for f in feats)

@mcp.tool()
async def get_forecast(latitude: float, longitude: float) -> str:
    """Get a short forecast for a location by lat/lon (first ~4 periods)."""
    try:
        lat = float(latitude)
        lon = float(longitude)
    except Exception:
        return "Invalid latitude/longitude."

    # Step 1: resolve gridpoint from lat/lon
    points_url = f"{NWS_API_BASE}/points/{lat},{lon}"
    points = await _get_json(points_url)
    if not points or "properties" not in points or "forecast" not in points["properties"]:
        return "Unable to resolve grid forecast URL for this location."

    forecast_url = points["properties"]["forecast"]

    # Step 2: fetch forecast periods
    fc = await _get_json(forecast_url)
    if not fc or "properties" not in fc or "periods" not in fc["properties"]:
        return "Unable to fetch forecast periods."

    periods: List[Dict[str, Any]] = fc["properties"]["periods"][:4]
    lines = []
    for p in periods:
        name = p.get("name", "Period")
        short = p.get("shortForecast", "n/a")
        temp = p.get("temperature", "n/a")
        unit = p.get("temperatureUnit", "")
        wind = p.get("windSpeed", "")
        lines.append(f"{name}: {short} ({temp}°{unit}) Wind {wind}")
    return "\n".join(lines)

if __name__ == "__main__":
    # Run over stdio (works with most MCP hosts/clients)
    mcp.run(transport="stdio")
