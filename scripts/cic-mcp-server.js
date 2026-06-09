const fs = require("fs");
const path = require("path");
const http = require("http");

const tools = {
  query_inventory: ({ filters }) => ({
    status: "ok",
    count: 0,
    message: "query_inventory stub (awaiting real API)",
  }),
  search_entity_graph: ({ entity }) => ({
    status: "ok",
    results: [],
    message: "search_entity_graph stub",
  }),
  get_archive_results: ({ date }) => ({
    status: "ok",
    records: 0,
    message: "get_archive_results stub",
  }),
  get_gaps_report: () => ({
    status: "ok",
    gaps: 0,
    message: "get_gaps_report stub",
  }),
};

const server = http.createServer((req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405);
    return res.end("POST only");
  }
  let body = "";
  req.on("data", chunk => (body += chunk));
  req.on("end", () => {
    try {
      const msg = JSON.parse(body || "{}");
      const { tool, params } = msg;
      if (!tool || !tools[tool]) {
        res.writeHead(400);
        return res.end(JSON.stringify({ error: "unknown_tool" }));
      }
      const result = tools[tool](params || {});
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ result }));
    } catch (e) {
      res.writeHead(500);
      res.end(JSON.stringify({ error: e.message }));
    }
  });
});

server.listen(7010, () => {
  console.log("CIC MCP server listening on 7010");
  console.log("Available tools: query_inventory, search_entity_graph, get_archive_results, get_gaps_report");
});

// Keep alive for 10 seconds in Docker
setTimeout(() => {
  console.log("MCP server shutting down");
  process.exit(0);
}, 10000);
