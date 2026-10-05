# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Audit Log RSS feed" do
  around do |example|
    ClimateControl.modify(CANONICAL_HOST: "sydneylindyhub.com") { example.run }
  end

  it "displays an RSS feed of audit events" do # rubocop:disable RSpec/ExampleLength
    audit_user = { "auth_id" => "abc123", "name" => "Pepsi Bethel" }
    Audited.store[:current_user] = -> { audit_user }

    venue = create(:venue, name: "The Alhambra")
    venue.update!(name: "La Mesquita")
    venue.destroy!

    social_dance = create(:social, title: "The Wednesday Stomp", url: "https://stomp.uk")
    social_dance.update!(title: "The Tuesday Stamp")
    social_dance.destroy!

    class_organiser = create(:organiser, name: "Maggie McMillan")
    dance_class = create(:class, url: "https://weds", class_organiser:)

    organiser = create(:organiser, name: "Johnny Waters")
    organiser.update!(name: "Jimmy Fire")
    organiser.destroy!

    ClimateControl.modify(AUDIT_LOG_PASSWORD: "pass") do
      get "/audit_log.atom?password=pass"
    end

    aggregate_failures do
      expect(response.media_type).to eq("application/atom+xml")
      expect(response.body).to include("Sydney Lindy Hub Audit Log")
      expect(response.body).to include("https://sydneylindyhub.com/audit_log.atom")
      expect(response.body).to include("Create Class (id: #{dance_class.id})")
      expect(response.body).to include("Delete Venue (id: #{venue.id})")
      expect(response.body).to include("Delete Organiser (id: #{organiser.id})")
      expect(response.body).to include("Pepsi Bethel")
    end
  end
end
