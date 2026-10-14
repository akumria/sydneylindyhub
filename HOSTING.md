# Hosting

Where the public Sydney Lindy Hub runs is an operational decision, not a
development one: the application already works locally and in CI, and Phase 1
is finished. This note records the hosting requirement, the recommendation, the
cost, the alternatives, and the work that has to happen before the first
public deploy.

The requirement section is deliberately written against the code rather than
against a wish list, so that the recommendation can be re-checked whenever the
stack changes. Prices were read on 2026-10-15 and are noted with their source
where a third party published them.

## Recommendation

Heroku, on the Cedar generation, using the classic Ruby buildpack: a Basic
dyno at US$7/month with Heroku Postgres Essential-0 at US$5/month, and the
free Scheduler add-on for the daily reminder job. US$12/month in total.

The reason is not price. It is that this application is already Heroku-shaped,
and upstream deploys this same codebase to three Heroku apps, so every part of
the deploy path has been exercised by the project this fork came from:

- `Procfile:1-2` declares `release:` and `web:` process types, which is
  Heroku's process model rather than a generic one;
- `db/schema.rb:15` creates the `heroku_ext` schema and `db/schema.rb:18`
  enables `pg_stat_statements`, both of which are Heroku Postgres fixtures;
- `README.md:140-143` records that upstream runs London, Bristol and staging on
  Heroku apps `soldneu`, `swing-out-bristol` and `soldn-staging`, and tells a
  developer to check the production Postgres version with
  `heroku pg:info --app soldneu`; and
- `Gemfile:5` reads the Ruby version from `.ruby-version`, which is how the
  buildpack is told which Ruby to install.

Nothing has to be invented to deploy this application to Heroku. Every other
platform needs a production Dockerfile that does not exist yet, plus a
replacement for the release process type and the scheduler.

## What the application asks of a host

These are the requirements, each one checked against the code.

**A specific Ruby, and a build step for the frontend.** `.ruby-version` pins
Ruby 4.0.7, `Gemfile:7` pins Rails 8.1.4. `package.json` requires Node 22
(`engines`, with `engineStrict`), names Yarn 4.2.2 in `packageManager`, and
compiles the JavaScript with webpack through `jsbundling-rails`. The Sass is
compiled by `dartsass-rails` from the three entry points in
`config/initializers/dartsass.rb`, into the gitignored `app/assets/builds/`
directory. So the host must be able to run a multi-step build with two
toolchains, or the deploy must do it inside a container.

**PostgreSQL 17, and permission to create schemas and extensions if the schema
file is ever loaded.** The devcontainer and CI both use `postgres:17-alpine`
(`.github/workflows/rubyonrails.yml:20`), and `db/schema.rb:14` is
`ActiveRecord::Schema[8.0]`. The two Heroku-specific lines are noted under
"the database" below.

**A release step that runs migrations before traffic arrives.**
`Procfile:1` is `bundle exec rake db:migrate`.

**A daily scheduled job.** `lib/tasks/schedule.rake` defines
`send_not_listed_reminders`, which sends organiser reminder emails for events
with no future date, and its comment records that it runs every day at
15:00 GMT. There is no queue, no worker and no scheduler in the application:
Active Job is left on the default in-process adapter, and the single
`deliver_later` in the codebase
(`app/services/organiser_reminder_sender.rb:12`) is only ever enqueued from
that job. One process running the job on a schedule is the whole requirement.

**One always-on process, at least.** `config/environments/production.rb:55`
sets `cache_store = :memory_store`, deliberately: the response cache is keyed
off the most recent audit record and has an hour's TTL
(`app/controllers/application_controller.rb:42`), so a single machine needs no
shared cache and no sticky sessions. Horizontal scaling would need a real cache
store, but this application is nowhere near needing two machines.

**Environment-variable configuration only.** `config.secret_key_base` is read
from the environment (`production.rb:103`), and so are the mailer credentials,
the Google Maps keys, `CANONICAL_HOST`, the Rollbar token and the IP blocklist.
There are no Rails credentials to decrypt, which is what makes a platform with
config variables a good fit and a Docker-only platform no harder.

**The real client IP in `request.ip`.** `config/initializers/rack_attack.rb:38`
throttles 5 requests per IP per 2 seconds and fails suspicious paths. Behind
any TLS-terminating proxy, `request.ip` has to be the visitor's address or every
visitor shares one bucket. This is currently correct on Heroku, Fly.io and
DigitalOcean, because Rails 8's `ActionDispatch::RemoteIp::TRUSTED_PROXIES`
already trusts the private ranges those proxies connect from (10/8, 172.16/12,
192.168/16 and the IPv6 equivalents). It becomes a real risk only behind a
proxy with a public source address, such as Cloudflare in front of the platform,
where `config.action_dispatch.trusted_proxies` would need setting explicitly.
Do not "fix" this by trusting `0.0.0.0/0`, which re-opens IP spoofing.

