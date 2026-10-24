# Static publication operations

Production is live on Cloudflare Pages and publishes through GitHub Actions,
including the daily 04:15 Sydney schedule. The editor button now uses the same workflow; no local publisher worker is
needed on Fly. See
[current hosting status](../HOSTING.md) for verified deployment boundaries.

The canonical launch host is `www.sydneylindyhub.com`. Rails and PostgreSQL remain
the editorial system; the exported public site needs neither at request time.

## Generate

Build the assets first (`bin/rails assets:precompile`, or `bin/rake` in the
development container); `bin/publish-static-site` below does that for you. Then,
with the source database available:

```sh
CANONICAL_HOST=www.sydneylindyhub.com OUTPUT=tmp/static-release-001 bin/rails static_site:export
```

In development also set `HOST=www.sydneylindyhub.com` to permit that host.
The output must be a **new** directory. Failed exports raise an error and leave
an `EXPORT_FAILED` marker; never upload that directory. Export reads data but
does not send mail or change listings. It clears the Rails response cache and
temporarily disables Rack::Attack in the exporting process, so run it as a
separate CLI process, never inside a web request. Use a consistent source
snapshot or prevent edits during export for this prototype.

Output includes the public listings, information pages, name-clash page,
all seven class days, all fourteen listing dates, today/tomorrow aliases,
HTML and JSON map views, embedded popup contents, required assets, icons,
robots.txt, sitemap.xml, Cloudflare redirect/header files, and a generation
manifest. Everything in `public/` is copied as well, so the static site serves
the same icons, `ads.txt` and `404.html` the Rails server does; only
`.htaccess` is left behind. Venue highlighting uses the existing `venue_id`
query parameter in the browser. The obsolete `venue_map_info` route is not
needed: popups are already embedded in the marker data.

Only explicitly allowed public routes are rendered. No login, organiser edit
tokens, admin pages, audit feeds, database dumps or environment files are
copied. Maps browser keys are intentionally public; restrict them to the
published domain in Google Cloud. Google Maps remains an external dependency.

## Preview and publication

Serve the output directory with an ordinary static server, e.g.
`python3 -m http.server 8088 --directory tmp/static-release-001`.
Extensionless HTML URLs (`/about` is `about.html`) and `.json` map requests
work without Rails.
`node scripts/check-static-site.mjs tmp/static-release-001` in the
devcontainer runs an HTTP and Chromium smoke check against an isolated static
server. It checks the entire manifest plus mobile layout and navigation;
it does not exercise Google's external service; that is verified on the live
domain below.

`bin/publish-static-site` does the whole sequence and refuses to upload an
artifact that fails the smoke check:

```sh
CANONICAL_HOST=www.sydneylindyhub.com bin/publish-static-site          # export and check
CANONICAL_HOST=www.sydneylindyhub.com bin/publish-static-site --deploy # and upload
```

It builds the assets itself before exporting, refuses a `CANONICAL_HOST` with a
port in it, never overwrites an existing output directory, and exits if an
`EXPORT_FAILED` marker is present. Everything public in the export is generated
from `CANONICAL_HOST` — the sitemap, `robots.txt`, canonical links and the map
links — so export with the host the site will actually be served from. The
launch host is `www.sydneylindyhub.com`; the Maps browser key is public and must
be referrer-restricted to that host. The `pages.dev` hostname remains useful
for preview deployments.

Cloudflare Pages receives the entire output with Wrangler Direct Upload. The
first deploy needs `yarn dlx wrangler login` and a Pages project
(`yarn dlx wrangler pages project create sydneylindyhub`); each Direct Upload is
an immutable deployment, which is the rollback story.

The Cloudflare account ID is `8c3ce6c47f419321900a6ecd5148b0f6`. It is an
identifier, not a secret, and Wrangler picks it up from
`CLOUDFLARE_ACCOUNT_ID`. Only an unattended deploy needs a token at all, and
then it is a custom token with a single permission: Account, Cloudflare Pages,
Edit, scoped to that account. `wrangler login` covers every manual deploy.
`www.sydneylindyhub.com` is already attached to this Pages project as a custom
subdomain. Its CloudNS CNAME points to `sydneylindyhub.pages.dev`, HTTPS serves
the static site, and the apex redirects to `www`; no nameserver migration is
needed for the chosen launch host. The DNS and redirect were checked on
2026-10-20. Pages custom-subdomain setup is documented at
https://developers.cloudflare.com/pages/configuration/custom-domains/.

### Live launch-domain verification — 2026-10-20

Confirmed on `https://www.sydneylindyhub.com/`: Google Maps renders, DNS and
TLS work, the site looks correct on mobile, and `https://sydneylindyhub.com/`
redirects to `https://www.sydneylindyhub.com/`. Cloudflare serves the site from
its Sydney edge. The sitemap and `robots.txt` advertise the `www` host. These
checks are complete; verify rollback separately before launch.

## Deploying from an agent

Run deployment commands from the project devcontainer, where the app's pinned
Ruby/Node toolchain, database access and Chromium smoke-check dependencies are
available. The script publishes the static snapshot only; it does not deploy
Rails or run database migrations. Review the working tree and confirm the
connected database contains publishable data before deploying.

For a manual deploy, set the non-secret account ID and confirm Wrangler's
identity. If it is not logged in, use device authorization and approve it in a
browser; keep the device code and callback URL out of chat and source control:

