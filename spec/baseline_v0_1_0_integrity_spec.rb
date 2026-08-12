RSpec.describe "mood_probe v0.1.0 frozen baseline" do
  let(:baseline_dir) { Pathname(__dir__).join("fixtures/mood_probe/baseline_v0_1_0") }
  let(:expected_sha256) do
    {
      "PROVENANCE.md" => "01161a4c404ea91198cb0a83118f0177d451f527d301bd9cdf0e7274ea62a2b2",
      "README.md" => "a85485fc8c4277325d85282435002a6a099674c11acdfa5f109a0b3a76313a1a",
      "chirp.json" => "b2a04b178b125e9ea823d122288472f9dc0665af3d44124bc38829b95131a0fb",
      "clicks.json" => "50c7ee158661219c41dc54c7eda799bbf7529a60f995bdde62fd5796ba7c2c84",
      "sine_440.json" => "1c4bfbc2bc42a54d10c73d6492252012c43be9b4c88fe5171dcab258036fdbb9",
      "white_noise.json" => "7a17251f3bad130b25292c03dbcff13ea89da8f0b8e2a35ae7c1ad40140915a3"
    }
  end

  it "keeps every frozen baseline file byte-identical" do
    actual_files = Dir.children(baseline_dir).reject { |name| name.start_with?(".") }.sort

    expect(actual_files).to eq(expected_sha256.keys.sort)
    expected_sha256.each do |filename, expected_digest|
      expect(Digest::SHA256.file(baseline_dir.join(filename)).hexdigest).to eq(expected_digest)
    end
  end
end
