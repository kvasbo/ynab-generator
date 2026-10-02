RSpec.describe YnabOfx::Parsers::Base do
  subject(:parser) { described_class.new }

  describe "#parse" do
    it "requires subclasses to implement #read_statements" do
      expect { parser.parse("x") }.to raise_error(NotImplementedError)
    end

    context "with a subclass" do
      def txn(amount) = YnabOfx::Transaction.new(date: Date.new(2026, 1, 1), amount: BigDecimal(amount), payee: amount)
      def statement(*amounts) = YnabOfx::Statement.new(account_id: amounts.join, transactions: amounts.map { |a| txn(a) })

      def parser_returning(result)
        Class.new(described_class) { define_method(:read_statements) { |_path| result } }.new
      end

      it "drops zero-amount transactions" do
        s = parser_returning(statement("-10", "0", "0.00", "5")).parse("x")
        expect(s.transactions.map(&:payee)).to eq(%w[-10 5])
      end

      it "returns a single statement as-is when the parser returns one" do
        expect(parser_returning(statement("1")).parse("x")).to be_a(YnabOfx::Statement)
      end

      it "drops statements left empty in a multi-account result" do
        result = parser_returning([statement("1"), statement("0")]).parse("x")
        expect(result.map(&:account_id)).to eq(["1"])
      end

      it "raises EmptyStatementError when nothing is left" do
        expect { parser_returning(statement("0")).parse("x") }
          .to raise_error(YnabOfx::EmptyStatementError)
        expect { parser_returning([statement("0"), statement]).parse("x") }
          .to raise_error(YnabOfx::EmptyStatementError)
      end
    end
  end

  describe "#parse_norwegian_amount" do
    def amount(str) = parser.send(:parse_norwegian_amount, str)

    it "treats comma as the decimal separator" do
      expect(amount("-347,00")).to eq(BigDecimal("-347"))
      expect(amount("15,60")).to eq(BigDecimal("15.6"))
    end

    it "strips dots used as thousands separators" do
      expect(amount("-12.345,67")).to eq(BigDecimal("-12345.67"))
      expect(amount("1.234.567,89")).to eq(BigDecimal("1234567.89"))
    end

    it "strips plain and non-breaking spaces used as thousands separators" do
      expect(amount("88 077,59")).to eq(BigDecimal("88077.59"))
      expect(amount("37\u00A0000,50")).to eq(BigDecimal("37000.50"))
    end

    it "ignores surrounding whitespace" do
      expect(amount("  -5,00 ")).to eq(BigDecimal("-5"))
    end

    it "returns a BigDecimal so amounts stay exact" do
      expect(amount("0,10")).to be_a(BigDecimal)
    end

    it "raises on garbage" do
      expect { amount("abc") }.to raise_error(ArgumentError)
    end
  end

  describe "#fitid_for" do
    def fitid(*args) = parser.send(:fitid_for, *args)

    let(:date) { Date.new(2026, 5, 4) }

    it "is a 32-char hex string" do
      expect(fitid(date, BigDecimal("-50"), "Rema", 1)).to match(/\A\h{32}\z/)
    end

    it "is deterministic" do
      a = fitid(date, BigDecimal("-50"), "Rema", 1)
      b = fitid(date, BigDecimal("-50.00"), "Rema", 1)
      expect(a).to eq(b)
    end

    it "differs when any input differs" do
      base = fitid(date, BigDecimal("-50"), "Rema", 1)
      expect(fitid(date + 1, BigDecimal("-50"), "Rema", 1)).not_to eq(base)
      expect(fitid(date, BigDecimal("-51"), "Rema", 1)).not_to eq(base)
      expect(fitid(date, BigDecimal("-50"), "Kiwi", 1)).not_to eq(base)
      expect(fitid(date, BigDecimal("-50"), "Rema", 2)).not_to eq(base)
    end
  end
end
