# Retry Policy & Logging Configuration

## WIL-006: Exponential Backoff (Retry Storm Prevention)

**Problem:** Immediate retries cause fast retry storms on transient failures.

**Solution:** Exponential backoff with jitter prevents thundering herd.

**Configuration:** `.wayland/retry-config.ron`

```
Retry sequence with backoff:
  Attempt 1: fail immediately
  Attempt 2: wait 1s, retry
  Attempt 3: wait 2s, retry
  Attempt 4: wait 4s, retry
  Attempt 5: wait 8s, retry (max_attempts=5 → stop)
```

**Implementation:** Wayland orchestrator applies retry policy automatically based on `retry_count` + `retry_config`.

**Jitter:** Add 10% random variance to prevent synchronized retries across workflows.

---

## WIL-007: Dynamic Log URLs (404 Prevention)

**Problem:** Hardcoded log URLs (https://cic-logs/...) point to undefined endpoint.

**Solution:** Configure base URL via environment variable, templates build complete URLs.

**Configuration:**

```bash
export CIC_LOGS_BASE_URL=https://logs.internal  # or https://cic-logs, etc.
```

**Slack Alert Template (Example):**
```
Workflow cic-daily-ingest FAILED at stage: classify.
Error: CSV parsing failed.
Logs: https://logs.internal/cic-daily-ingest/2026-06-09T03:00:00Z
```

**Validation:**

- Startup check: `CIC_LOGS_BASE_URL` must be set (non-empty string)
- Health check: HTTP GET to `$CIC_LOGS_BASE_URL/health` returns 200 (optional)
- Notification: If log URL returns 404, Slack alert includes fallback text

---

## Deployment

1. Set env var: `export CIC_LOGS_BASE_URL=<actual_url>`
2. Validate: `node scripts/validate-startup.js` (checks URL is set)
3. Test: Trigger a workflow failure, verify Slack alert includes working log URL

## Future

- **Logging Backend:** Implement https://logs.internal (Loki + Grafana or similar)
- **Health Check:** Add optional HTTP health check before sending Slack alerts
- **Archival:** Implement log retention + archival to S3 after `retention_days`
