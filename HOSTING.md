# Hosting

Current deployment record, checked on 25 October 2026. This replaces the earlier
Heroku recommendation: the public site is static on Cloudflare Pages and the
editorial Rails application runs on Fly.io, with PostgreSQL on Neon.

## Deployed topology

| Component | Host | State |
| --- | --- | --- |
| Public website | `www.sydneylindyhub.com`, Cloudflare Pages project `sydneylindyhub` | Live |
| Apex domain | `sydneylindyhub.com`, CloudNS forwarding to `www` | Live |
| Production editor | `edit.sydneylindyhub.com`, Fly app `sydneylindyhub-prod-editor` | Live in Sydney (`syd`) |
| Editorial database | Neon PostgreSQL | Connected; production schema checked at release |
| Outgoing mail | Fastmail SMTP, from `hello@sydneylindyhub.com` | Login delivery verified by the operator; SPF, DKIM and DMARC pass |
| Static publication | GitHub Actions → Cloudflare Pages | Manual and daily scheduled publication available |
| Staging editor | Fly app `sydneylindyhub-staging-editor` | Created; no deployed image or configured runtime secrets |

Public requests do not reach Rails or Neon. Editors save changes in Neon through
Rails; a separate publication exports a snapshot and uploads it to Cloudflare.
Saving an edit does not immediately update the public website.

The latest checks confirmed the editor login page (HTTP 200), production Fly
health and a successful scheduled GitHub publication. Direct public-site checks
returned 403 from this environment during this documentation refresh; earlier
checks had verified the live export manifest. That limits fresh public HTTP
verification and does not establish the cause of the 403.

DNS remains at CloudNS. The production editor uses A/AAAA records pointing to
Fly and a verified, active Fly-managed TLS certificate. No Google Cloud Run
service, extra HTTPS frontend or nameserver migration is part of this deployment.

## Production editorial runtime

[`fly.prod.toml`](fly.prod.toml) builds the Dockerfile's `web` target. There is one
shared-CPU machine with 512 MB RAM in `syd`, listening on port 8080. Fly terminates
TLS; Rails uses `RAILS_ASSUME_SSL=true` and `force_ssl`. Autostop/autostart allows
the machine to stop while idle and restart on a request. A stopped machine is
expected behaviour, not evidence of an outage; verify that requests wake it.

The publication integration is deployed as a release image tagged with its
source commit. Check `fly status` for the current image; a source commit on
`main` does not automatically deploy the editor. The release also includes the
Auto-Submitted mail-header change already present on `main`.

The image uses Ruby 4.0.8 and Rails 8.1.4, with Node 24 and Yarn 4.2.2 at build
time. Assets are compiled into the image. The runtime is non-root and excludes
Node and Chromium. The separate `publisher` target supplies the tools needed
for export validation. See [container setup](guides/production_container.md).

`/up` is a boot/liveness probe; it does not prove database availability. The
production homepage and login page have returned HTTP 200, protected editor
routes redirect to login, and Fly's HTTP health check has passed.

## Database and credentials

Production uses the restricted `site_editor` role for reading and editing data.
The GitHub publisher uses a separate read-only connection stored as
`PUBLICATION_DATABASE_URL`. Use direct Neon TLS endpoints for these small jobs;
keep owner credentials out of the running web application.

The Fly release command is `bin/rails db:abort_if_pending_migrations`. It checks
that Neon matches the code, and does not migrate, bootstrap or seed the database.
If a future release needs migrations, run them separately with the owner role
against the direct endpoint, then redeploy. Merely publishing a static snapshot
does not require migrations when the schema is already current.

Fly runtime secrets contain `DATABASE_URL`, `SECRET_KEY_BASE`, SMTP credentials,
and Maps configuration. Local deployment copies are in the Git-ignored
`.env.fly-prod-editor`; templates contain names and comments only. Never commit
connection strings, app passwords or signing secrets.

No Fly database, persistent volume, object store or shared cache is deployed.
Rails uses an in-memory cache. Database backups are separate from static output;
Neon recovery configuration and a restore rehearsal still need confirmation.

