# frozen_string_literal: true

class SOLDNTime
  MAX_LISTING_DATES = 14

  class << self
    # The listings day rolls over at 4am because a social can finish after
    # midnight. Compare the local wall-clock hour rather than adding or
    # subtracting a fixed duration: across a daylight-saving boundary a fixed
    # duration is not the same as a fixed number of hours on the clock, which
    # would misreport the dance date for a couple of hours that night.
    def today
      if Time.zone.now.hour < 4
        Date.current.yesterday
      else
        Date.current
      end
    end

    def listing_dates(first_date = today, number_of_days: MAX_LISTING_DATES)
      (first_date..).first(number_of_days)
    end
  end
end
