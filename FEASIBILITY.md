# Sydney Lindy Hub: implementation feasibility

## Recommendation

Start by adapting the open-source Swing Out London Rails application for a
Sydney-focused first release. Preserve its public listings interface and its
editorial workflow, while replacing the London-specific geography,
authentication, content, and branding.

Do not redesign the application around a national directory in the first
release. Keep the Sydney page's short, reliable 14-day window and weekly class
list. Add Australian festivals and exchanges as a separate second-stage
listing type with a longer time horizon.

Upstream source: <https://github.com/leveretweb/swing-out-london>

Inspected upstream revision:
`a580ae3c73307b03be1ba777e9423f21de1476ab` (2026-09-27).

## Why adapt the existing application

The valuable part of Swing Out London is not the visual design. It is the
small editorial system behind the page:

- events can be weekly or have individually confirmed dates;
- weekly events can have one-off cancellations;
- classes and socials can share an event and venue;
- venues and organisers are reusable records;
- organisers can receive restricted update links;
- stale events can trigger reminder emails;
- editors have roles and an audit trail;
- the public page and maps are cached; and
- listings are covered by an extensive automated test suite.

The current repository contains 795 test examples in 96 spec files, including
browser-level system coverage. It is active and has already been configured for a
second city, Bristol. A fresh implementation would need to recreate these
behaviours before it became equally trustworthy.

The code is GPLv3. A deployed modified version may be used, but any distributed
derivative must comply with the licence. The wallpaper and other credited
visual assets need their own permission/licence check before reuse. The Sydney
site should use its own name and artwork rather than imply affiliation with
Swing Out London.

## Current stack and local feasibility

Upstream currently uses:

- Ruby 4.0.7 and Rails 8.0.x;
- PostgreSQL;
- server-rendered ERB templates;
- Stimulus and Turbo for small interactions;
- Sass and Webpack/Yarn for assets;
- Google Maps JavaScript and Static Maps APIs;
- SMTP for organiser reminders;
- Facebook OAuth for editor identity; and
- a scheduled Rails task for reminder delivery.

The project now includes a reproducible development container with Ruby 4.0.7,
Node 22, Yarn 4.2.2, PostgreSQL 14, and Firefox. Its one-command setup installs
the locked dependencies, builds the assets, and prepares both databases.

The unchanged upstream baseline passes in this environment: 795 examples with
zero failures and 100% line coverage, 316 Ruby files with no RuboCop offenses,
61 ERB files with no lint errors, and a clean stylesheet lint.

## Sydney changes required for the first release

### City configuration

Add Sydney to `config/initializers/city.rb`, including:

- a central map coordinate;
- an initial map zoom;
- a coverage radius or a more explicit Greater Sydney boundary; and
- a Sydney Open Graph image.

The existing `CITY` environment variable can select Sydney just as it currently
selects Bristol. The default should become Sydney in the fork.

### Australian addresses

Replace the UK postcode assumptions with an Australian location presenter:

- validate four-digit postcodes;
- display the suburb as the compact location label, optionally followed by the
  postcode;
- retain the full street address for map popovers;
- remove the UK postcode-to-coordinate help link; and
- geocode the full address, suburb, state, postcode, and country.

The main affected code is the venue model, postcode presenter, listings helper,
venue form, map marker presenter, and the narrow fixed-width postcode CSS.

### Time and dates

Set the Rails time zone to `Australia/Sydney` and update audit-log text and
timezone tests. Preserve the existing rule that the listings day rolls over at
4 am, since socials may finish after midnight. Add explicit tests for both
Australian daylight-saving transitions.

### Site content and branding

Add Sydney entries to the city-aware translations and info-page configuration,
then write Sydney versions of:

- the introduction;
- the local scene guide;
- the listings policy;
- the contact and support text; and
- the social metadata and imagery.

The visual layout can remain essentially unchanged, but it needs original
branding and a licensed background treatment.

### Editor authentication

Replace Facebook OAuth. It couples the editor role table, login session,
account screen, token refresh, and some API code to Facebook identifiers.

For a small volunteer team, use passwordless email links or passkeys. Keep the
existing admin/editor roles and audit records. Do not expose general public
account creation in the first release.

### Maps and email

