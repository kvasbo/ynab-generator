require "rubyXL/convenience_methods"

RSpec.describe YnabOfx::Parsers::SasMc do
  subject(:parser) { described_class.new }

  def columns = ["Dato", "Bokført", "Spesifikasjon", "Sted", "Valuta", "Utl. beløp", "Beløp"]

  # Builds an .xlsx shaped like SAS's "Transaksjonseksport" and returns its path.
  def xlsx(rows)
    wb = RubyXL::Workbook.new
    sheet = wb[0]
    sheet.sheet_name = "Transaksjonseksport"
    rows.each_with_index do |row, r|
      row.each_with_index do |value, c|
        next if value.nil?
        cell = sheet.add_cell(r, c, value)
        cell.set_number_format("yyyy-mm-dd") if value.is_a?(DateTime)
      end
    end
    path = File.join(@tmp_dir, "sas-mc.xlsx")
    wb.write(path)
    path
  end

  def d(str) = DateTime.parse(str)

  let(:rows) do
    [
      ["Transaksjonseksport", nil, nil, nil, nil, nil, "30.04.2026, 15:33:16"],
      ["Totalt andre hendelser"],
      columns,
      [d("2026-04-07"), d("2026-04-07"), "INNBETALING BANKGIRO", "", "NOK", 0, -2000],
      ["", "", "Saldo hendelser", "", "", "", 2000],
      ["540185******1234", "Kari Nordmann"],
      ["Kjøp/uttak"],
      columns,
      [d("2026-04-08"), d("2026-04-09"), "REMA 1000", "OSLO", "NOK", 0, 123.45],
      [d("2026-04-09"), d("2026-04-10"), "STREAMING SERVICE", "SAN FRANCISCO", "USD", 9.99, 99.88],
      ["Valutakurs: 9.997998 Valutapåslag inngår med 2,00 %"],
      ["Totalbeløp", nil, nil, nil, nil, nil, 223.33],
      ["540185******5678", "Ola Nordmann"],
      columns,
      [d("2026-04-11"), d("2026-04-12"), "KIWI", "", "NOK", 0, 50],
      [d("2026-04-11"), d("2026-04-12"), "KIWI", "", "NOK", 0, 50]
    ]
  end

  let(:statement) { parser.parse(xlsx(rows)) }
  let(:txns) { statement.transactions }

  it "matches the Transaksjonseksport signature" do
    expect(described_class.signature).to match("Transaksjonseksport")
  end

  it "builds a credit card statement spanning the transaction dates" do
    expect(statement.account_id).to eq("SAS-MC")
    expect(statement.account_type).to eq(:creditcard)
    expect(statement.currency).to eq("NOK")
    expect(statement.balance).to be_nil
    expect(statement.start_date).to eq(Date.new(2026, 4, 7))
    expect(statement.end_date).to eq(Date.new(2026, 4, 12))
    expect(statement.balance_date).to eq(Date.new(2026, 4, 12))
  end

  it "skips headers, subtotals and exchange-rate notes" do
    expect(txns.map(&:payee)).to eq([
      "INNBETALING BANKGIRO",
      "REMA 1000 OSLO",
      "STREAMING SERVICE SAN FRANCISCO",
      "KIWI",
      "KIWI"
    ])
  end

  it "flips the sign: charges become debits, payments become credits" do
    expect(txns.map(&:amount)).to eq(
      %w[2000 -123.45 -99.88 -50 -50].map { |a| BigDecimal(a) }
    )
  end

  it "dates transactions by the booking date" do
    expect(txns[1].date).to eq(Date.new(2026, 4, 9))
  end

  it "records foreign amount, card and holder in the memo" do
    expect(txns[0].memo).to eq("INNBETALING BANKGIRO")
    expect(txns[1].memo).to eq("REMA 1000 OSLO | card 540185******1234 | Kari Nordmann")
    expect(txns[2].memo).to eq("STREAMING SERVICE SAN FRANCISCO | USD 9.99 | card 540185******1234 | Kari Nordmann")
    expect(txns[3].memo).to eq("KIWI | card 540185******5678 | Ola Nordmann")
  end

  it "gives identical same-day rows distinct, stable FITIDs" do
    expect(txns.map(&:fitid).uniq.size).to eq(txns.size)
    expect(parser.parse(xlsx(rows)).transactions.map(&:fitid)).to eq(txns.map(&:fitid))
  end

  it "accepts ISO date strings as well as real date cells" do
    path = xlsx([columns, ["2026-04-08", "2026-04-09", "REMA 1000", "", "NOK", 0, 10]])
    t = parser.parse(path).transactions.first
    expect(t.date).to eq(Date.new(2026, 4, 9))
    expect(t.amount).to eq(BigDecimal("-10"))
  end

  it "falls back to the purchase date when the booking date is missing" do
    path = xlsx([columns, [d("2026-04-08"), nil, "REMA 1000", "", "NOK", 0, 10]])
    expect(parser.parse(path).transactions.first.date).to eq(Date.new(2026, 4, 8))
  end

  it "skips rows without a description or with a missing or zero amount" do
    path = xlsx([
      columns,
      [d("2026-04-08"), d("2026-04-08"), "", "", "NOK", 0, 10],
      [d("2026-04-08"), d("2026-04-08"), "PENDING", "", "NOK", 0, nil],
      [d("2026-04-08"), d("2026-04-08"), "ZERO", "", "NOK", 0, 0],
      [d("2026-04-08"), d("2026-04-08"), "REAL", "", "NOK", 0, 10]
    ])
    expect(parser.parse(path).transactions.map(&:payee)).to eq(["REAL"])
  end

  context "with the fixture export" do
    let(:statement) { parser.parse(fixture_path("sas-mc.xlsx")) }

    it "finds every transaction across all cards" do
      expect(statement.transactions.size).to eq(70)
      expect(statement.transactions.count { |t| t.amount.positive? }).to eq(9)
    end

    it "matches the Totalbeløp at the top of the export" do
      expect(statement.transactions.sum(&:amount)).to eq(BigDecimal("-17376.64"))
    end

    it "gives every transaction a unique FITID" do
      fitids = statement.transactions.map(&:fitid)
      expect(fitids.uniq.size).to eq(fitids.size)
    end
  end
end