```sh
export CLOUDFLARE_ACCOUNT_ID=8c3ce6c47f419321900a6ecd5148b0f6
yarn dlx wrangler whoami
# If needed: yarn dlx wrangler login --device
```

`www.sydneylindyhub.com` is attached and serving the production Pages project.
Preview the artifact first, then deploy it to the production branch:

```sh
CANONICAL_HOST=www.sydneylindyhub.com bin/publish-static-site
CANONICAL_HOST=www.sydneylindyhub.com bin/publish-static-site --deploy
```

The production project is `sydneylindyhub`, branch `main` (both are the script
defaults). The command builds assets, exports the current database snapshot,
checks every manifest URL plus mobile layout/navigation, and uploads only if
the check passes. Do not use `--skip-check` for production. Use
`CANONICAL_HOST=www.sydneylindyhub.com` for production exports so canonical
URLs and the sitemap use the launch host. `--branch NAME` creates a Pages
preview deployment instead of updating production.

After upload, verify the deployment and live endpoints:

```sh
yarn dlx wrangler pages deployment list --project-name sydneylindyhub
curl -sS -o /dev/null -w '%{http_code}\n' https://www.sydneylindyhub.com/
curl -sS -o /dev/null -w '%{http_code}\n' https://www.sydneylindyhub.com/map/socials
curl -sS -o /dev/null -w '%{http_code}\n' https://www.sydneylindyhub.com/sitemap.xml
```

For unattended CI, use a Cloudflare custom API token scoped to this account
with **Account → Cloudflare Pages → Edit** only. Store it as the CI secret
`CLOUDFLARE_API_TOKEN`; provide `CLOUDFLARE_ACCOUNT_ID` as a normal variable.
Never put the token in the repository, a command recorded in logs, or an agent
conversation. The device-flow login is stored in the devcontainer user's home
and may need to be repeated after the container is recreated.

## Current operations and remaining acceptance

- Supply verified listings, real contact details and reviewed legal content;
  development sample listings are not launch content.
- Publishing runs in GitHub Actions, including requests from the production
  editor button. Keep its Fly token valid and monitor failures.
- Configure `CANONICAL_HOST=www.sydneylindyhub.com` for public URLs and
  `EDITORIAL_HOST=edit.sydneylindyhub.com` for editor login emails, organiser
  update links and audit-feed URLs. Both settings are required and must be
  non-empty in production. The editorial host is deployed on Fly with verified
  DNS/TLS. Local development defaults to `localhost:3000`.
- Run an isolated export after edits. GitHub schedules daily publication at
  **04:15 Australia/Sydney**, after the 04:00 rollover and accounting for daylight
  saving. Date aliases are snapshots, not live routes.
  Alert on failed/stale exports, and only deploy complete successful releases.
  Exporting from a Neon branch, or any consistent snapshot, is better than
  asking editors to hold still: the guide above says not to promise
  transactional consistency, and a branch is how that promise is kept.
- Keep Rails editor login and organiser edit links on a separately configured
  editorial host. This export deliberately does not provide those workflows.
- Run organiser reminders separately; publishing static files does not send them.
- Test rollback before launch; Google Maps, mobile layout, DNS/TLS and the
  apex-to-www redirect were verified on 2026-10-20.
- Schedule database backups and prove restoration. Static output is not a
  replacement for the editorial database backup.
- The exported `_redirects` file sends `/occasional` to `/` with HTTP 302; it
  is not a separate static listing page.

The prototype exports a current snapshot, not a future dated release, and does
not promise transactional consistency while editors are changing the source.
No hosting or database migration is required to evaluate it.

## Editor publishing through GitHub

Production uses `STATIC_PUBLISH_BACKEND=github` and `STATIC_PUBLISH_ENABLED=true`.
The production Fly app also needs `GITHUB_ACTIONS_TOKEN`, a fine-grained personal
access token restricted to `akumria/sydneylindyhub` with Actions read/write.
Contents write is not needed. The token stays in Fly secrets and is never sent
in HTML or to the publication build. Staging remains disabled and has no token.

Signed-in editors open **Publish website** and submit a request. PostgreSQL's
existing unique active-publication index prevents duplicate/concurrent requests.
Rails dispatches only `publish-static-site.yml` on `main`, supplying a generated
request identifier. The workflow title contains that identifier; it is not used
as a shell command or export path. No schema migration is required.

Refresh status queries the fixed workflow's runs and matches the request's exact
identifier. The page links to the run and records queued, running, succeeded or
failed. Status is refreshed on page requests, not by a background worker; a run
can finish while the stored status remains queued/running until the next refresh.
GitHub's workflow serializes button, manual and scheduled publications and only
succeeds after live manifest verification.

An explicit API rejection marks the request failed. A dispatch timeout or server
error has an uncertain outcome: the request stays active and blocks another
button click. Refresh status to find the run; never automatically redispatch.
If it cannot be reconciled, a maintainer must inspect GitHub and the public site
before marking that specific request failed. The lookup checks up to 100 manual
runs created since just before the request; very old or deleted runs can require
manual reconciliation. API failures display a generic error without credentials
or GitHub response bodies. Renew expired tokens before retrying.

## Optional local worker backend

The original worker remains available when `STATIC_PUBLISH_BACKEND` is unset.
It requires the publisher runtime, its Cloudflare credentials and a supervised
`bin/rails static_site:publication_worker` process. It does not claim GitHub-backed
requests. Do not run this worker against the production queue configured above.
No such worker is hosted on Fly. Public publishing remains off the web machine.
