# Fly.io editorial environments

Both editorial apps use the existing Dockerfile's `web` target in Fly organisation
`personal`, primary region `syd`. Public pages stay on Cloudflare Pages, databases
stay on Neon, and publishing stays in GitHub Actions.

| Environment | Fly app | Browser hostname | Config |
| --- | --- | --- | --- |
| Staging | `sydneylindyhub-staging-editor` | `sydneylindyhub-staging-editor.fly.dev` | `fly.staging.toml` |
| Production | `sydneylindyhub-prod-editor` | `edit.sydneylindyhub.com` | `fly.prod.toml` |

The initial config is a shared CPU, 512 MB RAM, three Puma threads, HTTPS and
`/up` health checks. Autostop/autostart allows zero running machines when idle.
Verify memory and cold-start behaviour under actual editing load. Root filesystem
storage and other resources can still incur charges while machines are stopped.
No Fly database or volume is needed. The web image has no Chromium or publisher.

## Secrets

Copy each `.env.fly-ENV-editor.example` to `.env.fly-ENV-editor`, fill it locally
and run `chmod 600` on the resulting file. Both real files are Git-ignored.
Never import the development `.env` wholesale; it has development-only settings.

| Setting | Staging | Production |
| --- | --- | --- |
| `DATABASE_URL` | Writable direct TLS URL for the staging Neon branch | Writable direct TLS URL for production |
| `SECRET_KEY_BASE` | A unique generated secret | A different persistent generated secret |
| `SMTP_USER_NAME`, `SMTP_PASSWORD` | Dedicated test Gmail account/app password | Real sender Gmail account/app password |
| Maps JavaScript/static keys and map ID | Restricted to staging where applicable | Restricted to production where applicable |

Generate each Rails signing secret once with `openssl rand -hex 64` and store it
in its local secret file. Do not paste credentials into chat or command arguments.
The current mailer uses Gmail SMTP. Browser Maps keys are public in rendered pages,
so API/referrer restrictions are essential; keys may be shared if correctly scoped.
The static Maps key is separate from a referrer-restricted browser key.

Do not use the read-only `site_publisher` role for editing or migrations. The
release command checks for pending migrations using the restricted role; it does
not apply them. Run required migrations separately with the database owner over
a direct Neon endpoint, then redeploy. Do not store owner credentials in the web
app. Do not point staging at production. Confirm a restore path before running
production migrations, and do not schedule staging organiser reminders.

## Deploy

Deploy staging first, using its own credentials:

```sh
fly secrets import --stage -a sydneylindyhub-staging-editor < .env.fly-staging-editor
fly deploy --remote-only --ha=false -c fly.staging.toml
fly status -a sydneylindyhub-staging-editor
fly checks list -a sydneylindyhub-staging-editor
```

After verifying staging, deploy production:

```sh
fly secrets import --stage -a sydneylindyhub-prod-editor < .env.fly-prod-editor
fly deploy --remote-only --ha=false -c fly.prod.toml
fly status -a sydneylindyhub-prod-editor
fly checks list -a sydneylindyhub-prod-editor
```

`--ha=false` avoids creating spare machines. `bin/rails db:abort_if_pending_migrations`
runs before web deployment and refuses a release if Neon needs migrations. It does
not migrate, seed or import data. The two environments have
separate sessions, database connections and mail credentials. Cloudflare API
tokens and Fly management tokens are not required by the Rails runtime.

`CANONICAL_HOST=www.sydneylindyhub.com` is for public links in both environments.
`EDITORIAL_HOST` is the environment-specific browser hostname in the table above.
`RAILS_ASSUME_SSL=true` accounts for Fly's TLS proxy. `STATIC_PUBLISH_ENABLED=false`
keeps the editor Publish button disabled: GitHub currently handles publication.

## DNS and TLS

The staging `.fly.dev` hostname has Fly-managed DNS and HTTPS. It is explicitly
allowed by staging Rails configuration and is used for staging email links.

At CloudNS, add these production records. No nameserver change is required:

| Type | Name | Value |
| --- | --- | --- |
| A | `edit` | `66.241.124.190` |
| AAAA | `edit` | `2a09:8280:1::1ca:8015:0` |

The production certificate request was created on 25 October 2026. These records
supersede the addresses briefly allocated to the now-deleted `sydneylindyhub-editor`
app. Confirm addresses with `fly ips list` if apps are recreated. Remove conflicting
records for `edit` only. The generated production `.fly.dev` hostname is not in
Rails's normal host allowlist; production browser requests use the custom hostname.

```sh
fly certs check edit.sydneylindyhub.com -a sydneylindyhub-prod-editor
curl --fail https://edit.sydneylindyhub.com/up
curl --fail https://edit.sydneylindyhub.com/login
```

`/up` proves boot only. Verify database-backed pages, receipt of login emails,
the environment-specific link hostname, sign-in and saving an edit. Verify real
client-IP handling for throttling. Publish production edits through GitHub and
check the public output. Organiser reminder scheduling is a separate operation.

## Provisioning status

- Both apps, shared IPv4 and IPv6 created in `personal`.
- Production certificate requested; DNS validation remains pending.
- Configurations use Sydney; machines will be placed there by deployment.
- The production web image built and was uploaded successfully on 25 October 2026:
  `registry.fly.io/sydneylindyhub-prod-editor:deployment-01M5Q1GSBXCMSK8NWRYBZB9NKR`
  (reported compressed size: 133 MB). No runtime secrets were used for the build.
- Runtime secrets, schema readiness, deployment and login/editing acceptance are pending.
- An initial build for the superseded app was cancelled when the two-app naming
  was requested. It did not deploy or access Neon; the unused app was removed.

References: [Fly configuration](https://docs.fly.io/reference/configuration),
[autostop/autostart](https://docs.fly.io/launch/autostop-autostart),
[custom domains](https://docs.fly.io/networking/custom-domain).
