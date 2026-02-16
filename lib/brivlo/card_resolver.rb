# frozen_string_literal: true

require "English"

module Brivlo
  # Extracts Trello card references from event summaries and resolves
  # card details by shelling out to the trello-cli.
  module CardResolver
    SHOW_PATTERN = %r{\Abin/trello card show (\S+)}
    DONE_PATTERN = %r{\Abin/trello card move (\S+) "Done/}

    def self.extract_card_ref(summary)
      return nil unless summary

      match = summary.match(SHOW_PATTERN)
      match && match[1]
    end

    def self.extract_done_ref(summary)
      return nil unless summary

      match = summary.match(DONE_PATTERN)
      match && match[1]
    end

    def self.resolve(ref, trello_cli_path: nil)
      output = run_trello(ref, trello_cli_path: trello_cli_path)
      return nil unless output

      lines = output.lines.map(&:strip)
      title = lines[0]
      url_line = lines.find { |l| l.start_with?("URL: ") }
      return nil unless title && url_line

      url = url_line.sub("URL: ", "")
      { card_title: title, card_url: url }
    end

    def self.run_trello(ref, trello_cli_path: nil)
      cmd = trello_cli_path || "trello"
      output = `#{cmd} card show #{ref} 2>/dev/null`
      $CHILD_STATUS.success? ? output : nil
    rescue StandardError
      nil
    end
  end
end
