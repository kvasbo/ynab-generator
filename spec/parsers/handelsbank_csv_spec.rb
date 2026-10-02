RSpec.describe YnabOfx::Parsers::HandelsbankCsv do
  subject(:parser) { described_class.new }

  let(:header) do
    "Utført dato;Bokført dato;Rentedato;Beskrivelse;Type;Undertype;Fra konto;Avsender;" \
      "Til konto;Mottakernavn;Beløp inn;Beløp ut;Valuta;Status;Melding/KID/Fakt.nr\n"
  end
  let(:blank) { ";;;;;;;;;;;;;;\n" }

  # Handelsbanken exports ISO-8859-1.
  def fixture(content) = write_temp_file("handelsbank.csv", content, encoding: "ISO-8859-1")

  let(:transactions) do
    <<~CSV
      06.05.2026;06.05.2026;06.05.2026;ARBEIDSGIVER AS;Betaling innland;Overføring fra annen konto;1111 22 33334;ARBEIDSGIVER AS;9000 12 34567;Kari Nordmann;12500.50;;NOK;Bokført;"Fra: ARBEIDSGIVER AS
      12.500,50"
      04.05.2026;05.05.2026;04.05.2026;Til konto: 9000 12 99999;Betaling innland;Overføring til annen konto;9000 12 34567;Brukskonto;9000 12 99999;;;-20000;NOK;Bokført;90001234567
    CSV
  end

  let(:summary) do
    blank + "Total beløp inn på konto:;;12 500,50 NOK;;;;;;;;;;;;\n" +
      blank + "Inngående saldo pr. 01.05.2026:;;25 000,00 NOK;;;;;;;;;;;;\n" +
      blank + "Utgående  saldo pr. 10.05.2026:;;17 500,50 NOK;;;;;;;;;;;;\n"
  end

  it "matches the Handelsbanken header signature" do
    expect(described_class.signature).to match(header)
  end

  it "parses transactions and the summary footer" do
    s = parser.parse(fixture(header + transactions + summary))

    expect(s).to be_a(YnabOfx::Statement)
    expect(s.account_id).to eq("9000 12 34567")
    expect(s.account_type).to eq(:bank)
    expect(s.currency).to eq("NOK")
    expect(s.start_date).to eq(Date.new(2026, 5, 1))
    expect(s.end_date).to eq(Date.new(2026, 5, 10))
    expect(s.balance).to eq(BigDecimal("17500.50"))
    expect(s.balance_date).to eq(Date.new(2026, 5, 10))
    expect(s.transactions.size).to eq(2)
  end

  it "decodes ISO-8859-1 and flattens multi-line messages into the memo" do
    inn = parser.parse(fixture(header + transactions)).transactions.first

    expect(inn.date).to eq(Date.new(2026, 5, 6))
    expect(inn.amount).to eq(BigDecimal("12500.50"))
    expect(inn.payee).to eq("ARBEIDSGIVER AS")
    expect(inn.memo).to eq("ARBEIDSGIVER AS | Kari Nordmann | Fra: ARBEIDSGIVER AS 12.500,50")
  end

  it "dates transactions by the booking date, not the execution date" do
    ut = parser.parse(fixture(header + transactions)).transactions.last

    expect(ut.date).to eq(Date.new(2026, 5, 5))
    expect(ut.amount).to eq(BigDecimal("-20000"))
    expect(ut.memo).to eq("Til konto: 9000 12 99999 | Brukskonto | 90001234567")
  end

  it "falls back to transaction dates and no balance when the footer is missing" do
    s = parser.parse(fixture(header + transactions))

    expect(s.start_date).to eq(Date.new(2026, 5, 5))
    expect(s.end_date).to eq(Date.new(2026, 5, 6))
    expect(s.balance).to be_nil
    expect(s.balance_date).to eq(Date.new(2026, 5, 6))
  end

  it "truncates long payees to 32 characters" do
    row = "04.05.2026;04.05.2026;04.05.2026;KORTSELSKAPET AS, OSLOFIL.NUF (55550000111);Betaling innland;" \
          "Utgående betaling;9000 12 34567;Brukskonto;5555 00 00111;KORTSELSKAPET;;-5000;NOK;Bokført;\n"
    t = parser.parse(fixture(header + row)).transactions.first

    expect(t.payee).to eq("KORTSELSKAPET AS, OSLOFIL.NUF (5")
    expect(t.memo).to start_with("KORTSELSKAPET AS, OSLOFIL.NUF (55550000111) | ")
  end

  it "gives identical same-day rows distinct, stable FITIDs" do
    row = "04.05.2026;04.05.2026;04.05.2026;Kiosk;Varekjøp;;9000 12 34567;Brukskonto;;;;-45;NOK;Bokført;\n"
    content = header + row + row

    first = parser.parse(fixture(content)).transactions.map(&:fitid)
    second = parser.parse(fixture(content)).transactions.map(&:fitid)
    expect(first.uniq.size).to eq(2)
    expect(first).to eq(second)
  end

  it "drops zero-amount rows" do
    zero = "04.05.2026;04.05.2026;04.05.2026;Varsel;Info;;9000 12 34567;Brukskonto;;;0;;NOK;Bokført;\n"
    blank = "04.05.2026;04.05.2026;04.05.2026;Tom;Info;;9000 12 34567;Brukskonto;;;;;NOK;Bokført;\n"
    s = parser.parse(fixture(header + transactions + zero + blank))

    expect(s.transactions.map(&:payee)).not_to include("Varsel", "Tom")
    expect(s.transactions.size).to eq(2)
  end

  it "raises EmptyStatementError when only the footer is present" do
    expect { parser.parse(fixture(header + summary)) }
      .to raise_error(YnabOfx::EmptyStatementError)
  end

  context "with the fixture export" do
    let(:statement) { parser.parse(fixture_path("handelsbank_csv_eksport.csv")) }

    it "parses the account, period and closing balance" do
      expect(statement.account_id).to eq("9000 12 34567")
      expect(statement.start_date).to eq(Date.new(2026, 5, 1))
      expect(statement.end_date).to eq(Date.new(2026, 5, 10))
      expect(statement.balance).to eq(BigDecimal("37000.50"))
    end

    it "reconciles: opening balance + transactions = closing balance" do
      opening = BigDecimal("25000.00")
      expect(opening + statement.transactions.sum(&:amount)).to eq(statement.balance)
    end
  end
end
