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

The database has been decided: it will be hosted on **Neon**, separately from
the application. That splits the question in two, and the split matters,
because a Rails application and its database should be in the same region. See
"The database on Neon" and "Region and latency", which is where this note now
reaches its most consequential conclusion.

## Recommendation

Heroku, on the Cedar generation, using the classic Ruby buildpack: a Basic
dyno at US$7/month, with the database on Neon for roughly US$10-20/month
depending on how much compute the traffic wakes, and the free Scheduler add-on
for the daily reminder job. This holds provided Heroku can place the app in the
same region as the database; `heroku regions` answers that, and if the answer is
no, the application host changes and the rest of this note does not.

The reason is not price. It is that this application is already Heroku-shaped,
and upstream deploys this same codebase to three Heroku apps, so every part of
the deploy path has been exercised by the project this fork came from:

- `Procfile:1-2` declares `release:` and `web:` process types, which is
  Heroku's process model rather than a generic one;
- `README.md:140-143` records that upstream runs London, Bristol and staging on
  Heroku apps `soldneu`, `swing-out-bristol` and `soldn-staging`, and tells a
  developer to check the production Postgres version with
  `heroku pg:info --app soldneu`; and
- `Gemfile:5` reads the Ruby version from `.ruby-version`, which is how the
  buildpack is told which Ruby to install.

`db/schema.rb:15` and `db/schema.rb:18` also pointed at Heroku - they create
the `heroku_ext` schema and enable `pg_stat_statements` - but they described
the database, and the database is no longer Heroku's. See below.

Nothing has to be invented to deploy this application to Heroku. Every other
platform needs a production Dockerfile that does not exist yet, plus a
replacement for the release process type and the scheduler.

## What the application asks of a host

These are the requirements, each one checked against the code. They apply to
the application host and, where marked, to the database host.

**A specific Ruby, and a build step for the frontend.** `.ruby-version` pins
Ruby 4.0.7, `Gemfile:7` pins Rails 8.1.4. `package.json` requires Node 22
(`engines`, with `engineStrict`), names Yarn 4.2.2 in `packageManager`, and
compiles the JavaScript with webpack through `jsbundling-rails`. The Sass is
compiled by `dartsass-rails` from the three entry points in
`config/initializers/dartsass.rb`, into the gitignored `app/assets/builds/`
directory. So the host must be able to run a multi-step build with two
toolchains, or the deploy must do it inside a container.

**PostgreSQL 17, reached over the public internet with TLS.** The devcontainer
and CI both use `postgres:17-alpine` (`.github/workflows/rubyonrails.yml:20`),
and `db/schema.rb:14` is `ActiveRecord::Schema[8.0]`. Neon offers PostgreSQL
14 through 18, so 17 is available. The database connection is a config var
(`config/database.yml`, `production:` section, read with `[]` rather than
`fetch`), so any provider that hands out a `postgres://` URL can be used
without touching the repository.

**Few database connections.** One dyno asks for `RAILS_MAX_THREADS` (3) plus 2
(`config/database.yml`, the `production:` pool line), so five. This matters
because it rules out a connection pooler as a necessity: Neon's smallest
compute allows 112 connections and reserves 7, leaving 97 available. Nothing
between the application and Postgres needs to proxy connections.

**A session that survives the release step.** `db:migrate` takes a
session-level advisory lock, and Neon's pooled endpoint is PgBouncer in
transaction mode, which does not support session-level advisory locks. The
release step therefore has to use Neon's *direct* connection string, not the
pooled one. This is the single most consequential difference from a
self-managed database, and it is why the pooler can be left switched off.

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
`DATABASE_URL` is the one that used to be supplied by the platform; on Neon it
is a connection string copied out of the console, and nothing in it is secret
except the password.

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

