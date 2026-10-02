RSpec.describe YnabOfx::OfxWriter do
  def statement(type: :bank, account_id: "9000 12 34567")
    txn = YnabOfx::Transaction.new(
      date: Date.new(2026, 5, 4), amount: BigDecimal("-45.5"),
      payee: "Kiosk & Kafé", memo: "<memo>", fitid: "abc"
    )
    YnabOfx::Statement.new(
      account_id: account_id, account_type: type, currency: "NOK", transactions: [txn],
      balance: BigDecimal("100"), start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 31)
    )
  end

  def bank_id(xml) = xml[%r{<BANKID>(.*?)</BANKID>}, 1]

  describe "bank statements" do
    it "uses the bank registration number from the account number as BANKID" do
      expect(bank_id(described_class.render(statement(account_id: "9000 12 34567")))).to eq("9000")
      expect(bank_id(described_class.render(statement(account_id: "3600.10.00001")))).to eq("3600")
      expect(bank_id(described_class.render(statement(account_id: "10000011111")))).to eq("1000")
    end

    it "falls back to 0000 when the account id is not a Norwegian account number" do
      expect(bank_id(described_class.render(statement(account_id: "ABC")))).to eq("0000")
    end
  end

  describe "credit card statements" do
    let(:xml) { described_class.render(statement(type: :creditcard, account_id: "SAS-MC")) }

    it "uses the credit card message set, which has no BANKID" do
      expect(xml).to include("<CCACCTFROM>", "<ACCTID>SAS-MC</ACCTID>")
      expect(xml).not_to include("<BANKID>")
    end
  end

  it "renders transactions with escaped text and two-decimal amounts" do
    xml = described_class.render(statement)
    expect(xml).to include(
      "<TRNTYPE>DEBIT</TRNTYPE>", "<DTPOSTED>20260504</DTPOSTED>", "<TRNAMT>-45.50</TRNAMT>",
      "<FITID>abc</FITID>", "<NAME>Kiosk &amp; Kafé</NAME>", "<MEMO>&lt;memo&gt;</MEMO>",
      "<BALAMT>100.00</BALAMT>"
    )
  end

  it "rejects unknown account types" do
    expect { described_class.render(statement(type: :savings)) }.to raise_error(ArgumentError)
  end
end
