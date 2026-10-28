# typed: strict

# Overlay for the RubyGems method lib/ calls, which Sorbet's own RubyGems signatures leave
# untyped (keep the arity identical to theirs).
class Gem::Requirement
  sig { params(version: Gem::Version).returns(T::Boolean) }
  def satisfied_by?(version); end
end
