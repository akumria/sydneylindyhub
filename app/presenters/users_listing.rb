# frozen_string_literal: true

# Presenter for displaying a list of "Users" based on the {Role}s stored in the
# database.
class UsersListing
  def initialize(current_user_id:, roles: Role.all)
    @roles = roles
    @current_user_id = current_user_id
  end

  class << self
    def for_user(session_user)
      new(
        current_user_id: session_user.email
      )
    end
  end

  def users
    @roles.map { build_user(it) }
  end

  User = Data.define(:id, :admin?, :current?, :name, :email) do
    def to_param
      id.to_s
    end
  end

  private

  attr_reader :current_user_id

  def build_user(role)
    id = role.id
    User.new(
      name: role.name,
      email: role.email,
      id:,
      admin?: role.admin?,
      current?: role.email == current_user_id
    )
  end
end
