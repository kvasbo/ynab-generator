RSpec.describe YnabOfx::CLI do
  let(:in_dir) { File.join(@tmp_dir, "in") }
  let(:out_dir) { File.join(@tmp_dir, "out") }

  def run(*argv)
    status = nil
    expect { status = described_class.run(argv) }.to output.to_stdout
    status
  end

  before do
    FileUtils.mkdir_p(File.join(in_dir, "kort"))
    FileUtils.cp(fixture_path("sb1-konto.csv"), in_dir)
    FileUtils.cp(fixture_path("handelsbank-mc-short.pdf"), File.join(in_dir, "kort"))
  end

  it "writes one OFX per statement, mirroring input subfolders" do
    expect(run(in_dir, out_dir)).to eq(0)

    files = Dir.glob("**/*.ofx", base: out_dir)
    expect(files).to contain_exactly("sb1-konto.ofx", "kort/handelsbank-mc-short.ofx")
    expect(File.read(File.join(out_dir, "sb1-konto.ofx"))).to include("<ACCTID>10000011111</ACCTID>")
  end

  it "replaces OFX files from earlier runs but leaves other files alone" do
    FileUtils.mkdir_p(out_dir)
    File.write(File.join(out_dir, "old.ofx"), "stale")
    File.write(File.join(out_dir, "notes.txt"), "keep me")

    run(in_dir, out_dir)

    expect(File).not_to exist(File.join(out_dir, "old.ofx"))
    expect(File.read(File.join(out_dir, "notes.txt"))).to eq("keep me")
  end

  it "picks up .txt exports" do
    FileUtils.cp(fixture_path("dnb-last-ned-fil.txt"), in_dir)
    run(in_dir, out_dir)
    expect(File).to exist(File.join(out_dir, "dnb-last-ned-fil.ofx"))
  end

  it "skips files it does not recognise" do
    File.write(File.join(in_dir, "other.csv"), "a,b\n1,2\n")
    expect { described_class.run([in_dir, out_dir]) }.to output(/SKIP other\.csv/).to_stdout
  end

  it "fails when the input directory is missing" do
    expect { expect(described_class.run([File.join(@tmp_dir, "nope"), out_dir])).to eq(66) }
      .to output(/input dir not found/).to_stderr
  end

  it "fails with usage on too many arguments" do
    expect { expect(described_class.run(%w[a b c])).to eq(64) }.to output(/usage/).to_stderr
  end
end
