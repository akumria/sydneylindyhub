# frozen_string_literal: true

require "rails_helper"
require "static_site_exporter" if Rails.root.join("lib/static_site_exporter.rb").exist?
require "tmpdir"

RSpec.describe "Workshop static export", :aggregate_failures do
  around do |example|
    ClimateControl.modify(CANONICAL_HOST: "www.sydneylindyhub.com") { example.run }
  end

  it "exports the dated workshop without private approval or editor links" do
    skip "Static exporter is not installed in this checkout" unless defined?(StaticSiteExporter)

    form = WorkshopForm.new(title: "Confirmed Blues workshop", url: "https://example.org/workshop",
                            venue_id: create(:venue).id, class_organiser_id: create(:organiser).id,
                            date: SOLDNTime.today + 2.days, last_verified_at: Time.current,
                            source_notes: "PRIVATE checked source", workshop_exception_reason: "PRIVATE exception")
    expect(form.save(Event.new)).to be true
    Dir.mktmpdir do |directory|
      output = Pathname.new(directory).join("site")
      StaticSiteExporter.new(output:, host: "www.sydneylindyhub.com").export
      expect(output.join("index.html").read).to include("Confirmed Blues workshop", "Workshops")
      expect(output.join("index.html").read).not_to include("PRIVATE", "/workshops/new")
    end
  end
end