The database is not on Heroku, so nothing in this section is a Heroku decision
any more. What survives is the connection itself: `DATABASE_URL` is read in the
`production:` section of `config/database.yml` with `[]` rather than `fetch`
because Rails evaluates the ERB in every section at load, and the pool size is
`RAILS_MAX_THREADS + 2`. Both work unchanged with a Neon connection string, and
the one thing that must not be done is letting Heroku overwrite `DATABASE_URL`
with its own - if a Heroku Postgres is ever attached to the app, its URL takes
that variable. See "The database on Neon".

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
`SECRET_KEY_BASE`, `CANONICAL_HOST`, `RAILS_MAX_THREADS`, `DATABASE_URL`,
`GOOGLE_MAPS_JAVASCRIPT_API_KEY`, `GOOGLE_MAPS_STATIC_API_KEY`,
`GOOGLE_MAPS_MAP_ID`, `GOOGLE_ANALYTICS_ID`, `SMTP_USER_NAME`,
`SMTP_PASSWORD`, `ROLLBAR_POST_SERVER_ITEM_ACCESS_TOKEN`, `AUDIT_LOG_PASSWORD`,
`BASIC_AUTH_USER` and `BASIC_AUTH_PASSWORD` (the last pair is read by
`app/controllers/application_controller.rb:25` and is how a staging site would
be protected), `IP_BLOCKLIST`, `BANNER_HEAD`, `BANNER_BODY` and `DONATE_LINK`.
All optional ones can simply be left unset. `.env.example` documents the
development subset.

## The database on Neon

Neon is Postgres, run as Lakebase Postgres and owned by Databricks as of 2026.
It is priced per Compute Unit-hour rather than per instance, with no monthly
minimum on the paid plans, and the compute suspends when it is idle. All of the
following was read from Neon's own documentation on 2026-10-15.

**What it fits, and what it does not.**

- **PostgreSQL 14, 15, 16, 17 and 18**, selectable at project creation. 17 is
  available, matching the devcontainer and CI.
- **An AWS Sydney region**, `aws-ap-southeast-2`, with Postgres available in it,
  alongside Singapore, Tokyo-equivalent Asia coverage, three US regions and two
  European ones. This is the single most useful fact in this section, and it is
  what makes the region pairing discussed below solvable.
- **The region is fixed when the project is created** and cannot be changed.
  Moving means creating another project and migrating. So the region decision
  has to be made once, correctly, before any data is loaded.
- **`pg_stat_statements` is supported** (1.11 on PG17), so the line in
  `db/schema.rb` would not fail if it were ever executed against Neon.
- **No superuser.** Neon substitutes a `neon_superuser` role, and roles created
  by SQL rather than through the console do not get it. The project's own role
  does, which is what runs migrations.
- **No tablespaces**, and no `ALTER SYSTEM`: instance-level parameters are not
  configurable outside a session, database or role.

**What has to change in the repository.**

1. **Delete `create_schema "heroku_ext"` and `enable_extension
   "pg_stat_statements"` from `db/schema.rb` (lines 15 and 18).** Both are
   Heroku fixtures. They would not break a schema load against Neon - the
   schema can be created and the extension is supported - but `heroku_ext` is
   an empty schema that nothing reads, and `pg_stat_statements` is a
   monitoring tool whose statistics are discarded when a compute suspends
   anyway, which is exactly what a scale-to-zero compute does every night.
   Removing them means `db/schema.rb` describes the database it will actually
   meet. Note that nothing in the application reads either: `db:migrate` never
   consults the schema file, because `production.rb:88` sets
   `dump_schema_after_migration = false`.

2. **Use the direct connection string, not the pooled one.** Neon's pooled
   endpoint is PgBouncer in transaction mode, which does not support
   session-level advisory locks, and `db:migrate` takes one. The pooled
   hostname is the direct one with `-pooler` added, so this is a matter of
   copying the right string from the console's Connect dialog. The direct
   string is also all this application needs: five connections against 97
   available. Protocol-level prepared statements, which Rails uses by default,
   do work through the pooler (`max_prepared_statements = 1000`), so prepared
   statements are not a reason to avoid it - the advisory lock is.

