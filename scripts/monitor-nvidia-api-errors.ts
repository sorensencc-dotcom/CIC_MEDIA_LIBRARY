#!/usr/bin/env node

/**
 * NVIDIA API Error Monitor
 *
 * Monitors CIC service logs for NVIDIA API errors (404, 400, 401).
 * Useful for detecting deprecation issues after Sep 30, 2026.
 *
 * Usage:
 *   ts-node monitor-nvidia-api-errors.ts --service orchestrator --tail 100
 *   ts-node monitor-nvidia-api-errors.ts --service ingestion --since 1h
 *   ts-node monitor-nvidia-api-errors.ts --all --alert-threshold 5
 */

import fs from "fs";
import path from "path";

interface NvidiaErrorEvent {
  timestamp: string;
  service: string;
  statusCode: number;
  message: string;
  endpoint: string;
  suggestion: string;
}

interface MonitorConfig {
  services: string[];
  logPaths: Record<string, string>;
  errorCodes: number[];
  since?: Date;
  tail?: number;
  alertThreshold: number;
}

const DEFAULT_CONFIG: MonitorConfig = {
  services: ["orchestrator", "ingestion", "audit"],
  logPaths: {
    orchestrator: "/var/log/cic/orchestrator.log",
    ingestion: "/var/log/cic/ingestion.log",
    audit: "/var/log/cic/audit.log"
  },
  errorCodes: [400, 401, 404, 429, 500],
  alertThreshold: 5
};

/**
 * Parse NVIDIA API error from log line
 */
function parseNvidiaError(line: string): NvidiaErrorEvent | null {
  // Match patterns like:
  // "NIM error 404: ..."
  // "API error: 400 Bad Request"
  // "NVIDIA API returned 401 Unauthorized"

  const match404 = line.match(/(?:NIM|NVIDIA|API).*?\b404\b/i);
  const match400 = line.match(/(?:NIM|NVIDIA|API).*?\b400\b/i);
  const match401 = line.match(/(?:NIM|NVIDIA|API).*?\b401\b/i);
  const match429 = line.match(/(?:NIM|NVIDIA|API).*?\b429\b/i);
  const matchIntegrate = line.match(/integrate\.api\.nvidia\.com/i);

  if (!matchIntegrate) return null; // Not a NVIDIA API call

  let statusCode = 0;
  if (match404) statusCode = 404;
  else if (match400) statusCode = 400;
  else if (match401) statusCode = 401;
  else if (match429) statusCode = 429;
  else return null;

  const timestamp = extractTimestamp(line) || new Date().toISOString();
  const service = extractService(line) || "unknown";
  const suggestion = getSuggestion(statusCode, line);

  return {
    timestamp,
    service,
    statusCode,
    message: line.substring(0, 200), // First 200 chars
    endpoint: "https://integrate.api.nvidia.com/v1",
    suggestion
  };
}

/**
 * Extract timestamp from log line
 */
function extractTimestamp(line: string): string | null {
  const isoMatch = line.match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/);
  if (isoMatch) return isoMatch[0];

  const dateMatch = line.match(/\[(.+?)\]/);
  if (dateMatch) return dateMatch[1];

  return null;
}

/**
 * Extract service name from log line
 */
function extractService(line: string): string | null {
  if (line.includes("orchestrator")) return "orchestrator";
  if (line.includes("ingestion")) return "ingestion";
  if (line.includes("audit")) return "audit";
  return null;
}

/**
 * Get remediation suggestion based on error code
 */
function getSuggestion(statusCode: number, line: string): string {
  switch (statusCode) {
    case 404:
      if (line.includes("/teams/")) {
        return "CRITICAL: Team-scoped path detected. Update NIM_BASE_URL to global endpoint.";
      }
      return "Endpoint not found. Check NVIDIA API status and NIM_BASE_URL configuration.";

    case 400:
      return "Bad request. Verify model names and request payload match NVIDIA API schema.";

    case 401:
      return "Unauthorized. Check NIM_API_KEY is valid and not expired.";

    case 429:
      return "Rate limited. Implement backoff or increase quota with NVIDIA.";

    case 500:
      return "NVIDIA API server error. Check service status page.";

    default:
      return "Unknown error. Check NVIDIA API documentation.";
  }
}

