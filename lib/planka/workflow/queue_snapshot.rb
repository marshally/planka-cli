require "time"

module Planka
  module Workflow
    # Validate the identities and associations that determine queue eligibility.
    module QueueSnapshot
      def self.board(included, base_url:)
        Snapshot.validate!(included)
        lists = index(included.fetch("lists"))
        cards = index(included.fetch("cards"))
        labels = index(included.fetch("labels"))
        task_lists = index(included.fetch("taskLists"))
        tasks = index(included.fetch("tasks"))
        valid!(lists.values.all? { |list| list["name"].is_a?(String) && %w[active closed].include?(list["type"]) })
        cards.each_value do |card|
          valid!(card["name"].is_a?(String) && lists.key?(card["listId"]) &&
            card["position"].is_a?(Numeric) && card["position"].finite?)
          timestamp!(card["createdAt"])
        end
        valid!(labels.values.all? { |label| label["name"].is_a?(String) })
        valid!(included.fetch("cardLabels").all? { |record| cards.key?(record["cardId"]) && labels.key?(record["labelId"]) })
        valid!(task_lists.values.all? { |list| cards.key?(list["cardId"]) && list["name"].is_a?(String) })
        valid!(tasks.values.all? { |task| task_lists.key?(task["taskListId"]) &&
          [true, false].include?(task["isCompleted"]) && (task["linkedCardId"].nil? || cards.key?(task["linkedCardId"])) })
        valid!(included.fetch("cardMemberships").all? { |record| cards.key?(record["cardId"]) &&
          record["userId"].is_a?(String) && !record["userId"].empty? })
        Board.new(Planka::Board.new(included, base_url: base_url))
      rescue KeyError
        raise InvalidResponse, "Missing workflow-next board records"
      end

      def self.index(records)
        valid!(records.all? { |record| record["id"].is_a?(String) && record["id"].match?(/\A\d+\z/) })
        result = records.to_h { |record| [record["id"], record] }
        valid!(result.size == records.size)
        result
      end

      def self.timestamp!(value)
        valid!(value.is_a?(String))
        Time.iso8601(value)
      rescue ArgumentError
        raise InvalidResponse, "Invalid workflow-next timestamp"
      end

      def self.valid!(condition)
        raise InvalidResponse, "Invalid workflow-next board records" unless condition
      end
      private_class_method :index, :timestamp!, :valid!
    end
  end
end
