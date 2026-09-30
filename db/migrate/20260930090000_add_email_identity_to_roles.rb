# frozen_string_literal: true

class AddEmailIdentityToRoles < ActiveRecord::Migration[8.0]
  def up
    change_table :roles, bulk: true do |table|
      table.string :email
      table.string :name
    end

    execute <<~SQL.squish
      UPDATE roles
      SET email = CONCAT('legacy-', facebook_ref, '@invalid.local'),
          name = 'Legacy editor'
    SQL

    change_table :roles, bulk: true do |table|
      table.change_null :email, false
      table.change_null :name, false
      table.change_null :facebook_ref, true
    end
    add_index :roles, "LOWER(email)", unique: true, name: "index_roles_on_lower_email"
  end

  def down
    remove_index :roles, name: "index_roles_on_lower_email"
    execute "DELETE FROM roles WHERE facebook_ref IS NULL"
    change_table :roles, bulk: true do |table|
      table.change_null :facebook_ref, false
      table.remove :name
      table.remove :email
    end
  end
end
