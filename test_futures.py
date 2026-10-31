import asyncio
import websockets
import json

async def test():
    uri = "wss://fstream.binance.com/ws/!ticker@arr"
    print("Connecting to Futures WS:", uri)
    try:
        async with websockets.connect(uri, proxy="http://127.0.0.1:10085") as ws:
            msg = await ws.recv()
            data = json.loads(msg)
            print(f"Futures WS Connected! Total pairs in feed: {len(data)}")
            ain = [x for x in data if "AIN" in x.get("s", "")]
            print("AIN in Futures:", ain)
    except Exception as e:
        print("Futures WS Error:", e)

if __name__ == "__main__":
    asyncio.run(test())
