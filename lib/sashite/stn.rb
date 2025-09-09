# frozen_string_literal: true

require_relative "stn/error"
require_relative "stn/transition"

module Sashite
  module Stn
    # Canonical, immutable transitions reused across calls.
    EMPTY_TRANSITION = Transition.new.freeze
    PASS_TRANSITION  = Transition.new(toggle: true).freeze

    class << self
      # Validate an STN payload (Hash) or a Transition instance.
      #
      # The validation is strict and delegated to {Transition.parse}.
      # It accepts top-level keys as strings ("board", "hands", "toggle")
      # or symbols (:board, :hands, :toggle). Nested keys are normalized to strings.
      #
      # @param data [Hash, Transition]
      # @return [Boolean] true if valid, false otherwise
      #
      # @example Hash – board-only change with turn toggle
      #   Sashite::Stn.valid?({ "board" => { "e2" => nil, "e4" => "C:P" }, "toggle" => true })
      #   # => true
      #
      # @example Hash – invalid CELL coordinate
      #   Sashite::Stn.valid?({ "board" => { "a0" => "C:P" } })
      #   # => false
      #
      # @example Transition – already parsed
      #   tr = Sashite::Stn.transition(board: { "e2" => nil, "e4" => "C:P" }, toggle: true)
      #   Sashite::Stn.valid?(tr)  # => true
      def valid?(data)
        case data
        when Transition
          true
        when ::Hash
          begin
            Transition.parse(_normalize_root(data))
            true
          rescue Error
            false
          end
        else
          false
        end
      end

      # Parse an STN payload (Hash) into a {Transition}, or return the
      # same {Transition} if one is passed. Raises on invalid input.
      #
      # Top-level keys may be symbols or strings and are normalized.
      #
      # @param data [Hash, Transition]
      # @return [Transition]
      # @raise [Sashite::Stn::Error::Validation]
      #
      # @example Parse from Hash
      #   tr = Sashite::Stn.parse({ "board" => { "e2" => nil, "e4" => "C:P" }, "toggle" => true })
      #   tr.toggle?        # => true
      #   tr.board_changes  # => { "e2" => nil, "e4" => "C:P" }
      #
      # @example Passing a Transition returns it unchanged
      #   tr = Sashite::Stn.transition(toggle: true)
      #   Sashite::Stn.parse(tr).equal?(tr)  # => true
      def parse(data)
        case data
        when Transition
          data
        when ::Hash
          Transition.parse(_normalize_root(data))
        else
          raise Error::Validation,
                "STN must be provided as a Hash or a Transition, got: #{data.class}"
        end
      end

      # Construct a {Transition} directly from keyword arguments.
      # Inputs are not mutated; keys are normalized to strings.
      #
      # @param board [Hash{String,Symbol=>String,nil}] CELL -> (QPI or nil)
      # @param hands [Hash{String,Symbol=>Integer}]    QPI  -> delta (non-zero)
      # @param toggle [Boolean] switch active player if true
      # @return [Transition]
      #
      # @example Build a standard move (e2->e4) with toggle
      #   tr = Sashite::Stn.transition(board: { "e2" => nil, "e4" => "C:P" }, toggle: true)
      #   tr.to_h
      #   # => { :board=>{"e2"=>nil,"e4"=>"C:P"}, :toggle=>true }
      #
      # @example Drop from hand (hand-only + board change)
      #   tr = Sashite::Stn.transition(
      #          board: { "e5" => "S:P" },
      #          hands: { "S:P" => -1 },
      #          toggle: true
      #        )
      def transition(board: {}, hands: {}, toggle: false)
        board_norm = _stringify_map(board)
        hands_norm = _stringify_map(hands)
        Transition.new(board: board_norm, hands: hands_norm, toggle: !!toggle)
      end

      # Return the canonical empty transition: no board changes, no hand changes,
      # no toggle. This instance is immutable and safe to reuse.
      #
      # @return [Transition]
      #
      # @example
      #   Sashite::Stn.empty.empty?   # => true
      #   Sashite::Stn.empty.toggle?  # => false
      def empty
        EMPTY_TRANSITION
      end

      # Return the canonical pass transition: toggle only, no board/hands changes.
      # This instance is immutable and safe to reuse.
      #
      # @return [Transition]
      #
      # @example
      #   Sashite::Stn.pass.pass_move?  # => true
      #   Sashite::Stn.pass.to_h        # => { :toggle=>true }
      def pass
        PASS_TRANSITION
      end

      # Combine (compose) several transitions or Hash payloads left-to-right.
      # Composition semantics follow STN rules:
      #  - board: last value wins per cell
      #  - hands: deltas are summed; entries summing to zero are removed
      #  - toggle: XOR across the sequence
      #
      # @param transitions [Array<Transition,Hash>]
      # @return [Transition]
      #
      # @example Combine two moves into a cumulative delta
      #   t1 = { "board" => { "e2" => nil, "e4" => "C:P" }, "toggle" => true }
      #   t2 = { "board" => { "e7" => nil, "e5" => "c:p" }, "toggle" => true }
      #   Sashite::Stn.combine(t1, t2).to_h
      #   # => { :board=>{"e2"=>nil,"e4"=>"C:P","e7"=>nil,"e5"=>"c:p"} }
      #
      # @example Mixed inputs (Hash and Transition)
      #   t1 = Sashite::Stn.transition(board: { "e1" => nil, "g1" => "C:K", "h1" => nil, "f1" => "C:R" }, toggle: true)
      #   t2 = { "hands" => { "c:b" => 1 }, "toggle" => true }
      #   combo = Sashite::Stn.combine(t1, t2)
      #   combo.toggle? # => false (true XOR true)
      def combine(*transitions)
        parsed = transitions.flatten.compact.map { |t| parse(t) }
        parsed.reduce(EMPTY_TRANSITION) { |acc, t| acc.combine(t) }
      end

      # Friendly alias for {combine}.
      #
      # @see #combine
      def compose(*transitions)
        combine(*transitions)
      end
    end

    # ---------------------
    # Private helpers
    # ---------------------

    # Normalize top-level keys to strings ("board", "hands", "toggle")
    # and stringify nested keys of board/hands maps. Input is not mutated.
    #
    # @param data [Hash]
    # @return [Hash]
    # @raise [Sashite::Stn::Error::Validation]
    def self._normalize_root(data)
      raise Error::Validation, "STN must be a Hash" unless data.is_a?(::Hash)

      board_key  = if data.key?("board")
                     "board"
                   else
                     (data.key?(:board) ? :board : nil)
                   end
      hands_key  = if data.key?("hands")
                     "hands"
                   else
                     (data.key?(:hands) ? :hands : nil)
                   end
      toggle_key = if data.key?("toggle")
                     "toggle"
                   else
                     (data.key?(:toggle) ? :toggle : nil)
                   end

      normalized = {}
      normalized["board"]  = _stringify_map(data[board_key]) if board_key
      normalized["hands"]  = _stringify_map(data[hands_key]) if hands_key

      if toggle_key
        val = data[toggle_key]
        raise Error::Validation, "toggle must be a boolean" unless [true, false].include?(val)

        normalized["toggle"] = val
      end

      normalized
    end
    private_class_method :_normalize_root

    # Stringify keys of a map (or return empty Hash for nil/{}).
    # Raises if a non-Hash is provided.
    #
    # @param h [Hash,nil]
    # @return [Hash]
    # @raise [Sashite::Stn::Error::Validation]
    def self._stringify_map(h)
      return {} if h.nil? || h == {}

      unless h.is_a?(::Hash)
        raise Error::Validation,
              "Expected a Hash for board/hands, got: #{h.class}"
      end

      h.transform_keys(&:to_s)
    end
    private_class_method :_stringify_map
  end
end
