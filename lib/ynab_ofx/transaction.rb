require "bigdecimal"
require "date"

module YnabOfx
  Transaction = Struct.new(:date, :amount, :payee, :memo, :fitid, keyword_init: true) do
    def trntype
      amount.negative? ? "DEBIT" : "CREDIT"
    end
  end
end
