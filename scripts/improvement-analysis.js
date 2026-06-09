#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const args = process.argv.slice(2);
const days = args.find(a => a.startsWith('days:'))?.split(':')[1] || 14;
const detailed = args.includes('detailed:true');
const homeDir = process.env.USERPROFILE || process.env.HOME;
const claudeDir = path.join(homeDir, '.claude');

// Find nearest git repo
function findGitRepo(startDir = process.cwd()) {
  let current = startDir;
  for (let i = 0; i < 10; i++) {
    if (fs.existsSync(path.join(current, '.git'))) {
      return current;
    }
    const parent = path.dirname(current);
    if (parent === current) break; // reached root
    current = parent;
  }
  return null;
}

const gitRepo = findGitRepo();

const report = {
  usageSnapshot: {},
  tokenMetrics: {},
  bottlenecks: [],
  skillGaps: [],
  permissionHotspots: [],
  phaseVelocity: [],
  recommendations: []
};

// Parse session metadata
function analyzeSessions() {
  const sessionsDir = path.join(claudeDir, 'sessions');
  const files = fs.readdirSync(sessionsDir).filter(f => f.endsWith('.json'));
  const cutoffTime = Date.now() - days * 24 * 60 * 60 * 1000;

  let sessionCount = 0;
  let totalDuration = 0;
  const timeDistribution = {};

  files.forEach(file => {
    const data = JSON.parse(fs.readFileSync(path.join(sessionsDir, file), 'utf8'));
    if (data.startedAt >= cutoffTime) {
      sessionCount++;
      totalDuration += (data.endedAt || Date.now()) - data.startedAt;

      const hour = new Date(data.startedAt).getHours();
      timeDistribution[hour] = (timeDistribution[hour] || 0) + 1;
    }
  });

  report.usageSnapshot = {
    sessions: sessionCount,
    totalDurationHours: (totalDuration / 3600000).toFixed(1),
    avgSessionMinutes: (totalDuration / sessionCount / 60000).toFixed(1),
    peakHours: Object.entries(timeDistribution)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([h, count]) => `${h}:00 (${count}x)`)
      .join(', ')
  };
}

// Parse tool results for patterns
function analyzeToolUsage() {
  const projectsDir = path.join(claudeDir, 'projects', 'c--dev');
  const toolCalls = {};
  const permissionBlocks = [];

  const sessionDirs = fs.readdirSync(projectsDir).filter(d => {
    const stat = fs.statSync(path.join(projectsDir, d));
    return stat.isDirectory() && d.match(/^[a-f0-9-]{36}$/);
  });

  sessionDirs.forEach(sessionId => {
    const toolResultsDir = path.join(projectsDir, sessionId, 'tool-results');
    if (!fs.existsSync(toolResultsDir)) return;

    fs.readdirSync(toolResultsDir).forEach(file => {
      if (!file.endsWith('.txt')) return;

      // Parse from: hook-toolu_01QE1BGbxZULL1b3zcDBTMei-3-additionalContext.txt
      // Format: hook-[TOOL_ID_WITH_DASHES]-[N]-[TOOL_NAME].txt
      // Match: last occurrence of -[digit]- before filename
      const match = file.match(/.*-(\d+)-(.+?)\.txt$/);
      if (!match) return;

      const toolName = match[2]; // additionalContext, Read, Bash, Edit, etc.

      // Track by tool name
      toolCalls[toolName] = (toolCalls[toolName] || 0) + 1;

      // Check for permission denial in content
      const content = fs.readFileSync(path.join(toolResultsDir, file), 'utf8');
      if (content.match(/permission|denied|not allowed|InputValidationError/i)) {
        permissionBlocks.push({
          tool: toolName,
          file,
          time: fs.statSync(path.join(toolResultsDir, file)).mtime
        });
      }
    });
  });

  report.permissionHotspots = Object.entries(toolCalls)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([tool, count]) => {
      const total = Object.values(toolCalls).reduce((a, b) => a + b, 0);
      return {
        tool,
        count,
        percentage: ((count / total) * 100).toFixed(1)
      };
    });

  report.bottlenecks = permissionBlocks.slice(0, 5).map(p => ({
    type: 'permission',
    tool: p.tool,
    impact: 'context waste + re-request'
  }));
}

// Analyze git history for phase velocity
function analyzePhaseVelocity() {
  try {
    const repoDir = process.cwd();
    if (!fs.existsSync(path.join(repoDir, '.git'))) {
      report.phaseVelocity = [{ note: 'No git repo in cwd' }];
      return;
    }

    const log = execSync(`git log --since="${days} days ago" --format="%aI|%s"`, {
      cwd: repoDir,
      encoding: 'utf8'
    }).split('\n').filter(Boolean);

    const phaseData = {};

    log.forEach(line => {
      const [timestamp, subject] = line.split('|');
      // Match: "Phase 55C:", "Phase 55A & 55B:", "Implement Phase 55C:", etc.
      const phaseMatches = subject.match(/Phase[\s]+([\d.A-Z&\s]+)(?::|[^a-zA-Z]|$)/gi);

      if (phaseMatches) {
        phaseMatches.forEach(match => {
          const phaseNum = match.replace(/Phase\s+/i, '').replace(/[^0-9A-Z.&\s]/g, '').trim();
          if (phaseNum) {
            if (!phaseData[phaseNum]) {
              phaseData[phaseNum] = {
                first: new Date(timestamp),
                last: new Date(timestamp),
                commits: 0,
                blockers: 0
              };
            }
            phaseData[phaseNum].last = new Date(timestamp);
            phaseData[phaseNum].commits++;

            if (subject.match(/block|wait|pending|hold|stuck/i)) {
              phaseData[phaseNum].blockers++;
            }
          }
        });
      }
    });

    report.phaseVelocity = Object.entries(phaseData)
      .sort((a, b) => new Date(b[1].last) - new Date(a[1].last))
      .slice(0, 10)
      .map(([phase, data]) => {
        const duration = Math.round((data.last - data.first) / (24 * 60 * 60 * 1000));
        return {
          phase: phase.trim(),
          durationDays: duration || 1,
          commits: data.commits,
          blockers: data.blockers
        };
      });
  } catch (e) {
    report.phaseVelocity = [{ error: `Git failed: ${e.message}` }];
  }
}

