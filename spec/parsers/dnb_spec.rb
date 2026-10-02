RSpec.describe YnabOfx::Parsers::Dnb do
  subject(:parser) { described_class.new }

  let(:header) { %("Dato";"Forklaring";"Rentedato";"Ut fra konto";"Inn på konto") }

  # DNB's "Last ned fil": CRLF line endings, no newline after the last row.
  def txt(*lines) = [header, *lines].join("\r\n")

  it "matches the DNB header signature" do
    expect(described_class.signature).to match(header)
    expect(described_class.signature).to match("Siste transaksjoner\nDato Forklaring Rentedato Ut fra konto Inn på konto")
  end

  it "parses money out and money in" do
    path = write_temp_file("dnb.txt", txt(
      %("24.09.2026";"Varekjøp Butikken Storgata Oslo Dato 24.09 kl. 18.40 ";"25.09.2026";34.9;""),
      %("28.09.2026";"Overføring Innland  12340000001 Ola Nordmann  ";"28.09.2026";"";1250.5)
    ))

    s = parser.parse(path)
    expect(s.account_id).to eq("DNB")
    expect(s.account_type).to eq(:bank)
    expect(s.currency).to eq("NOK")
    expect(s.balance).to be_nil
    expect(s.start_date).to eq(Date.new(2026, 9, 24))
    expect(s.end_date).to eq(Date.new(2026, 9, 28))
    expect(s.balance_date).to eq(Date.new(2026, 9, 28))

    ut, inn = s.transactions
    expect(ut.date).to eq(Date.new(2026, 9, 24))
    expect(ut.amount).to eq(BigDecimal("-34.9"))
    expect(inn.amount).to eq(BigDecimal("1250.5"))
    expect(inn.payee).to eq("Overføring Innland 12340000001 O")
    expect(inn.memo).to eq("Overføring Innland 12340000001 Ola Nordmann")
  end

  it "strips the purchase prefix and card timestamp from the payee but keeps them in the memo" do
    path = write_temp_file("dnb.txt", txt(
      %("24.09.2026";"Varekjøp Butikken Storgata Oslo Dato 24.09 kl. 18.40 ";"25.09.2026";34.9;""),
      %("22.09.2026";"E-varekjøp Vipps Kaffebaren s Oslo Dato 22.09 kl. 17.06 ";"23.09.2026";45;"")
    ))

    butikk, kaffe = parser.parse(path).transactions
    expect(butikk.payee).to eq("Butikken Storgata Oslo")
    expect(butikk.memo).to eq("Varekjøp Butikken Storgata Oslo Dato 24.09 kl. 18.40")
    expect(kaffe.payee).to eq("Vipps Kaffebaren s Oslo")
  end

  it "skips reserved transactions, whose text changes once they are booked" do
    path = write_temp_file("dnb.txt", txt(
      %("02.10.2026";"Overføring  Reservert transaksjon ";"02.10.2026";"";300),
      %("01.10.2026";"Visa  100031  Nok 99,00 Nettbutikk AS ";"02.10.2026";99;"")
    ))

    expect(parser.parse(path).transactions.map(&:amount)).to eq([BigDecimal("-99")])
  end

  it "gives same-day purchases that differ only by time distinct FITIDs" do
    path = write_temp_file("dnb.txt", txt(
      %("22.09.2026";"E-varekjøp Vipps Kaffebaren s Oslo Dato 22.09 kl. 17.06 ";"23.09.2026";45;""),
      %("22.09.2026";"E-varekjøp Vipps Kaffebaren s Oslo Dato 22.09 kl. 17.10 ";"23.09.2026";45;"")
    ))

    expect(parser.parse(path).transactions.map(&:fitid).uniq.size).to eq(2)
  end

  it "gives identical same-day rows distinct, stable FITIDs" do
    content = txt(
      %("08.06.2026";"Overføring  1234567890 Kari Nordmann Tpp: Vipps ";"09.06.2026";"";75),
      %("08.06.2026";"Overføring  1234567890 Kari Nordmann Tpp: Vipps ";"09.06.2026";"";75)
    )
    first = parser.parse(write_temp_file("a.txt", content)).transactions.map(&:fitid)
    second = parser.parse(write_temp_file("b.txt", content)).transactions.map(&:fitid)

    expect(first.uniq.size).to eq(2)
    expect(first).to eq(second)
  end

  it "raises EmptyStatementError for a header-only export" do
    path = write_temp_file("dnb.txt", txt)
    expect { parser.parse(path) }.to raise_error(YnabOfx::EmptyStatementError)
  end

  context "with the fixture exports" do
    let(:expected_amounts) do
      %w[500 -34.9 -45 -45 75 -99 -268.14 -5 1250.5].map { |a| BigDecimal(a) }
    end

    it "parses dnb-last-ned-fil.txt" do
      s = parser.parse(fixture_path("dnb-last-ned-fil.txt"))
      expect(s.transactions.map(&:amount)).to eq(expected_amounts)
      expect(s.start_date).to eq(Date.new(2026, 6, 27))
      expect(s.end_date).to eq(Date.new(2026, 9, 28))
    end

    it "parses dnb-excel.xlsx" do
      s = parser.parse(fixture_path("dnb-excel.xlsx"))
      expect(s.transactions.map(&:amount)).to eq(expected_amounts)
    end

    it "gives the same transactions for the .txt and the .xlsx download" do
      txt_txns = parser.parse(fixture_path("dnb-last-ned-fil.txt")).transactions
      xlsx_txns = parser.parse(fixture_path("dnb-excel.xlsx")).transactions
      expect(xlsx_txns.map(&:to_h)).to eq(txt_txns.map(&:to_h))
    end
  end
end
