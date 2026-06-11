#!/usr/bin/env node
// Startup validation: check required environment variables before launching Wayland

const fs = require("fs");
const path = require("path");
const https = require("https");

// V1.1: Check webhook reachability
function checkWebhookReachable(url) {
  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      resolve({ reachable: false, reason: "timeout" });
    }, 5000);

    https.get(url, { method: "HEAD" }, (res) => {
      clearTimeout(timeout);
      // Slack returns 200 or 3xx for valid webhooks
      resolve({ reachable: res.statusCode >= 200 && res.statusCode < 400, reason: null });
    }).on("error", (err) => {
      clearTimeout(timeout);
      resolve({ reachable: false, reason: err.message });
    });
  });
}

// V1.1: Check filesystem permissions (scripts executable, log dir writable)
function checkFilesystemPermissions() {
  const errors = [];
  const warnings = [];
  const SCRIPTS_DIR = path.join(__dirname);
  const LOG_DIR = path.join(__dirname, "..", "metadata");

  // Check if scripts directory exists
  if (!fs.existsSync(SCRIPTS_DIR)) {
    errors.push(`Scripts directory not found: ${SCRIPTS_DIR}`);
    return { errors, warnings };
  }

  // Check key scripts are executable (try to read)
  const keyScripts = ["cic-mcp-server.js", "validate-workflows.js"];
  for (const script of keyScripts) {
    const scriptPath = path.join(SCRIPTS_DIR, script);
    if (!fs.existsSync(scriptPath)) {
      warnings.push(`Key script missing: ${script}`);
    } else {
      try {
        fs.accessSync(scriptPath, fs.constants.R_OK);
      } catch {
        errors.push(`Script not readable: ${script}`);
      }
    }
  }

  // Check log directory is writable
  if (fs.existsSync(LOG_DIR)) {
    try {
      fs.accessSync(LOG_DIR, fs.constants.W_OK);
    } catch {
      warnings.push(`Log directory not writable: ${LOG_DIR}`);
    }
  } else {
    warnings.push(`Log directory does not exist: ${LOG_DIR}`);
  }

  return { errors, warnings };
}

const REQUIRED_VARS = {
  SLACK_WEBHOOK_MAIN: {
    description: "Primary Slack webhook URL",
    pattern: /^https:\/\/hooks\.slack\.com\/services\//,
  },
  SLACK_WEBHOOK_ALERTS: {
    description: "Alerts Slack webhook URL",
    pattern: /^https:\/\/hooks\.slack\.com\/services\//,
  },
};

const OPTIONAL_VARS = {
  MCP_PORT: { default: "7010", description: "MCP server port" },
  NODE_ENV: { default: "production", description: "Node environment" },
  CIC_ROOT: { default: "auto-detect", description: "CIC root directory" },
  CIC_LOGS_BASE_URL: { default: "https://cic-logs", description: "Base URL for workflow logs" },
  RETRY_BACKOFF_MULTIPLIER: { default: "2", description: "Retry backoff multiplier" },
  RETRY_INITIAL_DELAY_MS: { default: "1000", description: "Initial retry delay (ms)" },
};

async function validateEnv() {
  const errors = [];
  const warnings = [];
  const validated = {};

  console.log("=== STARTUP VALIDATION ===\n");

  // Check required
  console.log("Required environment variables:");
  for (const [key, config] of Object.entries(REQUIRED_VARS)) {
    const value = process.env[key];
    if (!value) {
      errors.push(`${key}: MISSING`);
      console.log(`  ✗ ${key}: NOT SET`);
    } else if (config.pattern && !config.pattern.test(value)) {
      errors.push(`${key}: INVALID FORMAT`);
      console.log(`  ✗ ${key}: Invalid format (expected: ${config.pattern})`);
    } else {
      validated[key] = value;
      console.log(`  ✓ ${key}: set (${value.substring(0, 40)}...)`);
    }
  }

  // Check optional
  console.log("\nOptional environment variables:");
  for (const [key, config] of Object.entries(OPTIONAL_VARS)) {
    const value = process.env[key] || config.default;
    validated[key] = value;
    if (process.env[key]) {
      console.log(`  ✓ ${key}: ${value}`);
    } else {
      console.log(`  ◇ ${key}: using default (${value})`);
    }
  }

  console.log("");

  if (errors.length > 0) {
    console.error("❌ VALIDATION FAILED\n");
    console.error("Errors:");
    errors.forEach(e => console.error(`  - ${e}`));
    console.error("\nFix:");
    Object.entries(REQUIRED_VARS).forEach(([key]) => {
      if (!process.env[key]) {
        console.error(`  export ${key}="<value>"`);
      }
    });
    console.error("\nOr create .env file:");
    console.error("  cp .env.example .env");
    console.error("  # Edit .env with real webhook URLs");
    process.exit(1);
  }

  // V1.1: Check webhook reachability if required vars are set
  console.log("Webhook reachability check:");
  for (const [key] of Object.entries(REQUIRED_VARS)) {
    const webhookUrl = validated[key];
    if (webhookUrl && webhookUrl.startsWith("https://hooks.slack.com")) {
      const reachability = await checkWebhookReachable(webhookUrl);
      if (reachability.reachable) {
        console.log(`  ✓ ${key}: reachable`);
      } else {
        warnings.push(`${key}: unreachable (${reachability.reason})`);
        console.log(`  ⚠ ${key}: unreachable (${reachability.reason})`);
      }
    }
  }

  // V1.1: Check filesystem permissions
  console.log("\nFilesystem permissions check:");
  const fsCheck = checkFilesystemPermissions();
  if (fsCheck.errors.length > 0) {
    fsCheck.errors.forEach(e => {
      errors.push(`FS: ${e}`);
      console.log(`  ✗ ${e}`);
    });
  } else {
    console.log(`  ✓ Scripts readable`);
    console.log(`  ✓ Log directory accessible`);
  }

  fsCheck.warnings.forEach(w => {
    warnings.push(`FS: ${w}`);
    console.log(`  ⚠ ${w}`);
  });

  console.log("");

  // Re-check errors after filesystem validation
  if (errors.length > 0) {
    console.error("❌ VALIDATION FAILED\n");
    console.error("Errors:");
    errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }

  if (warnings.length > 0) {
    console.warn("⚠️  Warnings:");
    warnings.forEach(w => console.warn(`  - ${w}`));
  }

  console.log("✅ All validations passed\n");
  return validated;
}

// Auto-run if invoked directly
if (require.main === module) {
  validateEnv().catch(err => {
    console.error("Validation error:", err.message);
    process.exit(1);
  });
}

module.exports = { validateEnv };
