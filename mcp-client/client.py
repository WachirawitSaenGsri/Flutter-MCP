# mcp-client/client.py
# Minimal Python MCP client that launches a server over stdio and calls tools.
#
# Usage:
#   python client.py ../weather/weather.py
# Then try commands:
#   alerts CA
#   forecast 37.78 -122.42

import sys
import asyncio
from contextlib import AsyncExitStack
from mcp import ClientSession
from mcp.client.stdio import stdio_client
from mcp.client.stdio import StdioServerParameters

async def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python client.py path/to/weather.py")
        sys.exit(1)

    server_script = sys.argv[1]

    async with AsyncExitStack() as stack:
        params = StdioServerParameters(command="python", args=[server_script], env=None)
        reader, writer = await stack.enter_async_context(stdio_client(params))
        session: ClientSession = await stack.enter_async_context(ClientSession(reader, writer))
        await session.initialize()

        tools = (await session.list_tools()).tools
        print("Connected. Tools available:", [t.name for t in tools])

        while True:
            try:
                q = input("\nQuery (alerts <STATE> | forecast <LAT> <LON> | quit): ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            if not q:
                continue
            if q.lower() == "quit":
                break

            try:
                if q.startswith("alerts "):
                    _, state = q.split(maxsplit=1)
                    res = await session.call_tool("get_alerts", {"state": state})
                    print(res.content[0].text)

                elif q.startswith("forecast "):
                    parts = q.split()
                    if len(parts) != 3:
                        print("Usage: forecast <LAT> <LON>")
                        continue
                    lat, lon = float(parts[1]), float(parts[2])
                    res = await session.call_tool("get_forecast", {"latitude": lat, "longitude": lon})
                    print(res.content[0].text)

                else:
                    print("Unknown command. Try: alerts CA  |  forecast 37.78 -122.42")
            except Exception as e:
                print(f"Error: {e}")

if __name__ == "__main__":
    asyncio.run(main())
