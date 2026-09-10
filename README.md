# Booking platform - infrastructure and database reliability

Terraform for an ALB / ECS Fargate / RDS stack on AWS, plus a local Postgres
setup with seed data, an indexed reporting query, and backup and restore
scripts.

Nothing here is deployed to AWS. The Terraform is written to be applied for
real, but it is reviewed with `fmt`, `init`, `validate` and `plan`. The database
half genuinely runs: `docker compose up` gives you a seeded database in about
thirty seconds.

## Running the review

The Terraform lives one level down, per environment - there is no configuration
at the repo root, so run it from inside an environment directory:

```bash
cd infra/envs/dev          # then repeat in infra/envs/prod
terraform fmt
terraform init
terraform validate
terraform plan -refresh=false
```

`fmt` prints nothing when everything is already formatted. `validate` reports
the configuration is valid. `plan` reports **41 resources for dev, 45 for prod**,
and needs no AWS account - the provider runs in plan-only mode, explained under
[State](#state). `-var-file` is optional: each environment's variables carry the
same defaults as its tfvars.

The database half runs from the repo root:

```bash
docker compose up -d
./scripts/backup.sh
./scripts/restore.sh
```

`docker compose up -d` creates the schema, indexes and 50,000 seeded bookings
before it reports healthy. If port 5432 is already taken on your machine - a
local Postgres, another container - start it on a different host port instead;
nothing else changes, because both scripts talk to the database inside the
container:

```bash
HOST_PORT=5433 docker compose up -d
``` `backup.sh` writes a timestamped dump into
`./backups/` and verifies it can be read back. `restore.sh` loads that dump into
a brand new database and prints a row-by-row comparison against the source,
exiting non-zero if anything differs.

## Contents

```
infra/
  modules/
    network/          VPC, public and private subnets, NAT, route tables
    ecs/              ALB, target group, listener, cluster, task definition, service, IAM
    rds/              subnet group, security group, parameter group, Postgres instance
  envs/
    dev/              small, single AZ, 1 day of backups, no deletion protection
    prod/             larger, multi AZ, 30 days of backups, deletion protection on
db/
  migrations/         001_schema.sql, 002_indexes.sql
  seed/               seed.sql - 50,000 bookings, 58,735 events
  queries/            the Part 5 reporting query, with EXPLAIN
scripts/
  backup.sh           timestamped pg_dump, verified and checksummed
  restore.sh          restores into a fresh database and compares it to the source
docs/
  query-optimization.md   index choice, with before/after EXPLAIN output
.github/workflows/
  terraform.yml       fmt, init, validate, plan for both envs; plan posted on the PR
  database.yml        brings the stack up in CI and runs backup + restore
```

## Prerequisites

- Docker and Docker Compose v2 (`docker compose version`)
- Terraform >= 1.6 (developed against 1.9.8)
- bash, for the two scripts

No Postgres client is needed on the host. `psql`, `pg_dump` and `pg_restore` all
run inside the container.

---

# Part 1 and 2 - Terraform

## The stack

```
                 internet
                     |
            ALB (public subnets)          sg-alb    : 80 from 0.0.0.0/0
                     |                              : egress anywhere
             target group (ip)
                     |
        ECS Fargate tasks (private)       sg-tasks  : container port from sg-alb only
                     |                              : egress via NAT
              RDS Postgres (private)      sg-rds    : 5432 from sg-tasks only
                                                    : no CIDR ingress at all
```

Three security groups chained by reference, not by CIDR. The database rule is
`referenced_security_group_id = <task sg>`, so nothing outside the service can
reach 5432 even from inside the VPC, and the rule keeps working when tasks are
replaced and get new IPs. The instance is `publicly_accessible = false` in
private subnets with no route to the internet gateway, so there is no path in
from outside regardless of what the security group says.

Other things worth pointing at:

- **Credentials.** `manage_master_user_password = true` - RDS generates the
  master password and stores it in Secrets Manager. It never lands in Terraform
  state or a tfvars file. The ECS task definition pulls `DB_USER` and
  `DB_PASSWORD` out of that secret with the `arn:...:username::` syntax, and the
  task execution role is granted `secretsmanager:GetSecretValue` on that one
  secret rather than on `*`.
- **Two IAM roles, not one.** The execution role is what the ECS agent uses to
  pull images and resolve secrets. The task role is what the application itself
  would use. They are separate so that granting the app an S3 permission later
  does not also hand it to the agent.
- **NAT.** Fargate tasks need outbound access to pull images. Dev runs one NAT
  gateway to save money; prod runs one per AZ, because a single NAT means every
  task in the VPC loses egress when that AZ has a problem.
- **`aws_vpc_security_group_ingress_rule`** instead of inline `ingress` blocks -
  inline rules make Terraform fight with anything that touches the SG out of
  band, and a single rule change rewrites the whole group.

## Environment differences

Both environments call the same three modules. Only the inputs differ.

| | dev | prod |
|---|---|---|
| VPC CIDR | 10.20.0.0/16 | 10.10.0.0/16 |
| NAT gateways | 1, shared | 1 per AZ |
| Fargate task | 256 CPU / 512 MiB | 1024 CPU / 2048 MiB |
| Desired count | 1 | 3 |
| Log retention | 7 days | 90 days |
| RDS class | db.t4g.micro | db.m7g.large |
| Storage | 20 GB, autoscale to 50 | 100 GB, autoscale to 500 |
| Multi-AZ | no | yes |
| Backup retention | 1 day | 30 days |
| Deletion protection | off (RDS and ALB) | on (RDS and ALB) |
| Final snapshot | skipped | taken |
| `apply_immediately` | true | false, waits for the maintenance window |
| Performance Insights | off | on, with 30s enhanced monitoring |
| Container Insights | off | on |

Sizing lives in `envs/<env>/variables.tf` as defaults and in
`envs/<env>/<env>.tfvars` as the values actually used. Structural choices that
are not really tunable - Multi-AZ, deletion protection, whether the final
snapshot is taken - are set directly in `envs/<env>/main.tf`, so nobody can turn
prod's deletion protection off by editing a tfvars file.

## Reviewing it

```bash
cd infra
terraform fmt -check -recursive

cd envs/dev
terraform init
terraform validate
terraform plan -refresh=false -var-file=dev.tfvars

cd ../prod
terraform init
terraform validate
terraform plan -refresh=false -var-file=prod.tfvars
```

Expected: `dev` plans 41 resources, `prod` plans 45. No AWS account, no
credentials, no network access to AWS required.

That works because each environment's `providers.tf` runs the provider in
plan-only mode - dummy static keys and `skip_credentials_validation`,
`skip_requesting_account_id`, `skip_metadata_api_check`. The block is commented
to say so and lists exactly which lines to delete before a real apply. The same
reason there are no `aws_availability_zones` or `aws_caller_identity` data
sources anywhere: they would need a live API call at plan time. AZs are a plain
variable instead.

## State

`versions.tf` in each environment has the S3 backend block commented out, with
the real values sitting next to it in `backend.hcl`:

```hcl
bucket         = "tripare-tfstate-ap-south-1"
key            = "booking-platform/dev/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "tripare-tfstate-locks"
encrypt        = true
```

Uncomment `backend "s3" {}` and initialise with the partial config:

```bash
terraform init -backend-config=backend.hcl
```

It is left commented so this repo can be reviewed offline - an active S3 backend
would make `terraform init` fail on a machine that cannot reach that bucket. The
two environments use different state keys (and in a real account, different AWS
accounts) so a mistake in dev cannot touch prod state. The bucket and lock table
are created out of band, once, because bootstrapping state storage should not
depend on the state it is storing.

---

# Part 3 - GitHub Actions

`.github/workflows/terraform.yml` runs on pull requests that touch `infra/`:

1. `terraform fmt -check -recursive -diff` across the whole tree, as its own job.
2. A matrix over `dev` and `prod`, each running `init`, `validate` and
   `plan -refresh=false` against its own tfvars.
3. The plan is uploaded as an artifact (`tfplan-dev`, `tfplan-prod`) **and**
   posted as a PR comment. The comment carries a hidden marker per environment,
   so re-running the workflow updates the existing comment instead of adding a
   new one on every push.

The comment step trims to the last 60,000 characters if a plan is ever bigger
than a GitHub comment allows, and says so, pointing at the artifact for the
full output.

No AWS credentials are configured in the workflow - it inherits the same
plan-only provider mode. The step is commented with what a real pipeline would
put there instead: `aws-actions/configure-aws-credentials` with an OIDC role, so
no long-lived access keys ever live in GitHub secrets.

There is a second workflow, `database.yml`, that is not part of the assignment.
It shellchecks both scripts, brings the compose stack up, asserts the seed
loaded, asserts the planner still picks the covering index, then runs
`backup.sh` and `restore.sh`. It exists because a backup script nobody exercises
is a backup script that does not work.

---

# Part 4 and 5 - local database

## Start it

```bash
docker compose up -d
docker compose logs -f postgres     # optional, watch the seed run
```

The image is `postgres:16-alpine`. On first start, the files mounted into
`/docker-entrypoint-initdb.d/` run in order: schema, then indexes, then seed.
Postgres does not accept outside connections until they finish, so a healthy
container means the data is already there.

```
Seed complete:
 bookings | events | cities | orgs | statuses
----------+--------+--------+------+----------
    50000 |  58735 |      9 |    6 |        5
```

Those numbers are exact, not approximate. The seed derives every value from an
md5 hash of the row number rather than `random()`, so a rebuild produces
identical data and any figure quoted in this README can be re-checked.

To start over from an empty database:

```bash
docker compose down -v && docker compose up -d
```

Init scripts only run when the data volume is created, so `down -v` (which drops
the volume) is what forces a re-seed.

Connection details, all overridable through `.env` (see `.env.example`):

| | |
|---|---|
| host / port | `localhost:5432` |
| database | `bookings` |
| user | `bookings_app` |
| password | `local_dev_password` |

```bash
docker compose exec postgres psql -U bookings_app -d bookings
```

## Schema

`db/migrations/001_schema.sql` follows the schema in the brief with two
deliberate changes:

- **`created_at` is `timestamptz`, not `timestamp`.** Bookings arrive from
  several timezones and the reporting query is anchored to `NOW()`. A naive
  timestamp column drifts the moment the app server and the database disagree
  about local time, and the bug shows up as slightly wrong revenue numbers,
  which is the worst way to find out.
- **`booking_events.booking_id` has a real foreign key** with
  `ON DELETE CASCADE`. Events with no parent booking are garbage that nobody
  notices until a report is wrong.

Plus check constraints for the things that are always true: checkout after
checkin, non-negative amount, status from a known set.

## The reporting query

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

Index added for it:

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);
```

**`city` first, `created_at` second**, because a b-tree can only apply a range
bound to the column after the equality predicates. Reversed, the scan would have
to cover every city inside the time window and filter afterwards - measurably
worse, 32 index buffers instead of 7.

**`org_id`, `status` and `amount` as `INCLUDE` payload**, because they are never
searched on, only projected. Carrying them in the leaf pages makes this an
index-only scan: the aggregate is answered without touching the table at all.
Putting them in the key would enlarge the tree for no benefit, since nothing
sorts or searches by them.

Measured on the seeded 50,000 rows (3,018 of them match):

| | plan | buffers | time |
|---|---|---|---|
| before | Seq Scan, 46,982 rows discarded | 725 | 8.09 ms |
| after | Index Only Scan, `Heap Fetches: 0` | 41 | 1.30 ms |

The buffer count is the number that matters. On a laptop the whole table is
cached so the milliseconds understate it; on RDS with a working set larger than
`shared_buffers`, 725 page reads against 41, on a query a dashboard runs
constantly, is the difference.

Check it yourself:

```bash
docker compose exec postgres psql -U bookings_app -d bookings -f /work/db/queries/booking_rollup.sql
```

Full write-up, including the two index shapes that were tried and rejected and
why there is no partial index: [docs/query-optimization.md](docs/query-optimization.md).

---

# Part 6 - backup and restore

Both scripts run `pg_dump` / `pg_restore` inside the container, so nothing has
to be installed on the host except docker.

## Backup

```bash
./scripts/backup.sh
```

```
==> Backing up database 'bookings' from service 'postgres'
    file    : ./backups/bookings_20260910_224712.dump
    size    : 4.2M
    tables  : 2 with data
    verified: archive listing is readable
