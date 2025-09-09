# frozen_string_literal: true

require "simplecov"

SimpleCov.command_name "Unit Tests"
SimpleCov.start

# Tests for Sashite::Stn (State Transition Notation)
#
# Focus on the functional, immutable API:
# - Module-level helpers (valid?, parse, transition, combine/compose, empty, pass)
# - Transition value object: validation, accessors, transformations, composition, inversion
# - Strict error hierarchy under Sashite::Stn::Error
#
# Assumes:
#   - lib/sashite/stn.rb
#   - lib/sashite/stn/transition.rb
#   - lib/sashite/stn/error.rb

# Use local lib when running from a cloned repo
$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "sashite/stn"
require "set"

# Helper function to run a test and report errors
def run_test(name)
  print "  #{name}... "
  yield
  puts "✓ Success"
rescue StandardError => e
  warn "✗ Failure: #{e.message}"
  warn "    #{e.backtrace.first}"
  exit(1)
end

puts
puts "Tests for Sashite::Stn (State Transition Notation)"
puts

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

run_test("Module validation accepts valid transitions") do
  valid = [
    {},  # empty
    { "toggle" => true },                         # pass
    { "board" => { "e4" => "C:P" } },             # board only
    { "hands" => { "S:P" => -1 } },               # hands only
    { "board" => { "e2" => nil, "e4" => "C:P" }, "toggle" => true }, # move
    { "board" => { "e4" => nil }, "hands" => { "c:p" => 1 }, "toggle" => true }, # capture
    { "board" => { "e5" => "S:P" }, "hands" => { "S:P" => -1 }, "toggle" => true } # drop
  ]
  valid.each { |t| raise "#{t.inspect} should be valid" unless Sashite::Stn.valid?(t) }
end

run_test("Module validation rejects invalid transitions (strict toggle, CELL/QPI, shapes)") do
  invalid = [
    { "board" => { "a0" => "C:P" } },     # invalid CELL
    { "board" => { "" => "C:P" } },       # invalid CELL (empty)
    { "board" => { "e4" => "invalid" } }, # invalid QPI value
    { "hands" => { "invalid" => 1 } },    # invalid QPI key
    { "hands" => { "S:P" => 0 } },        # zero delta
    { "hands" => { "S:P" => "x" } },      # non-integer delta
    { "board" => "not_hash" },            # bad shape
    { "hands" => "not_hash" },            # bad shape
    { "toggle" => "not_boolean" },        # strict boolean toggle (module normalization)
    "not_hash",
    nil
  ]
  invalid.each { |t| raise "#{t.inspect} should be invalid" if Sashite::Stn.valid?(t) }
end

# -----------------------------------------------------------------------------
# Module API
# -----------------------------------------------------------------------------

run_test("Factories: transition/empty/pass return immutable Transition instances") do
  t = Sashite::Stn.transition(board: { "e2" => nil, "e4" => "C:P" }, hands: { "S:P" => -1 }, toggle: true)
  raise "transition() should return Transition" unless t.is_a?(Sashite::Stn::Transition)
  raise "toggle? should be true" unless t.toggle?

  e1 = Sashite::Stn.empty
  e2 = Sashite::Stn.empty
  raise "empty should be Transition" unless e1.is_a?(Sashite::Stn::Transition)
  raise "empty should be memoized" unless e1.equal?(e2)
  raise "empty should be empty" unless e1.empty?

  p1 = Sashite::Stn.pass
  p2 = Sashite::Stn.pass
  raise "pass should be Transition" unless p1.is_a?(Sashite::Stn::Transition)
  raise "pass should be memoized" unless p1.equal?(p2)
  raise "pass should be a pass move" unless p1.pass_move?
end

