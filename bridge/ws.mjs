// Minimal RFC6455 WebSocket server (text frames only, no extensions).
// Enough for a local Godot client and keeps the bridge dependency-free.
import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const MAX_MESSAGE = 8 * 1024 * 1024;

export class WsConnection extends EventEmitter {
  constructor(socket) {
    super();
    this.socket = socket;
    this.buffer = Buffer.alloc(0);
    this.closed = false;
    this.fragments = [];
    this.fragmentOpcode = 0;
    socket.setNoDelay(true);
    socket.on("data", (chunk) => this._onData(chunk));
    socket.on("close", () => this._finish());
    socket.on("error", (err) => {
      this.emit("error", err);
      this._finish();
    });
  }

  _finish() {
    if (this.closed) return;
    this.closed = true;
    this.emit("close");
  }

  _onData(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (true) {
      const frame = this._readFrame();
      if (!frame) return;
      this._handleFrame(frame);
    }
  }

  _readFrame() {
    const buf = this.buffer;
    if (buf.length < 2) return null;
    const b0 = buf[0];
    const b1 = buf[1];
    const fin = (b0 & 0x80) !== 0;
    const opcode = b0 & 0x0f;
    const masked = (b1 & 0x80) !== 0;
    let length = b1 & 0x7f;
    let offset = 2;
    if (length === 126) {
      if (buf.length < offset + 2) return null;
      length = buf.readUInt16BE(offset);
      offset += 2;
    } else if (length === 127) {
      if (buf.length < offset + 8) return null;
      const big = buf.readBigUInt64BE(offset);
      if (big > BigInt(MAX_MESSAGE)) {
        this.close(1009, "message too large");
        return null;
      }
      length = Number(big);
      offset += 8;
    }
    let maskKey = null;
    if (masked) {
      if (buf.length < offset + 4) return null;
      maskKey = buf.subarray(offset, offset + 4);
      offset += 4;
    }
    if (buf.length < offset + length) return null;
    let payload = buf.subarray(offset, offset + length);
    if (maskKey) {
      const copy = Buffer.allocUnsafe(length);
      for (let i = 0; i < length; i++) copy[i] = payload[i] ^ maskKey[i & 3];
      payload = copy;
    }
    this.buffer = buf.subarray(offset + length);
    return { fin, opcode, payload };
  }

  _handleFrame({ fin, opcode, payload }) {
    switch (opcode) {
      case 0x0: // continuation
        this.fragments.push(payload);
        if (fin) {
          const full = Buffer.concat(this.fragments);
          const op = this.fragmentOpcode;
          this.fragments = [];
          this.fragmentOpcode = 0;
          if (op === 0x1) this.emit("message", full.toString("utf8"));
        }
        break;
      case 0x1: // text
      case 0x2: // binary (treated as utf8, not used)
        if (fin) {
          this.emit("message", payload.toString("utf8"));
        } else {
          this.fragmentOpcode = opcode;
          this.fragments = [payload];
        }
        break;
      case 0x8:
        this.close(1000, "");
        break;
      case 0x9:
        this._sendFrame(0xa, payload);
        break;
      case 0xa:
        break;
      default:
        break;
    }
  }

  send(obj) {
    if (this.closed) return false;
    const data = Buffer.from(typeof obj === "string" ? obj : JSON.stringify(obj), "utf8");
    return this._sendFrame(0x1, data);
  }

  _sendFrame(opcode, payload) {
    if (this.closed || this.socket.destroyed) return false;
    const len = payload.length;
    let header;
    if (len < 126) {
      header = Buffer.allocUnsafe(2);
      header[1] = len;
    } else if (len < 65536) {
      header = Buffer.allocUnsafe(4);
      header[1] = 126;
      header.writeUInt16BE(len, 2);
    } else {
      header = Buffer.allocUnsafe(10);
      header[1] = 127;
      header.writeBigUInt64BE(BigInt(len), 2);
    }
    header[0] = 0x80 | opcode;
    try {
      this.socket.write(Buffer.concat([header, payload]));
      return true;
    } catch {
      this._finish();
      return false;
    }
  }

  close(code = 1000, reason = "") {
    if (this.closed) return;
    const reasonBuf = Buffer.from(reason, "utf8");
    const payload = Buffer.allocUnsafe(2 + reasonBuf.length);
    payload.writeUInt16BE(code, 0);
    reasonBuf.copy(payload, 2);
    this._sendFrame(0x8, payload);
    this.closed = true;
    try {
      this.socket.end();
    } catch {
      /* ignore */
    }
    this.emit("close");
  }
}

export function attachWebSocketServer(server, onConnection) {
  server.on("upgrade", (req, socket) => {
    const upgrade = String(req.headers.upgrade || "").toLowerCase();
    const key = req.headers["sec-websocket-key"];
    if (upgrade !== "websocket" || !key) {
      socket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
      socket.destroy();
      return;
    }
    const accept = createHash("sha1").update(key + GUID).digest("base64");
    socket.write(
      "HTTP/1.1 101 Switching Protocols\r\n" +
        "Upgrade: websocket\r\n" +
        "Connection: Upgrade\r\n" +
        `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
    );
    const conn = new WsConnection(socket);
    onConnection(conn, req);
  });
}