/**
 * Monitor log file for errors
 */
function monitorLogFile(filePath: string, config: MonitorConfig): NvidiaErrorEvent[] {
  if (!fs.existsSync(filePath)) {
    console.warn(`Log file not found: ${filePath}`);
    return [];
  }

  try {
    const content = fs.readFileSync(filePath, "utf-8");
    const lines = content.split("\n");

    // Apply tail limit if set
    const linesToCheck = config.tail
      ? lines.slice(Math.max(0, lines.length - config.tail))
      : lines;

    const errors: NvidiaErrorEvent[] = [];

    for (const line of linesToCheck) {
      const error = parseNvidiaError(line);
      if (error && config.errorCodes.includes(error.statusCode)) {
        errors.push(error);
      }
    }

    return errors;
  } catch (err) {
    console.error(`Error reading ${filePath}:`, err);
    return [];
  }
}

/**
 * Format errors for display
 */
function formatReport(allErrors: NvidiaErrorEvent[]): string {
  if (allErrors.length === 0) {
    return "✅ No NVIDIA API errors detected in logs.";
  }

  let report = `⚠️  Found ${allErrors.length} NVIDIA API error(s):\n\n`;

  // Group by service
  const byService = new Map<string, NvidiaErrorEvent[]>();
  for (const err of allErrors) {
    if (!byService.has(err.service)) {
      byService.set(err.service, []);
    }
    byService.get(err.service)!.push(err);
  }

  // Format by service
  for (const [service, errors] of byService) {
    report += `## ${service.toUpperCase()} (${errors.length} errors)\n`;

    for (const err of errors) {
      report += `
  **${err.timestamp}** — HTTP ${err.statusCode}
  Message: ${err.message}
  Endpoint: ${err.endpoint}
  Action: ${err.suggestion}\n`;
    }

    report += "\n";
  }

  return report;
}

/**
 * Alert if threshold exceeded
 */
function checkAlert(errors: NvidiaErrorEvent[], threshold: number): void {
  if (errors.length >= threshold) {
    const criticalCount = errors.filter(e => e.statusCode === 404).length;
    if (criticalCount > 0) {
      console.error("\n🚨 CRITICAL ALERT: 404 errors detected from NVIDIA API!");
      console.error("   This may indicate team-scoped path deprecation or endpoint change.");
      console.error("   Verify NIM_BASE_URL and check NVIDIA API status immediately.");
    } else {
      console.warn(`\n⚠️  WARNING: ${errors.length} NVIDIA API errors (threshold: ${threshold})`);
    }
  }
}

/**
 * Main monitor function
 */
function main() {
  const args = process.argv.slice(2);
  const config = { ...DEFAULT_CONFIG };

  // Parse CLI args
  if (args.includes("--all")) {
    // Monitor all services (default)
  } else {
    const serviceIdx = args.indexOf("--service");
    if (serviceIdx !== -1 && args[serviceIdx + 1]) {
      config.services = [args[serviceIdx + 1]];
    }
  }

  const tailIdx = args.indexOf("--tail");
  if (tailIdx !== -1 && args[tailIdx + 1]) {
    config.tail = parseInt(args[tailIdx + 1], 10);
  }

  const thresholdIdx = args.indexOf("--alert-threshold");
  if (thresholdIdx !== -1 && args[thresholdIdx + 1]) {
    config.alertThreshold = parseInt(args[thresholdIdx + 1], 10);
  }

  // Collect errors from all services
  const allErrors: NvidiaErrorEvent[] = [];
  for (const service of config.services) {
    const logPath = config.logPaths[service];
    if (logPath) {
      const errors = monitorLogFile(logPath, config);
      allErrors.push(...errors);
    }
  }

  // Generate report
  const report = formatReport(allErrors);
  console.log(report);

  // Check alert threshold
  checkAlert(allErrors, config.alertThreshold);

  // Exit code
  if (allErrors.some(e => e.statusCode === 404)) {
    process.exit(2); // Critical error
  } else if (allErrors.length > 0) {
    process.exit(1); // Warning
  }
}

main();
