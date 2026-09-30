# frozen_string_literal: true

class AddVerificationDetailsToEvents < ActiveRecord::Migration[8.0]
  def change
    change_table :events, bulk: true do |table|
      table.datetime :last_verified_at
      table.text :source_notes
    end
  end
end
