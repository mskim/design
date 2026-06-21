# Minimal stand-in for the host's User model.
#
# The design engine's only hard requirements are:
#   * `Design::Theme belongs_to :user, class_name: Design.config.user_class` resolves
#     (so themes can be owned by a user), and
#   * `can_design?` exists, because the dummy app's `authorize` proc is
#     `->(u) { u&.can_design? }` (mirrors book_write, where administrators and
#     designers can design).
#
# Roles mirror book_write's relevant set: writers cannot design; administrators
# and designers can. Fixtures: david = administrator, jz/kevin = member (writer).
class User < ApplicationRecord
  has_secure_password validations: false

  enum :role, { member: 0, administrator: 1, designer: 2 }, default: :member

  def can_design?
    administrator? || designer?
  end
end