==> Backup complete
```

- Custom format (`-Fc`): compressed, selectively restorable, and listable
  without restoring.
- `--no-owner --no-privileges` so the dump can be restored as any role.
- After the dump, the script reads the archive back with `pg_restore --list`. A
  `pg_dump` that exits 0 can still leave a truncated file behind if the pipe
  broke; if the archive cannot be listed, the file is deleted and the script
  fails rather than leaving a bad backup that looks fine.
- Writes a `.sha256` next to the dump.
- Keeps the newest 7 dumps (`-k N` to change, `-k 0` to keep everything).
  Count-based rather than age-based on purpose: on a machine where the script
  has not run for a while, "delete anything older than N days" can leave you
  with nothing.

`-o <dir>` writes somewhere other than `./backups`.

## Restore

```bash
./scripts/restore.sh
```

With no arguments it takes the newest dump and restores it into a **new**
database called `bookings_restore_<timestamp>`. That is the point: the original
is untouched, so the two can be compared. Pass a dump path to pick a different
one, `-d <name>` to choose the target database, and `--force` to overwrite an
existing database (it asks first).

## How to verify the restore worked

The script does it and prints the evidence:

```
==> Restoring ./backups/bookings_20260910_224712.dump into database 'bookings_restore_20260910_225106'
    checksum: ok
    created empty database
    data loaded
    statistics rebuilt (VACUUM ANALYZE)