The application currently expects three Google Maps values and SMTP
credentials. Restrict browser keys by production hostname and server keys by
API/IP as appropriate. Use a transactional email provider rather than a
personal Gmail account for organiser reminders.

## Data entry for launch

The first dataset should be curated manually from primary organiser sources.
For each listing record:

- organiser and source URL;
- venue, suburb, postcode, latitude, and longitude;
- class/social flags and dance style;
- weekly recurrence or confirmed dates;
- first and last active dates;
- known cancellations; and
- date last verified.

The existing schema does not expose `last_verified_at`. Add it so readers and
editors can distinguish a current listing from an old recurring assumption.
Also add an internal source note for editors. Public links should continue to
lead to the organiser's authoritative page.

Do not scrape private Facebook group content for launch. Where Facebook is the
only source, editors should enter the relevant public event URL and verify it
manually.

## Australia-wide second stage

National events have different semantics from Sydney weekly listings. Add a
separate `Festival` or `RegionalEvent` model rather than stretching the current
`Event` record. It should support:

- start and end dates;
- city, state, country, and timezone;
- one or more dance styles;
- event format such as exchange, festival, workshop weekend, or competition;
- registration URL and status;
- annual-series identity without assuming next year's dates;
- source and last-verified timestamps; and
- cancelled/postponed status.

Display these on a separate Australia page with a 12-month horizon. Sydney
events may be linked between the two sections, but the short local calendar
should remain optimized for “where can I dance this week?”

## Delivery plan

### Phase 0: runnable fork

- Import upstream with its Git history and retain GPL notices.
- Add a pinned development environment for Ruby, PostgreSQL, Node, and Yarn.
- Run the upstream test and lint suite unchanged.
- Record the deployed source-code location required by the chosen GPL
  compliance approach.

Exit condition: a developer can clone the project, run one setup command, and
see the upstream application with its tests passing.

### Phase 1: Sydney adaptation

Status: complete.

- Add Sydney city configuration, timezone, Australian addresses, and content.
- Replace Facebook authentication.
- Create original branding while preserving the listing layout.
- Add `last_verified_at` and editor source notes.
- Seed a small representative dataset covering a weekly class, weekly social,
  monthly social, one-off event, cancellation, and hidden-address event.

Exit condition: all upstream behaviour still passes, Sydney-specific tests
cover addresses and daylight saving, and the desktop/mobile UI matches the
reference structure.

The first two are covered by the automated suite. The UI comparison is a
manual review and is not yet recorded here.

Testing both Australian daylight-saving transitions found a defect in the 4am
listings-day rollover. It compared "4 hours ago" against local midnight, but a
fixed duration is not a fixed number of hours on the clock across an offset
change, so on the night the clocks go back the listings page showed the current
date instead of the previous dance date between 3am and 4am. `SOLDNTime.today`
now compares the local wall-clock hour directly.

### Phase 2: operational launch

- Configure production PostgreSQL, maps, email, scheduled jobs, backups,
  monitoring, analytics, and domain/DNS.
- Load and verify the initial Sydney directory.
- Write the editorial checklist and nominate at least two maintainers.
- Add a simple correction/submission path that enters an editorial queue.

Exit condition: listings can be updated without developer access, reminders
run, backups are tested, and every launch listing has a recent verification
date.

### Phase 3: Australian events

- Add the national-event model and filters.
- Import events from primary organiser pages and selected public calendars.
- Add duplicate detection and an editor review queue before any automated
  ingestion is published.

## Effort and risk

For one developer familiar with Rails, a credible Sydney MVP is roughly two to
four focused weeks after the development environment is working. Authentication,
branding/assets, and initial data verification are more variable than the
Sydney code changes themselves. The national directory is a separate one-to-two
week feature before data collection and ongoing editorial work.

The largest ongoing risk is stale information, not software complexity. The
product should optimize for fast verification and correction: visible source
links, last-verified dates, cancellation exceptions, organiser reminders, and
an editor queue.

## Immediate next implementation step

Phases 0 and 1 are complete. The next implementation step is the Phase 2
operational launch work: production PostgreSQL, maps, email, scheduled jobs,
backups, monitoring, and domain/DNS, followed by loading and verifying the
initial Sydney directory.

One item still needs a decision before launch: `FORK_NOTICE.md` records that
the public source location is not yet chosen, and the About page colophon
cannot link to the corresponding source until a public repository exists.
