#!/usr/bin/env node
// Workflow validation: check PowerShell script existence + RON syntax (WIL-008 fix)

const fs = require("fs");
const path = require("path");

const WORKFLOW_DIR = path.join(__dirname, "..", ".wayland", "workflows");
const SCRIPTS_DIR = path.join(__dirname);

// WIL-008 fix: Simple RON syntax validation instead of brittle regex
function validateRonSyntax(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  let parenCount = 0;
  let bracketCount = 0;
  let inString = false;
  let escapeNext = false;

  for (let i = 0; i < content.length; i++) {
    const char = content[i];

    if (escapeNext) {
      escapeNext = false;
      continue;
    }

    if (char === "\\") {
      escapeNext = true;
      continue;
    }

    if (char === '"') {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (char === "(") parenCount++;
    if (char === ")") parenCount--;
    if (char === "[") bracketCount++;
    if (char === "]") bracketCount--;

    if (parenCount < 0 || bracketCount < 0) {
      return { valid: false, error: "Unmatched closing bracket" };
    }
  }

  if (parenCount !== 0) {
    return { valid: false, error: `Unmatched parentheses (${parenCount > 0 ? "missing" : "extra"} closing parens)` };
  }

  if (bracketCount !== 0) {
    return { valid: false, error: `Unmatched brackets (${bracketCount > 0 ? "missing" : "extra"} closing brackets)` };
  }

  return { valid: true };
}

// Extract stages from RON (robust: looks for name + kind + args pattern, but doesn't require perfect regex)
function parseRonFile(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  const stages = [];

  // Find all stage blocks: (name: "...", kind: "shell", args: [...])
  const stageRegex = /\(\s*name:\s*"([^"]+)"[\s\S]*?kind:\s*"([^"]+)"[\s\S]*?args:\s*\[([^\]]+)\]/g;

  let match;
  while ((match = stageRegex.exec(content)) !== null) {
    const stageName = match[1];
    const kind = match[2];
    const argsStr = match[3];

    // Parse args array
    const args = argsStr
      .split(",")
      .map(s => s.trim().replace(/^["']|["']$/g, ""))
      .filter(s => s.length > 0);

    stages.push({ stageName, kind, args });
  }

  return stages;
}

function validateWorkflows() {
  const workflows = fs.readdirSync(WORKFLOW_DIR).filter(f => f.endsWith(".ron"));
  const results = { passed: 0, failed: 0, errors: [] };

  console.log("=== CIC Workflow Validation (WIL-008 compliant) ===\n");

  workflows.forEach(workflow => {
    const filePath = path.join(WORKFLOW_DIR, workflow);

    // Step 1: Validate RON syntax (WIL-008 fix)
    const syntaxCheck = validateRonSyntax(filePath);
    if (!syntaxCheck.valid) {
      results.failed++;
      results.errors.push({
        workflow,
        error: `RON syntax error: ${syntaxCheck.error}`,
      });
      console.error(`✗ ${workflow}: ${syntaxCheck.error}`);
      return;
    }

    // Step 2: Validate referenced scripts exist
    const stages = parseRonFile(filePath);

    stages.forEach(({ stageName, kind, args }) => {
      if (kind !== "shell") return; // Only validate shell stages

      const script = args[args.length - 1]; // Last arg is usually the script
      if (!script || !script.endsWith(".ps1")) return;

      // Strip "scripts/" prefix if present
      const scriptName = script.replace(/^scripts\//, "");
      const scriptPath = path.join(SCRIPTS_DIR, scriptName);

      if (!fs.existsSync(scriptPath)) {
        results.failed++;
        results.errors.push({
          workflow,
          stage: stageName,
          script: scriptName,
          error: "script_not_found",
        });
        console.error(`✗ ${workflow}: stage "${stageName}" references missing script "${scriptName}"`);
      } else {
        results.passed++;
        console.log(`✓ ${workflow}: stage "${stageName}" → ${scriptName} exists`);
      }
    });
  });

  console.log(`\n=== WORKFLOW VALIDATION SUMMARY ===`);
  console.log(`RON Syntax: ${workflows.length} files checked`);
  console.log(`Scripts: ${results.passed} passed, ${results.failed} failed`);

  if (results.failed > 0) {
    console.log("\nErrors:");
    results.errors.forEach(err => {
      console.log(`  - ${err.workflow}: ${err.error}`);
    });
    process.exit(1);
  } else {
    console.log("\n✓ All workflow validations passed");
    process.exit(0);
  }
}

validateWorkflows();
