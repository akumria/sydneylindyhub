# frozen_string_literal: true

# Exceptional workshops are dated, verified editorial listings, never recurring classes.
class ValidWorkshopException < ActiveModel::Validator
  def validate(event)
    return unless event.workshop?

    event.errors.add(:base, "Workshop exceptions are only supported in Sydney") unless CITY.sydney?
    validate_kind(event)
    validate_verification(event)
    validate_date(event)
  end

  private

  def validate_kind(event)
    return if event.has_class? && !event.has_social? && !event.has_taster? && event.infrequent? && event.day.blank?

    event.errors.add(:base, "A workshop must be a non-recurring class without a social or taster")
  end

  def validate_verification(event)
    %i[title class_organiser_id last_verified_at source_notes].each do |field|
      event.errors.add(field, "must be present for workshop exceptions") if event.public_send(field).blank?
    end
  end

  def validate_date(event)
    dates = event.event_instances.reject(&:marked_for_destruction?).map(&:date)
    return if dates.size == 1 && dates.first.present? && event.first_date == dates.first && event.last_date == dates.first

    event.errors.add(:dates, "must contain exactly one confirmed date matching the first and last date")
  end
end
