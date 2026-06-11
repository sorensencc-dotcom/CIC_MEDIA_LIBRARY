const fs = require("fs");
const path = require("path");
const http = require("http");
const { validateEnv } = require("./validate-startup");

const ROOT = process.env.CIC_ROOT || path.dirname(path.dirname(__filename));
const INVENTORY = path.join(ROOT, "metadata", "master_media_inventory.csv");
const ENTITY_GRAPH = path.join(ROOT, "metadata", "entity_graph.json");
const ARCHIVE_DIR = path.join(ROOT, "metadata");
const REPORTS_DIR = path.join(ROOT, "reports");

// Structured logging (production-safe: no stack traces in logs)
const isDev = process.env.NODE_ENV === "development";
const log = (level, msg, data = {}) => {
  const timestamp = new Date().toISOString();
  const logEntry = {
    timestamp,
    level,
    message: msg,
    service: "cic-mcp-server",
    ...data,
  };
  // Scrub stack traces in production (WIL-001 fix)
  if (!isDev && logEntry.stack) {
    delete logEntry.stack;
  }
  console.log(JSON.stringify(logEntry));
};

// CSV parser — simple, handles quoted fields
function parseCSV(csv) {
  const lines = csv.trim().split("\n");
  if (lines.length === 0) return [];

  const headers = lines[0].split(",").map(h => h.trim());
  const rows = [];

  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split(",").map(v => v.trim());
    const row = {};
    headers.forEach((h, idx) => {
      row[h] = values[idx] || "";
    });
    rows.push(row);
  }
  return rows;
}

function readJson(filePath) {
  try {
    if (!fs.existsSync(filePath)) return {};
    const content = fs.readFileSync(filePath, "utf8");
    return JSON.parse(content);
  } catch (e) {
    log("warn", "json_read_error", { file: filePath, error: e.message });
    return {};
  }
}

function readCsv(filePath) {
  try {
    if (!fs.existsSync(filePath)) return [];
    const content = fs.readFileSync(filePath, "utf8");
    return parseCSV(content);
  } catch (e) {
    log("warn", "csv_read_error", { file: filePath, error: e.message });
    return [];
  }
}

