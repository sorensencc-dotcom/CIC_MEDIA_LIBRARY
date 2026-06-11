# Skill Contribution Pipeline

**Status:** Design Spec  
**Phase:** 28.2 (Proposed)  
**Date:** 2026-06-11

---

## Problem

Skills adopted into workflow improve over time:
- Bug fixes
- Performance optimizations  
- Feature additions
- Test coverage gains
- Better error handling

Currently: improvements stay local. Upstream creators miss value. Community doesn't benefit.

**Goal:** Automatic feedback loop — detect local improvements, submit PRs upstream, track acceptance, notify contributor.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Skills Manifest (~/.claude/skills/manifest.json)            │
│ Tracks: adopted skills, source repos, versions              │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Change Detection (Periodic or On-Demand)                     │
│ Compares local skill vs upstream HEAD                        │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Contribution Agent                                           │
│ Generates: PR title, description, commit message            │
│ Creates: GitHub PR to upstream                              │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Status Tracker                                               │
│ Polls: GitHub API for PR status (open/merged/closed)        │
│ Stores: PR metadata + acceptance/rejection reason           │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Notification Engine                                          │
│ Channels: Slack, Teams, SMS/iMessage (Phase 2)              │
│ Events: Submission, merge, close/rejection                  │
└─────────────────────────────────────────────────────────────┘
```

---

## MVP Scope (Phase 28.2a)

### 1. Skills Manifest

**File:** `~/.claude/skills/manifest.json`

```json
{
  "version": "1.0",
  "lastUpdated": "2026-06-11T00:00:00Z",
  "skills": [
    {
      "id": "fewer-permission-prompts",
      "name": "Fewer Permission Prompts",
      "localPath": "~/.claude/skills/fewer-permission-prompts.md",
      "sourceRepo": {
        "url": "https://github.com/anthropics/claude-skills",
        "branch": "main",
        "remotePath": "skills/fewer-permission-prompts.md",
        "lastSyncCommit": "a1b2c3d"
      },
      "localModified": false,
      "modifications": []
    },
    {
      "id": "improvement-analysis",
      "name": "Improvement Analysis",
      "localPath": "~/.claude/skills/improvement-analysis.md",
      "sourceRepo": {
        "url": "https://github.com/anthropics/claude-skills",
        "branch": "main",
        "remotePath": "skills/improvement-analysis.md",
        "lastSyncCommit": "x9y8z7w"
      },
      "localModified": true,
      "modifications": [
        {
          "type": "perf-optimization",
          "description": "Parallel transcript scanning, 3x faster",
          "dateModified": "2026-06-05"
        }
      ]
    }
  ]
}
```

### 2. Diff Detection Agent

**Triggered:** Daily (cron) or on-demand (`/skill-check-upstream`)

**Logic:**
1. For each skill in manifest:
   - Clone/fetch upstream repo (GitHub only, MVP)
   - Git diff: `upstream/branch:remotePath` vs `localPath`
   - If diff exists, mark `localModified: true`
   - Store diff summary + metadata

2. Report:
   ```
   ✓ Skill: fewer-permission-prompts — no changes
   ⚠ Skill: improvement-analysis — 47 LOC changed (perf-optimization)
   ⚠ Skill: permission-audit — 12 LOC changed (bug-fix)
   ```

### 3. Contribution Agent

**Triggered:** On-demand via `/skill-contribute <skill-id>` or auto on >threshold change

**Flow:**
1. Load diff + skill metadata
2. Auto-generate:
   - **PR Title:** `[skill-name] {type}: {summary}` (e.g., `[improvement-analysis] perf: parallel transcript scanning`)
   - **PR Description:**
     ```markdown
     ## Summary
     {user-provided or auto-inferred description}
     
     ## Changes
     - {bullet points from diff}
     
     ## Testing
     {reference to local tests or validation}
     
     ## Metrics (if applicable)
     - Performance: {e.g., 3x faster}
     - Coverage: {test additions}
     - LOC: +47
     
     ---
     *Contributed via [Skill Contribution Pipeline](https://github.com/your-org/skill-pipeline)*
     ```
   - **Commit Message:**
     ```
     {type}({skill-name}): {summary}
     
     {detailed description from PR body}
     
     Contributed-By: Skill Pipeline <pipeline@skill-contrib.dev>
     ```

3. Create GitHub branch: `contrib/skill-{name}-{date}`
4. Commit diff
5. Create PR (GitHub API)
6. Store PR metadata locally: `~/.claude/skills/contributions/{skill-id}-{pr-number}.json`

### 4. Status Tracker

**File:** `~/.claude/skills/contributions/` (per-contribution metadata)

```json
{
  "skillId": "improvement-analysis",
  "skillName": "Improvement Analysis",
  "prNumber": 42,
  "upstreamRepo": "https://github.com/anthropics/claude-skills",
  "prUrl": "https://github.com/anthropics/claude-skills/pull/42",
  "status": "open",
  "createdAt": "2026-06-05T10:30:00Z",
  "lastChecked": "2026-06-11T08:15:00Z",
  "author": "soren",
  "type": "perf-optimization",
  "description": "Parallel transcript scanning, 3x faster",
  "valueFlag": false,
  "notificationSent": true
}
```

**Polling:** Daily, update status from GitHub API
- Open → no action
- Merged → celebrate, tag as success
- Closed (not merged) → log reason (if available), tag as closed
- Stale (>30 days) → escalate notification

### 5. Notification Engine (MVP: Slack only)

**Channel:** Dedicated Slack channel or thread

**Events:**

| Event | Trigger | Message |
|-------|---------|---------|
| **Submitted** | PR created | "📤 Contribution submitted: `[skill-name] {type}`\nPR: {url}\nChanges: +{LOC} -{LOC}" |
| **Merged** | PR merged | "✅ Contribution merged! `{skill-name}` accepted upstream.\nPR: {url}" |
| **Closed** | PR closed without merge | "❌ Contribution closed: `{skill-name}`\nReason: {comment from maintainer, if available}\nPR: {url}" |
| **Stale** | PR >30d no activity | "⏱️ Contribution pending: `{skill-name}` waiting {days} days.\nPR: {url}\nAction: follow up or close?" |

---

## Phase 2 (Deferred)

- [ ] Multi-repo support (GitLab, Gitea, Gitea)
- [ ] Valuation heuristics (flag "extremely valuable" contributions for licensing negotiation)
- [ ] SMS/iMessage notifications (Twilio integration)
- [ ] Automated quality gates (require tests, min coverage %, perf benchmarks)
- [ ] License & CLA handling (detect CLA requirement, auto-sign or escalate)
- [ ] Contribution acceptance analytics (success rate per repo, feedback patterns)

---

## Open Questions (Design Refinement)

1. **Auth:** GitHub token storage?
   - Option A: `.env` + secrets manager
   - Option B: OAuth callback
   - **Deferred to Phase 2 design**

2. **Change Detection:** Manual flag vs automatic?
   - Option A: User explicitly marks changes in manifest
   - Option B: Git diff triggers auto-detection
   - **MVP: Manual flag, auto-diff validation**

3. **Contribution Filtering:** Auto-submit all or curate first?
   - Option A: Auto-submit all diffs >threshold
   - Option B: Auto-generate PR draft, user reviews before submit
   - **MVP: Auto-submit; user can reject post-merge**

4. **Skipped Skills:** Mark non-contributing skills?
   - Some skills adopted but never modified. Skip in checks?
   - **MVP: Include all; report "no changes" for visibility**

---

## Implementation Roadmap

### Phase 28.2a: MVP Foundation
- [ ] Manifest schema + CLI (`/skill-manifest`)
- [ ] Change detection agent + diff report
- [ ] GitHub PR creation agent
- [ ] Status tracker (GitHub API polling)
- [ ] Slack notification engine
- [ ] Initial skill registration (fewer-permission-prompts, improvement-analysis)

### Phase 28.2b: Hardening & Automation
- [ ] Cron scheduling for daily diff checks
- [ ] CLA/licensing detection
- [ ] Acceptance analytics
- [ ] Error handling for repo unavailable / auth failures

### Phase 28.3+: Expansion
- [ ] Multi-repo hosts
- [ ] Valuation & licensing negotiation
- [ ] SMS/iMessage channels
- [ ] Quality gates

---

## References

- [[phase-28-1-docker-complete]] — Docker infrastructure foundation
- [[skills-policy-agent-requirement]] — Skill governance
- [[permission-audit-skill]] — Permission management skill
- [[improvement-analysis-skill]] — Session audit & gap detection

---

## Success Criteria

- ✓ MVP deployed in Phase 28.2a (by 2026-06-18)
- ✓ 2+ skills registered and monitored
- ✓ Slack notifications working (submission → status updates)
- ✓ At least 1 successful upstream PR merged
- ✓ Zero auth/credential leaks (secrets properly stored)
