# frozen_string_literal: true

require "json"

# Manual batch runner. Previews never submit mail or write delivery records.
class OrganiserReminderRun
  LOCK_ID = 7_241_025
  Unconfirmed = Class.new(StandardError)

  def initialize(sender: OrganiserReminderSender.new, output: $stdout)
    @sender = sender
    @output = output
  end

  def call(mode: "dry-run", event_ids: [])
    raise ArgumentError, "Mode must be dry-run or send" unless mode.in?(%w[dry-run send])
    return process(event_ids, dry_run: true) if mode == "dry-run"

    with_lock { process(event_ids, dry_run: false) }
  end

  private

  def with_lock
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      verify_write_access(connection)
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_ID})")
      raise Unconfirmed, "Another reminder batch holds the lock" unless locked

      begin
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{LOCK_ID})")
      end
    end
  end

  def process(ids, dry_run:)
    events = Event.notifiable.order(:id)
    events = events.where(id: ids) if ids.any?
    counts = { reviewed: 0, would_send: 0, submitted: 0, skipped: 0, unconfirmed: 0 }
    events.each { |event| process_event(event, counts, dry_run:) }
    counts
  ensure
    emit(mode: dry_run ? "dry-run" : "send", summary: counts) if counts
  end

  def process_event(event, counts, dry_run:)
    counts[:reviewed] += 1
    reason = skip_reason(event)
    if reason
      counts[:skipped] += 1
      emit(event_id: event.id, outcome: "skipped", reason:)
    else
      process_due(event, counts, dry_run:)
    end
  end

  def verify_write_access(connection)
    if ActiveRecord::Base.connection_db_config.configuration_hash[:host].to_s.include?("-pooler.")
      raise ArgumentError, "Send requires a direct database endpoint for its session lock"
    end

    sql = "SELECT has_table_privilege(current_user, 'public.email_deliveries', 'INSERT') AND " \
          "has_sequence_privilege(current_user, pg_get_serial_sequence('public.email_deliveries', 'id'), 'USAGE')"
    raise ArgumentError, "Send requires permission to record accepted submissions" unless connection.select_value(sql)
  end

  def skip_reason(event)
    return "no_recipient" if event.reminder_email_address.blank?
    return "no_update_link" if event.organiser_token.blank?
    return "listed" unless EventStatus.new.status_for(event) == :not_listed
    return "recent_submission" if event.last_reminder_delivered_at&.after?(1.week.ago)

    nil
  end

  def process_due(event, counts, dry_run:)
    dry_run ? preview_due(event, counts) : submit(event, counts)
  rescue StandardError => e
    counts[:unconfirmed] += 1
    emit(event_id: event.id, outcome: "unconfirmed", error_class: e.class.name)
    raise Unconfirmed, "Batch stopped. Inspect Fastmail Sent and delivery history before retrying event #{event.id}."
  end

  def preview_due(event, counts)
    counts[:would_send] += 1
    preview(event)
  end

  def submit(event, counts)
    message = @sender.send!(event)
    counts[message ? :submitted : :skipped] += 1
    emit(event_id: event.id, outcome: message ? "submitted" : "skipped", message_id: message&.message_id)
  end

  def preview(event)
    message = @sender.preview(event)
    local, domain = event.reminder_email_address.split("@", 2)
    body = message.text_part.body.decoded.gsub(event.organiser_token, "[PRIVATE UPDATE TOKEN]")
    emit(event_id: event.id, title: event.title, recipient: "#{local.first}***@#{domain}",
         outcome: "would_send", subject: message.subject, body:)
  end

  def emit(data)
    @output.puts(JSON.generate(data))
  end
end
