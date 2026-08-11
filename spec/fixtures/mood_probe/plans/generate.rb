#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path("../../../../lib", __dir__)

require "json"
require "mood_probe"

planner = MoodProbe::Planner.new(registry: MoodProbe::Registry.default)
plans = {
  musicnn_only: %i[mood_happy],
  algorithm_only: %i[bpm],
  mixed: %i[bpm mood_happy]
}

plans.each do |name, descriptors|
  path = File.join(__dir__, "#{name}.json")
  File.write(path, JSON.pretty_generate(planner.plan_for(descriptors:).to_h) << "\n")
end
