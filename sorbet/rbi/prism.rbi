# typed: strict
# Hand-written shim for the optional Prism backend (bundled with Ruby >= 3.3, loaded only
# when recent enough) plus the `parser` gem grammar classes `ASTResolver::ParserBackend`
# selects between. Only the surface the backend touches is declared.
module Prism
  VERSION = T.let(T.unsafe(nil), String)

  module Translation
    # `parser`-compatible translation entry point, parsing with Prism's newest grammar.
    class Parser < ::Parser::Base; end
    class Parser33 < Parser; end
    class Parser34 < Parser; end
    class Parser40 < Parser; end
    class Parser41 < Parser; end
  end
end

module Parser
  class Ruby27 < Base; end
  class Ruby30 < Base; end
  class Ruby31 < Base; end
  class Ruby32 < Base; end
  class Ruby33 < Base; end
  class Ruby34 < Base; end
end
