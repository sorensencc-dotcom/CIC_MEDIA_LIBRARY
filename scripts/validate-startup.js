#!/usr/bin/env node
// Startup validation: check required environment variables before launching Wayland

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
};

function validateEnv() {
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

  if (warnings.length > 0) {
    console.warn("⚠️  Warnings:");
    warnings.forEach(w => console.warn(`  - ${w}`));
  }

  console.log("✅ All validations passed\n");
  return validated;
}

// Auto-run if invoked directly
if (require.main === module) {
  validateEnv();
}

module.exports = { validateEnv };
