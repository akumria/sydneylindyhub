# frozen_string_literal: true

desc "Preview organiser reminders; MODE=send requires EVENT_IDS, CONFIRM=SEND, SENT_COPY_CONFIRMED=true"
task send_not_listed_reminders: :environment do
  ids = ENV.fetch("EVENT_IDS", "").strip
  abort "EVENT_IDS must be comma-separated numeric IDs" unless ids.empty? || ids.match?(/\A\d+(,\s*\d+)*\z/)

  OrganiserReminderRun.new.call(mode: ENV.fetch("MODE", "dry-run"), event_ids: ids.split(",").map(&:to_i),
                                confirmation: ENV.fetch("CONFIRM", nil),
                                sent_copy_confirmed: ENV["SENT_COPY_CONFIRMED"] == "true")
rescue ArgumentError, OrganiserReminderRun::Unconfirmed => e
  abort e.message
end
