# Production containers (local validation)

The root Dockerfile has two targets:

- `web` (default): Rails, precompiled assets and production gems; no Node or browsers.
- `publisher`: the same app plus Node, Yarn and Chromium for export smoke checks.

Both run as UID 10001. Dependencies and assets are installed at build time.
No source mount, development gems, local `.env`, database dump, Git checkout,
Rails master key or Cloudflare login is copied into the build context.

```sh
podman build --target web -t localhost/sydneylindyhub-web:local .
podman build --target publisher -t localhost/sydneylindyhub-publisher:local .
bin/check-production-container
```

The smoke check requires the existing development PostgreSQL container
`devcontainer-postgres-1`. It reads a dump, restores it into disposable
PostgreSQL on an isolated network, and removes its containers/network on exit.
It never migrates or edits the source database. Evidence goes under
`tmp/container-proof-<pid>/`. It expects the researched Gustavo Swing listing.

## Runtime configuration

Both images require `DATABASE_URL`, `SECRET_KEY_BASE`, `CANONICAL_HOST`
(public host) and `EDITORIAL_HOST` (Rails host). Supply secrets at runtime.
Set `RAILS_ASSUME_SSL=true` behind Cloud Run's TLS-terminating proxy.
The web image starts Puma on all interfaces at `PORT` (default 8080).
`/up` is a boot/liveness check; it bypasses HTTPS redirection and host checking,
but does not prove database availability. The smoke check separately queries
PostgreSQL and renders the real homepage.

Run schema preparation explicitly as a separate release operation, never on
web startup: `bin/rails db:prepare`. No automatic migrations are in the image.

The publisher defaults to `bin/publish-static-site`: export and full Chromium
validation, **without upload**. Assets are already compiled into the image.
Use a fresh writable `OUTPUT` for each execution. To upload, override the
command with `bin/publish-static-site --deploy` and supply worker-only
Cloudflare credentials. The upload currently uses Yarn to resolve Wrangler;
that step needs outbound package-registry access. Chromium is baked in.
Maps keys, banner settings and other application runtime settings must be
provided identically to the editor and publisher where applicable.

Cloud Run must use the publisher as a Job, not a detached subprocess after a
web response: request-based services can lose CPU or shut down while idle.
The existing editorial queue trigger still needs cloud integration in stage 2.
Build linux/amd64 for Cloud Run. Export files are ephemeral and use memory on
Cloud Run; measure the Job's memory before selecting its production limit.

## Boundaries

This stage creates no cloud resources, copies no data to Neon, configures no
SMTP, and performs no Cloudflare upload. Cloud account permissions, runtime
secrets, production database migration/import, scheduler and job invocation,
email delivery, backups and production-domain checks remain stage 2 work.

## Validation — 21 October 2026

- Web image: `localhost/sydneylindyhub-web:local`, ID `8718613d2ef0`,
  linux/amd64, approximately 331 MB uncompressed, non-root `rails` user.
- Publisher: `localhost/sydneylindyhub-publisher:local`, ID `bfe443058a18`,
  approximately 1.61 GB uncompressed including Chromium and its OS dependencies.
- Full `bin/rake`: 793 examples, zero failures, 100% line coverage; Ruby,
  ERB and stylesheet checks passed. Log: `tmp/production-container-test.log`.
- `bin/check-production-container` passed against an isolated copy of all 15
  local events: production boot on PORT=8097, health HTTP 200, editorial host,
  login page, non-root UID, absence of local secrets/Node from web image,
  database query, and complete export/browser smoke checks.
- Export: 32 pages, 27 map datasets, 5 assets. Evidence:
  `tmp/container-proof-1172335/`; summary `tmp/production-container-smoke.log`.
- Web memory snapshot after these requests: 170.5 MB. This is an idle/local
  observation, not a production peak measurement or a recommended memory cap.
- Corrected an inherited Rack canonical-host redirect which sent editorial and
  health requests to the separate public site. Rails host authorization remains.
- Temporary containers and network were removed; development DB was not modified.
  No cloud provisioning or live upload was performed.

## Manual GitHub publication

`.github/workflows/publish-static-site.yml` adds **Publish static site → Run
workflow**, and publishes daily at 04:15 Australia/Sydney (including daylight
saving adjustments). Scheduled runs can start late if GitHub is busy, and the
site updates when export, validation and deployment finish. It runs only from
`main`, serializes production publications, builds
the publisher image, queries the source database, exports and checks all public
pages, then uploads that exact artifact. No push trigger is enabled.
The job does not migrate, seed, or import the database.

Configure the GitHub `production` environment (or repository-level fallbacks):

| Setting | Type | Purpose |
| --- | --- | --- |
| `PUBLICATION_DATABASE_URL` | Secret | Reachable PostgreSQL containing the real listings; use a read-only role and TLS. |
| `CLOUDFLARE_API_TOKEN` | Secret | Account → Cloudflare Pages → Edit, scoped to the configured account. |
| `GOOGLE_MAPS_JAVASCRIPT_API_KEY` | Secret | Existing public browser key, restricted to the public site's domains/APIs. |
| `GOOGLE_MAPS_MAP_ID` | Variable | Existing public map ID. |
| `BANNER_HEAD`, `BANNER_BODY` | Optional variables | Public banner content. |

The Cloudflare account, project, public and editorial hosts are explicit in the
workflow. The export receives no Cloudflare credentials; the upload receives no
database credentials. A temporary Rails signing secret is generated inside the
export container; it is not the editorial application's session secret.

The workflow and its Dockerfile/application dependencies must be committed and
available on the repository's default branch before GitHub can expose the manual
trigger. Our laptop's `soldn1_dev` database is not accessible to GitHub-hosted
runners: first provide a populated, reachable database such as Neon. An empty
DB is rejected; never substitute sample seed data for researched listings.

Run through GitHub Actions, or `gh workflow run publish-static-site.yml --ref main`.
See [GitHub manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
and [Cloudflare Direct Upload CI](https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/).
