require "open3"

RSpec.describe "model fetch license notice" do
  let(:root) { Pathname(__dir__).join("..").expand_path }
  let(:executable) { root.join("exe/sonance") }
  let(:recording_support) { root.join("spec/support/recording_model_fetch.rb") }
  let(:ruby_options) { "-r#{recording_support}" }

  it "prints manifest-derived licenses before the first download in one ordered stream" do
    models = recording_models
    stdout = run_fetch(executable)

    expect_notice_contract(stdout, models)
  end

  it "proves the ordering contract fails when the notice is suppressed" do
    source = executable.read
    suppressed = source.sub(/^\s*print_model_license_notice\(registry\)\n/, "")

    expect(suppressed).not_to eq(source)

    Dir.mktmpdir do |dir|
      suppressed_executable = Pathname(dir).join("sonance")
      suppressed_executable.write(suppressed)
      stdout = run_fetch(suppressed_executable)

      expect do
        expect_notice_contract(stdout, recording_models)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /MODEL LICENSE/)
    end
  end

  it "states the compliance floor without the obsolete per-model claim" do
    notice = root.join("NOTICE").read

    expect(notice).not_to include("depending on the model")
    expect(notice).to include(
      "Sonance::Registry",
      "CC BY-NC-ND 4.0",
      "ShareAlike",
      "NoDerivatives"
    )
  end

  it "verifies every registered model through the real CLI subprocess" do
    Dir.mktmpdir do |models_dir|
      recording_payloads.each do |filename, payload|
        File.binwrite(File.join(models_dir, filename), payload)
      end

      stdout, stderr, status = Open3.capture3(
        { "RUBYOPT" => ruby_options },
        Gem.ruby,
        "-I#{root.join('lib')}",
        executable.to_s,
        "--models-dir",
        models_dir,
        "models",
        "verify",
        chdir: root
      )

      expect(status).to be_success, stderr
      expect(stdout).to eq("Models verified\n")
    end
  end

  def run_fetch(command)
    Dir.mktmpdir do |models_dir|
      stdout, stderr, status = Open3.capture3(
        { "RUBYOPT" => ruby_options },
        Gem.ruby,
        "-I#{root.join('lib')}",
        command.to_s,
        "--models-dir",
        models_dir,
        "models",
        "fetch",
        chdir: root
      )

      expect(status).to be_success, stderr
      return stdout
    end
  end

  def recording_models
    stdout, stderr, status = Open3.capture3(
      { "RUBYOPT" => ruby_options },
      Gem.ruby,
      "-I#{root.join('lib')}",
      "-rjson",
      "-e",
      "puts JSON.generate(Sonance::Registry.default.models.map(&:to_h))",
      chdir: root
    )

    expect(status).to be_success, stderr
    JSON.parse(stdout)
  end

  def recording_payloads
    {
      "notice-a.pb" => "notice-a-payload",
      "notice-b.pb" => "notice-b-payload"
    }
  end

  def expect_notice_contract(stdout, models)
    lines = stdout.lines(chomp: true)
    first_download = lines.index { |line| line.start_with?("DOWNLOAD ") }

    expect(first_download).not_to be_nil
    models.each do |model|
      notice = model_notice(model)
      notice_position = lines.index(notice)

      expect(lines).to include(notice)
      expect(notice_position).to be < first_download
    end
  end

  def model_notice(model)
    [
      "MODEL LICENSE #{model.fetch('id')}:",
      model.fetch("license"),
      "|",
      model.fetch("attribution"),
      "|",
      model.fetch("source_url"),
      "| non-commercial use only"
    ].join(" ")
  end
end
