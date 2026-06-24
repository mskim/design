module Design
  # Stores host-registered action blocks per named slot. Blocks are stored RAW
  # (not called) — a block binds to its definition site (an initializer with no
  # view context), so it must be re-bound at render time via instance_exec in the
  # Phlex view (see Design::Views::Base#render_host_actions, a later task).
  class ActionRegistry
    def for(slot, &block) = registrations[slot.to_sym] = block
    def resolve(slot)     = registrations[slot.to_sym]

    private

    def registrations = @registrations ||= {}
  end
end
