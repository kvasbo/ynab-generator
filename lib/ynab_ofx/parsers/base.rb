require "bigdecimal"
require "digest"

module YnabOfx
  module Parsers
    class Base
      class << self
        attr_accessor :extensions, :signature
      end

      # Returns a Statement, or an Array of them for multi-account exports.
      # Subclasses implement #read_statements; shared clean-up happens here.
      def parse(path)
        result = read_statements(path)
        statements = result.is_a?(Array) ? result : [result]
        statements.each { |s| s.transactions = s.transactions.reject { |t| t.amount.zero? } }
        statements.reject! { |s| s.transactions.empty? }
        raise EmptyStatementError, "no transactions in #{path}" if statements.empty?

        result.is_a?(Array) ? statements : statements.first
      end

      private

      def read_statements(_path)
        raise NotImplementedError
      end

      def parse_norwegian_amount(str)
        cleaned = str.to_s.strip.delete("  ").tr(".", "").tr(",", ".")
        BigDecimal(cleaned)
      end

      def fitid_for(date, amount, description, same_day_index)
        key = [date.strftime("%Y%m%d"), amount.to_s("F"), description, same_day_index].join("|")
        Digest::SHA1.hexdigest(key)[0, 32]
      end
    end
  end
end
