# frozen_string_literal: true

module Sashite
  module Stn
    # Base error namespace for STN.
    #
    # Usage patterns:
    #   rescue Sashite::Stn::Error => e
    #   rescue Sashite::Stn::Error::Validation
    #   rescue Sashite::Stn::Error::Coordinate, Sashite::Stn::Error::Piece
    class Error < StandardError
      # Raised when an STN payload fails structural or semantic validation.
      #
      # @example
      #   begin
      #     Sashite::Stn.parse("not a hash")
      #   rescue Sashite::Stn::Error::Validation => e
      #     warn "Validation failed: #{e.message}"
      #   end
      class Validation < Error; end

      # Raised when a CELL coordinate used as a board key is invalid.
      #
      # @example
      #   begin
      #     Sashite::Stn.parse({ "board" => { "a0" => "C:P" } })
      #   rescue Sashite::Stn::Error::Coordinate => e
      #     warn "Bad CELL: #{e.message}"
      #   end
      class Coordinate < Validation; end

      # Raised when a QPI identifier (in board values or hand keys) is invalid.
      #
      # @example
      #   begin
      #     Sashite::Stn.parse({ "board" => { "e4" => "C:k" } }) # semantic mismatch
      #   rescue Sashite::Stn::Error::Piece => e
      #     warn "Bad QPI: #{e.message}"
      #   end
      class Piece < Validation; end

      # Raised when a hand delta is not a non-zero Integer.
      #
      # @example
      #   begin
      #     Sashite::Stn.parse({ "hands" => { "c:p" => 0 } })
      #   rescue Sashite::Stn::Error::Delta => e
      #     warn "Bad delta: #{e.message}"
      #   end
      class Delta < Validation; end
    end
  end
end
