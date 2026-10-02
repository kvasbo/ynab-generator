RSpec.describe YnabOfx::Parsers::Sparebank1Csv do
  subject(:parser) { described_class.new }

  let(:header) { "\uFEFFDato;Beskrivelse;Rentedato;Inn;Ut;Til konto;Fra konto;\n" }

  def csv(*lines) = header + lines.map { |l| "#{l}\n" }.join

  it "matches the SpareBank 1 header signature" do
    expect(described_class.signature).to match(header)
  end

  it "parses incoming and outgoing rows into one statement per account" do
    path = write_temp_file("sb1.csv", csv(
      %("08.06.2026";"Lønn";;"25000,00";;"10000011111";"90001234567";),
      %("09.06.2026";"Rema 1000";;;"-545,50";"10000099999";"10000011111";)
    ))

    statements = parser.parse(path)
    expect(statements.size).to eq(1)

    s = statements.first
    expect(s.account_id).to eq("10000011111")
    expect(s.account_type).to eq(:bank)
    expect(s.currency).to eq("NOK")
    expect(s.balance).to be_nil
    expect(s.start_date).to eq(Date.new(2026, 6, 8))
    expect(s.end_date).to eq(Date.new(2026, 6, 9))
    expect(s.balance_date).to eq(Date.new(2026, 6, 9))

    inn, ut = s.transactions
    expect(inn.date).to eq(Date.new(2026, 6, 8))
    expect(inn.amount).to eq(BigDecimal("25000"))
    expect(inn.payee).to eq("Lønn")
    expect(inn.memo).to eq("Lønn | 90001234567")

    expect(ut.amount).to eq(BigDecimal("-545.50"))
    expect(ut.payee).to eq("Rema 1000")
    expect(ut.memo).to eq("Rema 1000 | 10000099999")
  end

  it "routes each side of a transfer to its own account" do
    path = write_temp_file("sb1.csv", csv(
      %("08.06.2026";"Overføring";;"1000,00";;"111";"222";),
      %("08.06.2026";"Overføring";;;"-1000,00";"111";"222";)
    ))

    statements = parser.parse(path).to_h { |s| [s.account_id, s] }
    expect(statements.keys).to contain_exactly("111", "222")
    expect(statements["111"].transactions.map(&:amount)).to eq([BigDecimal("1000")])
    expect(statements["222"].transactions.map(&:amount)).to eq([BigDecimal("-1000")])
  end

  it "falls back to the other account column when the owning one is blank" do
    path = write_temp_file("sb1.csv", csv(
      %("08.06.2026";"Renter";;"12,00";;"";"333";)
    ))

    expect(parser.parse(path).map(&:account_id)).to eq(["333"])
  end

  it "skips rows without an amount or with a zero amount" do
    path = write_temp_file("sb1.csv", csv(
      %("08.06.2026";"Reservasjon";;;;"111";"222";),
      %("08.06.2026";"Varsel";;"0,00";;"111";"222";),
      %("08.06.2026";"Kaffe";;;"-45,00";"999";"222";)
    ))

    txns = parser.parse(path).flat_map(&:transactions)
    expect(txns.map(&:payee)).to eq(["Kaffe"])
  end

  it "gives identical same-day rows distinct, stable FITIDs" do
    content = csv(
      %("08.06.2026";"Kaffe";;;"-45,00";"999";"222";),
      %("08.06.2026";"Kaffe";;;"-45,00";"999";"222";)
    )
    first = parser.parse(write_temp_file("a.csv", content)).first.transactions.map(&:fitid)
    second = parser.parse(write_temp_file("b.csv", content)).first.transactions.map(&:fitid)

    expect(first.uniq.size).to eq(2)
    expect(first).to eq(second)
  end

  it "truncates the payee to 32 characters but keeps the full text in the memo" do
    long = "A" * 40
    path = write_temp_file("sb1.csv", csv(%("08.06.2026";"#{long}";;;"-1,00";"999";"222";)))

    t = parser.parse(path).first.transactions.first
    expect(t.payee).to eq("A" * 32)
    expect(t.memo).to start_with(long)
  end

  it "raises EmptyStatementError for a header-only export" do
    path = write_temp_file("sb1.csv", header)
    expect { parser.parse(path) }.to raise_error(YnabOfx::EmptyStatementError)
  end

  it "raises ParseError when no row has an account number" do
    path = write_temp_file("sb1.csv", csv(%("08.06.2026";"X";;;"-1,00";"";"";)))
    expect { parser.parse(path) }.to raise_error(YnabOfx::ParseError)
  end

  context "with the fixture export" do
    it "parses sb1-konto.csv" do
      statements = parser.parse(fixture_path("sb1-konto.csv"))
      expect(statements.map(&:account_id)).to eq(["10000011111"])
      expect(statements.first.transactions.map(&:amount))
        .to eq([BigDecimal("25000"), BigDecimal("-545")])
    end

    it "parses sb1-laan.csv" do
      statements = parser.parse(fixture_path("sb1-laan.csv"))
      expect(statements.map(&:account_id)).to eq(["10000022222"])
      expect(statements.first.transactions.map(&:amount)).to eq([BigDecimal("-3500000")])
    end

    it "treats the header-only sb1-sparekonto.csv as empty" do
      expect { parser.parse(fixture_path("sb1-sparekonto.csv")) }
        .to raise_error(YnabOfx::EmptyStatementError)
    end
  end
end