## Email and editor access

Rails sends through `smtp.fastmail.com`, port 587 with STARTTLS and PLAIN
authentication, using a Fastmail app password. The sender is
`hello@sydneylindyhub.com`; login and organiser links use `EDITORIAL_HOST`, not
the public-site host. Credentials remain in Fly secrets.

Approved editor/admin accounts are stored as `Role` records. Administrators can
manage them at `/admin/users`; unknown addresses are not sent login links. Links
expire after 15 minutes and are reusable until expiry, which the operator has
accepted. Do not describe them as technically single-use.

The operator confirmed receipt of login mail with passing SPF, DKIM and DMARC.
Browser editing is also verified: audit entry 77 records Anand Kumria updating
Event 20 at 01:33 Sydney time on 25 October 2026. The event was Gustavo Swing
Roaring 1920s Swing Party; changed fields were `class_style`, `source_notes` and
`last_verified_at`. No credentials or login tokens belong in operational logs.

## Public publication

[The publication workflow](.github/workflows/publish-static-site.yml) runs from
`main`, manually or daily at 04:15 `Australia/Sydney`. A scheduled run has
succeeded. GitHub scheduling can be delayed; the workflow is not an exact-time
service. The 04:15 schedule is after the site's 04:00 date rollover.

It builds the publisher image, reads Neon, exports public pages and map data,
runs static HTTP/Chromium validation, and uploads the checked artifact to Pages.
It then checks the live site's manifest against the artifact. Exports receive
database credentials without a Cloudflare token; the upload receives Cloudflare
credentials without database credentials. Production runs are serialized.

`CANONICAL_HOST=www.sydneylindyhub.com` controls public URLs and the sitemap.
`EDITORIAL_HOST=edit.sydneylindyhub.com` controls Rails account and organiser
links. Neither variable configures DNS or performs an apex redirect itself.

The editor's **Publish website** button dispatches this same workflow on `main`.
Production uses `STATIC_PUBLISH_BACKEND=github`, `STATIC_PUBLISH_ENABLED=true`
and a repository-scoped Actions read/write token stored as `GITHUB_ACTIONS_TOKEN`
in Fly secrets. No Contents write permission or Cloudflare credential is granted
to the editor. Refreshing the page reconciles the queued/running/terminal status
and shows the matched GitHub run. Ambiguous dispatch errors stay active until
reconciled, preventing duplicate publication. No Fly publisher worker is needed.

## Staging and remaining operations

[`fly.staging.toml`](fly.staging.toml) targets
`sydneylindyhub-staging-editor.fly.dev`, with Sydney placement and separate
secrets. Staging still needs an isolated Neon branch, credentials, safe test
email delivery, deployment and acceptance checks. It must not use production
write credentials or send reminders to copied real recipients. No static
staging publication target is configured.

Organiser reminders run Mondays at 10:00 am Australia/Sydney through GitHub,
with daylight saving handled by the schedule timezone. Manual dry-run/send is also available.
The mode defaults to send; dry-run uses the existing read-only publication
connection and prints masked previews. Send uses credentials in
`production-reminders`. Fastmail Sent-copy retention has been verified. Submission is
synchronous and recorded only after SMTP acceptance; uncertain outcomes stop the
batch for manual review. See [reminder operations](guides/organiser_reminders.md).
Reminder contacts must be configured per listing. A one-off production reminder
was submitted successfully; ongoing eligibility is checked on every run.

Other follow-ups are recovery/restore verification, failure and stale-publication
alerts, client-IP/throttling acceptance, and a complete browser edit → publish →
public-output check. These are distinct from the verified editor save.

See [Fly editorial operations](guides/fly_editorial.md) and
[static publication operations](guides/static_publication.md) for commands.

## Costs

The old Heroku/Neon estimates are not this deployment's budget. Current costs
come from Fly machine runtime/rootfs/builds/network, Neon compute/storage/recovery,
GitHub Actions, Cloudflare and Fastmail, subject to each account's plan and
allowances. Confirm actual bills rather than treating staging branches or stopped
machines as free. No current monthly total has been established.
