# Optional production web container

The root Dockerfile builds a Rails web image with precompiled JavaScript and
CSS. Its default `web` target uses the Ruby version currently pinned by this
repository and Node 22 for asset compilation. The runtime contains production
gems and assets, runs as UID 10001, and has no Node, build compiler or browser.
Existing Procfile deployments are unaffected.

```sh
podman build -t localhost/swing-out-london-web:local .
bin/check-production-container
```

Docker is also supported: build the same Dockerfile and set
`CONTAINER_ENGINE=docker` for the check. `CONTAINER_IMAGE` overrides its image
name. The check creates an empty disposable PostgreSQL 14 database and network,
runs the existing `release` task, checks database access and HTTP responses,
then removes its containers and network. It never reads the development
or production database. Logs remain under `tmp/container-check-<pid>/`.

## Running

Supply `DATABASE_URL`, `SECRET_KEY_BASE`, and `CANONICAL_HOST` at runtime.
Configure existing Facebook, Google Maps, SMTP, MemCachier and other application
settings as appropriate for your deployment. No provider resources or settings
are provisioned by the image. The build uses only placeholder host/secret values
and requires no database or production credentials.

Puma listens on `PORT` (8080 by default). Run the existing release command
explicitly against the target database before starting web processes:

```sh
podman run --rm --env-file /path/to/runtime.env localhost/swing-out-london-web:local bin/rails release
podman run --env-file /path/to/runtime.env -p 8080:8080 localhost/swing-out-london-web:local
```

The image does not migrate on web startup. Protect the runtime environment file;
it is supplied at runtime and is not part of the build context.

Place the app behind a trusted TLS-terminating proxy. Preserve the forwarded
HTTPS scheme, or set `RAILS_ASSUME_SSL=true` when every request comes through
that proxy. Leave it unset when the proxy assumption is inappropriate. Rails
continues to enforce HTTPS and secure cookies.

`/up` is a boot/liveness check, not a database readiness check. It skips Rails'
HTTPS redirect and host authorization, but the existing outer canonical-host
middleware still applies. Send `Host: <CANONICAL_HOST>` with container probes;
the smoke check does this. Other paths retain host and HTTPS enforcement.

The build context is allowlisted to application files. Local environment files,
Git metadata, Rails keys and database dumps are excluded. Upstream's tracked
`public/assets` error-page CSS and images are retained alongside precompiled
assets. Supply secrets only at runtime. This image adds no publisher, queue,
static export, hostname split or automatic deployment.
