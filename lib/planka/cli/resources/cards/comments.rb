require "planka"
require "planka/cli/command"

module Planka
  module CLI
    module Resources
      module Cards
        module Comments
          ROOT_HELP = <<~HELP.gsub(/^/, "  ")
            get comments --card CARD  Read all card comments
            get comment COMMENT --card CARD  Read one comment
            create comment --card CARD --text TEXT  Post one comment
            update comment COMMENT --card CARD --text TEXT  Edit one comment
            delete comment COMMENT --card CARD  Delete one comment
          HELP
          GROUP_HELP = {
            "get" => "  comments --card CARD  Read all comments\n  comment COMMENT --card CARD  Read one comment\n",
            "create" => "  comment --card CARD --text TEXT  Post one comment\n",
            "update" => "  comment COMMENT --card CARD --text TEXT  Edit one comment\n",
            "delete" => "  comment COMMENT --card CARD  Delete one comment\n",
          }.freeze
          COMMON_HELP = <<~HELP
            COMMENT is a numeric ID; comments have no names or supported URLs. --card is always required:
            Community v2.2.1 has no individual comment GET. CARD is an ID, same-instance /cards/ID URL,
            or exact name with --board BOARD or PLANKA_BOARD_ID. Explicit card IDs/URLs ignore the default
            board; --board asserts the parent. Ambiguous card names report candidate IDs.
            Requires PLANKA_BASE_URL, PLANKA_AGENT_EMAIL, PLANKA_AGENT_PASSWORD.
            Success exits 0, local input 2, operational failures 1. comment/comments are aliases.
            JSON uses data/meta/error. Comment fields: id, cardId, nullable userId, text, nullable
            createdAt/updatedAt. Human output shows the comment ID, card ID, and exact text.
          HELP
          GET_HELP = <<~HELP + COMMON_HELP
            usage: planka get comments --card CARD [--board BOARD] [--limit N] [-o human|json]
                   planka get comment COMMENT --card CARD [--board BOARD] [-o human|json]
            Read-only. Fetch all 50-item native pages in descending numeric ID order (newest first).
            Collection data is an array with meta.complete, false on truncation or retrieval failure.
            Positive --limit caps output after paging; failures keep verified partial results. Concurrent
            changes can affect paging; it is not a consistent snapshot. No filters are supported.
            Individual data is one comment object with empty meta; --limit requires an omitted COMMENT.
          HELP
          TEXT_HELP = <<~HELP
            TEXT must be nonblank UTF-8, at most 1048576 UTF-16 units; it is sent exactly as supplied,
            preserving multiline Unicode and surrounding whitespace. Empty/blank input is rejected;
            clearing text is unsupported. Shell/OS argument-size limits may be lower than the native limit.
          HELP
          WRITE_HELP = <<~HELP
            JSON data is the comment; meta.changed is true/false/null. Rejected writes retain known state.
            Unknown or malformed responses set uncertain fields null and provide readback-comment recovery
            when an ID is known, otherwise readback-comments for the card. A usable returned ID is retained.
            Read back with get comment COMMENT --card CARD or get comments --card CARD before retrying.
            Writes are sent once, never automatically retried. Cleanup preserves the primary result.
          HELP
          CREATE_HELP = <<~HELP + TEXT_HELP + WRITE_HELP + COMMON_HELP
            usage: planka create comment --card CARD [--board BOARD] --text TEXT [-o human|json]
            Post one comment even when identical text exists. Requires board editor or viewer canComment
            permission. Planka maintains the card comment count and notifications; no extra client writes.
          HELP
          UPDATE_HELP = <<~HELP + TEXT_HELP + WRITE_HELP + COMMON_HELP
            usage: planka update comment COMMENT --card CARD [--board BOARD] --text TEXT [-o human|json]
            Change only text; --text is required. Identical text is a no-op with meta.changed false.
            Native writes require the author with board editor or viewer canComment permission.
          HELP
          DELETE_HELP = <<~HELP + WRITE_HELP + COMMON_HELP
            usage: planka delete comment COMMENT --card CARD [--board BOARD] [-o human|json]
            Delete only this comment without prompts. Preserve its card and other comments; Planka updates
            the card comment count and timestamp. Native permission: project manager, or the author with
            board editor/viewer canComment permission. No child cleanup requests or cascade flag.
            JSON adds deleted: true on success, null when uncertain, and omits it on rejection.
          HELP

          def self.prepare_write(env, instance:, flags:, **)
            raise Failure.invalid_input("--text is required") unless flags[:text]

            Cards.prepare_scope(env, instance: instance, flags: flags).merge(text: flags[:text].first)
          end

          def self.validate_text(flags)
            error = Cards.validate_scope_flags(flags)
            return error if error

            "--text must be at most #{Planka::Cards::CommentRecord::TEXT_LIMIT} UTF-16 units" if flags[:text] && !Records.text?(flags[:text].first, Planka::Cards::CommentRecord::TEXT_LIMIT)
          end

          def self.create(client, text:, **scope)
            Planka::Cards::Comments.new(client, **scope).create(text: text)
          end

          def self.update(client, reference, text:, **scope)
            Planka::Cards::Comments.new(client, **scope).update(reference, text: text)
          end

          def self.delete(client, reference, **scope)
            Planka::Cards::Comments.new(client, **scope).delete(reference)
          end

          def self.prepare_get(env, instance:, flags:, **)
            Cards.prepare_scope(env, instance: instance, flags: flags).merge(limit: flags[:limit]&.first&.to_i)
          end

          def self.get(client, reference = nil, **options)
            limit = options.delete(:limit)
            comments = Planka::Cards::Comments.new(client, **options)
            reference ? comments.find(reference) : comments.all(limit: limit)
          end

          def self.format(data)
            data = [data] if data.is_a?(Hash)
            data.empty? ? "No comments." : data.map { |comment| "Comment #{comment["id"]} on card #{comment["cardId"]}\n#{comment["text"]}" }.join("\n")
          end

          COMMANDS = {
            ["delete", "comment"] => Command.new(aliases: [["delete", "comments"]], mutation: true, resource: "comment",
                                                 flags: { "--card CARD" => :card, "--board BOARD" => :board },
                                                 validate_flags: Cards.method(:validate_scope_flags), prepare: Cards.method(:prepare_scope),
                                                 help: DELETE_HELP, operation: method(:delete), formatter: ->(data) { "Deleted #{format(data)}" }),
            ["update", "comment"] => Command.new(aliases: [["update", "comments"]], mutation: true, resource: "comment",
                                                 flags: { "--card CARD" => :card, "--board BOARD" => :board, "--text TEXT" => :text },
                                                 validate_flags: method(:validate_text), prepare: method(:prepare_write),
                                                 help: UPDATE_HELP, operation: method(:update), formatter: ->(data) { "Updated #{format(data)}" }),
            ["create", "comment"] => Command.new(aliases: [["create", "comments"]], reference: false, mutation: true, resource: "comment",
                                                 flags: { "--card CARD" => :card, "--board BOARD" => :board, "--text TEXT" => :text },
                                                 validate_flags: method(:validate_text), prepare: method(:prepare_write),
                                                 help: CREATE_HELP, operation: method(:create), formatter: ->(data) { "Created #{format(data)}" }),
            ["get", "comment"] => Command.new(aliases: [["get", "comments"]], optional_reference: true, collection_read: true, collection_flags: [:limit],
                                              resource: "comment", flags: { "--card CARD" => :card, "--board BOARD" => :board, "--limit N" => :limit },
                                              validate_flags: Cards.method(:validate_scope_flags), prepare: method(:prepare_get),
                                              help: GET_HELP, operation: method(:get), formatter: method(:format)),
          }.freeze

          def self.commands = COMMANDS
          def self.root_help = ROOT_HELP
        end
      end
    end
  end
end
