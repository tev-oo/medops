# MedOps — Monitoring, Observability, and Alerting

## Overview

MedOps uses Prometheus, Grafana, and Alertmanager to observe its Django REST API, PostgreSQL database, and Debian deployment host. Prometheus collects metrics, evaluates alerting rules, and sends firing/resolved alerts to Alertmanager. Alertmanager delivers notifications through Gmail SMTP.

**Environment:** Debian 13 Vagrant VM (`medops-node01`), Docker Compose application and monitoring projects. Source-controlled configuration lives in this repository; credentials are provisioned separately on the VM.

**Status at last validation (November 3, 2026):** Four of four Prometheus scrape targets reported `up=1`; the Grafana dashboard contained 12 panels; three alert rules were healthy; synthetic rule unit tests passed; Gmail FIRING and RESOLVED messages were received. These are point-in-time checks, not a guarantee of present health.

## Architecture

```text
Debian host (medops-node01)
│
├── Application Compose project: medops
│   ├── web: Django REST API + Gunicorn (2 workers)
│   │   ├── /api/health/ — health check
│   │   └── /metrics — authenticated Prometheus endpoint
│   └── db: PostgreSQL 17 (persistent named volume)
│
└── Monitoring Compose project: medops-monitoring
    ├── prometheus — metrics scraping, retention, alert evaluation
    ├── node-exporter — CPU, memory, disk, uptime
    ├── postgres-exporter — PostgreSQL metrics
    ├── grafana — provisioned dashboards
    └── alertmanager — alert routing and Gmail notifications
```

Prometheus and PostgreSQL Exporter share the external `medops_default` Docker network with the application. All dashboard/monitoring web ports are bound to Debian loopback rather than published on the VM's external interfaces.

### Network endpoints

| Component | Endpoint on Debian | Purpose |
|---|---|---|
| MedOps API | `127.0.0.1:8000` | Health/API, plus token-protected `/metrics` |
| Prometheus | `127.0.0.1:9090` | Queries, targets, alert rules |
| Grafana | `127.0.0.1:3000` | Dashboards |
| Alertmanager | `127.0.0.1:9093` | Alert status and routing |

Access the UIs from the Arch workstation through SSH port forwarding. For example, in a terminal in the local repository root:

```bash
ssh -F .vagrant/ssh-config -N \
  -L 127.0.0.1:3000:127.0.0.1:3000 \
  -L 127.0.0.1:9090:127.0.0.1:9090 \
  -L 127.0.0.1:9093:127.0.0.1:9093 \
  default
```

Open `http://localhost:3000`, `http://localhost:9090`, and `http://localhost:9093` as needed.

## Source-controlled configuration

| Path | Responsibility |
|---|---|
| `compose.yaml` | Django and PostgreSQL services; metrics credential mount for `web` |
| `monitoring/compose.yaml` | Prometheus, exporters, Grafana, Alertmanager and networks |
| `monitoring/prometheus/prometheus.yml` | Scrape jobs, rule-file references, Alertmanager target |
| `monitoring/prometheus/alert-rules.yml` | Availability and disk alerts |
| `monitoring/prometheus/alert-rules.test.yml` | Synthetic alert-rule tests |
| `monitoring/grafana/dashboards/medops-infrastructure.json` | 12-panel dashboard |
| `monitoring/grafana/provisioning/` | Grafana data source and dashboard provisioning |
| `monitoring/alertmanager/alertmanager.yml` | Alert routing, Gmail SMTP, and notification templates |
| `config/metrics_auth.py` | Bearer-token protection for `/metrics` |
| `config/settings.py`, `config/urls.py` | Django metrics middleware and endpoint |
| `gunicorn.conf.py`, `scripts/start-web.sh` | Gunicorn multiprocess metric collection and startup |
| `.github/workflows/ci.yml` | Application, image-build, and Prometheus-rule CI checks |

The Git-provisioned dashboard is **MedOps — Infrastructure Overview**, UID `ad2shf2`, with data source UID `medops-prometheus`. The Grafana *Working Copy* is for GUI edits; export **Classic JSON**, replace the tracked dashboard JSON, retain UID `ad2shf2`, set `id` to `null`, and deploy through Git/Ansible.

## Prometheus scrape jobs

| Job | Target | What it measures |
|---|---|---|
| `prometheus` | `prometheus:9090` | Prometheus itself |
| `medops-node` | `node-exporter:9100` | Debian CPU, RAM, filesystem and uptime |
| `medops-postgres` | `postgres-exporter:9187` | Database availability, connections, transactions and size |
| `medops-django` | `web:8000/metrics` | Request throughput, HTTP status metrics and latency |

`medops-django` uses an HTTP Bearer token loaded from a file. Its Django endpoint is **not** intended for unauthenticated access. Gunicorn runs two workers; shared Prometheus multiprocess files are initialized by `scripts/start-web.sh` and worker-exit cleanup is configured in `gunicorn.conf.py`.

