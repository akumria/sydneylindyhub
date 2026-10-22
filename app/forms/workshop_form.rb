# frozen_string_literal: true

# Editor-only form; model validation is authoritative for the exception and its date.
class WorkshopForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :title, :string
  attribute :url, :string
  attribute :venue_id, :integer
  attribute :class_organiser_id, :integer
  attribute :class_style, :string
  attribute :date, :date
  attribute :cancelled, :boolean, default: false
  attribute :last_verified_at, :datetime
  attribute :source_notes, :string
  attribute :workshop_exception_reason, :string

  validates :date, :workshop_exception_reason, presence: true

  def self.from_event(event)
    new(event.attributes.slice(*attribute_names).merge(date: event.first_date,
                                                       cancelled: event.event_instances.first.cancelled?))
  end

  def save(event)
    return false unless valid?

    persist(event)
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.merge!(e.record.errors)
    false
  end

  private

  def persist(event)
    event.transaction do
      event.assign_attributes(event_attributes)
      assign_instance(event)
      event.audit_comment = "Workshop confirmed date: #{date}; cancelled: #{cancelled}"
      event.save!
    end
  end

  def assign_instance(event)
    instance = event.event_instances.to_a.first || event.event_instances.build
    instance.assign_attributes(date:, cancelled:)
  end

  def event_attributes
    attributes.except("date", "cancelled").merge(
      has_class: true, has_social: false, has_taster: false, frequency: 0,
      day: nil, first_date: date, last_date: date
    )
  end
end
