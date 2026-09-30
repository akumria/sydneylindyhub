# frozen_string_literal: true

require "rails_helper"

RSpec.describe City do
  describe ".build_sydney" do
    subject(:city) { described_class.build_sydney }

    it "defines the Sydney map, address, and branding defaults", :aggregate_failures do
      expect(city).to have_attributes(
        key: :sydney,
        center_coordinates: Coordinates.new(lat: -33.8688, lng: 151.2093),
        max_radius_miles: 40,
        country: "Australia",
        opengraph_image: "sydney_lindy_hub_og.svg"
      )
      expect(city.postcode_regexp).to match("2042")
      expect(city.sydney?).to be true
    end
  end
end