const tools = {
  query_inventory: ({ filters }) => {
    try {
      const rows = readCsv(INVENTORY);
      if (!filters || Object.keys(filters).length === 0) {
        return {
          status: "ok",
          count: rows.length,
          records: rows,
        };
      }

      const filtered = rows.filter(r =>
        Object.entries(filters).every(([k, v]) => {
          const cellVal = String(r[k] || "").toLowerCase();
          const filterVal = String(v).toLowerCase();
          return cellVal.includes(filterVal);
        })
      );

      log("info", "inventory_query_executed", {
        total: rows.length,
        filtered: filtered.length,
        filters: Object.keys(filters)
      });

      return {
        status: "ok",
        count: filtered.length,
        total_in_inventory: rows.length,
        records: filtered,
      };
    } catch (e) {
      log("error", "query_inventory_failed", { error: e.message });
      return {
        status: "error",
        error: e.message,
        records: [],
      };
    }
  },

  search_entity_graph: ({ entity }) => {
    try {
      const graph = readJson(ENTITY_GRAPH);
      const entities = graph.entities || [];
      const needle = (entity || "").toLowerCase();

      const results = entities.filter(e =>
        String(e.name || "").toLowerCase().includes(needle) ||
        String(e.aliases || "").toLowerCase().includes(needle)
      );

      log("info", "entity_graph_search_executed", {
        query: entity,
        total_entities: entities.length,
        matches: results.length,
      });

      return {
        status: "ok",
        query: entity,
        results,
        relationships: graph.relationships || [],
      };
    } catch (e) {
      log("error", "search_entity_graph_failed", { error: e.message });
      return {
        status: "error",
        error: e.message,
        results: [],
      };
    }
  },

  get_archive_results: ({ date }) => {
    try {
      const files = fs.readdirSync(ARCHIVE_DIR)
        .filter(f => f.startsWith("archive_results_") && f.endsWith(".json"));

      if (files.length === 0) {
        return {
          status: "ok",
          records: [],
          message: "no archive results found",
        };
      }

      let target = files[files.length - 1]; // Latest
      if (date) {
        target = files.find(f => f.includes(date)) || target;
      }

      const content = fs.readFileSync(path.join(ARCHIVE_DIR, target), "utf8");
      const results = JSON.parse(content);

      log("info", "archive_results_retrieved", {
        file: target,
        records: Array.isArray(results) ? results.length : Object.keys(results).length,
      });

      return {
        status: "ok",
        source_file: target,
        records: results,
        retrieved_at: new Date().toISOString(),
      };
    } catch (e) {
      log("error", "get_archive_results_failed", { error: e.message });
      return {
        status: "error",
        error: e.message,
        records: [],
      };
    }
  },

  get_gaps_report: () => {
    try {
      const files = fs.readdirSync(REPORTS_DIR)
        .filter(f => (f.includes("gap") || f.includes("Gap")) &&
                     (f.endsWith(".md") || f.endsWith(".txt")))
        .sort()
        .reverse();

      if (files.length === 0) {
        return {
          status: "ok",
          content: "",
          message: "no gaps report found",
        };
      }

      const latest = files[0];
      const content = fs.readFileSync(path.join(REPORTS_DIR, latest), "utf8");

      log("info", "gaps_report_retrieved", {
        file: latest,
        size_chars: content.length,
      });

      return {
        status: "ok",
        source_file: latest,
        content,
        retrieved_at: new Date().toISOString(),
      };
    } catch (e) {
      log("error", "get_gaps_report_failed", { error: e.message });
      return {
        status: "error",
        error: e.message,
        content: "",
      };
    }
  },

  get_system_health: () => {
    try {
      const inventory = readCsv(INVENTORY);
      const graph = readJson(ENTITY_GRAPH);
      const archiveFiles = fs.readdirSync(ARCHIVE_DIR)
        .filter(f => f.startsWith("archive_results_"));

      return {
        status: "ok",
        inventory_records: inventory.length,
        entity_graph_nodes: (graph.entities || []).length,
        archive_query_results: archiveFiles.length,
        last_updated: new Date().toISOString(),
      };
    } catch (e) {
      log("error", "get_system_health_failed", { error: e.message });
      return {
        status: "error",
        error: e.message,
      };
    }
  },
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
        log("warn", "unknown_tool_requested", {
          tool,
          availableTools: Object.keys(tools)
        });
        res.writeHead(400);
        return res.end(JSON.stringify({
          error: "unknown_tool",
          available: Object.keys(tools)
        }));
      }

      log("info", "tool_execute_start", {
        tool,
        paramsKeys: Object.keys(params || {})
      });

      const result = tools[tool](params || {});
      const duration = Date.now() - startTime;

      log("info", "tool_execute_end", {
        tool,
        duration_ms: duration,
        status: result.status
      });

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        result,
        duration_ms: duration,
        tool,
        timestamp: new Date().toISOString(),
      }));
    } catch (e) {
      const duration = Date.now() - startTime;
      const errorLog = {
        error: e.message,
        duration_ms: duration,
      };
      // Include stack only in dev (WIL-001 fix)
      if (isDev) {
        errorLog.stack = e.stack;
      }
      log("error", "tool_execute_error", errorLog);
      res.writeHead(500);
      res.end(JSON.stringify({ error: e.message }));
    }
  });
});

// Validate startup before listening (WIL-004 fix)
const validatedEnv = validateEnv();

const PORT = parseInt(validatedEnv.MCP_PORT, 10);
server.listen(PORT, () => {
  log("info", "mcp_server_started", {
    port: PORT,
    tools: Object.keys(tools),
    cic_root: ROOT,
    env: validatedEnv.NODE_ENV,
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

process.on("SIGINT", () => {
  log("info", "sigint_received");
  server.close(() => {
    log("info", "server_closed");
    process.exit(0);
  });
});
