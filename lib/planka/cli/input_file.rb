module Planka
  module CLI
    # Reads a --*-file flag's text: a path, or - for stdin, as UTF-8 whatever the
    # process locale. Callers validate the text and classify read failures.
    module InputFile
      def self.read(path) = (path == "-" ? $stdin.binmode.read : File.binread(path)).force_encoding(Encoding::UTF_8)
    end
  end
end
