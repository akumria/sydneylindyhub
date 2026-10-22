# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event, "#workshop?", :aggregate_failures do
  let(:date) { Date.current + 3.days }
  let(:event) do
    build(:class, class_organiser: create(:organiser), title: "Blues workshop", frequency: 0, day: nil,
                  first_date: date, last_date: date, last_verified_at: Time.current,
                  source_notes: "Primary source confirmed", workshop_exception_reason: "Visiting Blues teachers",
                  event_instances: [build(:event_instance, date:)])
  end

  it "allows the verified dated exception" do
    expect(event).to be_valid
  end

  it "retains the rejection of ordinary standalone workshops" do
    event.workshop_exception_reason = nil
    expect(event).not_to be_valid
    expect(event.errors[:frequency]).to be_present
    expect(event.errors[:base]).to be_present
  end

  it "requires Sydney editorial policy" do
    stub_const("CITY", City.build_london)
    expect(event).not_to be_valid
  end

  [[:has_class, false], [:has_social, true], [:has_taster, true], [:frequency, 1], [:day, "Tuesday"],
   [:title, nil], [:class_organiser, nil], [:last_verified_at, nil], [:source_notes, nil],
   [:first_date, nil], [:last_date, nil]].each do |field, value|
    it "rejects an invalid #{field}" do
      event.public_send("#{field}=", value)
      expect(event).not_to be_valid
    end
  end

  it "requires exactly one confirmed instance" do
    event.event_instances = []
    expect(event).not_to be_valid
    event.event_instances.build(date:)
    event.event_instances.build(date: date + 1.day)
    expect(event).not_to be_valid
  end
end
