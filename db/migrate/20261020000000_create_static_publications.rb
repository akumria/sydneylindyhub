# frozen_string_literal: true

class CreateStaticPublications < ActiveRecord::Migration[8.0]
  def change
    create_table :static_publications do |t|
      t.string :status, null: false, default: "queued"
      t.string :requested_by, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :static_publications, "(1)", unique: true,
                                           where: "status IN ('queued', 'running')", name: "one_active_static_publication"
  end
end
