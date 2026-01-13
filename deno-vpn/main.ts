
import { serveDir } from "https://deno.land/std@0.220.1/http/file_server.ts";
import { crypto } from "https://deno.land/std@0.220.1/crypto/mod.ts";

const PORT = 8000;
const ENV_UUID = Deno.env.get("UUID") || "8f91b6a0-e8ee-4497-b08e-8e9935147575"; // Default UUID
const TROJAN_PASSWORD = Deno.env.get("TROJAN_PASSWORD") || ENV_UUID; // Use UUID as Trojan password by default

console.log(`Server running on http://localhost:${PORT}`);
console.log(`UUID/Secret: ${ENV_UUID}`);

Deno.serve({ port: PORT }, async (req) => {
  const url = new URL(req.url);

  // 1. Handle WebSocket Upgrade (VPN Traffic)
  if (req.headers.get("upgrade") === "websocket") {
    return handleWebSocket(req, url.pathname);
  }

  // 2. Serve Static Files (Dashboard)
  // Check if we are in a deployment where we can read files, otherwise serve from memory string?
  // For Deno Deploy, reading from "public" works if included in deployment.
  // We use serveDir for simplicity.
  return serveDir(req, {
    fsRoot: "./public",
    urlRoot: "",
    showDirListing: false,
    enableCors: true,
  });
});

async function handleWebSocket(req: Request, path: string) {
  const { socket, response } = Deno.upgradeWebSocket(req);

  // Determine protocol based on path or try to detect?
  // Standard V2Ray path conventions are flexible.
  // We will support /vless and /trojan explicitly,
  // or default to VLESS on other paths if header matches.

  const protocol = path.startsWith("/trojan") ? "trojan" : "vless";

  socket.onopen = () => {
    // console.log(`[${protocol}] Client connected`);
  };

  let isHeaderProcessed = false;
  let remoteSocket: Deno.Conn | null = null;

  socket.onmessage = async (event) => {
    if (!(event.data instanceof ArrayBuffer)) return; // Binary only
    const data = new Uint8Array(event.data);

    if (!isHeaderProcessed) {
      try {
        let result = null;
        if (protocol === "vless") {
          result = processVlessHeader(data, ENV_UUID);
        } else if (protocol === "trojan") {
          result = await processTrojanHeader(data, TROJAN_PASSWORD);
        }

        if (!result) {
          console.error(`[${protocol}] Auth failed or Invalid Header`);
          socket.close();
          return;
        }

        const { address, port, rawDataIndex, command } = result;

        // Block UDP (Command 2 for VLESS, 3 for Trojan UDP ASSOCIATE)
        const isUdp = (protocol === "vless" && command === 2) || (protocol === "trojan" && command === 3);
        if (isUdp) {
             console.error(`[${protocol}] UDP not supported`);
             socket.close();
             return;
        }

        // console.log(`[${protocol}] Connecting to ${address}:${port}`);
        remoteSocket = await Deno.connect({ hostname: address, port });
        isHeaderProcessed = true;

        // Pipe Remote -> WS
        pipeRemoteToWs(remoteSocket, socket);

        // Forward initial payload
        if (rawDataIndex < data.length) {
           await remoteSocket.write(data.subarray(rawDataIndex));
        }

      } catch (err) {
        console.error(`[${protocol}] Connection Error: ${err}`);
        socket.close();
      }
    } else {
      // Forward WS -> Remote
      if (remoteSocket) {
        try {
          await remoteSocket.write(data);
        } catch (_) {
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

  return response;
}

async function pipeRemoteToWs(remote: Deno.Conn, ws: WebSocket) {
  const buf = new Uint8Array(16 * 1024);
  try {
    while (true) {
      const n = await remote.read(buf);
      if (n === null) break;
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(buf.subarray(0, n));
      } else {
        break;
      }
    }
  } catch (_) {
    // ignore
  } finally {
    ws.close();
    try { remote.close(); } catch (_) {}
  }
}

// --- VLESS PARSER ---
function processVlessHeader(buffer: Uint8Array, uuid: string) {
  if (buffer.length < 24) return null;

  const expectedUUID = uuid.replace(/-/g, "").toLowerCase();

  // 1. Version
  if (buffer[0] !== 0) return null;

  // 2. UUID Validation
  const uuidBytes = buffer.subarray(1, 17);
  const uuidHex = [...uuidBytes].map(b => b.toString(16).padStart(2, "0")).join("");
  if (uuidHex !== expectedUUID) return null;

  // 3. Addons
  const addonsLen = buffer[17];
  let cursor = 18 + addonsLen;
  if (cursor >= buffer.length) return null;

  // 4. Command
  const command = buffer[cursor++];

  // 5. Port
  const port = (buffer[cursor] << 8) | buffer[cursor + 1];
  cursor += 2;

  // 6. Address
  const addrType = buffer[cursor++];
  let address = "";

  if (addrType === 1) { // IPv4
    address = buffer.subarray(cursor, cursor + 4).join(".");
    cursor += 4;
  } else if (addrType === 2) { // Domain
    const len = buffer[cursor++];
    const domainBytes = buffer.subarray(cursor, cursor + len);
    address = new TextDecoder().decode(domainBytes);
    cursor += len;
  } else if (addrType === 3) { // IPv6
    // Simplification: We don't fully support IPv6 string parsing here yet
    // Just skip bytes and return null or try to connect?
    // Deno.connect handles IPv6 strings, but we need to parse bytes to string.
    cursor += 16;
    return null;
  } else {
    return null;
  }

  return { address, port, command, rawDataIndex: cursor };
}

// --- TROJAN PARSER ---
async function processTrojanHeader(buffer: Uint8Array, password: string) {
  if (buffer.length < 58) return null; // Min length estimate

  // Trojan Protocol:
  // hex(SHA224(password)) + CR + LF + Cmd + AddrType + Addr + Port + CRLF + Payload

  // 1. Calculate SHA224 of password
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest("SHA-224", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const expectedHashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

  // 2. Extract Hash from header (56 chars)
  const incomingHash = new TextDecoder().decode(buffer.subarray(0, 56));

  if (incomingHash.toLowerCase() !== expectedHashHex) {
    return null;
  }

  // 3. Check CR LF (56, 57)
  if (buffer[56] !== 0x0d || buffer[57] !== 0x0a) return null;

  let cursor = 58;

  // 4. Command (1=CONNECT, 3=ASSOCIATE)
  const command = buffer[cursor++];

  // 5. Address Type
  const addrType = buffer[cursor++];
  let address = "";

  if (addrType === 1) { // IPv4
    address = buffer.subarray(cursor, cursor + 4).join(".");
    cursor += 4;
  } else if (addrType === 3) { // Domain
    const len = buffer[cursor++];
    const domainBytes = buffer.subarray(cursor, cursor + len);
    address = new TextDecoder().decode(domainBytes);
    cursor += len;
  } else if (addrType === 4) { // IPv6
     cursor += 16;
     return null;
  } else {
    return null;
  }

  // 6. Port
  const port = (buffer[cursor] << 8) | buffer[cursor + 1];
  cursor += 2;

  // 7. Payload starts after CRLF
  if (buffer[cursor] === 0x0d && buffer[cursor+1] === 0x0a) {
      cursor += 2;
  } else {
      return null;
  }

  return { address, port, command, rawDataIndex: cursor };
}
