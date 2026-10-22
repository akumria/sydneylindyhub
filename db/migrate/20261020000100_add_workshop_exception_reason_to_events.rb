# frozen_string_literal: true

class AddWorkshopExceptionReasonToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :workshop_exception_reason, :text
  end
end
