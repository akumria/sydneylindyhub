# frozen_string_literal: true

# Data object for configuring the starting location and zoom level of a map.
class MapConfig
  def initialize(center:, zoom:)
    @center = center
    @zoom = zoom
  end

  attr_reader :center

  def to_h
    {
      center: {
        lat: @center.lat,
        lng: @center.lng
      },
      zoom: @zoom
    }
  end
end

Coordinates = Data.define(:lat, :lng) do
  def distance_to(coordinates)
    Geocoder::Calculations.distance_between(deconstruct, coordinates.deconstruct)
  end
end

UK_POSTCODE_REGEXP = /\A^[a-z]{1,2}\d[a-z\d]?\s*\d[a-z]{2}\z/i
AUSTRALIAN_POSTCODE_REGEXP = /\A\d{4}\z/

City = Data.define(:key, :map_config, :max_radius_miles, :opengraph_image, :postcode_regexp, :country) do
  class << self
    def build_london
      map_config = MapConfig.new(
        center: Coordinates.new(lat: 51.526532, lng: -0.087777), # Bar Nightjar
        zoom: 11
      )
      max_radius_miles = 16 # Greater than the distance between Nightjar and Heathrow
      new(
        key: :london,
        map_config:,
        max_radius_miles:,
        opengraph_image: "swingoutlondon_og.png",
        postcode_regexp: UK_POSTCODE_REGEXP,
        country: "United Kingdom"
      )
    end

    def build_bristol
      map_config = MapConfig.new(
        center: Coordinates.new(lat: 51.4750364, lng: -2.5659198),
        zoom: 12
      )
      max_radius_miles = 4.5 # Greater than the distance between central Bristol and Keynsham
      new(
        key: :bristol,
        map_config:,
        max_radius_miles:,
        opengraph_image: "swingoutbristol_og.png",
        postcode_regexp: UK_POSTCODE_REGEXP,
        country: "United Kingdom"
      )
    end

    def build_sydney
      map_config = MapConfig.new(
        center: Coordinates.new(lat: -33.8688, lng: 151.2093),
        zoom: 10
      )
      max_radius_miles = 40
      new(
        key: :sydney,
        map_config:,
        max_radius_miles:,
        opengraph_image: "sydney_lindy_hub_og.svg",
        postcode_regexp: AUSTRALIAN_POSTCODE_REGEXP,
        country: "Australia"
      )
    end
  end

  def london?
    key == :london
  end

  def sydney?
    key == :sydney
  end

  def center_coordinates
    map_config.center
  end
end

CITY =
  case ENV.fetch("CITY", "sydney")
  when "london"
    City.build_london
  when "bristol"
    City.build_bristol
  else
    City.build_sydney
  end
