module Planka
  # The "Branch:" / "PR:" comment an /implement session leaves on its card, so
  # the tickets it blocks know which branch to stack on.
  Handoff = Data.define(:branch, :pr_url) do
    def self.parse(text)
      branch = text[/^Branch:\s*`?([^`\s]+)`?\s*$/, 1] or return
      new(branch:, pr_url: text[%r{^PR:\s*<?(https?://[^\s>]+?)>?[.,;]?\s*$}, 1])
    end

    def self.latest(comments)
      comments.sort_by { |comment| comment["createdAt"] }.reverse_each.lazy.filter_map { |comment| parse(comment["text"]) }.first
    end
  end
end
