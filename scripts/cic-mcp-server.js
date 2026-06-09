const fs = require("fs");
const path = require("path");
const http = require("http");

// Structured logging
const log = (level, msg, data = {}) => {
  const timestamp = new Date().toISOString();
  console.log(JSON.stringify({
    timestamp,
    level,
    message: msg,
    ...data,
  }));
};

const tools = {
  query_inventory: ({ filters }) => ({
    status: "ok",
    count: 0,
    message: "query_inventory stub (awaiting real API integration)",
  }),
  search_entity_graph: ({ entity }) => ({
    status: "ok",
    results: [],
    message: "search_entity_graph stub (awaiting real API integration)",
  }),
  get_archive_results: ({ date }) => ({
    status: "ok",
    records: 0,
    message: "get_archive_results stub (awaiting real API integration)",
  }),
  get_gaps_report: () => ({
    status: "ok",
    gaps: 0,
    message: "get_gaps_report stub (awaiting real API integration)",
  }),
};

const server = http.createServer((req, res) => {
  const startTime = Date.now();

  if (req.method !== "POST") {
    log("warn", "invalid_http_method", { method: req.method, path: req.url });
    res.writeHead(405);
    return res.end(JSON.stringify({ error: "POST only" }));
  }

  let body = "";
  req.on("data", chunk => (body += chunk));
  req.on("end", () => {
    try {
      const msg = JSON.parse(body || "{}");
      const { tool, params } = msg;

      if (!tool || !tools[tool]) {
        log("warn", "unknown_tool_requested", { tool, availableTools: Object.keys(tools) });
        res.writeHead(400);
        return res.end(JSON.stringify({ error: "unknown_tool", available: Object.keys(tools) }));
      }

      log("info", "tool_execute_start", { tool, paramsKeys: Object.keys(params || {}) });
      const result = tools[tool](params || {});
      const duration = Date.now() - startTime;

      log("info", "tool_execute_end", { tool, duration, status: result.status });
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ result, duration_ms: duration }));
    } catch (e) {
      const duration = Date.now() - startTime;
      log("error", "tool_execute_error", { error: e.message, duration, stack: e.stack });
      res.writeHead(500);
      res.end(JSON.stringify({ error: e.message }));
    }
  });
});

const PORT = process.env.MCP_PORT || 7010;
server.listen(PORT, () => {
  log("info", "mcp_server_started", {
    port: PORT,
    tools: Object.keys(tools),
    env: process.env.NODE_ENV || "development",
  });
});

// Graceful shutdown on signal
process.on("SIGTERM", () => {
  log("info", "sigterm_received");
  server.close(() => {
    log("info", "server_closed");
    process.exit(0);
  });
});