**TLS termination, a custom domain and DNS.** `force_ssl` is on
(`production.rb:29`).

**No object storage.** There is no ActiveStorage in this application, so no
bucket is required, and no upload path to configure.

## Why Heroku fits this application

### The build, with no Dockerfile

This is the decisive point. Both bundler gems enhance the same rake task:
`jsbundling-rails` runs `Rake::Task["assets:precompile"].enhance(["javascript:build"])`
and `dartsass-rails` runs `Rake::Task["assets:precompile"].enhance(["dartsass:build"])`,
both guarded by `SKIP_JS_BUILD` and `SKIP_CSS_BUILD`. Heroku's Ruby buildpack
compiles assets by running `rake assets:precompile` when that task exists, so a
Heroku slug build runs `yarn install`, `webpack`, and `dart-sass` in the correct
order, with no extra configuration and no Dockerfile. Dart Sass ships as
prebuilt platform binaries, so nothing has to be compiled from source either.

Every container-first platform needs a `Dockerfile` that does not exist. The
devcontainer's (`.devcontainer/Dockerfile`, `ruby:4.0.7-bookworm` plus Node 22
copied from `node:22-bookworm`) is about 70% of one, but it installs Chromium,
Firefox and build tooling that has no business in a production image.

The classic buildpack must be used rather than Heroku's Cloud Native
buildpacks, for two reasons. Cloud Native buildpacks do not receive the
application's config variables at build time by default, and
`rake assets:precompile` boots the production environment, which reads
`SECRET_KEY_BASE` with `fetch` and will raise without it. Config variables must
therefore be set before the first deploy either way.

Ruby 4.0.7 is available on Heroku: it was added on 2026-09-15
(Heroku Dev Center changelog item 3814). Ruby support is not a reason to
choose an older version here.

### The database

`create_schema "heroku_ext"` and `enable_extension "pg_stat_statements"` in
`db/schema.rb` are Heroku Postgres fixtures. Neither is required at runtime:
`production.rb:88` sets `config.active_record.dump_schema_after_migration = false`,
so `db:migrate` never dumps the schema file, and `db/schema.rb` is only read
when something loads a schema into an empty database. So they are a signal
about the intended host, not a constraint - but they do mean the schema file
would be rewritten with the same two lines every time it is regenerated, and
they are a legitimate thing to delete once the host is decided.

Heroku Postgres Essential-0 gives 1GB of storage and 20 connections, which is
generous for a directory of a few hundred listings and a few hundred organiser
records. Essential-1 at US$9 gives 10GB if the dataset or the audit log
outgrows it. The audit log is the one table that grows without bound; if it
becomes a concern, pruning it is cheaper than a larger database.

The database URL is read from `DATABASE_URL` in the `production:` section of
`config/database.yml`, with `[]` rather than `fetch` because Rails evaluates the
ERB in every section at load. Heroku supplies `DATABASE_URL` automatically, so
this needs no change.

### The scheduled job

Heroku Scheduler is a free add-on that runs a command as a one-off dyno on a
10-minute, hourly or daily schedule, in UTC. `send_not_listed_reminders` is a
short task that sends email and returns, so it suits a one-off dyno. Two things
to know: the dyno counts towards monthly dyno-hours, and the documentation is
explicit that job execution is "expected but not guaranteed" and is occasionally
missed. For a reminder email that editors can trigger manually, that is an
acceptable trade. It also means a missed day is silent, so the editor checklist
should include verifying that reminders ran.

### Configuration and secrets

Config vars cover everything the application reads in production:
`SECRET_KEY_BASE`, `CANONICAL_HOST`, `RAILS_MAX_THREADS`,
`GOOGLE_MAPS_JAVASCRIPT_API_KEY`, `GOOGLE_MAPS_STATIC_API_KEY`,
`GOOGLE_MAPS_MAP_ID`, `GOOGLE_ANALYTICS_ID`, `SMTP_USER_NAME`,
`SMTP_PASSWORD`, `ROLLBAR_POST_SERVER_ITEM_ACCESS_TOKEN`, `AUDIT_LOG_PASSWORD`,
`BASIC_AUTH_USER` and `BASIC_AUTH_PASSWORD` (the last pair is read by
`app/controllers/application_controller.rb:25` and is how a staging site would
be protected), `IP_BLOCKLIST`, `BANNER_HEAD`, `BANNER_BODY` and `DONATE_LINK`.
All optional ones can simply be left unset. `.env.example` documents the
development subset.

## What it costs

