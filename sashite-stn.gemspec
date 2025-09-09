# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name    = "sashite-stn"
  spec.version = ::File.read("VERSION.semver").chomp
  spec.author  = "Cyril Kato"
  spec.email   = "contact@cyril.email"
  spec.summary = "STN (State Transition Notation) implementation for Ruby with immutable transition objects"

  spec.description = <<~DESC
    STN (State Transition Notation) provides a rule-agnostic format for describing state transitions
    in abstract strategy board games. This gem implements the STN Specification v1.0.0 with a modern
    Ruby interface featuring immutable transition objects and functional programming principles. STN
    captures net changes between game positions by recording modifications in piece locations, hand/reserve
    contents, and active player status using standardized CELL coordinates and QPI piece identification.
    Perfect for game engines, position diff tracking, undo/redo systems, and network synchronization
    requiring efficient state delta representation across multiple game types and traditions.
  DESC

  spec.homepage               = "https://github.com/sashite/stn.rb"
  spec.license                = "MIT"
  spec.files                  = ::Dir["LICENSE.md", "README.md", "lib/**/*"]
  spec.required_ruby_version  = ">= 3.2.0"

  # Runtime dependencies on foundational specifications
  spec.add_dependency "sashite-cell", "~> 2.0"
  spec.add_dependency "sashite-qpi", "~> 1.0"

  spec.metadata = {
    "bug_tracker_uri"       => "https://github.com/sashite/stn.rb/issues",
    "documentation_uri"     => "https://rubydoc.info/github/sashite/stn.rb/main",
    "homepage_uri"          => "https://github.com/sashite/stn.rb",
    "source_code_uri"       => "https://github.com/sashite/stn.rb",
    "specification_uri"     => "https://sashite.dev/specs/stn/1.0.0/",
    "rubygems_mfa_required" => "true"
  }
end