3. **Lower the pool's `idle_timeout`.** Rails' connection pool discards
   connections that have been idle longer than `idle_timeout`, and the default
   is 300 seconds. Neon's compute suspends after five minutes and closes idle
   connections when it does. Those are the same number, which is a race the
   application can lose: a connection checked in at second 299 is closed by
   Neon at second 300, while Rails still considers it fresh, and the next
   request to check it out gets a dead socket. Setting `idle_timeout: 240` in
   the `production:` block of `config/database.yml` puts Rails clearly in front
   of Neon. (`keepalive`, which defaults to 600 seconds, is the other half of
   this machinery, and is no help here: it fires later than the close.)

4. **Expect a cold start on the first query after five idle minutes.** This is
   a few hundred milliseconds on the first request of each quiet stretch, which
   is a fair trade for a compute that costs nothing while suspended. Scale to
   zero can be disabled on the paid plans if that trade is not wanted; it
   cannot be disabled on the Free plan.

5. **Decide the collation deliberately.** Neon uses `C.UTF-8`, with limited
   `libc` locales and `icu` locales available. Any listing ordered by name -
   venues, suburbs, organisers - will sort by byte order rather than
   dictionary order, and capitals sort before lower case. The devcontainer and
   CI should be checked for the same setting, or local specs will disagree with
   production.

6. **Use a Neon branch for staging.** Child branches are copy-on-write and
   effectively free (10 per project on the included plans, US$1.50 per extra
   branch-month), so the "no staging environment" decision recorded below can
   be revisited at no cost, and a staging database can exist without a second
   application host.

**What it costs.** The Free plan is permanent and includes 100 CU-hours per
project per month, but when that quota is exhausted the compute is suspended
"until the next billing period or until you upgrade", existing connections drop
and new ones cannot open. For a public site that is not an acceptable failure
mode. The Launch plan has no minimum: US$0.106 per CU-hour, US$0.35 per GB-month
of storage, US$0.20 per GB-month of instant-restore history, 500GB of egress
included, a seven-day history window, and a 0.25 CU compute (about 1GB) as the
floor. A month that keeps that compute running continuously is 0.25 x 730 =
about 183 CU-hours, or US$19, plus storage. A directory that is queried in
bursts and then idle suspends more often and costs proportionally less; the
honest estimate for launch traffic is US$10-20/month, to be replaced with a real
number after the first month of usage. Neon reports the bill per branch, so the
cost of a staging branch should be visible.

Two things come with the plan that were previously unbudgeted. Instant restore
is a seven-day history window and snapshots, which satisfies the tested-backups
exit condition in FEASIBILITY.md without anyone writing a `pg_dump` cron - the
restore still has to be rehearsed once, deliberately. And branching is a
staging database for free.

## What it costs

| Item | Price | Notes |
|---|---|---|
| Heroku Basic dyno | US$7/month | 0.5GB RAM, always on, 10 process types, free SSL. One dyno per process type |
| Neon, Launch plan | US$10-20/month | Estimate. US$0.106 per CU-hour on a 0.25 CU floor, US$0.35/GB-month storage; scale to zero after five idle minutes |
| Heroku Scheduler | Free | One-off dyno per run, counted as dyno hours |
| | **US$17-27/month** | |

Two traps in that table. Heroku's Eco dyno is US$5 and looks cheaper, but it
sleeps after 30 minutes of inactivity, is limited to two process types, and is
for personal accounts; a directory that crawlers index and that sends daily
reminder email needs a process that is awake. And Heroku's Fir generation -
which uses Cloud Native buildpacks by default - requires a Private Space, which
starts at US$125/month. Fir is not affordable for this project, which is another
reason to stay on the classic buildpack.

The Neon figure is a range because it is the one line item that scales with
success, which is the right property for it to have. The month it becomes
expensive is the month the site is busy.

## The alternatives, and why they are second

These are alternatives for the application host only. The database is Neon.