| Item | Price | Notes |
|---|---|---|
| Basic dyno | US$7/month | 0.5GB RAM, always on, 10 process types, free SSL. One dyno per process type |
| Postgres Essential-0 | US$5/month | 1GB, 20 connections, shared RAM, 4,000-table limit |
| Postgres Essential-1 | US$9/month | 10GB - the step up when the audit log or dataset needs it |
| Scheduler | Free | One-off dyno per run, counted as dyno hours |
| | **US$12/month** | Basic plus Essential-0 |

Two traps in that table. Heroku's Eco dyno is US$5 and looks cheaper, but it
sleeps after 30 minutes of inactivity, is limited to two process types, and is
for personal accounts; a directory that crawlers index and that sends daily
reminder email needs a process that is awake. And Heroku's Fir generation -
which uses Cloud Native buildpacks by default - requires a Private Space, which
starts at US$125/month. Fir is not affordable for this project, which is another
reason to stay on the classic buildpack.

## The alternatives, and why they are second

| Platform | Indicative monthly cost | Why it is not the recommendation |
|---|---|---|
| DigitalOcean App Platform | US$5-10 for the web service, US$7 for a development database, US$15+ for managed Postgres | Runs in `syd`, which is genuinely attractive for latency. But the service still needs a Dockerfile or App Platform's own Ruby build, and the reminder job becomes a scheduled Job rather than an add-on |
| Fly.io | US$4.39 for a 512MB machine (from 2026-10-01), US$38+ for Managed Postgres | Runs in `syd` too, and is the cheapest compute. The cost moves: managed Postgres is expensive, and self-hosting Postgres on a machine means owning backups, patching and restore drills |
| Render | US$7 for a Starter web service, US$7+ for Postgres | The free tier spins down after 15 minutes of inactivity and has no cron, which is wrong for a public directory. No Australian region |
| Railway | About US$5 in credit, then usage-priced | Has cron and usage pricing, which suits a small site. The credit is tight against a database and the platform is less predictable to budget |
| A virtual server, with Kamal or Coolify | Hetzner from EUR 4-6/month plus the database | Most control, and all of the consequences: OS patching, TLS renewal, database backups, and uptime. For a volunteer-maintained site whose real risk is stale listings rather than software, this is the wrong thing for one person to own |

Two of these have a real advantage that should be recorded rather than
dismissed: DigitalOcean App Platform and Fly.io both run in a Sydney region,
which Heroku may not. See below.

## Region and latency

For a listings site with an hour-long response cache, latency is a second-order
concern - a cache hit is one request, and the response is a fragment-cached
page - but the first request from a Sydney visitor, and every editor action,
carry the full round trip.

Fly.io's `syd` region and DigitalOcean's `sydney1` both put the application in
Australia. Heroku lists Sydney among its selectable regions, but that page is
about Private Spaces, which is the Fir generation, not Cedar. Whether a Cedar
app can be created in Sydney has to be checked with `heroku regions` before
this recommendation is final. If it cannot, then a Heroku app sits in the US or
Europe, and the difference in time-to-first-byte for a Sydney visitor is the
price of the simplest deploy path.

The other half of that decision is where the database is, and that only became
a live question once the database was separated from the application host. A
Sydney application talking to a database in Virginia pays the round trip on
every query the response cache misses, which is every request the cache has not
seen in the last hour, and every editor request. Regions on both sides of the
wire should be chosen together.

## Before the first deploy

### Hosting-independent blockers

These have to be fixed whatever the host, and two of them make the site
unusable rather than merely unpolished.

1. **The mailer host is `example.com`.**
   `config/environments/production.rb:65` sets
   `config.action_mailer.default_url_options = { host: "example.com" }`. Phase 1
   replaced Facebook OAuth with an emailed magic link
   (`app/controllers/sessions_controller.rb:41`), so every editor login link
   would be generated as `http://example.com/...` and no editor could sign in.
   This must become `ENV.fetch("CANONICAL_HOST")`. Line 73's
   `smtp_settings[:domain] = "example.com"` has the same problem for the
   `Message-ID` domain.

2. **The release step skips schema bootstrap.** `Procfile:1` runs
   `bundle exec rake db:migrate`, which drops the `ensure_schema` step in
   `lib/tasks/release.rake` that calls `db:prepare` when the database has no
   schema version. Against a fresh, empty production database, `db:migrate` has
   nothing to apply and the application starts with no tables. The release step
   should be `bundle exec rake release`, which is also what upstream runs.

3. **SMTP is hardcoded to Gmail.** `production.rb:71` pins
   `smtp_settings[:address]` to `smtp.gmail.com` on port 587. Moving to a
   transactional provider - which FEASIBILITY.md requires for organiser
   reminders - means making the address, port and `domain` configurable, not
   just supplying different credentials.