run_test("parse returns Transition or raises; parse(Transition) returns same object") do
  data = { "board" => { "e4" => "C:P" }, "toggle" => true }
  t = Sashite::Stn.parse(data)
  raise "parse should return Transition" unless t.is_a?(Sashite::Stn::Transition)
  raise "board value mismatch" unless t.board_changes == { "e4" => "C:P" }
  raise "toggle mismatch" unless t.toggle?

  same = Sashite::Stn.parse(t)
  raise "parse(Transition) should be identity" unless same.equal?(t)

  begin
    Sashite::Stn.parse("not a hash")
    raise "parse should have raised on non-hash"
  rescue Sashite::Stn::Error::Validation
    # expected
  end
end

run_test("combine/compose: board last-write, hands sum/drop zero, toggle XOR") do
  t1 = Sashite::Stn.transition(board: { "a1" => "C:R" }, hands: { "S:P" => -1 }, toggle: true)
  t2 = Sashite::Stn.transition(board: { "a1" => "C:B", "b2" => "C:N" }, hands: { "S:P" => 1, "c:r" => 1 }, toggle: true)
  c  = Sashite::Stn.combine(t1, t2)

  raise "board last-write failed" unless c.board_changes == { "a1" => "C:B", "b2" => "C:N" }
  raise "hands sum/drop zero failed" unless c.hand_changes == { "c:r" => 1 }
  raise "toggle XOR failed" if c.toggle?

  # compose alias + edge cases
  cc = Sashite::Stn.compose(Sashite::Stn.empty, {}, t1, nil, t2)
  raise "compose should equal combine result" unless cc == c

  raise "combine() with no args should be empty" unless Sashite::Stn.combine.empty?
end

# -----------------------------------------------------------------------------
# Transition: construction, parsing, accessors
# -----------------------------------------------------------------------------

run_test("Transition.new validates inputs and freezes state") do
  t = Sashite::Stn::Transition.new(board: { "e2" => nil, "e4" => "C:P" }, hands: { "S:P" => -1 }, toggle: true)
  raise "not frozen" unless t.frozen?
  raise "board_changes not frozen" unless t.board_changes.frozen?
  raise "hand_changes not frozen" unless t.hand_changes.frozen?

  begin
    Sashite::Stn::Transition.new(board: { "a0" => "C:P" })
    raise "should fail on invalid CELL"
  rescue Sashite::Stn::Error::Coordinate
    # expected
  end

  begin
    Sashite::Stn::Transition.new(board: { "e4" => "invalid" })
    raise "should fail on invalid QPI"
  rescue Sashite::Stn::Error::Piece
    # expected
  end

  begin
    Sashite::Stn::Transition.new(hands: { "S:P" => 0 })
    raise "should fail on zero delta"
  rescue Sashite::Stn::Error::Delta
    # expected
  end

  begin
    Sashite::Stn::Transition.new(board: "not_hash")
    raise "should fail on non-hash board"
  rescue Sashite::Stn::Error::Validation
    # expected
  end

  begin
    Sashite::Stn::Transition.new(hands: "not_hash")
    raise "should fail on non-hash hands"
  rescue Sashite::Stn::Error::Validation
    # expected
  end
end

run_test("Transition.parse normalizes keys and returns equivalent value object") do
  data = { board: { e4: "C:P" }, hands: { "S:P" => -1 }, toggle: true }
  t = Sashite::Stn::Transition.parse(data)
  raise "normalized board mismatch" unless t.board_changes == { "e4" => "C:P" }
  raise "normalized hands mismatch" unless t.hand_changes == { "S:P" => -1 }
  raise "toggle mismatch" unless t.toggle?
end

