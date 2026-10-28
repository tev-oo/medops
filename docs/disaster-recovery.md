# MedOps — PostgreSQL Disaster Recovery Runbook

## 1. Purpose

This runbook describes how to back up, verify, and restore the MedOps PostgreSQL database running in Docker Compose on Debian 13.

It covers logical database recovery using PostgreSQL custom-format dumps. It does not yet cover recovery from complete VM or physical host failure.

**Environment**

| Component | Configuration |
|---|---|
| Operating system | Debian 13 (Trixie) |
| Provisioning | Vagrant + VirtualBox |
| Configuration management | Ansible |
| Application directory | `/opt/medops` |
| Database | PostgreSQL 17 |
| Database name | `medops` |
| Backup directory | `/opt/medops/backups` |
| Backup service | `medops-backup.service` |
| Backup timer | `medops-backup.timer` |
| Schedule | Daily at 20:00 Africa/Nairobi |

## 2. Recovery objectives

**Recovery Point Objective (RPO):** Planning target of up to 24 hours of data loss under successful daily backups. This is not guaranteed if backups fail or the VM is unavailable.

**Recovery Time Objective (RTO):** Not yet established. Measure during a timed recovery exercise.

**Current limitations:**

- Backups are stored on the same VM as PostgreSQL.
- No off-host replication or backup copies are implemented.
- No automated backup retention policy is implemented.
- A complete VM-loss recovery has not yet been tested.
- Current restoration tests use synthetic appointment data only.

## 3. Backup operations

Run these commands on the Debian VM from `/opt/medops`, using a root shell or equivalent privileges.

### Check backup timer

```bash
systemctl status medops-backup.timer --no-pager
systemctl list-timers --all medops-backup.timer
```

### Trigger a manual backup

```bash
systemctl start medops-backup.service
systemctl show medops-backup.service -p Result -p ExecMainStatus
journalctl -u medops-backup.service -n 30 --no-pager
```

A successful execution reports `Result=success` and `ExecMainStatus=0`.

### List backup archives

```bash
ls -lh /opt/medops/backups/
```

Backups should have permission mode `600`, and the backup directory should have mode `700`.

### Verify backup archive readability

```bash
cd /opt/medops

LATEST=$(find backups -maxdepth 1 -type f \
  -name 'medops-*.dump' | sort | tail -n 1)

test -n "$LATEST" || {
  echo "ERROR: No backup archive found"
  exit 1
}

docker compose exec -T db pg_restore --list \
  < "$LATEST" > /dev/null \
  && echo "Backup archive readable"
```

This verifies that PostgreSQL can read the archive's table of contents. It is not a substitute for a complete restoration test.

## 4. Restore procedure — isolated test database

**Safety:** Never restore a test archive into the operational `medops` database. Use a new, empty database.

Ensure that the PostgreSQL container is healthy:

```bash
cd /opt/medops
docker compose ps
```

Select and validate the archive using the procedure in Section 3.

Create a new test database with a unique name:

```bash
docker compose exec -T db sh -c \
  'createdb -U "$POSTGRES_USER" medops_restore_verify'
```

This step should be performed only when the test database does not already exist.

Restore the archive:

```bash
docker compose exec -T db sh -c \
  'pg_restore \
    -U "$POSTGRES_USER" \
    -d medops_restore_verify \
    --no-owner \
    --no-privileges \
    --exit-on-error' < "$LATEST"
```

Confirm the record count:

```bash
docker compose exec -T db sh -c \
  'psql -U "$POSTGRES_USER" \
  -d medops_restore_verify \
  -Atc "SELECT COUNT(*) FROM appointments_appointment;"'
```

Verify the Django migration history:

```bash
docker compose exec -T db sh -c \
  'psql -U "$POSTGRES_USER" \
  -d medops_restore_verify \
  -Atc "SELECT COUNT(*) FROM django_migrations;"'
```

Compare the restored content against the state of the original database at backup time. Comparing against a live database after additional writes may produce legitimate differences.

## 5. Verified disaster-recovery exercise

**Date:** October 28, 2026

**Source database:** `medops`

**Restored database:** `medops_restore_drill2`

**Backup archive:** `medops-20261028T112454Z.dump`

**Outcome:**

| Verification | Result |
|---|---|
| Backup systemd service | Success |
| PostgreSQL archive readable | Passed |
| `pg_restore --exit-on-error` | Passed |
| Source appointments | 3 |
| Restored appointments | 3 |
| Django migrations restored | 19 |
| Appointment content checksum | Match |

**Content checksum:**

```text
01071de83ef68c750ea15f5bba6bf5c6
```

Both databases returned the same checksum using a deterministic, ID-ordered serialization of appointment rows.

This verifies recovery of the tested appointment records within the same PostgreSQL instance. It does not establish cryptographic backup authenticity or guarantee full-system recovery.

## 6. Operational safeguards

- Do not run `docker compose down -v` during recovery; it can delete the PostgreSQL data volume.
- Never overwrite the operational database during a practice restore.
- Protect database credentials and backup archives from unauthorized access.
- Check systemd logs after unsuccessful backups.
- Treat backup success and restore success as separate checks.
- Preserve a known-good archive before attempting destructive recovery actions.
- Avoid placing secrets or real patient information in GitHub documentation.

## 7. Future improvements

- Introduce an automated backup retention policy.
- Copy encrypted backups to storage outside the VM.
- Perform a complete recovery onto a new Debian VM.
- Measure and document recovery duration.
- Add scheduled restore verification and failure alerts.
- Document full production recovery steps after testing them in a disposable environment.

## 8. Recovery exercise log

Record future tests with the date, archive name, restoration target, record count, validation result, elapsed time, and any errors encountered.

Update this runbook whenever backup scripts, deployment paths, database versions, or recovery procedures change.
