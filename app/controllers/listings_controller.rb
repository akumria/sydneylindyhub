# frozen_string_literal: true

class ListingsController < ApplicationController
  layout "website"

  around_action :cache_index, only: :index

  def index
    @today = SOLDNTime.today
    @classes = Event.listing_classes.includes(:venue, :class_organiser).map { ClassListing.new(it) }
    dates = SOLDNTime.listing_dates
    @socials_dates = SocialsListings.new.build(dates)
    @workshop_dates = SocialsListings.new(event_finder: lambda { |date|
      Event.workshops_on_date(date).includes(:venue)
    }).build(workshop_listing_dates)
  end

  private

  # Workshops that ended within the listing grace window remain listed until the end of the listing window.
  def workshop_listing_dates
    first_date = SOLDNTime.today - Event::WORKSHOP_LISTING_GRACE_DAYS
    last_date = SOLDNTime.today + (SOLDNTime::MAX_LISTING_DATES - 1)
    first_date..last_date
  end

  def cache_key
    return if Audit.none?

    "listings-#{SOLDNTime.today}-#{Audit.last.cache_key}"
  end

  def cache_index(&)
    cache_action(cache_key, &)
  end
end
