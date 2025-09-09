# Stn.rb

[![Version](https://img.shields.io/github/v/tag/sashite/stn.rb?label=Version&logo=github)](https://github.com/sashite/stn.rb/tags)
[![Yard documentation](https://img.shields.io/badge/Yard-documentation-blue.svg?logo=github)](https://rubydoc.info/github/sashite/stn.rb/main)
![Ruby](https://github.com/sashite/stn.rb/actions/workflows/main.yml/badge.svg?branch=main)
[![License](https://img.shields.io/github/license/sashite/stn.rb?label=License&logo=github)](https://github.com/sashite/stn.rb/raw/main/LICENSE.md)

> **STN** (State Transition Notation) for Ruby — a small, pure, functional core to describe **position deltas** (board, hands/reserve, and active player toggle) in a **rule-agnostic** way.

- **Functional & Immutable**: no side effects, no in-place mutation.
- **Object-oriented surface**: simple module + value object (`Transition`).
- **Spec-accurate**: strictly follows the STN specification.
- **Minimalist**: no JSON (de)serialization inside the gem.

---

## What is STN?

**STN** encodes the **net difference** between two positions in abstract strategy games:

- `board`: map of **CELL** → `QPI or nil` (final state per cell)
- `hands`: map of **QPI** → `Integer delta` (non-zero)
- `toggle`: `true` when the active player switches, else `false`

STN is **rule-agnostic**: it does not prescribe legal moves or game rules; it only describes what changes.

This gem builds upon:

- [CELL] — *Coordinate Encoding for Layered Locations*
- [QPI]  — *Qualified Piece Identifier*

> JSON (de)serialization is intentionally **out of scope**: keep it at your app boundary.

---

## Installation

Add to your `Gemfile`:

```ruby
gem "sashite-stn"
````

Then:

```sh
bundle install
```

This gem depends on:

```ruby
gem "sashite-cell"
gem "sashite-qpi"
```

Bundler will install them automatically when you use `sashite-stn`.

---

## STN format at a glance

```ruby
{
  "board"  => { "e2" => nil, "e4" => "C:P" }, # e2 empties, e4 now has white pawn
  "hands"  => { "c:p" => 1 },                 # add one black pawn to reserve
  "toggle" => true                            # switch active player
}
```

* All top-level keys are optional.
* Empty object `{}` means “no changes”.

---

## Quick start

```ruby
require "sashite/stn"

# Validate a payload (Hash) or an instance (Transition)
Sashite::Stn.valid?({ "board" => { "e2" => nil, "e4" => "C:P" }, "toggle" => true })
# => true

# Parse into an immutable Transition (raises on invalid)
tr = Sashite::Stn.parse({ "board" => { "e2" => nil, "e4" => "C:P" }, "toggle" => true })
tr.toggle?        # => true
tr.board_changes  # => { "e2" => nil, "e4" => "C:P" }

# Construct directly (keywords)
castle = Sashite::Stn.transition(
  board:  { "e1" => nil, "g1" => "C:K", "h1" => nil, "f1" => "C:R" },
  toggle: true
)

# Compose transitions (left → right)
op_reply = Sashite::Stn.transition(board: { "e7" => nil, "e5" => "c:p" }, toggle: true)
combined = Sashite::Stn.combine(castle, op_reply)
combined.toggle? # => false  (true XOR true)

# Canonical helpers
Sashite::Stn.empty.to_h # => {}
Sashite::Stn.pass.to_h  # => { :toggle=>true }
```

---

## API

### Module: `Sashite::Stn`

* `Sashite::Stn.valid?(data) → Boolean`
  Validate a payload (`Hash`) or a `Transition`.

* `Sashite::Stn.parse(data) → Transition`
  Parse a payload (`Hash`) or return the same `Transition`.
  Raises `Sashite::Stn::Error::Validation` on invalid input.

* `Sashite::Stn.transition(board: {}, hands: {}, toggle: false) → Transition`
  Build a transition from keyword args. Keys are normalized to strings.

* `Sashite::Stn.empty → Transition`
  Canonical empty transition (no board/hands changes, no toggle).

* `Sashite::Stn.pass → Transition`
  Canonical pass transition (toggle only).

* `Sashite::Stn.combine(*transitions) → Transition` (alias: `compose`)
  Compose left-to-right using STN semantics:

  * **board**: *last write wins* per cell
  * **hands**: sum deltas; drop zero results
  * **toggle**: XOR across the sequence

### Class: `Sashite::Stn::Transition`

**Construction & parsing**

* `Transition.new(board: {}, hands: {}, toggle: false)`
  Validates and freezes the instance.
* `Transition.parse(hash) → Transition`
  Parses a top-level Hash with `"board"`, `"hands"`, `"toggle"`.
* `Transition.valid?(hash) → Boolean`
  True/false wrapper over `parse`.

**Accessors & queries**

* `#board_changes → Hash{String=>String|nil}`
* `#hand_changes  → Hash{String=>Integer}`
* `#toggle?       → Boolean`
* `#empty?        → Boolean`
* `#pass_move?    → Boolean`
* `#board_change(cell) → String|nil`
* `#hand_change(qpi)   → Integer|nil`
* `#has_board_change?(cell) → Boolean`
* `#has_hand_change?(qpi)   → Boolean`

**Transformations (return new instances)**

* `#with_board_change(cell, value) → Transition`
* `#with_hand_change(qpi, delta)   → Transition`
* `#with_toggle(bool)              → Transition`
* `#without_board_change(cell)     → Transition`
* `#without_hand_change(qpi)       → Transition`

**Composition & inversion**

* `#combine(other) → Transition`
  STN composition semantics (board last-write, summed hands, XOR toggle).
* `#invert → Transition`
  Invert **hands** and keep **toggle** as is (board left untouched).
* `#invert_board_against(previous_board:) → Transition`
  Build a board inverse using the provided *previous* snapshot.
  Also inverts **hands** and keeps **toggle**.

**Conversion & equality**

* `#to_h → Hash` — omits empty fields; top-level keys are symbols
* `#==`, `#eql?`, `#hash` — structural equality

---

## Error handling

All exceptions are scoped under `Sashite::Stn::Error`:

* `Sashite::Stn::Error` *(base class)*

  * `Sashite::Stn::Error::Validation` — structural/semantic validation failures
  * `Sashite::Stn::Error::Coordinate` — invalid **CELL** keys in `board`
  * `Sashite::Stn::Error::Piece` — invalid **QPI** values/keys in `board`/`hands`
  * `Sashite::Stn::Error::Delta` — invalid **hands** deltas (must be non-zero integers)

```ruby
begin
  tr = Sashite::Stn.parse({ "board" => { "a0" => "C:P" } })
rescue Sashite::Stn::Error::Coordinate => e
  warn "Invalid CELL: #{e.message}"
rescue Sashite::Stn::Error::Piece => e
  warn "Invalid QPI: #{e.message}"
rescue Sashite::Stn::Error::Delta => e
  warn "Invalid delta: #{e.message}"
rescue Sashite::Stn::Error::Validation => e
  warn "STN validation failed: #{e.message}"
end
```

---

## Design properties

* **Rule-agnostic**: independent from game rules and engines
* **Pure & Immutable**: no mutation of inputs; instances are frozen
* **Composable**: transitions merge cleanly and predictably
* **Minimal surface**: no JSON (de)serialization built-in
* **CELL/QPI-strict**: delegates coordinate/piece validation to their specs

---

## Development

```sh
# Clone
git clone https://github.com/sashite/stn.rb.git
cd stn.rb

# Install
bundle install

# Run smoke tests
ruby test.rb

# Generate YARD docs
yard doc
```

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-change`
3. Add tests covering your changes
4. Ensure everything is green (lint, tests, docs)
5. Commit with a conventional message
6. Push and open a Pull Request

---

## License

Open source under the [MIT License](https://opensource.org/licenses/MIT).

---

## About

Maintained by **Sashité** — promoting chess variants and sharing the beauty of board-game cultures.

[CELL]: https://sashite.dev/specs/cell/1.0.0/
[QPI]: https://sashite.dev/specs/qpi/1.0.0/
