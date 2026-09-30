# frozen_string_literal: true

# Presenter exposing different ways to format a Postcode
class Postcode
  class << self
    def build(postcode_string, area: nil, city: CITY)
      if postcode_string.present?
        new(postcode_string, area:, city:)
      else
        SecretPostcode.new(area:, city:)
      end
    end
  end

  def initialize(postcode_string, area:, city:)
    @postcode_string = postcode_string
    @area = area
    @city = city
  end

  def short
    return area if city.sydney? && area.present?

    # Match the first part of the postcode - the "outward code":
    regexp = /^(?<outward_code>[A-Z0-9]{2,4})(?:\s*[A-Z0-9]{3})?$/

    matches = postcode_string.strip.upcase.match(regexp)

    raise(ArgumentError, "Couldn't parse #{postcode_string} as a postcode") if matches.nil?

    matches[:outward_code]
  end

  def description
    location = [area, city.sydney? ? "NSW" : nil, postcode_string].compact_blank.join(" ")
    "#{location} to be precise. Click to see the venue on a map"
  end

  private

  attr_reader :postcode_string, :area, :city

  # Handles events which don't publicise their address
  class SecretPostcode
    def initialize(area:, city:)
      @area = area
      @city = city
    end

    def short
      area.presence || "???"
    end

    def description
      return "#{area}. Click to see the venue on a map" if area.present?
      return "Bah - this event is too secret to have a postcode!" unless city.sydney?

      "This event does not publicise its address."
    end

    private

    attr_reader :area, :city
  end
end