Prometheus is configured for a 15-second scrape interval and evaluation interval, with TSDB retention constrained to seven days and 512 MB. This is a local lab retention policy, not a long-term archive.

## Grafana dashboard: 12 panels

**Infrastructure (4):** CPU Usage, Memory Usage, Disk Usage, Server Uptime.

**PostgreSQL (4):** PostgreSQL Availability, Database Connections, Transactions per Second, Database Size.

**Django (4):** Django HTTP Request Rate, Django HTTP 5xx Error Rate, Django P95 Response Latency, Django API Availability.

Examples of the deployed PromQL expressions:

```promql
# Django scrape health
up{job="medops-django"}

# HTTP requests per second
sum(rate(django_http_requests_before_middlewares_total{job="medops-django"}[5m]))

# HTTP 5xx responses per second
sum(rate(django_http_responses_total_by_status_total{job="medops-django",status=~"5.."}[5m])) or vector(0)

# P95 request latency (seconds)
histogram_quantile(0.95, sum by (le) (
  rate(django_http_requests_latency_including_middlewares_seconds_bucket{job="medops-django"}[5m])
))
```

A zero error rate can mean no observed errors during the selected window; assess it alongside scrape health and request traffic. Quantile readings require enough observations to be meaningful.

## Alerting rules

| Alert | Trigger | `for` | Severity |
|---|---|---|---|
| `MedOpsDjangoDown` | `up{job="medops-django"} == 0` | 2m | Critical |
| `MedOpsPostgreSQLDown` | Exporter scrape down **or** `pg_up == 0` | 2m | Critical |
| `MedOpsDiskUsageHigh` | Root ext4 filesystem usage >85% | 5m | Warning |

Rules are evaluated by Prometheus, then firing/resolved states are routed to Alertmanager. The configured route groups by alert name and severity, waits 30 seconds to group initial alerts, uses a 5-minute group interval, and repeats firing notifications after four hours (subject to Alertmanager behavior and config).

**Tested:** `promtool test rules` synthetic scenarios cover both PostgreSQL failure modes, Django availability and disk threshold/timing. These tests do **not** stop production services.

## Gmail notifications and secret management

Alertmanager uses `smtp.gmail.com:587` with STARTTLS and a Google App Password, not the Gmail account password. The email integration has `send_resolved: true`; a synthetic `MedOpsGmailTest` demonstrated receipt of both FIRING and RESOLVED emails on November 3, 2026.

Never commit, print, or share the Gmail App Password, the Django metrics Bearer token, or the PostgreSQL exporter password. They are mounted read-only from Debian paths outside the Git working tree:

| Debian host path | Mounted inside container | Purpose |
|---|---|---|
| `/opt/medops-secrets/gmail_app_password` | `/run/secrets/gmail_app_password` | Alertmanager Gmail SMTP |
| `/opt/medops-secrets/medops_metrics_token` | `/run/secrets/medops_metrics_token` | Django/Prometheus Bearer token |
| `/opt/medops-secrets/pg_monitor_password` | `/run/secrets/pg_monitor_password` | PostgreSQL exporter |

The first two secret files were configured with ownership UID 0, GID 65534 and mode `640`. The secret directory is protected. Container permissions and group memberships must remain compatible with the mounts.

To verify permissions without exposing contents:

```bash
sudo stat -c '%u %g %a %n' \
  /opt/medops-secrets/gmail_app_password \
  /opt/medops-secrets/medops_metrics_token
```

Avoid including SMTP credentials in logs, diagnostics, GitHub Actions, screenshots or support tickets. Rotate/revoke an App Password if exposed, then safely update the host secret and recreate only Alertmanager.

## Operations and verification

All commands below run **inside Debian**, in `/opt/medops`, unless otherwise stated.

```bash
cd /opt/medops

# App and database health
sudo docker compose ps
curl -fsS http://127.0.0.1:8000/api/health/

# Monitoring services
sudo docker compose -f monitoring/compose.yaml -p medops-monitoring ps

# Inspect all scrape jobs
for job in prometheus medops-node medops-postgres medops-django; do
  curl -fsSG --data-urlencode "query=up{job=\"$job\"}" \
    http://127.0.0.1:9090/api/v1/query \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print([x["value"][1] for x in d["data"]["result"]])'
done

# Loaded alert rule status
curl -fsS 'http://127.0.0.1:9090/api/v1/rules?type=alert' \
  | python3 -m json.tool

# Alertmanager connectivity and readiness
curl -fsS http://127.0.0.1:9090/api/v1/alertmanagers \
  | python3 -m json.tool
curl -fsS -o /dev/null -w 'Alertmanager HTTP %{http_code}\n' \
  http://127.0.0.1:9093/-/ready

# Focused email notification metrics
curl -fsS http://127.0.0.1:9093/metrics \
  | grep -E '^alertmanager_notifications_(total|failed_total)\{integration="email"'
```

`up=1` indicates a successful scrape, not necessarily that every application request succeeds. Alertmanager delivery counters indicate attempts and failures, while actual inbox receipt is a separate verification.

### Configuration validation (Arch workstation)