4. **There is no health endpoint.** The `/up` route and its `ssl_options`
   exclusion are both commented out (`production.rb:32` and `:44`). Any platform
   health check needs a real path, and it has to probe over HTTPS, because
   `force_ssl` is on with `assume_ssl = false` and an `http://` probe is
   answered with a redirect rather than a 200.

5. **`config/puma.rb:38` offers a Solid Queue plugin that is not installed.**
   `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` will stop Puma booting
   if that variable is ever set, because `solid_queue` is not in the Gemfile.
   Either add the gem or delete the line.

### Hosting-specific checks

1. Set `SECRET_KEY_BASE` as a config var before the first deploy, because
   `assets:precompile` boots the production environment.
2. Decide the region, then set `CANONICAL_HOST` to whichever of
   `sydneylindyhub.com` and `www.sydneylindyhub.com` is canonical. It feeds the
   sitemap (`app/controllers/sitemaps_controller.rb:15`), `robots.txt`
   (`app/controllers/robots_controller.rb:8`), the audit log feed
   (`app/presenters/url_helpers.rb:13`), `config.hosts`
   (`production.rb:94`) and every link in every email.
3. Configure the Scheduler add-on for 15:00 UTC daily. Sydney is UTC+10 or
   UTC+11, so this is 01:00 or 02:00 the next morning local time - which is the
   right time for a reminder email, but worth confirming that is the intent.
4. Verify the first build produces `app/assets/builds/application.css`,
   `application_cms.css`, `mail.css` and the webpack bundle, and that the
   health of the dyno is not being carried by a stale bundle.

## What we are deliberately not deploying

- **Memcached.** `production.rb:49-55` explains the decision in the code. The
  response cache is a speed optimisation with keys derived from the last audit
  record, and a handful of keys with an hour's TTL does not pay for a cache
  server on one machine. The `memcachier` and `dalli` gems are still in the
  Gemfile as dead weight and can be removed at leisure.
- **A worker dyno or a background queue.** There is no queue and no worker to
  run. `Active Job` stays on its in-process adapter. `puma.rb:38` refers to
  Solid Queue, which is not installed and is not needed.
- **Object storage.** No ActiveStorage means no bucket.
- **A staging environment with its own database.** Not before launch. The
  in-process HTTP basic auth in `application_controller.rb:25` is the
  mechanism for protecting an otherwise-public preview if one is ever wanted,
  and `README.md:140-143` describes how upstream protects its staging app.
- **A second region, or a read replica.** The audit log is the only growing
  table, and pruning it is a better answer than a replica.

## What would change this recommendation

- **Ruby or Rails dropping off Heroku.** Heroku tracks Ruby releases closely -
  4.0.7 was available within a month of release - but it is a commercial
  platform that can raise prices. The cost of leaving is the Dockerfile plus the
  release and scheduler work, which is a day, not a rewrite.
- **A genuine need for an Australian region.** If `heroku regions` shows no
  Cedar region in Australia and the latency measurement on a staging deploy is
  bad enough to notice, DigitalOcean App Platform in `syd` or Fly.io in `syd`
  become the better answer, at the cost of writing the Dockerfile and owning
  the release and cron wiring.
- **The database leaving the application host.** If the database is hosted
  separately from the application - which is a reasonable thing to do, and which
  changes the calculus above - then the region of the database matters as much
  as the region of the application, and the "Heroku Postgres comes with it"
  argument weakens considerably.
- **Scale.** If the site needs Australia-wide coverage with traffic worth
  horizontal scaling, the in-memory response cache has to become a real cache
  store, and that is a Heroku add-on, a Fly Redis, or neither.

## To verify before committing

Commands and checks, in the order they are worth running:

1. `heroku regions` - whether a Cedar app can be created near Australia.
2. A scratch Heroku app with this repository pushed to it, to confirm that the
   classic buildpack's bundled Yarn satisfies `packageManager: yarn@4.2.2`.
   The lockfile is Yarn Berry format (`__metadata: version: 8`), and the build
   needs Yarn 4 to read it; if the buildpack's Yarn 1 cannot, the fix is
   `corepack enable` in the build, and that is the one unknown in this whole
   recommendation.
3. `heroku pg:info` on the created database - the Postgres version should be 17
   to match the devcontainer and CI.
4. A staging deploy with the two launch blockers fixed, then a real editor
   login from a phone, to prove the magic link carries the right host.

The repository has no `Dockerfile`, no `fly.toml`, no `render.yaml` and no
`app.json`, and `Procfile` carries only the two process types Heroku needs
(`Procfile.dev` is for local development: a server plus the webpack and
dart-sass watchers). Whichever host is chosen, `Procfile` is the place that
choice is recorded in code.