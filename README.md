# Sydney Lindy Hub

Sydney Lindy Hub is an independent directory of swing dance classes and events
in Sydney, NSW. It is a maintained fork of
[Swing Out London](https://www.swingoutlondon.co.uk) and retains its compact
calendar and map interface.

## Setup

### Development container

The reproducible development environment includes Ruby 4.0.7, Node 22,
Yarn 4.2.2, PostgreSQL 17, Firefox, and Chromium. Open the repository in an
editor that supports the
[Development Containers specification](https://containers.dev/),
then rebuild/open it in the container. The container runs
`bin/devcontainer-setup` after creation.

Once setup completes:

    bin/dev

The application is available at <http://localhost:3000>. Run the test and lint
suite with:

    bin/rake

`bin/rake` also builds the asset bundles, which the browser-driven system specs
load: the Sass is compiled by a `dartsass:build` step, and `jsbundling-rails`
hangs `javascript:build` off the `spec` task. Running the specs any other way
skips both, so the specs would test the previous build. Prefer `bin/rake`
unless you have just built the bundles yourself.

The PostgreSQL data and installed gems live in named container volumes. The
application source remains in the repository checkout.

### Prerequisites

- [Yarn](https://yarnpkg.com/en/docs/install/) is used in development.
- [Postgres](https://www.postgresql.org/) is the database. If you don't have a
preference for how to run Postgres locally we recommend
[Postgres.app](https://postgresapp.com/).

The postgres version you run locally should match the version used in production.
If the app is deployed on Heroku (and you have access to it) you can check this with the
[Heroku CLI](https://devcenter.heroku.com/articles/heroku-cli).

For example, to get the version used on Swing Out London production:

    heroku pg:info --app soldneu

Other dependencies (including ruby) are listed in
[`.tool-versions`](.tool-versions).

We recommend using [asdf](https://github.com/asdf-vm/asdf) and running `asdf
install` to install these. If you're already managing dependencies in a
different way, ensure that you install the versions listed in
`.tool_versions`.

Set up the app from scratch:

    bin/setup

Run the tests and linters:

    bin/rake

The devcontainer also installs Chromium, which only the screenshot harness
needs - see "Reviewing the UI" below.

### Local development

See [`Procfile.dev`](Procfile.dev): run each command in its own terminal, or
run them together using the heroku CLI (installed as part of the bundle):

    heroku local -f Procfile.dev

#### Previewing emails

Emails sent by the site can be previewed in the development environment at
[/rails/mailers](http://localhost:3000/rails/mailers).

#### Reviewing the UI

`yarn screenshots` captures every public and editor page at 1280px and 375px
into `tmp/ui-review`, and prints the measured document width of each. Use it to
review a layout change, or before a release, since the specs assert on text and
not on how the page looks.

It signs in as `editor@example.com`, which only works with `SKIP_LOGIN=true`
(the `.env.example` default). Override with `EDITOR_EMAIL`, `BASE_URL` and
`OUT_DIR`.

The report flags two things worth reading rather than skimming: a page whose
document is wider than its viewport, and a failed subresource. A failed
subresource matters because `Rack::Attack` throttles at 5 requests per 2
seconds and a single page view can exceed that, so a 429 leaves a page
screenshotting a broken image with no error anywhere else. Re-run after a pause
if the report lists one.

This uses Playwright rather than the specs' Selenium driver because Firefox
clamps its window to about 450px wide: `resize_to(375, 800)` lands on 450, and
`-width`/`--window-size` are ignored at launch, so a "phone" screenshot is
silently a desktop one. The specs are unaffected and stay on Selenium.

## Environment Variables

This project uses [.env](https://github.com/bkeepers/dotenv) to manage
environment variables.

See [`.env.example`](.env.example) for documentation of environment variables
which can be used in development, some of which are required for the
application to run.

Running `bin/setup` command will copy this file to your `.env` - that's the
file you'll need to modify in order to change these variables. Restart your
server after editing this file.

### Production environment Variables

The following variables are only used in the production environment and so
are not included in the .env.example file:

  - `IP_BLOCKLIST` (optional) A comma-separated list of IP addresses which
    should be blocked (e.g. spambots, attackers). _Example:
    `119.29.55.93,62.210.111.122`_
  - `ROLLBAR_POST_SERVER_ITEM_ACCESS_TOKEN` [Rollbar](https://rollbar.com/) is
    used for exception reporting. This value can be found in Account Settings
    => Account Access Tokens in your Rollbar account.
  - `CANONICAL_HOST` - all variations of the domain will be `301` redirected
    to this. Set it to `www.sydneylindyhub.com` to have
    `sydneylindyhub.com` redirect to www, or the reverse. The sitemap, the audit
    log feed, and the URLs in reminder emails are all built from it, so it must
    match the domain actually served.

## Environments

- Sydney Production: [Sydney Lindy Hub](https://www.sydneylindyhub.com/) (Cloudflare Pages)

Upstream deploys three sites using this codebase on heroku:

- London Production: https://www.swingoutlondon.co.uk/ (heroku app: `soldneu`)
- Bristol Production: https://www.swingoutbristol.org/ (heroku app:
  `swing-out-bristol`)
- Staging: https://soldn-staging.herokuapp.com/ (heroku app: `soldn-staging`)- used for testing changes.
(Protected by HTTP Basic Authentication)
