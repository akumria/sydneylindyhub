# frozen_string_literal: true

# Responsible for abstracting away how reminders are sent to organisers about an event
class OrganiserReminderSender
  def initialize(mailer: OrganiserMailer)
    @mailer = mailer
  end

  def send!(event)
    return if event.last_reminder_delivered_at&.after?(1.week.ago)

    message = mailer.reminder_email(to: event.reminder_email_address, event:).deliver_now
    event.email_deliveries.create!(recipient: event.reminder_email_address)
    message
  end

  def preview(event)
    mailer.reminder_email(to: event.reminder_email_address, event:).message
  end

  private

  attr_reader :mailer
end
