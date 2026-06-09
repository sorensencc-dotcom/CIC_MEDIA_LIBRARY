#!/usr/bin/env node
// Workflow validation: check PowerShell script existence before scheduling

const fs = require("fs");
const path = require("path");

const WORKFLOW_DIR = path.join(__dirname, "..", ".wayland", "workflows");
const SCRIPTS_DIR = path.join(__dirname);

function parseRonFile(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  // Simple extraction: find all shell/kind stages with args containing .ps1
  const shellStages = content.match(/name:\s*"([^"]+)"[\s\S]*?kind:\s*"shell"[\s\S]*?args:\s*\[([^\]]+)\]/g) || [];
  const stages = [];

  shellStages.forEach(match => {
    const nameMatch = match.match(/name:\s*"([^"]+)"/);
    const argsMatch = match.match(/args:\s*\[([^\]]+)\]/);
    if (nameMatch && argsMatch) {
      const stageName = nameMatch[1];
      const args = argsMatch[1]
        .split(",")
        .map(s => s.trim().replace(/["\[\]]/g, ""))
        .filter(Boolean);

      stages.push({ stageName, args });
    }
  });

  return stages;
}

function validateWorkflows() {
  const workflows = fs.readdirSync(WORKFLOW_DIR).filter(f => f.endsWith(".ron"));
  const results = { passed: 0, failed: 0, errors: [] };

  workflows.forEach(workflow => {
    const filePath = path.join(WORKFLOW_DIR, workflow);
    const stages = parseRonFile(filePath);

    stages.forEach(({ stageName, args }) => {
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

  console.log(`\n=== WORKFLOW VALIDATION ==`);
  console.log(`Passed: ${results.passed}`);
  console.log(`Failed: ${results.failed}`);

  if (results.failed > 0) {
    console.log("\nMissing scripts:");
    results.errors.forEach(err => {
      console.log(`  - ${err.workflow}: ${err.script}`);
    });
    process.exit(1);
  } else {
    console.log("\n✓ All workflow scripts present");
    process.exit(0);
  }
}

validateWorkflows();
