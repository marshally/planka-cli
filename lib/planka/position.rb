module Planka
  # Planka orders records by sparse numeric positions. New records go one gap
  # after the highest existing position so later inserts fit between them.
  module Position
    GAP = 65_536
    # The position a move sends when the caller gives none.
    MOVE_DEFAULT = 65_535

    def self.after(records) = (records.map { |record| record["position"].to_f }.max || 0) + GAP
  end
end
