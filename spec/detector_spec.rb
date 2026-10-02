RSpec.describe YnabOfx::Detector do
  describe ".for" do
    {
      "bulder_export_all.csv" => YnabOfx::Parsers::BulderCsv,
      "handelsbank_csv_eksport.csv" => YnabOfx::Parsers::HandelsbankCsv,
      "dnb-last-ned-fil.txt" => YnabOfx::Parsers::Dnb,
      "dnb-excel.xlsx" => YnabOfx::Parsers::Dnb,
      "sb1-konto.csv" => YnabOfx::Parsers::Sparebank1Csv,
      "sb1-laan.csv" => YnabOfx::Parsers::Sparebank1Csv,
      "sb1-sparekonto.csv" => YnabOfx::Parsers::Sparebank1Csv,
      "handelsbank-mc.pdf" => YnabOfx::Parsers::HandelsbankMc,
      "handelsbank-mc-short.pdf" => YnabOfx::Parsers::HandelsbankMc,
      "sas-mc.xlsx" => YnabOfx::Parsers::SasMc
    }.each do |fixture, parser_class|
      it "picks #{parser_class.name.split('::').last} for #{fixture}" do
        expect(described_class.for(fixture_path(fixture))).to be_a(parser_class)
      end
    end

    it "detects by content, not filename" do
      path = write_temp_file("export.csv", File.binread(fixture_path("sb1-konto.csv")))
      expect(described_class.for(path)).to be_a(YnabOfx::Parsers::Sparebank1Csv)
    end

    it "rejects unsupported extensions" do
      path = write_temp_file("notes.doc", "hello")
      expect { described_class.for(path) }
        .to raise_error(YnabOfx::UnknownFileTypeError, /extension \.doc/)
    end

    it "rejects a supported extension with unrecognised contents" do
      path = write_temp_file("other.csv", "Date,Amount,Payee\n2026-01-01,1,X\n")
      expect { described_class.for(path) }
        .to raise_error(YnabOfx::UnknownFileTypeError, /no parser matched/)
    end

    it "rejects corrupt files instead of crashing" do
      path = write_temp_file("broken.pdf", "not a pdf")
      expect { described_class.for(path) }.to raise_error(YnabOfx::UnknownFileTypeError)
    end
  end
end