run_test("Accessors and lookups") do
  t = Sashite::Stn::Transition.new(board: { "e2" => nil, "e4" => "C:P" }, hands: { "S:P" => -1 }, toggle: false)
  raise "board_change(e4)" unless t.board_change("e4") == "C:P"
  raise "board_change(e2)" unless t.board_change("e2").nil?
  raise "board_change(a1)" unless t.board_change("a1").nil?
  raise "hand_change(S:P)" unless t.hand_change("S:P") == -1
  raise "hand_change(C:K)" unless t.hand_change("C:K").nil?
  raise "has_board_change? e2" unless t.has_board_change?("e2")
  raise "has_board_change? a1 should be false" if t.has_board_change?("a1")
  raise "has_hand_change? S:P" unless t.has_hand_change?("S:P")
  raise "has_hand_change? C:K should be false" if t.has_hand_change?("C:K")
end

# -----------------------------------------------------------------------------
# State queries & analysis (limited to documented API)
# -----------------------------------------------------------------------------

run_test("State queries: empty? and pass_move?") do
  empty = Sashite::Stn::Transition.new
  pass  = Sashite::Stn::Transition.new(toggle: true)

  raise "empty? failed" unless empty.empty?
  raise "pass_move? failed" unless pass.pass_move?
end

# -----------------------------------------------------------------------------
# Transformations & immutability
# -----------------------------------------------------------------------------

run_test("Transformations return new instances and preserve immutability") do
  original = Sashite::Stn::Transition.new(board: { "e2" => nil, "e4" => "C:P" }, hands: { "S:P" => -1 }, toggle: true)

  t1 = original.with_board_change("f1", "C:B")
  raise "with_board_change should return new instance" if t1.equal?(original)
  raise "with_board_change should add board change" unless t1.board_changes.size == 3
  raise "original must remain unchanged" unless original.board_changes.size == 2

  t2 = original.with_hand_change("C:R", 2)
  raise "with_hand_change should return new instance" if t2.equal?(original)
  raise "with_hand_change should add hand change" unless t2.hand_changes.size == 2
  raise "original must remain unchanged" unless original.hand_changes.size == 1

  t3 = original.with_toggle(false)
  raise "with_toggle should return new instance" if t3.equal?(original)
  raise "with_toggle should change toggle" if t3.toggle?
  raise "with_toggle should preserve board" unless t3.board_changes == original.board_changes

  t4 = t1.without_board_change("f1")
  raise "without_board_change should return new instance" if t4.equal?(t1)
  raise "without_board_change should remove board change" unless t4.board_changes == original.board_changes

  t5 = t2.without_hand_change("C:R")
  raise "without_hand_change should return new instance" if t5.equal?(t2)
  raise "without_hand_change should remove hand change" unless t5.hand_changes == original.hand_changes
end

# -----------------------------------------------------------------------------
# Composition & inversion
# -----------------------------------------------------------------------------

run_test("Transition#combine enforces STN composition rules") do
  move1 = Sashite::Stn::Transition.new(
    board: { "e2" => nil, "e4" => "C:P" },
    hands: { "S:P" => -1 },
    toggle: true
  )

  move2 = Sashite::Stn::Transition.new(
    board: { "e7" => nil, "e5" => "c:p" },
    hands: { "c:r" => 1 },
    toggle: true
  )

  combined = move1.combine(move2)
  expected_board = { "e2" => nil, "e4" => "C:P", "e7" => nil, "e5" => "c:p" }
  expected_hands = { "S:P" => -1, "c:r" => 1 }

  raise "board merge failed" unless combined.board_changes == expected_board
  raise "hands merge failed" unless combined.hand_changes == expected_hands
  raise "toggle XOR failed" if combined.toggle?

  # Zero-delta removal
  move3 = Sashite::Stn::Transition.new(hands: { "S:P" => 1 })
  zeroed = move1.combine(move3)
  raise "zero deltas should be removed" if zeroed.hand_changes.key?("S:P")
end

