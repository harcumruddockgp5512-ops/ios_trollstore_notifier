import os
os.environ["NO_PROXY"] = "*"
os.environ["no_proxy"] = "*"
import asyncio
import websockets
import json

async def test_ws():
    uri = "ws://127.0.0.1:8080/ws/radar"
    print(f"Connecting to {uri}...")
    try:
        async with websockets.connect(uri) as ws:
            print("Connected!")
            init_msg = await ws.recv()
            print("Received initial:", init_msg)
            await asyncio.sleep(3)
            print("After 3s, is closed:", ws.closed)
    except Exception as e:
        print("WS Error:", e)

if __name__ == "__main__":
    asyncio.run(test_ws())
