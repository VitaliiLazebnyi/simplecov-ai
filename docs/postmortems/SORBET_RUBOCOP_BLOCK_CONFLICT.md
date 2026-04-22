# Postmortem: Sorbet & RuboCop `Lint/UnusedBlockArgument` Conflict

## 1. Background
During the implementation of `SimpleCov::Formatter::AIFormatter.configure`, a block parameter was required to allow developers to configure the formatter cleanly:

```ruby
SimpleCov::Formatter::AIFormatter.configure do |c|
  c.output_to_console = true
end
```

To strictly type this block, we included a Sorbet signature (`T::Sig`), alongside an idiomatic Ruby `yield` pattern:

```ruby
sig { params(block: T.nilable(T.proc.params(config: Configuration).void)).void }
def self.configure(&block)
  yield(configuration) if block_given?
end
```

## 2. The Incident
When the CI mandate to format code via `rubocop -A` was executed, the build pipeline (specifically, the RSpec test suite) immediately and completely failed with the following fatal crash:

```text
RuntimeError: The declaration for `configure` has extra parameter(s): block
```

## 3. Root Cause Analysis
The crash was caused by an unexpected, destructive interaction between **RuboCop's Auto-Correction** and **Sorbet Runtime Signatures**.

1. **RuboCop's View:** 
   The `Lint/UnusedBlockArgument` rule correctly identified that the `&block` parameter was declared in the method signature `def self.configure(&block)`, but was *never explicitly called* in the method body (the code used `yield` instead of `block.call`). 
2. **The Auto-Correction:**
   Believing the argument was redundant, `rubocop -A` automatically erased the `&block` parameter from the method definition, shortening it to:
   ```ruby
   def self.configure
     yield(configuration) if block_given?
   end
   ```
3. **Sorbet's View:**
   Sorbet’s runtime `sig` checks enforce absolute parity between the `params` defined in the `sig` block and the actual ruby method parameters natively defined.
   Because the signature explicitly declared `params(block: ...)`, but RuboCop erased `&block` from the underlying method, Sorbet detected a strict signature-to-definition mismatch and raised a fatal `RuntimeError`—crashing the load cycle before any tests could execute.

## 4. Remediation
To resolve this conflict without disabling either the Sorbet signature or the RuboCop rules, we had to architect a method that pleased both static constraints.

We explicitly referenced the block in the method body and executed it directly rather than relying on Ruby's implicit `yield`. By changing the implementation to:

```ruby
sig { params(blk: T.nilable(T.proc.params(config: Configuration).void)).void }
def self.configure(&blk)
  blk&.call(configuration)
end
```

1. **Sorbet is satisfied** because the parameter `&blk` is explicitly declared natively matching its `params(blk: ...)` mapping.
2. **RuboCop is satisfied** because the parameter is actively consumed inside the method via `blk&.call()`, thus perfectly bypassing `Lint/UnusedBlockArgument` without requiring an unlisted AI exception or `# rubocop:disable` directive.