run_test("invert negates hands and preserves toggle; invert_board_against restores cells") do
  original = Sashite::Stn::Transition.new(
    board: { "e2" => nil, "e4" => "C:P" },
    hands: { "S:P" => -1, "c:r" => 2 },
    toggle: true
  )

  inv = original.invert
  raise "invert must negate hands" unless inv.hand_changes == { "S:P" => 1, "c:r" => -2 }
  raise "invert must preserve toggle" unless inv.toggle?
  raise "invert must keep board shape" unless inv.board_changes.size == original.board_changes.size

  before = { "e2" => "C:P", "e4" => nil }
  inv_board = original.invert_board_against(previous_board: before)
  raise "invert_board_against must restore cells" unless inv_board.board_changes == before
  raise "invert_board_against must invert hands" unless inv_board.hand_changes == { "S:P" => 1, "c:r" => -2 }
  raise "invert_board_against must preserve toggle" unless inv_board.toggle?
end

# -----------------------------------------------------------------------------
# to_h, equality, hashing, roundtrip
# -----------------------------------------------------------------------------

run_test("to_h omits empty fields; roundtrip parse == original") do
  cases = [
    Sashite::Stn::Transition.new,
    Sashite::Stn::Transition.new(toggle: true),
    Sashite::Stn::Transition.new(board: { "e4" => "C:P" }),
    Sashite::Stn::Transition.new(hands: { "S:P" => -1 }),
    Sashite::Stn::Transition.new(board: { "e2" => nil, "e4" => "C:P" }, toggle: true),
    Sashite::Stn::Transition.new(board: { "e4" => "C:P" }, hands: { "S:P" => -1 }, toggle: true)
  ]
  cases.each do |t|
    h = t.to_h
    raise "unexpected :board" if h.key?(:board) && t.board_changes.empty?
    raise "unexpected :hands" if h.key?(:hands) && t.hand_changes.empty?
    raise "unexpected :toggle" if h.key?(:toggle) && !t.toggle?
    parsed = Sashite::Stn.parse(h)
    raise "roundtrip mismatch" unless parsed == t
  end
end

run_test("Structural equality and hash consistency") do
  t1 = Sashite::Stn::Transition.new(board: { "e2" => nil, "e4" => "C:P" }, hands: { "S:P" => -1 }, toggle: true)
  t2 = Sashite::Stn::Transition.new(board: { "e2" => nil, "e4" => "C:P" }, hands: { "S:P" => -1 }, toggle: true)
  t3 = Sashite::Stn::Transition.new(board: { "e2" => nil, "e4" => "C:P" }, hands: { "S:P" => -1 }, toggle: false)

  raise "== failed" unless t1 == t2
  raise "eql? failed" unless t1.eql?(t2)
  raise "hash equality failed" unless t1.hash == t2.hash
  raise "inequality failed" if t1 == t3

  set = Set.new([t1, t2, t3])
  raise "set should collapse equal values" unless set.size == 2

  map = { t1 => :a, t2 => :b, t3 => :c }
  raise "map should treat equal keys as single entry" unless map.size == 2
end

# -----------------------------------------------------------------------------
# Strict toggle enforcement (module normalization path)
# -----------------------------------------------------------------------------

run_test("Strict toggle boolean enforced by module normalization") do
  begin
    Sashite::Stn.parse({ "toggle" => "yes" })
    raise "toggle non-boolean should raise"
  rescue Sashite::Stn::Error::Validation => e
    raise "message should mention boolean" unless e.message.downcase.include?("boolean")
  end
end

# -----------------------------------------------------------------------------
# Performance smoke (quick)
# -----------------------------------------------------------------------------

run_test("Performance smoke: repeated combine/parse") do
  500.times do
    a = Sashite::Stn.transition(board: { "e2" => nil, "e4" => "C:P" }, toggle: true)
    b = Sashite::Stn.transition(board: { "e7" => nil, "e5" => "c:p" }, toggle: true)
    c = Sashite::Stn.combine(a, b)
    h = c.to_h
    r = Sashite::Stn.parse(h)
    raise "roundtrip mismatch" unless r == c
  end
end

puts
puts "All STN tests passed!"
puts
