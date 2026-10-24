# frozen_string_literal: true

require "spec_helper"
require "app/services/organiser_reminder_sender"
require "active_support"
require "active_support/core_ext/numeric/time"

RSpec.describe OrganiserReminderSender do
  describe "send!" do
    it "submits an email and records acceptance" do
      mail = fake_mail
      mailer = fake_mailer(mail)
      event = instance_double("Event", reminder_email_address: "herbert@white.com", last_reminder_delivered_at: nil,
                                       email_deliveries: double(create!: true))
      sender = described_class.new(mailer:)

      sender.send!(event)

      aggregate_failures do
        expect(mailer).to have_received(:reminder_email).with(to: "herbert@white.com", event:)
        expect(mail).to have_received(:deliver_now)
      end
    end

    context "when an email has recently been sent" do
      it "does nothing" do
        mail = fake_mail
        mailer = fake_mailer(mail)
        event = instance_double("Event", reminder_email_address: "herbert@white.com", last_reminder_delivered_at: 1.day.ago)
        sender = described_class.new(mailer:)

        sender.send!(event)

        expect(mail).not_to have_received(:deliver_now)
      end
    end

    context "when an email was sent more than a week ago" do
      it "submits an email and records acceptance" do
        mail = fake_mail
        mailer = fake_mailer(mail)
        event = instance_double("Event", reminder_email_address: "herbert@white.com", last_reminder_delivered_at: 8.days.ago,
                                         email_deliveries: double(create!: true))
        sender = described_class.new(mailer:)

        sender.send!(event)

        expect(mail).to have_received(:deliver_now)
      end
    end

    it "renders a preview without submitting mail", :aggregate_failures do
      mail = fake_mail
      event = instance_double("Event", reminder_email_address: "herbert@white.com")
      sender = described_class.new(mailer: fake_mailer(mail))
      expect(sender.preview(event)).to eq(mail.message)
      expect(mail).not_to have_received(:deliver_now)
    end

    def fake_mailer(mail = fake_mail)
      class_double("OrganiserMailer", reminder_email: mail)
    end

    def fake_mail
      instance_double("ActionMailer::MessageDelivery", deliver_now: double, message: double)
    end
  end
end
