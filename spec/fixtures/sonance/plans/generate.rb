#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path("../../../../lib", __dir__)

require "json"
require "sonance"

planner = Sonance::Planner.new(registry: Sonance::Registry.default)
plans = {
  musicnn_only: %i[mood_happy_musicnn],
  algorithm_only: %i[bpm_rhythm2013],
  mixed: %i[bpm_rhythm2013 mood_happy_musicnn],
  emomusic: %i[valence_emomusic]
}

plans.each do |name, descriptors|
  path = File.join(__dir__, "#{name}.json")
  File.write(path, JSON.pretty_generate(planner.plan_for(descriptors:).to_h) << "\n")
end
