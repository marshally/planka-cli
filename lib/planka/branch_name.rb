module Planka
  # The branch a card is worked on: feature/<slug>-<ticket#>-<title> for a
  # card with a feature label, card/<title> without one. It also names the
  # checkout's Compose project and preview host with an optional prefix, a
  # DNS label of at most 63 characters, so it is cut on a word to fit.
  module BranchName
    def self.for(card, prefix: ENV.fetch("PLANKA_BRANCH_PREFIX", ""))
      max = 63 - prefix.length
      raise Error, "branch prefix leaves too little space" if max < 8

      feature = card.features.first&.delete_prefix("feature:")
      name = feature ? "feature/#{feature}-#{slug(card.name)}" : "card/#{slug(card.name)}"
      fit(name, max:)
    end

    def self.slug(text) = text.downcase.gsub(/[^a-z0-9.]+/, "-").gsub(/\A-|-\z/, "")

    def self.fit(name, max:)
      return name if name.length <= max

      cut = name[0, max]
      boundary = cut.rindex("-")
      cut = cut[0, boundary] if boundary && name[max] != "-" && !cut.end_with?("-")
      cut.chomp("-")
    end
  end
end
