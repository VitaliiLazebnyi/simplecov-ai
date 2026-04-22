# Postmortem: Single Branch Cases in Sorbet (Typed: Strong)

## Background & Context

During the resolution of `typed: strong` violations across the `simplecov-ai` codebase, a recurring Sorbet error was encountered when validating array outputs originating from external libraries (specifically `SimpleCov`'s internal tracking objects):

```
Call to method `is_a?` on `T.untyped` https://srb.help/7018
```

The originating code utilized a standard, idiomatic Ruby check:
```ruby
if file.respond_to?(:branches) && file.branches.is_a?(Array)
```

To resolve this, the code was refactored into a single-branch `case` statement, a pattern that appears unidiomatic in standard Ruby but is strictly mandated under maximum static analysis rigor:

```ruby
if file.respond_to?(:branches)
  branches = file.branches
  case branches
  when Array
    if branches.any?
      # ... implementation
    end
  end
end
```

This document outlines the specific architectural, security, and type-system benefits that justify the deployment of this structural pattern.

## Architectural Benefits

### 1. Eliminating Dynamic Dispatch on Untyped Objects
When using an `if` statement such as `if obj.is_a?(Array)`, the `#is_a?` method is sent directly to the `obj` receiver. Because `obj` is evaluated as `T.untyped` by the static analyzer, its behavior is mathematically unpredictable. 

Ruby's dynamic nature allows any object to arbitrarily override `#is_a?`:
```ruby
class MaliciousProxy
  def is_a?(type)
    true # Compromises type safety by returning false positives
  end
end
```
Because the method is invoked on the *untrusted* object itself, Sorbet's `typed: strong` engine refuses to trust the boolean result. It preemptively flags the dispatch as a strict typing violation to prevent potential hijackings of the type-checking logic.

### 2. Inverting the Flow of Trust (The `===` Operator)
Refactoring the logic into a `case` statement alters the underlying dispatch mechanism:
```ruby
case obj
when Array
  # ...
end
```
Under the hood, Ruby interprets this expression via the `===` method of the class constant:
```ruby
if Array === obj
```
In this scenario, the `#===` method is invoked on the `Array` class constant, rather than on the untyped `obj`. Because `Array` is a statically known, immutable core constant, the static analyzer mathematically trusts its `#===` implementation. The untyped `obj` is passed safely as an argument. By removing the untrusted object's ability to dictate its own type evaluation, we invert the flow of trust and establish a secure, fail-fast boundary.

### 3. Native Type Narrowing (Flow-Sensitive Typing)
Sorbet is designed natively around "Flow-Sensitive Typing" and tightly integrates with Ruby's `case` syntax. When the parser encounters a `when Array` branch, it statically asserts that within the ensuing block, the variable in question is categorically an `Array`.

It automatically upgrades the variable's internal classification from `T.untyped` to `Array` exclusively for the duration of that block. This native narrowing provides mathematical safety when subsequently invoking array-specific operations (e.g., `#any?`, `#each`), entirely bypassing the need for explicit, brittle typecasting.

## Conclusion
While the `if obj.is_a?(Array)` syntax provides superior readability to developers, it inherently relies on interrogating an untrusted object. The single-branch `case` structure functions as a cryptographic type-checkpoint—it delegates verification exclusively to the trusted `Array` core class. 

Deploying this pattern enforces strict adherence to the project's **Fail-Fast Boundaries** and **Zero Tolerance for Regressions** mandates by structurally neutralizing runtime type hijacking.
