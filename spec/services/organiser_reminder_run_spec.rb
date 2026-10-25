# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrganiserReminderRun, :aggregate_failures do
  let(:output) { StringIO.new }
  let(:runner) { described_class.new(output:) }
  let(:event) do
    create(:social, :occasional, :with_organiser_token, title: "Due social",
                                                        reminder_email_address: "organiser@example.com", dates: [])
  end

  def send_options
    { mode: "send", event_ids: [event.id] }
  end

  it "defaults to a preview without sending or writing history, redacting the recipient and update token" do
    event
    expect { runner.call }.not_to change(EmailDelivery, :count)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(output.string).to include('"would_send":1', "o***@example.com", "[PRIVATE UPDATE TOKEN]", "missing dates")
    expect(output.string).not_to include(event.organiser_token, "organiser@example.com")
  end

  it "reports an empty database accurately" do
    expect(runner.call).to include(reviewed: 0, would_send: 0, submitted: 0, skipped: 0)
  end

  it "filters previews to the explicitly selected event IDs" do
    event
    expect(runner.call(event_ids: [0])).to include(reviewed: 0)
  end

  it "rejects unsupported modes" do
    expect { runner.call(mode: "other") }.to raise_error(ArgumentError)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "submits synchronously and records only accepted mail" do
    result = runner.call(**send_options)
    expect(result).to include(reviewed: 1, submitted: 1, unconfirmed: 0)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(event.email_deliveries.count).to eq(1)
    expect(output.string).to include(ActionMailer::Base.deliveries.last.message_id)
  end

  it "sends all eligible contacts when no event IDs are provided" do
    event
    result = runner.call(mode: "send")
    expect(result).to include(reviewed: 1, submitted: 1)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[event.reminder_email_address]])
  end

  it "skips recently submitted reminders and future listings" do
    event.email_deliveries.create!(recipient: event.reminder_email_address)
    create(:social, :occasional, :with_organiser_token, reminder_email_address: "listed@example.com", dates: [Date.tomorrow])
    expect(runner.call).to include(skipped: 2, would_send: 0)
    expect(output.string).to include("recent_submission", "listed")
  end

  it "skips incomplete imported contacts instead of attempting an unusable email" do
    # rubocop:disable Rails/SkipsModelValidations -- exercise imported invalid data
    event.update_columns(reminder_email_address: "")
    expect(runner.call).to include(skipped: 1)
    event.update_columns(reminder_email_address: "organiser@example.com", organiser_token: nil)
    # rubocop:enable Rails/SkipsModelValidations
    expect(runner.call).to include(skipped: 1)
    expect(output.string).to include("no_recipient", "no_update_link")
  end

  it "handles a reminder becoming recent after the preview check" do
    sender = instance_double(OrganiserReminderSender, send!: nil)
    result = described_class.new(sender:, output:).call(**send_options)
    expect(result).to include(submitted: 0, skipped: 1)
  end

  it "stops on uncertain submission, reports counts and does not expose exception details" do
    sender = instance_double(OrganiserReminderSender)
    allow(sender).to receive(:send!).and_raise(IOError, "secret private-link")
    expect do
      described_class.new(sender:,
                          output:).call(**send_options)
    end.to raise_error(described_class::Unconfirmed, /Inspect Fastmail/)
    expect(output.string).to include('"unconfirmed":1', '"submitted":0')
    expect(output.string).not_to include("secret private-link")
  end

  it "refuses a concurrent sender if the database lock is already held" do
    connection = ActiveRecord::Base.connection
    allow(connection).to receive(:select_value).and_call_original
    sql = "SELECT pg_try_advisory_lock(#{described_class::LOCK_ID})"
    allow(connection).to receive(:select_value).with(sql).and_return(false)
    expect { runner.call(**send_options) }.to raise_error(described_class::Unconfirmed, /Another reminder batch/)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "refuses a pooled endpoint before taking a session lock or sending mail" do
    config = double(configuration_hash: { host: "ep-example-pooler.neon.tech" })
    allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(config)
    expect { runner.call(**send_options) }.to raise_error(ArgumentError, /direct database/)
  end

  it "refuses a read-only credential before submitting any mail" do
    allow(ActiveRecord::Base.connection).to receive(:select_value).and_return(false)
    expect { runner.call(**send_options) }.to raise_error(ArgumentError, /permission to record/)
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
