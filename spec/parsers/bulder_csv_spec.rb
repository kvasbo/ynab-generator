RSpec.describe YnabOfx::Parsers::BulderCsv do
  subject(:parser) { described_class.new }

  let(:header) do
    "Dato;Beløp;Originalt Beløp;Original Valuta;Til konto;Til kontonummer;" \
      "Fra konto;Fra kontonummer;Type;Tekst;KID;Hovedkategori;Underkategori\n"
  end

  def csv(*lines) = header + lines.map { |l| "#{l}\n" }.join

  def by_account(statements) = statements.to_h { |s| [s.account_id, s] }

  it "matches the Bulder header signature" do
    expect(described_class.signature).to match(header)
  end

  it "builds a bank statement from a single account's rows" do
    path = write_temp_file("bulder.csv", csv(
      "2026-05-13;-248,00;-248,00;NOK;;Bakeriet;BRUKSKONTO;3600.10.00001;Betaling;Bakeriet;;Mat og drikke;Bakervarer",
      "2026-05-14;1.500,50;1.500,50;NOK;BRUKSKONTO;3600.10.00001;Ola;1234.56.78901;Betaling;Vipps fra Ola;;;"
    ))

    statements = parser.parse(path)
    expect(statements.size).to eq(1)

    s = statements.first
    expect(s.account_id).to eq("3600.10.00001")
    expect(s.account_name).to eq("BRUKSKONTO")
    expect(s.account_type).to eq(:bank)
    expect(s.currency).to eq("NOK")
    expect(s.balance).to be_nil
    expect(s.start_date).to eq(Date.new(2026, 5, 13))
    expect(s.end_date).to eq(Date.new(2026, 5, 14))

    out, inn = s.transactions
    expect(out.amount).to eq(BigDecimal("-248"))
    expect(out.payee).to eq("Bakeriet")
    expect(out.memo).to eq("Bakeriet | Betaling | Mat og drikke | Bakervarer")

    expect(inn.amount).to eq(BigDecimal("1500.50"))
    expect(inn.payee).to eq("Vipps fra Ola")
    expect(inn.memo).to eq("Vipps fra Ola | Ola 1234.56.78901 | Betaling")
  end

  it "routes each half of an internal transfer to the account it belongs to" do
    path = write_temp_file("bulder.csv", csv(
      "2026-04-24;-20000,00;-20000,00;NOK;BRUKSKONTO;3600.10.00001;Buffer;3600.10.00002;Overføring;;;;",
      "2026-04-24;20000,00;20000,00;NOK;BRUKSKONTO;3600.10.00001;Buffer;3600.10.00002;Overføring;;;;"
    ))

    statements = by_account(parser.parse(path))
    expect(statements.keys).to contain_exactly("3600.10.00001", "3600.10.00002")

    buffer = statements["3600.10.00002"]
    expect(buffer.account_name).to eq("Buffer")
    expect(buffer.transactions.map(&:amount)).to eq([BigDecimal("-20000")])
    # No Tekst: the payee falls back to the counter-account name.
    expect(buffer.transactions.first.payee).to eq("BRUKSKONTO")

    brukskonto = statements["3600.10.00001"]
    expect(brukskonto.transactions.map(&:amount)).to eq([BigDecimal("20000")])
    expect(brukskonto.transactions.first.payee).to eq("Buffer")
  end

  it "drops zero-amount rows such as e-faktura notices" do
    path = write_temp_file("bulder.csv", csv(
      "2026-04-23;0,00;0,00;NOK;;1111.22.33333;BRUKSKONTO;3600.10.00001;Efaktura;Strøm;123;;",
      "2026-04-23;0,00;0,00;NOK;Buffer;3600.10.00002;;;Renter;Renter;;;",
      "2026-04-23;-10,00;-10,00;NOK;;Rema;BRUKSKONTO;3600.10.00001;Betaling;Rema;;;"
    ))

    statements = parser.parse(path)
    expect(statements.map(&:account_id)).to eq(["3600.10.00001"])
    expect(statements.first.transactions.map(&:payee)).to eq(["Rema"])
  end

  it "raises EmptyStatementError when every row is zero" do
    path = write_temp_file("bulder.csv", csv(
      "2026-04-23;0,00;0,00;NOK;;1111.22.33333;BRUKSKONTO;3600.10.00001;Efaktura;Strøm;123;;"
    ))
    expect { parser.parse(path) }.to raise_error(YnabOfx::EmptyStatementError)
  end

  it "uses the counter-account number, then the type, when there is no other payee text" do
    path = write_temp_file("bulder.csv", csv(
      "2026-05-01;-10,00;-10,00;NOK;;5555.66.77778;BRUKSKONTO;3600.10.00001;Betaling;;;;",
      "2026-05-01;-20,00;-20,00;NOK;;;BRUKSKONTO;3600.10.00001;Gebyr;;;;"
    ))

    payees = parser.parse(path).first.transactions.map(&:payee)
    expect(payees).to eq(["5555.66.77778", "Gebyr"])
  end

  it "drops rows where no account number can be found" do
    path = write_temp_file("bulder.csv", csv(
      "2026-05-01;-10,00;-10,00;NOK;;;;;Betaling;Mystery;;;",
      "2026-05-01;-20,00;-20,00;NOK;;Rema;BRUKSKONTO;3600.10.00001;Betaling;Rema;;;"
    ))

    txns = parser.parse(path).flat_map(&:transactions)
    expect(txns.map(&:payee)).to eq(["Rema"])
  end

  it "gives identical same-day rows distinct, stable FITIDs" do
    row = "2026-05-14;-129,00;-129,00;NOK;;Apple;BRUKSKONTO;3600.10.00001;Betaling;Apple;;;"
    content = csv(row, row)

    first = parser.parse(write_temp_file("a.csv", content)).first.transactions.map(&:fitid)
    second = parser.parse(write_temp_file("b.csv", content)).first.transactions.map(&:fitid)
    expect(first.uniq.size).to eq(2)
    expect(first).to eq(second)
  end

  it "raises EmptyStatementError for a header-only export" do
    path = write_temp_file("bulder.csv", header)
    expect { parser.parse(path) }.to raise_error(YnabOfx::EmptyStatementError)
  end

  it "raises ParseError when no row has an account number" do
    path = write_temp_file("bulder.csv", csv("2026-05-01;-10,00;-10,00;NOK;;;;;Betaling;X;;;"))
    expect { parser.parse(path) }.to raise_error(YnabOfx::ParseError)
  end

  context "with the fixture export" do
    let(:statements) { by_account(parser.parse(fixture_path("bulder_export_all.csv"))) }

    it "splits the combined export into one statement per account" do
      counts = statements.transform_values { |s| s.transactions.size }
      expect(counts).to eq(
        "3600.10.00001" => 16,
        "3600.10.00002" => 2,
        "3600.10.00003" => 6,
        "3600.20.00001" => 2
      )
    end

    it "keeps every non-zero row exactly once" do
      # 28 rows, two of which are 0,00 e-faktura notices.
      expect(statements.values.sum { |s| s.transactions.size }).to eq(26)
    end

    it "gives every transaction a unique FITID" do
      fitids = statements.values.flat_map(&:transactions).map(&:fitid)
      expect(fitids.uniq.size).to eq(fitids.size)
    end
  end
end
