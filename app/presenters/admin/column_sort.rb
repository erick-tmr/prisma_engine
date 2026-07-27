module Admin
  class ColumnSort
    ARROWS = { "asc" => "▲", "desc" => "▼" }.freeze
    FLIPPED = { "asc" => "desc", "desc" => "asc" }.freeze

    def initialize(key:, sort:, direction:, default_direction:)
      @key = key
      @sort = sort
      @direction = direction
      @default_direction = default_direction
    end

    def active?
      @key == @sort
    end

    def arrow
      active? ? ARROWS.fetch(@direction) : ""
    end

    def next_direction
      active? ? FLIPPED.fetch(@direction) : @default_direction
    end
  end
end