| Platform | Indicative monthly cost | Why it is not the recommendation |
|---|---|---|
| DigitalOcean App Platform | US$5-10 for the web service | Runs in `syd`, which is genuinely attractive for latency. But the service still needs a Dockerfile or App Platform's own Ruby build, and the reminder job becomes a scheduled Job rather than an add-on |
| Fly.io | US$4.39 for a 512MB machine (from 2026-10-01) | Runs in `syd` too, and is the cheapest compute. But it also needs the Dockerfile, and its own Managed Postgres would be redundant next to Neon |
| Render | US$7 for a Starter web service | The free tier spins down after 15 minutes of inactivity and has no cron, which is wrong for a public directory. No Australian region |
| Railway | About US$5 in credit, then usage-priced | Has cron and usage pricing, which suits a small site. The credit is tight and the platform is less predictable to budget |
| A virtual server, with Kamal or Coolify | Hetzner from EUR 4-6/month | Most control, and all of the consequences: OS patching, TLS renewal, database backups, and uptime. For a volunteer-maintained site whose real risk is stale listings rather than software, this is the wrong thing for one person to own |

The first two have an advantage that should be recorded rather than dismissed:
both run in a Sydney region, which would pair well with Neon's Sydney region.
Whether that outweighs the Dockerfile is the region question below.

## Region and latency

For a listings site with an hour-long response cache, latency is second-order for
a cache hit: one request, one fragment-cached response. It is not
second-order for the first request after an hour of quiet, for every editor
action, and - now that the database is a separate service - for every query the
cache has not already served.

Both sides can now be in Australia. Neon has an AWS Sydney region
(`aws-ap-southeast-2`), Fly.io has `syd`, and DigitalOcean has `sydney1`. Heroku
lists Sydney among its selectable regions, but that page is about Private
Spaces, which is the Fir generation; whether a Cedar app can be created in
Australia has to be checked with `heroku regions`.

That gives three pairings, and they are not equivalent:

- **Application and database in the same non-Australian region.** Consistent,
  and the cheapest round trip between the dyno and Postgres, but a Sydney
  visitor still pays roughly 180ms to reach the application at all.
- **Application outside Australia, database in Neon Sydney.** The worst
  pairing, and the one to avoid. The visitor pays a round trip to the dyno, and
  every query the response cache misses pays another. The cache hides most of
  it on the front page and none of it on the editor screens.
- **Application and database both in Sydney.** Both hops local, the best
  experience for readers and for the volunteers who do the actual editorial
  work, at the cost of the Dockerfile and the cron wiring that Heroku removes.

