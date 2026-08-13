$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "digest"
require "json"
require "pathname"
require "tmpdir"
require "sonance"

RSpec.configure do |config|
  config.filter_run_excluding essentia: true unless ENV["ESSENTIA_SPECS"] == "1"

  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) do |mocks|
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end
  config.order = :random
  Kernel.srand config.seed
end