check              source (bookings)            restored (bookings_restore_20260910_225106)
------------------ ---------------------------- ----------------------------
hotel_bookings     50000                        50000
booking_events     58735                        58735
sum(amount)        2166272590.26                2166272590.26
max(created_at)    2026-09-10 17:12:44.208611+00 2026-09-10 17:12:44.208611+00
indexes            4                            4

==> Restore verified: the restored database matches the source on every check.
```

It compares five things, and exits non-zero on any mismatch:

- row counts in both tables - the obvious check, and the weakest one
- `sum(amount)` - row counts pass even if every amount came back NULL
- `max(created_at)` - catches a restore from an older dump than expected
- index count - a restore that drops the Part 5 index is a working database
  that is quietly slow
- the sha256 of the dump, before it restores anything

If the checksum file is missing the script skips that check rather than failing,
so dumps taken elsewhere still restore.

Manual check, if you would rather not trust the script:

```bash
docker compose exec postgres psql -U bookings_app -d bookings_restore_<timestamp> -c '\dt'
docker compose exec postgres psql -U bookings_app -d bookings_restore_<timestamp> \
  -c 'SELECT count(*) FROM hotel_bookings; SELECT count(*) FROM booking_events;'
```

Drop it when you are done:

```bash
docker compose exec postgres psql -U bookings_app -d postgres \
  -c 'DROP DATABASE bookings_restore_<timestamp>'