So the decision order is: run `heroku regions` first. If Cedar includes an
Australian region, Heroku and Neon Sydney together is the answer and nothing
else needs deciding. If it does not, the choice is between moving the
application to Australia (Fly.io or DigitalOcean App Platform) and moving the
database out of Australia (a Neon project in the application's region) - and
the first is better, because the audience and the editors are in Sydney while
the cost of moving the database is only latency, which is exactly what the
response cache already absorbs. Note also that Neon's region cannot be changed
after the project is created, so this decision has to be made before the first
database is provisioned, not after.

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

### Database checks

1. **Create the Neon project in the region decided above, on PostgreSQL 17,
   before anything else is provisioned.** The region cannot be changed later.
2. **Copy the direct (not `-pooler`) connection string** into the Heroku
   `DATABASE_URL` config var, and check that nothing else has claimed that
   variable: attaching any Heroku Postgres will overwrite it.
3. **Delete `create_schema "heroku_ext"` and `enable_extension
   "pg_stat_statements"` from `db/schema.rb`**, then let `rake release` load the
   schema into the empty database. Loading a schema containing them would also
   work, but it would create an empty schema nothing reads.
4. **Run the release step once against the empty database** and confirm
   `schema_migrations` is populated. This is the check that catches a wrong
   Procfile before the first request arrives.
5. **Check the collation.** `SHOW lc_collate;` should return the same answer in
   Neon as it does in the devcontainer and CI, or listings ordered by name will
   differ between environments.
6. **Lower `idle_timeout` in the `production:` block of
   `config/database.yml`** from its 300-second default to something under five
   minutes, so the Rails pool discards connections before Neon closes them.
7. **Rehearse one restore** from Neon's instant-restore or snapshot history,
   onto a scratch branch. "Backups work" is only true once this has been done.

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
- **Neon's connection pooler.** Five connections from one dyno against 97
  available is not a problem worth solving, and the pooler is the component
  that cannot hold a session-level advisory lock, which migrations need.
- **`pg_cron` for the reminder job.** It is available on Neon, but only runs
  while the compute is active, so using it means disabling scale to zero and
  paying for an always-on database to run a job that Heroku Scheduler already
  runs for free.
- **Object storage.** No ActiveStorage means no bucket.
- **A staging environment with its own database.** Not before launch - although
  a Neon branch makes the database half free, so this is the first thing to
  revisit once the site is up. The in-process HTTP basic auth in
  `application_controller.rb:25` is the mechanism for protecting an
  otherwise-public preview, and `README.md:140-143` describes how upstream
  protects its staging app.
- **A second region, or a read replica.** The audit log is the only growing
  table, and pruning it is a better answer than a replica.

## What would change this recommendation

- **Ruby or Rails dropping off Heroku.** Heroku tracks Ruby releases closely -
  4.0.7 was available within a month of release - but it is a commercial
  platform that can raise prices. The cost of leaving is the Dockerfile plus the
  release and scheduler work, which is a day, not a rewrite.
- **`heroku regions` showing no Australian Cedar region.** This is the open
  question, and it is now the only thing standing between the recommendation
  above and a different application host. If Cedar has no Australian region,
  then Heroku plus Neon Sydney is the worst pairing of the three, and either
  Fly.io or DigitalOcean App Platform in Sydney - accepting the Dockerfile -
  or a Neon project in the Heroku region - accepting visitor and editor latency
  - is the better answer. Moving the application is the better of those two.
- **The database leaving the application host.** Done, and it is the change
  with the widest consequences in this document: it splits one hosting decision
  into two, it moves the region question from "where is the whole site" to "are
  both halves in the same place", and it removes the strongest argument for
  Heroku, which was that the database came with it. What replaced it is
  branching and point-in-time restore, both of which the Heroku Postgres tier
  did not give us.
- **Scale.** If the site needs Australia-wide coverage with traffic worth
  horizontal scaling, the in-memory response cache has to become a real cache
  store, and that is a Heroku add-on, a Fly Redis, or neither. Two dynos would
  also mean ten database connections, which is still nothing.

## To verify before committing

Commands and checks, in the order they are worth running:

1. `heroku regions` - whether a Cedar app can be created near Australia. This
   decides the region pairing, and therefore whether Heroku survives as the
   application host.
2. Create the Neon project in the chosen region on PostgreSQL 17, and confirm
   with `SHOW lc_collate;` and `SHOW server_version;` that it matches what the
   devcontainer reports.
3. A scratch Heroku app with this repository pushed to it, to confirm that the
   classic buildpack's bundled Yarn satisfies `packageManager: yarn@4.2.2`. The
   lockfile is Yarn Berry format (`__metadata: version: 8`), and the build needs
   Yarn 4 to read it; if the buildpack's Yarn 1 cannot, the fix is
   `corepack enable` in the build, and that is the one unknown left in this
   recommendation.
4. Run `rake release` against the empty Neon database and check
   `schema_migrations` is populated - this is the check that catches a wrong
   Procfile before the first request arrives.
5. A staging deploy with the two launch blockers fixed, then a real editor
   login from a phone, to prove the magic link carries the right host.
6. Leave the site idle for ten minutes, then request it again, and confirm the
   wake-up neither errors nor returns a stale connection. That is the one Neon
   behaviour the application has no local equivalent for.

The repository has no `Dockerfile`, no `fly.toml`, no `render.yaml` and no
`app.json`, and `Procfile` carries only the two process types Heroku needs
(`Procfile.dev` is for local development: a server plus the webpack and
dart-sass watchers). Whichever application host is chosen, `Procfile` is the
place that choice is recorded in code.