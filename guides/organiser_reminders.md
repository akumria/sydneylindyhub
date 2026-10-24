# Manual organiser reminders

Use **Actions → Organiser reminders → Run workflow** on `main`. There is no
schedule and no automatic send. Leave mode at **dry-run** for normal review.
The existing public-site publication workflow is independent.

## First configure retained Sent copies

In Fastmail, open **Settings → My email addresses → hello@sydneylindyhub.com →
Show advanced composing preferences**. In **Save sent messages in**, select
Sent (or a dedicated folder) and enable saving messages sent through third-party
clients. Verify the setting by requesting a login email and checking its copy.
The application does not save messages through IMAP or silently BCC anyone.

[Fastmail's alias options](https://www.fastmail.help/hc/en-us/articles/360060591073-How-to-set-up-aliases#advanced-composing-preferences)
describe this setting. A retained copy or SMTP acceptance is not proof of delivery
to the organiser. Fastmail Sent is the message archive; PostgreSQL keeps accepted
submission history. Older `email_deliveries` records predate the recording fix
and must not be treated as conclusive evidence of SMTP acceptance.

## Dry-run

The workflow uses the existing `production` environment's
`PUBLICATION_DATABASE_URL` read-only secret. No SMTP credentials are supplied.
It builds the `web` image, checks schema readiness and runs
`bin/rails send_not_listed_reminders` in its default dry-run mode.

Leave `event_ids` blank to review all events with configured reminder contacts,
or supply comma-separated numeric event IDs to narrow the review. It considers
only contacts with an organiser update token, no current/future listing, and no
recorded submission in the previous seven days.

Output contains event IDs, titles, masked recipients, subjects and plain-text
message previews. Private organiser tokens are replaced before printing. The
repository's workflow logs may be public: full addresses and update links must
not be added to the logs or uploaded as artifacts. Review the full recipient in
the authenticated editor. Dry-run sends nothing and writes no delivery records.

The summary distinguishes `reviewed`, `would_send`, `submitted`, `skipped` and
`unconfirmed`. A successful empty dry-run means no eligible configured contacts;
it does not prove Fastmail delivery or Sent-copy retention.

## Enable manual send

Create a separate GitHub environment named **production-reminders**. Restrict it
to `main` and configure required reviewers if available on the repository's plan.
Add these environment secrets:

| Secret | Value |
| --- | --- |
| `REMINDER_DATABASE_URL` | Direct, TLS-protected Neon connection with SELECT access and INSERT/sequence USAGE for `email_deliveries`; the existing `site_editor` role is sufficient |
| `SMTP_USER_NAME` | The Fastmail account login, which may differ from the From alias |
| `SMTP_PASSWORD` | A dedicated Fastmail mail-access app password |

No Cloudflare credential, GitHub API token, migration owner credential or
persistent Rails signing secret is required. Credentials stay out of the build.
Do not use the read-only publisher connection as the send connection. Send mode
checks delivery-table/sequence permissions before submitting mail and refuses
Neon pooled endpoints because its overlap lock is session-scoped.

Run another dry-run, then start the workflow with:

- `mode`: **send**
- `event_ids`: only the event IDs you just reviewed
- `confirmation`: **SEND**
- `sent_copy_confirmed`: checked, after verifying Fastmail's setting

Approve the environment deployment if review protection is enabled. The task
rechecks eligibility rather than trusting the earlier preview. Sends are
synchronous; history is inserted only after Fastmail accepts the message. The
report includes the Message-ID for matching accepted mail in Fastmail Sent.
No database schema migration is required.

## Failure and retry handling

GitHub concurrency serializes workflow runs. A PostgreSQL advisory lock also
blocks overlapping manual batch send commands. Do not run an unrelated direct
mailer script as a parallel sender.

On a submission exception or failure to record an accepted message, the task
stops, reports the event ID as `unconfirmed`, prints counts and exits nonzero.
It does not automatically retry. SMTP and a database insert cannot be committed
atomically: the recipient may have received a message even if history is absent.
Check Fastmail Sent by event subject/time or Message-ID, then reconcile the
specific event's submission history before any retry. Do not blindly rerun a
failed send or bypass the seven-day limit. The batch never claims final inbox
delivery, and does not handle provider bounces automatically.

The old Ruby `OrganiserRemindersSender#send_unlisted` service remains for existing
callers; it now counts actual submissions and sends synchronously. Operational
runs should use the guarded workflow/task above, not invoke that service directly.
Staging must use captured delivery or a dedicated test mailbox; never run this
production workflow against copied real contacts in a staging database.

## Local commands

Preview with an appropriate local/test or read-only production environment:

```sh
bin/rails send_not_listed_reminders
EVENT_IDS=20 bin/rails send_not_listed_reminders
```

Actual send requires all explicit approvals plus SMTP and writable database
configuration. Keep secrets in the environment, never command arguments:

```sh
MODE=send EVENT_IDS=20 CONFIRM=SEND SENT_COPY_CONFIRMED=true bin/rails send_not_listed_reminders
```

Implementing this workflow does not schedule reminders, configure contact
addresses, enable Fastmail Sent copies or add GitHub send credentials. Those
are separate operator actions. A live send rehearsal remains pending until an
explicitly approved test recipient is configured.