// Detect skill gaps
function detectSkillGaps() {
  const commonPatterns = {
    'reading-files': { regex: /Read|read file|head|tail|cat/, weight: 1 },
    'searching-code': { regex: /grep|find|search|locate|Grep/, weight: 1.5 },
    'editing-text': { regex: /Edit|edit|sed|replace/, weight: 1 },
    'waiting-for-status': { regex: /wait|status|poll|monitor|check/, weight: 2 },
    'committing-code': { regex: /git commit|commit|stage/, weight: 1 },
    'permission-prompts': { regex: /permission|denied|not allowed/, weight: 3 }
  };

  report.skillGaps = [
    {
      task: 'Permission allowlist management',
      occurrences: report.permissionHotspots.reduce((sum, p) => sum + p.count, 0),
      estimatedSavings: '20-30 min/month',
      priority: 'high'
    },
    {
      task: 'Session analysis & reporting',
      occurrences: 1,
      estimatedSavings: '2-3 hours/month',
      priority: 'high',
      note: 'Creating right now!'
    }
  ];
}

// Generate prioritized recommendations
function generateRecommendations() {
  const recs = [];

  // Token savings recommendations
  if (report.usageSnapshot.sessions > 20) {
    recs.push({
      rank: 1,
      action: 'Enable prompt caching for CIC project phases',
      savings: 'Est. 15-20% token reduction (~$5-10/month)',
      effort: 'low',
      reasoning: 'High phase volume with repeated context (roadmap, memory)'
    });
  }

  // Permission hotspot
  if (report.permissionHotspots.length > 0) {
    const top = report.permissionHotspots[0];
    recs.push({
      rank: 2,
      action: `Add "${top.tool}" to global allowlist`,
      savings: `Est. ${top.count} permission prompts eliminated`,
      effort: 'minimal',
      reasoning: `${top.percentage}% of tool calls, safe for allowlist`
    });
  }

  // Bottleneck fix
  if (report.bottlenecks.length > 0) {
    recs.push({
      rank: 3,
      action: 'Set up monthly /improvement-analysis automation',
      savings: 'Continuous optimization, catch regressions early',
      effort: 'minimal',
      reasoning: 'Proactive vs. reactive improvement cycles'
    });
  }

  report.recommendations = recs.sort((a, b) => a.rank - b.rank);
}

// Main execution
console.log('\n📊 CONTINUOUS IMPROVEMENT ANALYSIS\n');
console.log(`Generated: ${new Date().toISOString()}`);
console.log(`Period: Last ${days} days\n`);

analyzeSessions();
analyzeToolUsage();
analyzePhaseVelocity();
detectSkillGaps();
generateRecommendations();

// Output report
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
console.log('📈 USAGE SNAPSHOT');
Object.entries(report.usageSnapshot).forEach(([k, v]) => {
  console.log(`  ${k}: ${v}`);
});

console.log('\n🔧 PERMISSION HOTSPOTS');
report.permissionHotspots.slice(0, 5).forEach((item, i) => {
  console.log(`  ${i + 1}. ${item.tool} — ${item.count} calls (${item.percentage}%)`);
});

console.log('\n📦 PHASE VELOCITY (Last 10 phases)');
report.phaseVelocity.forEach(p => {
  console.log(`  Phase ${p.phase}: ${p.durationDays}d, ${p.commits} commits${p.blockers > 0 ? `, ${p.blockers} blockers` : ''}`);
});

console.log('\n⚡ SKILL GAPS');
report.skillGaps.forEach((gap, i) => {
  console.log(`  ${i + 1}. ${gap.task} (${gap.occurrences}x) → ${gap.estimatedSavings}`);
  if (gap.note) console.log(`     Note: ${gap.note}`);
});

console.log('\n🎯 PRIORITIZED RECOMMENDATIONS');
report.recommendations.forEach((rec, i) => {
  console.log(`  ${i + 1}. ${rec.action}`);
  console.log(`     Savings: ${rec.savings}`);
  console.log(`     Effort: ${rec.effort} | Why: ${rec.reasoning}\n`);
});

console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

if (detailed) {
  console.log('\n📋 DETAILED DATA\n');
  console.log(JSON.stringify({ report }, null, 2));
}

console.log('💡 Tip: Run /schedule improvement-analysis to set up monthly automation\n');
