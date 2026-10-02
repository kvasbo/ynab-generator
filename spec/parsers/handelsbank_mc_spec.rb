RSpec.describe YnabOfx::Parsers::HandelsbankMc do
  subject(:parser) { described_class.new }

  # Mimics PDF::Reader's text layout: columns separated by runs of spaces.
  let(:summary_page) do
    <<~TXT
                                                                         Platinum Kredittkort
                                                    Periode:                      01.03.26 - 31.03.26
           Kari Nordmann
           Storgata 1                                Bankkonto                          90001234575
           Overført saldo fra forrige periode                                    -2.500,00
            =  Saldo i vår favør                                                 -3.248,46
    TXT
  end

  let(:transaction_page) do
    <<~TXT
                                                    Periode                     01.03.26 - 31.03.26
                                                    Kontonr.:                        90001234575
       Bruks      Bokført     Brukersted                          Valuta           Beløp    Gebyr          Beløp kr
       dato        dato
       28.02.26   01.03.26    Kebabsjappa Oslo                                    -189,00                   -189,00
       28.02.26   01.03.26    TM *TICKETMASTER BERLIN               EUR           -125,80                  -1.449,46
       01.03.26   02.03.26    SVØMMEHALLEN OSLO                                -55,00                     -55,00
       01.03.26   02.03.26    SVØMMEHALLEN OSLO                                -55,00                     -55,00
       15.03.26   15.03.26    Innbetaling                                        1.000,00                  1.000,00
       Betaler alt ved første faktura              0                                   0            15.000
       Minimum å betale - forfall 15.04.26                                   2.456,95
    TXT
  end

  def stub_pdf(*pages)
    reader = instance_double(PDF::Reader, pages: pages.map { |t| instance_double(PDF::Reader::Page, text: t) })
    allow(PDF::Reader).to receive(:new).with("statement.pdf").and_return(reader)
    "statement.pdf"
  end

  it "matches the Platinum Kredittkort signature" do
    expect(described_class.signature).to match(summary_page)
  end

  it "parses the account, period and balance from the summary page" do
    s = parser.parse(stub_pdf(summary_page, transaction_page))

    expect(s.account_id).to eq("90001234575")
    expect(s.account_type).to eq(:creditcard)
    expect(s.currency).to eq("NOK")
    expect(s.start_date).to eq(Date.new(2026, 3, 1))
    expect(s.end_date).to eq(Date.new(2026, 3, 31))
    expect(s.balance).to eq(BigDecimal("-3248.46"))
    expect(s.balance_date).to eq(Date.new(2026, 3, 31))
  end

  it "parses transaction lines and ignores everything else" do
    txns = parser.parse(stub_pdf(summary_page, transaction_page)).transactions

    expect(txns.map(&:payee)).to eq([
      "Kebabsjappa Oslo",
      "TM *TICKETMASTER BERLIN",
      "SVØMMEHALLEN OSLO",
      "SVØMMEHALLEN OSLO",
      "Innbetaling"
    ])
    expect(txns.map(&:amount)).to eq(
      %w[-189 -1449.46 -55 -55 1000].map { |a| BigDecimal(a) }
    )
  end

  it "dates transactions by the booking date" do
    txns = parser.parse(stub_pdf(summary_page, transaction_page)).transactions
    expect(txns.first.date).to eq(Date.new(2026, 3, 1))
    expect(txns[2].date).to eq(Date.new(2026, 3, 2))
  end

  it "uses the NOK amount and records the foreign amount in the memo" do
    fx = parser.parse(stub_pdf(summary_page, transaction_page)).transactions[1]

    expect(fx.amount).to eq(BigDecimal("-1449.46"))
    expect(fx.memo).to eq("TM *TICKETMASTER BERLIN | EUR -125,80")
  end

  it "uses just the merchant as memo for domestic purchases" do
    t = parser.parse(stub_pdf(summary_page, transaction_page)).transactions.first
    expect(t.memo).to eq("Kebabsjappa Oslo")
  end

  it "gives identical same-day rows distinct FITIDs" do
    txns = parser.parse(stub_pdf(summary_page, transaction_page)).transactions
    expect(txns.map(&:fitid).uniq.size).to eq(txns.size)
  end

  it "drops zero-amount lines" do
    zero = "   05.03.26   05.03.26    Kortgebyr                                             0,00                      0,00\n"
    txns = parser.parse(stub_pdf(summary_page, transaction_page + zero)).transactions
    expect(txns.map(&:payee)).not_to include("Kortgebyr")
    expect(txns.size).to eq(5)
  end

  it "falls back to the Kontonr. label when there is no Bankkonto line" do
    s = parser.parse(stub_pdf(transaction_page))
    expect(s.account_id).to eq("90001234575")
    expect(s.balance).to be_nil
  end

  it "raises ParseError without an account number" do
    path = stub_pdf("Platinum Kredittkort\nPeriode: 01.03.26 - 31.03.26\n")
    expect { parser.parse(path) }.to raise_error(YnabOfx::ParseError, /no account/)
  end

  it "raises ParseError without a period" do
    path = stub_pdf("Platinum Kredittkort\nKontonr.:   90001234575\n")
    expect { parser.parse(path) }.to raise_error(YnabOfx::ParseError, /no period/)
  end

  context "with the fixture export" do
    let(:statement) { parser.parse(fixture_path("handelsbank-mc.pdf")) }

    it "parses the statement header" do
      expect(statement.account_id).to eq("90001234575")
      expect(statement.start_date).to eq(Date.new(2026, 3, 1))
      expect(statement.end_date).to eq(Date.new(2026, 3, 31))
      expect(statement.balance).to eq(BigDecimal("-20929.49"))
    end

    it "finds every transaction" do
      expect(statement.transactions.size).to eq(30)
    end

    it "reconciles: previous balance + period spend = closing balance" do
      previous = BigDecimal("-2500")
      expect(statement.transactions.sum(&:amount)).to eq(BigDecimal("-18429.49"))
      expect(previous + statement.transactions.sum(&:amount)).to eq(statement.balance)
    end

    it "gives every transaction a unique FITID" do
      fitids = statement.transactions.map(&:fitid)
      expect(fitids.uniq.size).to eq(fitids.size)
    end
  end

  context "with the short fixture export (credit balance, refund and payout)" do
    let(:statement) { parser.parse(fixture_path("handelsbank-mc-short.pdf")) }

    it "parses the statement header" do
      expect(statement.account_id).to eq("90001234575")
      expect(statement.start_date).to eq(Date.new(2026, 8, 21))
      expect(statement.end_date).to eq(Date.new(2026, 9, 20))
      expect(statement.balance).to eq(BigDecimal("-12.40"))
    end

    it "keeps refunds positive and the payout of the credit balance negative" do
      expect(statement.transactions.map { |t| [t.payee, t.amount] }).to eq([
        ["FLYSELSKAPET Norway", BigDecimal("3200")],
        ["90001234567", BigDecimal("-3950")],
        ["NETTBUTIKKEN.FR PARIS", BigDecimal("-12.40")]
      ])
    end

    it "reconciles: credit carried over + period spend = closing balance" do
      expect(BigDecimal("750") + statement.transactions.sum(&:amount)).to eq(statement.balance)
    end
  end
end
