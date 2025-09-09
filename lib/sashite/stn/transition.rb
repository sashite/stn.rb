# frozen_string_literal: true

require "sashite/cell"
require "sashite/qpi"

module Sashite
  module Stn
    # Immutable representation of an STN delta.
    #
    # A Transition encodes the *net* differences between two positions:
    # - board changes (CELL => QPI or nil)
    # - hand/reserve deltas (QPI => non-zero Integer)
    # - active player toggle (Boolean)
    #
    # All instances are frozen; any "mutation" returns a new Transition.
    #
    # @example Board-only change with toggle
    #   t = Sashite::Stn::Transition.new(
    #         board: { "e2" => nil, "e4" => "C:P" },
    #         toggle: true
    #       )
    #   t.toggle?        # => true
    #   t.board_changes  # => { "e2" => nil, "e4" => "C:P" }
    #
    # @example Hand-only delta (add one black pawn to reserve)
    #   t = Sashite::Stn::Transition.new(hands: { "c:p" => 1 })
    #   t.hand_changes   # => { "c:p" => 1 }
    #
    # @example Empty transition
    #   Sashite::Stn::Transition.new.empty? # => true
    class Transition
      # @return [Hash{String=>String,nil}] board final states by CELL
      attr_reader :board_changes
      # @return [Hash{String=>Integer}] hand deltas by QPI (non-zero)
      attr_reader :hand_changes
      # @return [Boolean] true if active player should switch
      attr_reader :toggle

      # Build an immutable transition.
      #
      # Keys for +board+ and +hands+ are *stringified* and values are validated.
      # Inputs are never mutated.
      #
      # @param board [Hash{String,Symbol=>String,nil}]
      # @param hands [Hash{String,Symbol=>Integer}]
      # @param toggle [Boolean]
      #
      # @raise [Sashite::Stn::Error::Coordinate] if a CELL key is invalid
      # @raise [Sashite::Stn::Error::Piece]      if a QPI value/key is invalid
      # @raise [Sashite::Stn::Error::Delta]      if a hand delta is not a non-zero Integer
      #
      # @example
      #   Sashite::Stn::Transition.new(board: { "e1" => nil, "g1" => "C:K" }, toggle: true)
      def initialize(board: {}, hands: {}, toggle: false)
        @board_changes = _stringify_map(board).freeze
        @hand_changes  = _stringify_map(hands).freeze
        @toggle        = toggle

        _validate!
        freeze
      end

      # Parse a Ruby Hash (with "board", "hands", "toggle") into a Transition.
      # Keys inside "board"/"hands" may be symbols or strings.
      #
      # @param data [Hash]
      # @return [Transition]
      #
      # @example
      #   Sashite::Stn::Transition.parse(
      #     "board" => { "e2" => nil, "e4" => "C:P" }, "toggle" => true
      #   )
      def self.parse(data)
        raise Error::Validation, "STN must be a Hash" unless data.is_a?(::Hash)

        board  = data.key?("board")  ? data["board"]  : (data[:board]  if data.key?(:board))
        hands  = data.key?("hands")  ? data["hands"]  : (data[:hands]  if data.key?(:hands))
        toggle = data.key?("toggle") ? data["toggle"] : (data[:toggle] if data.key?(:toggle))

        new(board: board || {}, hands: hands || {}, toggle: !!toggle)
      end

      # Predicate wrapper for +parse+ that traps validation errors.
      #
      # @param data [Hash]
      # @return [Boolean]
      #
      # @example
      #   Sashite::Stn::Transition.valid?({ "board" => { "a0" => "C:P" } }) # => false
      def self.valid?(data)
        !!parse(data)
      rescue ::Sashite::Stn::Error
        false
      end

      # @return [Boolean] true if +toggle+ is set.
      def toggle?
        @toggle
      end

      # @return [Boolean] true when no changes at all and no toggle.
      def empty?
        @board_changes.empty? && @hand_changes.empty? && !@toggle
      end

      # @return [Boolean] true when there is a toggle only (no board/hands).
      def pass_move?
        @board_changes.empty? && @hand_changes.empty? && @toggle
      end

      # Read a single board change for a given CELL.
      #
      # @param cell [String]
      # @return [String,nil] QPI or nil for empty; nil if the cell is not changed by this transition
      def board_change(cell)
        @board_changes[cell]
      end

      # Read a single hand delta for a given QPI key.
      #
      # @param qpi [String]
      # @return [Integer,nil]
      def hand_change(qpi)
        @hand_changes[qpi]
      end

      # Whether a CELL is present in the board delta.
      #
      # @param cell [String]
      # @return [Boolean]
      def has_board_change?(cell)
        @board_changes.key?(cell)
      end

      # Whether a QPI key is present in the hand delta.
      #
      # @param qpi [String]
      # @return [Boolean]
      def has_hand_change?(qpi)
        @hand_changes.key?(qpi)
      end

      # Replace or add a board entry (CELL => value) and return a new Transition.
      #
      # @param cell [String,Symbol]
      # @param value [String,nil] QPI or nil
      # @return [Transition]
      #
      # @example
      #   t2 = t1.with_board_change("f3", "S:+N")
      def with_board_change(cell, value)
        self.class.new(
          board:  @board_changes.merge(cell.to_s => value),
          hands:  @hand_changes,
          toggle: @toggle
        )
      end

      # Replace or add a single hand delta and return a new Transition.
      #
      # @param qpi [String,Symbol]
      # @param delta [Integer] non-zero
      # @return [Transition]
      #
      # @example
      #   t2 = t1.with_hand_change("c:b", 1)
      def with_hand_change(qpi, delta)
        self.class.new(
          board:  @board_changes,
          hands:  @hand_changes.merge(qpi.to_s => delta),
          toggle: @toggle
        )
      end

      # Return a new Transition with the given toggle flag.
      #
      # @param value [Boolean]
      # @return [Transition]
      #
      # @example
      #   t2 = t1.with_toggle(false)
      def with_toggle(value)
        self.class.new(
          board:  @board_changes,
          hands:  @hand_changes,
          toggle: value
        )
      end

      # Remove a board entry (if present) and return a new Transition.
      #
      # @param cell [String,Symbol]
      # @return [Transition]
      def without_board_change(cell)
        key = cell.to_s
        return self unless @board_changes.key?(key)

        self.class.new(
          board:  @board_changes.reject { |k, _| k == key },
          hands:  @hand_changes,
          toggle: @toggle
        )
      end

      # Remove a hand entry (if present) and return a new Transition.
      #
      # @param qpi [String,Symbol]
      # @return [Transition]
      def without_hand_change(qpi)
        key = qpi.to_s
        return self unless @hand_changes.key?(key)

        self.class.new(
          board:  @board_changes,
          hands:  @hand_changes.reject { |k, _| k == key },
          toggle: @toggle
        )
      end

      # Combine this transition with another one, left-to-right.
      # STN composition semantics:
      # - board: last write wins per CELL
      # - hands: deltas are summed; entries summing to zero are removed
      # - toggle: XOR
      #
      # @param other [Transition]
      # @return [Transition]
      #
      # @example
      #   t = t1.combine(t2)
      def combine(other)
        raise Error::Validation, "Expected Transition, got: #{other.class}" unless other.is_a?(Transition)

        combined_board = @board_changes.merge(other.board_changes)

        combined_hands = ::Hash.new(0)
        (@hand_changes.keys | other.hand_changes.keys).each do |k|
          sum = (@hand_changes[k] || 0) + (other.hand_changes[k] || 0)
          combined_hands[k] = sum unless sum.zero?
        end

        self.class.new(
          board:  combined_board,
          hands:  combined_hands,
          toggle: (@toggle ^ other.toggle?)
        )
      end

      # Produce a Ruby Hash representation suitable for serialization.
      # Keys at the top level use Ruby symbols (:board, :hands, :toggle).
      # Omitted fields are not present in the result.
      #
      # @return [Hash]
      #
      # @example
      #   Sashite::Stn::Transition.new(toggle: true).to_h # => { :toggle=>true }
      def to_h
        h = {}
        h[:board]  = @board_changes unless @board_changes.empty?
        h[:hands]  = @hand_changes  unless @hand_changes.empty?
        h[:toggle] = true if @toggle
        h
      end

      # Structural equality.
      #
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.is_a?(Transition) &&
          board_changes == other.board_changes &&
          hand_changes == other.hand_changes &&
          toggle? == other.toggle?
      end
      alias eql? ==

      # Hash code consistent with #==.
      #
      # @return [Integer]
      def hash
        [@board_changes, @hand_changes, @toggle].hash
      end

      # --------- Advanced helpers (optional) ---------

      # Compute an inverse transition for *hands* and *toggle* only.
      # Board inversion requires knowledge of the surrounding positions and
      # therefore is not attempted here (board delta left untouched).
      #
      # If you need a full board inverse, use {#invert_board_against}.
      #
      # @return [Transition]
      #
      # @example
      #   t  = Sashite::Stn::Transition.new(hands: { "c:p" => 2 }, toggle: true)
      #   ti = t.invert
      #   ti.hand_changes # => { "c:p" => -2 }
      #   ti.toggle?      # => true
      def invert
        inv_hands = @hand_changes.transform_values(&:-@)
        self.class.new(board: @board_changes, hands: inv_hands, toggle: @toggle)
      end

      # Build a board inverse against a known *before* position snapshot.
      # Given a map of *previous* CELL states (QPI or nil), construct a transition
      # that would restore those cells. Hands and toggle are inverted like {#invert}.
      #
      # @param previous_board [Hash{String=>String,nil}] canonical "before" snapshot
      # @return [Transition]
      #
      # @example
      #   # Suppose before: e2 => "C:P", e4 => nil   and t sets e2=>nil, e4=>"C:P"
      #   before = { "e2" => "C:P", "e4" => nil }
      #   t  = Sashite::Stn::Transition.new(board: { "e2" => nil, "e4" => "C:P" }, toggle: true)
      #   ti = t.invert_board_against(previous_board: before)
      #   ti.board_changes # => { "e2" => "C:P", "e4" => nil }
      def invert_board_against(previous_board:)
        raise Error::Validation, "previous_board must be a Hash of CELL=>QPI/nil" unless previous_board.is_a?(::Hash)

        inv_board = {}
        @board_changes.each_key do |cell|
          inv_board[cell] = previous_board[cell]
        end

        self.class.new(
          board:  inv_board,
          hands:  @hand_changes.transform_values(&:-@),
          toggle: @toggle
        )
      end

      private

      # -- Validation ---------------------------------------------------------

      def _validate!
        _validate_board!
        _validate_hands!
        _validate_toggle!
      end

      def _validate_board!
        raise Error::Validation, "board must be a Hash" unless @board_changes.is_a?(::Hash)

        @board_changes.each do |cell, qpi|
          raise Error::Coordinate, "Invalid CELL coordinate: #{cell.inspect}" unless ::Sashite::Cell.valid?(cell)
          unless qpi.nil? || ::Sashite::Qpi.valid?(qpi)
            raise Error::Piece, "Invalid QPI for board cell #{cell}: #{qpi.inspect}"
          end
        end
      end

      def _validate_hands!
        raise Error::Validation, "hands must be a Hash" unless @hand_changes.is_a?(::Hash)

        @hand_changes.each do |qpi, delta|
          raise Error::Piece, "Invalid QPI in hands: #{qpi.inspect}" unless ::Sashite::Qpi.valid?(qpi)
          unless delta.is_a?(Integer) && !delta.zero?
            raise Error::Delta, "Hand delta must be a non-zero Integer for #{qpi.inspect}, got: #{delta.inspect}"
          end
        end
      end

      def _validate_toggle!
        return if [true, false].include?(@toggle)

        raise Error::Validation, "toggle must be a Boolean, got: #{@toggle.inspect}"
      end

      # -- Utilities ----------------------------------------------------------

      def _stringify_map(h)
        return {} if h.nil? || h == {}

        raise Error::Validation, "Expected a Hash, got: #{h.class}" unless h.is_a?(::Hash)

        h.transform_keys(&:to_s)
      end
    end
  end
end
