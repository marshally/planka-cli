module Planka
  # Resolves a user-supplied reference within records already scoped to one
  # board: an ID matches by id, anything else by exact name. Unknown and
  # ambiguous references are input failures, not API failures.
  module Reference
    def self.resolve(records, reference, resource:)
      matches = records.select { |record| Records.id?(reference) ? record["id"] == reference : record["name"] == reference }
      raise ReferenceError.new("#{resource.capitalize} not found on the specified board", code: "not_found", status: 1) if matches.empty?
      if matches.size > 1
        raise ReferenceError, "Ambiguous #{resource} name; candidate IDs: #{matches.map { |record| record['id'] }.join(', ')}"
      end
      matches.first
    end
  end
end
