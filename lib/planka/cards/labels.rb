module Planka
  module Cards
    # Observes a card's labels, then sets one verified card-label relationship.
    class Labels
      class << self
        def read(client, label, card_id:, present:, base_url:, board_id: nil) # rubocop:disable Lint/UnusedMethodArgument -- base_url is part of the shared prepared-reader contract.
          card, board = Scope.read(client, card_id: card_id, board_id: board_id)
          label_id = resolve_label(label, board, card)
          applied = applied?(card, label_id)
          data = { "cardId" => Scope.card_id(card), "labelId" => label_id, "present" => present }
          return MutationResult.new(data: data, changed: false) if applied == present

          mutate(client, Scope.card_id(card), label_id, present, data)
        end

        private

        def resolve_label(label, board, card)
          Reference.resolve(board_labels(board, Scope.board_id(card)), label, resource: "label").fetch("id")
        end

        def applied?(card, label_id) = applied_labels(card).any? { |entry| entry["labelId"] == label_id }

        def applied_labels(card)
          included = card["included"]
          raise InvalidResponse, "Invalid card relations" unless included.is_a?(Hash)

          applied = included["cardLabels"]
          unless applied.is_a?(Array) && applied.all? { |entry|
            entry.is_a?(Hash) &&
            entry["cardId"] == Scope.card_id(card) && entry["labelId"].is_a?(String)
          }
            raise InvalidResponse, "Invalid card label records"
          end

          applied
        end

        def board_labels(board, board_id)
          labels = board["labels"]
          unless labels.is_a?(Array) && labels.all? { |record|
            record.is_a?(Hash) && Records.id?(record["id"]) &&
            record["boardId"] == board_id && (record["name"].nil? || record["name"].is_a?(String))
          } &&
                 labels.map { |record| record["id"] }.uniq.size == labels.size
            raise InvalidResponse, "Invalid board labels"
          end

          labels
        end

        def mutate(client, card, id, present, data)
          Write.perform(unchanged: data.merge("present" => !present), unknown: data.merge("present" => nil),
                        recovery: recovery(card)) do
            confirm_write!(write(client, card, id, present), card, id)
            data
          end
        end

        def write(client, card, id, present)
          present ? client.add_card_label(card, id) : client.remove_card_label(card, id)
        end

        def confirm_write!(response, card, id)
          item = response["item"]
          unless item.is_a?(Hash) && item["cardId"] == card && item["labelId"] == id
            raise InvalidResponse, "Invalid relationship write response"
          end
        end

        def recovery(card)
          { "action" => "readback-card-labels", "resources" => [{ "type" => "card", "id" => card }] }
        end
      end
    end
  end
end
