# SQLite Setup Guide

**Date:** 2026-02-27
**Author:** claude-4.6-opus

Haven supports both PostgreSQL (upstream default) and SQLite as database backends.
This guide covers how to switch between them.

## How it works

The `Gemfile` includes both `pg` and `sqlite3` gems in separate Bundler groups.
The `Dockerfile` includes build dependencies for both adapters.
Switching is done via the `DATABASE_URL` environment variable, which overrides
`config/database.yml` at runtime.

Docker Compose auto-merges `docker-compose.override.yml` on top of
`docker-compose.yml`. The override file sets `DATABASE_URL` for SQLite and
removes the PostgreSQL service dependency.

## Running with SQLite (Docker)

With `docker-compose.override.yml` present (the default in this fork):

```bash
docker compose build
docker compose up
```

The SQLite database file is stored at `/app/storage/haven_production.sqlite3`
inside the container, persisted via the `haven_storage` Docker volume.

## Reverting to PostgreSQL (Docker)

Remove or rename the override file:

```bash
mv docker-compose.override.yml docker-compose.override.yml.bak
docker compose up
```

This starts the PostgreSQL container and Haven connects to it using the
credentials in `docker-compose.yml`.

## Local development with SQLite

Skip the `pg` gem (which requires `libpq` headers to compile):

```bash
bundle config set --local without postgresql
bundle install
```

Set `DATABASE_URL` for your environment (or add it to `.env` which is loaded by
`dotenv-rails`):

```bash
export DATABASE_URL=sqlite3:db/development.sqlite3
bin/rails db:create db:migrate
bin/rails server
```

## Local development with PostgreSQL

Skip the `sqlite` gem group instead:

```bash
bundle config set --local without sqlite
bundle install
bin/rails db:create db:migrate
bin/rails server
```

## Pulling upstream changes

The diff from upstream is minimal (2 files modified, 2 files added):

| File | Change | Conflict risk |
|------|--------|---------------|
| `Gemfile` | Added `sqlite3` gem, `pg` moved to group | Low -- only if upstream changes pg version line |
| `Dockerfile` | Added `libsqlite3-dev` to apt-get | Low -- only if upstream rewrites the apt line |
| `docker-compose.override.yml` | New file | None -- upstream doesn't have it |
| `docs/sqlite-setup.md` | New file | None -- upstream doesn't have it |

All other files (`config/database.yml`, `db/schema.rb`, `.github/workflows/tests.yml`,
`deploymentscripts/`, `bin/docker-start`) are untouched and will merge cleanly.

To pull upstream:

```bash
git remote add upstream https://github.com/havenweb/haven.git  # once
git fetch upstream
git merge upstream/master
```

If a conflict occurs on the Gemfile `pg` line, keep both the group annotation
and any version bump from upstream.

## Backup with SQLite

SQLite backup is a file copy. From the host:

```bash
docker compose cp haven:/app/storage/haven_production.sqlite3 ./backup.sqlite3
```

Or from inside the container:

```bash
sqlite3 storage/haven_production.sqlite3 ".backup /tmp/backup.sqlite3"
```

## Smoke test checklist

After switching to SQLite, verify these flows:

1. Container starts without DB errors (`docker compose up`)
2. Login works with configured credentials
3. Create, edit, and delete a post
4. Upload an image
5. Subscribe to an RSS feed
6. Change site settings (title, CSS, visibility)
7. Data survives `docker compose down && docker compose up`
8. SQLite file copies out and opens with `sqlite3` CLI

## Notes

- SQLite uses file-level locking (single writer). This is fine for Haven's
  typical single-process deployment. If running multiple Puma workers, enable
  WAL mode by adding a Rails initializer.
- The upstream CI tests run against PostgreSQL. The SQLite adapter is validated
  by the existing test suite (all tests pass against SQLite).
- `db/schema.rb` is generated with the PostgreSQL adapter (upstream default).
  SQLite ignores PostgreSQL-specific directives like `enable_extension "plpgsql"`
  when running `db:migrate`.