```

One detail worth calling out: the script runs `VACUUM ANALYZE` on the restored
database. `pg_dump` does not carry planner statistics, so a freshly restored
database plans from defaults until something analyses it. Forgetting this is a
common reason a restore "works" and then everything is mysteriously slow.

---

## Notes and trade-offs

**The seed loads 50,000 rows, not 100.** With a hundred rows the planner
seq-scans no matter what you do, so the index makes no measurable difference and
the Part 5 answer cannot be demonstrated. 50,000 rows still seed in about three
seconds.

**Hash-based seed data instead of `random()`.** Reproducibility was the goal,
but there was a second reason. The first version put `random()` inside a
`LATERAL` that did not reference the row - Postgres is free to evaluate an
uncorrelated subquery once and reuse it, and it did, producing 50,000 bookings
that all shared one city. Deriving from `md5(row_number)` fixes both problems at
once.

**Placeholder container image.** The ECS service runs `nginx` from public ECR,
as the brief allows. Swapping it for a real image means changing
`container_image` and `health_check_path` - the ALB, target group and health
check wiring do not change.

**Backups here are logical dumps, which is not the production answer.** For the
RDS instance, `backup_retention_period` gives point-in-time recovery to any
second in the window, which `pg_dump` cannot do. The scripts in this repo are
the right tool for a local database, for moving data between environments, and
for the thing PITR does not give you - a copy that survives the account. In
production I would keep both: automated backups plus periodic logical dumps to a
separate account, and, importantly, a restore that actually runs on a schedule.
`database.yml` is the small version of that idea.

**What I would add next, given more time:** HTTPS on the ALB with ACM and a
redirect from 80, application autoscaling on the ECS service, VPC endpoints for
ECR / S3 / Secrets Manager so image pulls and secret reads skip the NAT
gateway (cheaper and one less dependency), CloudWatch alarms on ALB 5xx and RDS
free storage, and `checkov` or `tfsec` in the PR workflow next to `validate`.
