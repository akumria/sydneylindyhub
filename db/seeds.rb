# frozen_string_literal: true

admin_email = ENV.fetch("DEVELOPMENT_USER_EMAIL", "editor@example.com")
Role.find_or_create_by!(email: admin_email.downcase) do |role|
  role.name = ENV.fetch("DEVELOPMENT_USER_NAME", "Development Editor")
  role.role = "admin"
end

return unless Rails.env.development?

organiser = Organiser.find_or_create_by!(name: "Sydney Lindy Hub Sample Organiser") do |record|
  record.shortname = "Sample organiser"
  record.website = "https://example.com/sydney-swing"
end

newtown = Venue.find_or_create_by!(name: "Sample Newtown Hall") do |venue|
  venue.area = "Newtown"
  venue.address = "204 King Street"
  venue.postcode = "2042"
  venue.lat = -33.8970
  venue.lng = 151.1799
  venue.website = "https://example.com/sample-newtown-hall"
end

city = Venue.find_or_create_by!(name: "Sample Sydney Studio") do |venue|
  venue.area = "Sydney"
  venue.address = "100 George Street"
  venue.postcode = "2000"
  venue.lat = -33.8634
  venue.lng = 151.2065
  venue.website = "https://example.com/sample-sydney-studio"
end

private_venue = Venue.find_or_create_by!(name: "Sample Private Venue") do |venue|
  venue.area = "Marrickville"
  venue.address = "Address supplied by the organiser"
  venue.postcode = nil
  venue.lat = -33.9111
  venue.lng = 151.1559
  venue.website = "https://example.com/sample-private-venue"
end

verified_at = Time.zone.now

weekly_class = Event.find_or_initialize_by(url: "https://example.com/sample-weekly-class")
weekly_class.update!(venue: city, title: "", has_class: true, has_social: false,
                     frequency: 1, day: "Tuesday", class_organiser: organiser,
                     last_verified_at: verified_at,
                     source_notes: "Development sample: weekly class verified against the example organiser page.")

weekly_social = Event.find_or_initialize_by(url: "https://example.com/sample-weekly-social")
weekly_social.update!(venue: newtown, title: "Sample Tuesday Swing Social", has_class: false,
                      has_social: true, frequency: 1, day: "Tuesday", social_organiser: organiser,
                      last_verified_at: verified_at,
                      source_notes: "Development sample: weekly social with a known cancellation.")
weekly_social.event_instances.find_or_create_by!(date: Date.current.next_occurring(:tuesday)) do |instance|
  instance.cancelled = true
end

monthly = Event.find_or_initialize_by(url: "https://example.com/sample-monthly-social")
monthly.update!(venue: newtown, title: "Sample Monthly Social", has_class: false, has_social: true,
                frequency: 0, social_organiser: organiser, last_verified_at: verified_at,
                source_notes: "Development sample: monthly social with individually confirmed dates.")
2.times do |offset|
  date = Date.current.next_month(offset + 1).beginning_of_month.next_occurring(:saturday)
  monthly.event_instances.find_or_create_by!(date:)
end

one_off = Event.find_or_initialize_by(url: "https://example.com/sample-one-off")
one_off.update!(venue: city, title: "Sample One-off Live Band Dance", has_class: false,
                has_social: true, frequency: 0, social_organiser: organiser,
                last_verified_at: verified_at,
                source_notes: "Development sample: one-off event confirmed by the organiser.")
one_off.event_instances.find_or_create_by!(date: 6.weeks.from_now.to_date)

hidden_address = Event.find_or_initialize_by(url: "https://example.com/sample-hidden-address")
hidden_address.update!(venue: private_venue, title: "Sample Invitation Social", has_class: false,
                       has_social: true, frequency: 0, social_organiser: organiser,
                       last_verified_at: verified_at,
                       source_notes: "Development sample: organiser supplies the street address after booking.")
hidden_address.event_instances.find_or_create_by!(date: 8.weeks.from_now.to_date)