```bash
cd ~/Projects/medops

docker compose -f monitoring/compose.yaml -p medops-monitoring config --quiet

docker run --rm --entrypoint /bin/promtool \
  -v "$PWD/monitoring/prometheus:/etc/prometheus:ro" \
  prom/prometheus:v3.15.1 \
  test rules /etc/prometheus/alert-rules.test.yml

docker run --rm --entrypoint /bin/promtool \
  -v "$PWD/monitoring/prometheus:/etc/prometheus:ro" \
  prom/prometheus:v3.15.1 \
  check rules /etc/prometheus/alert-rules.yml

# Config lint only; smtp password is not required for this check
docker run --rm --entrypoint /bin/amtool \
  -v "$PWD/monitoring/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager:v0.29.0 \
  check-config /etc/alertmanager/alertmanager.yml
```

For `promtool check config` of the **full** Prometheus YAML, mount a temporary dummy Bearer-token file at `/run/secrets/medops_metrics_token`; otherwise `promtool` fails because the referenced credentials file is absent. Use the real secret only on Debian.

## Deployment workflow

1. Edit monitoring configuration on **Arch** and validate YAML, `promtool`, `amtool`, and Git whitespace checks.
2. Commit and push to `main`; confirm the applicable GitHub Actions jobs pass.
3. Update `/opt/medops` with the existing Ansible playbook from Arch:

   ```bash
   ansible-playbook -i 'default,' \
     --ssh-common-args='-F .vagrant/ssh-config' \
     ansible/playbooks/deploy-medops.yml \
     -e "medops_version=$(git rev-parse HEAD)"
   ```

4. Verify the deployed Git revision and any required secret files **before** recreating services.
5. Apply only the changed monitoring service, for example:

   ```bash
   cd /opt/medops
   sudo docker compose -f monitoring/compose.yaml \
     -p medops-monitoring up -d --no-deps --force-recreate alertmanager
   ```

6. Verify readiness, API status, container logs, scrape targets, alert rules, and—when changing notifications—test email delivery.

The Ansible playbook updates source; it does not automatically recreate Docker services. Recreating monitoring services does not require removing the database volume. **Never use `docker compose down -v` in the application deployment.**

## Troubleshooting guide

| Symptom | Check |
|---|---|
| `medops-django` scrape is down (`up=0`) | Prometheus target `lastError`, Django logs, `DJANGO_ALLOWED_HOST` includes `web`, network reachability, Bearer token mount |
| Django `/metrics` returns `404` | Expected without correct Bearer token; check the secret path and authentication middleware |
| Django `/metrics` returns `400` from Prometheus | Verify Django `ALLOWED_HOSTS` includes `web` (request host `web:8000`) |
| PostgreSQL exporter up but `pg_up=0` | Database connectivity and read-only monitor role/secret |
| Dashboard is missing new panels | Confirm JSON UID `ad2shf2`, file provisioned in Grafana, and deployed commit is current; Grafana periodically rescans provisioning files |
| Alert rules missing | Verify `rule_files` path and bind mount; inspect `/api/v1/rules?type=alert` |
| No Gmail notifications | Verify receiver routing, active alert lifecycle, App Password secret, Alertmanager logs and `alertmanager_notifications_*{integration="email"}` metrics; check Inbox/All Mail/Spam |
| Alertmanager fails after config update | Run `amtool check-config`, verify token file mount/permissions, inspect container logs; revert the Git config if necessary |

Useful logs:

```bash
sudo docker compose logs --tail=50 web
sudo docker compose -f monitoring/compose.yaml -p medops-monitoring logs --tail=50 prometheus
sudo docker compose -f monitoring/compose.yaml -p medops-monitoring logs --tail=50 alertmanager
```

## Validation evidence and limitations

- Monitoring checked with four scrape jobs returning `up=1`.
- Deployed Grafana dashboard validated with UID `ad2shf2` and 12 panels (application, PostgreSQL, infrastructure).
- Three alert rules loaded with `health: ok`; unit tests passed via `promtool test rules`.
- Alertmanager v0.29.0 reported ready and was listed as an active Prometheus Alertmanager endpoint.
- Gmail SMTP notification counters reported one email send with zero failures during the initial firing test; both FIRING and RESOLVED messages were subsequently observed in Gmail.
- Metrics and monitoring interfaces are loopback-bound on the Debian VM, but users with forwarded or host-level access should still be trusted; `/metrics` has additional Bearer-token protection.
- This is a single-node lab deployment: monitoring and notification delivery may be unavailable during a full VM outage, and no external uptime probe is configured. Synthetic alert tests validate rule behavior, not a complete real-world incident response.

## Future improvements

- Add an external availability check or independent monitoring host for full-VM outages.
- Add a disk-space *prediction* alert and a separate low-free-inodes alert.
- Add CI validation for Alertmanager config and full Prometheus config (using non-secret test credentials).
- Pin currently `latest` monitoring images to tested versions or digests.
- Review alert thresholds, runbooks, metrics retention and backup requirements before any production use.
