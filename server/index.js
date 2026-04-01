const express = require("express");
const crypto = require("crypto");

const app = express();
const PORT = process.env.PORT || 3000;
const AUTH_TOKEN = process.env.AUTH_TOKEN || null;

// topic -> Message[]
const messages = new Map();
// topic -> Set<res>
const subscribers = new Map();

const MAX_MESSAGES = 100;
const MAX_AGE_S = 86400; // 24h

app.use(express.text({ type: "*/*" }));

// CORS
app.use((req, res, next) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

// Auth
function auth(req, res, next) {
  if (!AUTH_TOKEN) return next();
  const header = req.headers.authorization || "";
  if (header === `Bearer ${AUTH_TOKEN}`) return next();
  res.status(401).json({ error: "Unauthorized" });
}

function pruneMessages(topic) {
  const list = messages.get(topic);
  if (!list) return;
  const cutoff = Math.floor(Date.now() / 1000) - MAX_AGE_S;
  const pruned = list.filter((m) => m.time >= cutoff);
  if (pruned.length > MAX_MESSAGES) pruned.splice(0, pruned.length - MAX_MESSAGES);
  messages.set(topic, pruned);
}

function parseSince(since) {
  if (!since) return 0;
  const match = since.match(/^(\d+)(s|m|h)$/);
  if (!match) return 0;
  const n = parseInt(match[1]);
  const unit = match[2];
  const multiplier = { s: 1, m: 60, h: 3600 };
  return n * (multiplier[unit] || 1);
}

// POST /publish/:topic
app.post("/publish/:topic", auth, (req, res) => {
  const { topic } = req.params;
  const title = req.headers["title"] || "";
  const tags = req.headers["tags"] ? req.headers["tags"].split(",").map((t) => t.trim()) : [];
  const body = typeof req.body === "string" ? req.body : "";

  const msg = {
    id: crypto.randomUUID(),
    event: "message",
    time: Math.floor(Date.now() / 1000),
    title,
    message: body,
    tags,
  };

  if (!messages.has(topic)) messages.set(topic, []);
  messages.get(topic).push(msg);
  pruneMessages(topic);

  // Broadcast to SSE subscribers
  const subs = subscribers.get(topic);
  if (subs) {
    const data = JSON.stringify(msg);
    for (const client of subs) {
      client.write(`data: ${data}\n\n`);
    }
  }

  res.json(msg);
});

// GET /sse/:topic
app.get("/sse/:topic", auth, (req, res) => {
  const { topic } = req.params;

  res.set({
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });
  res.flushHeaders();

  if (!subscribers.has(topic)) subscribers.set(topic, new Set());
  subscribers.get(topic).add(res);

  // Keep-alive every 30s
  const keepAlive = setInterval(() => res.write(": keepalive\n\n"), 30000);

  req.on("close", () => {
    clearInterval(keepAlive);
    const subs = subscribers.get(topic);
    if (subs) {
      subs.delete(res);
      if (subs.size === 0) subscribers.delete(topic);
    }
  });
});

// GET /poll/:topic?since=10s
app.get("/poll/:topic", auth, (req, res) => {
  const { topic } = req.params;
  const sinceSeconds = parseSince(req.query.since);
  const cutoff = sinceSeconds > 0 ? Math.floor(Date.now() / 1000) - sinceSeconds : 0;

  pruneMessages(topic);
  const list = messages.get(topic) || [];
  const filtered = list.filter((m) => m.time >= cutoff);

  // Return newline-delimited JSON (same format as ntfy)
  const lines = filtered.map((m) => JSON.stringify(m)).join("\n");
  res.set("Content-Type", "application/x-ndjson");
  res.send(lines);
});

app.listen(PORT, () => {
  console.log(`macbook-notify-server running on port ${PORT}`);
});
