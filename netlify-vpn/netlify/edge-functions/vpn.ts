import type { Context } from "https://edge.netlify.com";

export default async (request: Request, context: Context) => {
  const url = new URL(request.url);

  // Upgrade to WebSocket
  if (request.headers.get("Upgrade") !== "websocket") {
    return new Response("VLESS WebSocket Endpoint. Please use a VLESS client.", { status: 426 });
  }

  // Get UUID from Environment Variable or use a default one for easy setup
  const ENV_UUID = Deno.env.get("UUID") || "8f91b6a0-e8ee-4497-b08e-8e9935147575";
  const expectedUUID = ENV_UUID.toLowerCase().replace(/-/g, "");

  const { socket, response } = Deno.upgradeWebSocket(request);

  socket.onopen = () => {
    // console.log("WS Connected");
  };

  let isHeaderProcessed = false;
  let remoteSocket: Deno.Conn | null = null;

  socket.onmessage = async (event) => {
    if (!(event.data instanceof ArrayBuffer)) {
      return; // Ignore text frames
    }

    const data = new Uint8Array(event.data);

    if (!isHeaderProcessed) {
      try {
        const result = processVlessHeader(data, expectedUUID);
        if (!result) {
          console.log("Invalid VLESS Header or UUID mismatch");
          socket.close();
          return;
        }

        const { address, port, rawDataIndex, command } = result;

        // Block UDP (Command = 2) explicitly since we only support TCP connect
        if (command === 2) {
            console.error("UDP requested but not supported");
            socket.close();
            return;
        }

        // console.log(`Connecting to target: ${address}:${port}`);

        remoteSocket = await Deno.connect({ hostname: address, port: port });
        isHeaderProcessed = true;

        // Pipe from Remote -> WebSocket
        pipeRemoteToWs(remoteSocket, socket);

        // Send remaining data from the first packet to Remote
        if (rawDataIndex < data.length) {
          const firstChunk = data.subarray(rawDataIndex);
          await remoteSocket.write(firstChunk);
        }

      } catch (err) {
        console.error("Connection failed:", err);
        socket.close();
      }
    } else {
      // Forward data WebSocket -> Remote
      if (remoteSocket) {
        try {
          await remoteSocket.write(data);
        } catch (err) {
          socket.close();
        }
      }
    }
  };

  socket.onclose = () => {
    if (remoteSocket) {
      try { remoteSocket.close(); } catch (_) {}
    }
  };

  socket.onerror = (e) => {
    console.error("WS Error:", e);
    if (remoteSocket) {
      try { remoteSocket.close(); } catch (_) {}
    }
  };

  return response;
};

async function pipeRemoteToWs(remote: Deno.Conn, ws: WebSocket) {
  const buffer = new Uint8Array(16 * 1024); // 16KB buffer
  try {
    while (true) {
      const n = await remote.read(buffer);
      if (n === null) break; // EOF
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(buffer.subarray(0, n));
      } else {
        break;
      }
    }
  } catch (err) {
    // console.error("Pipe error:", err);
  } finally {
    ws.close();
    try { remote.close(); } catch (_) {}
  }
}

function processVlessHeader(buffer: Uint8Array, expectedUUID: string) {
  if (buffer.length < 24) return null;

  // 1. Check Version (0)
  if (buffer[0] !== 0) return null;

  // 2. Check UUID
  const uuidBytes = buffer.subarray(1, 17);
  const uuidHex = [...uuidBytes].map(b => b.toString(16).padStart(2, "0")).join("");

  if (uuidHex !== expectedUUID) {
    return null;
  }

  // 3. Addons Length
  const addonsLen = buffer[17];
  let cursor = 18 + addonsLen;

  if (cursor >= buffer.length) return null;

  // 4. Command (1 = TCP, 2 = UDP)
  const command = buffer[cursor];
  cursor++;

  // 5. Port
  const port = (buffer[cursor] << 8) | buffer[cursor + 1];
  cursor += 2;

  // 6. Address Type
  const addrType = buffer[cursor];
  cursor++;

  let address = "";
  if (addrType === 1) { // IPv4
    address = buffer.subarray(cursor, cursor + 4).join(".");
    cursor += 4;
  } else if (addrType === 2) { // Domain
    const domainLen = buffer[cursor];
    cursor++;
    const domainBytes = buffer.subarray(cursor, cursor + domainLen);
    address = new TextDecoder().decode(domainBytes);
    cursor += domainLen;
  } else if (addrType === 3) { // IPv6
    // Skip IPv6
    cursor += 16;
    return null;
  } else {
    return null;
  }

  return {
    address,
    port,
    command,
    rawDataIndex: cursor
  };
}
