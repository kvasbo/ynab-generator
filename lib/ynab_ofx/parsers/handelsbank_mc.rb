require "pdf-reader"

module YnabOfx
  module Parsers
    class HandelsbankMc < Base
      self.extensions = %w[.pdf].freeze
      self.signature = /Platinum Kredittkort/i

      ACCOUNT_RX = /Bankkonto\s+(\d+)|Kontonr\.:\s+(\d+)/
      PERIOD_RX  = /Periode[:\s]+(\d{2}\.\d{2}\.\d{2})\s*-\s*(\d{2}\.\d{2}\.\d{2})/
      BALANCE_RX = /Saldo i v\S+r fav\S+r\s+(-?[\d.,]+)/
      DATE_RX    = /\A\d{2}\.\d{2}\.\d{2}\z/
      CURRENCY_RX = /\A[A-Z]{3}\z/
      AMOUNT_RX   = /\A-?[\d.,]+\z/

      def read_statements(path)
        text = PDF::Reader.new(path).pages.map(&:text).join("\n")
        account_id = (m = text.match(ACCOUNT_RX)) ? (m[1] || m[2]) : raise(ParseError, "no account in #{path}")
        period = text.match(PERIOD_RX) or raise ParseError, "no period in #{path}"
        end_date = parse_short_date(period[2])

        Statement.new(
          account_id: account_id,
          account_type: :creditcard,
          currency: "NOK",
          transactions: parse_transactions(text),
          balance: parse_balance(text),
          balance_date: end_date,
          start_date: parse_short_date(period[1]),
          end_date: end_date
        )
      end

      private

      def parse_balance(text)
        m = text.match(BALANCE_RX) or return nil
        parse_norwegian_amount(m[1])
      end

      def parse_transactions(text)
        same_day_seen = Hash.new(0)

        text.each_line.filter_map do |line|
          fields = line.strip.split(/\s{2,}/)
          next if fields.size < 5
          next unless fields[0] =~ DATE_RX && fields[1] =~ DATE_RX

          bokfort = parse_short_date(fields[1])
          merchant = fields[2]
          nok_amount = parse_norwegian_amount(fields.last)

          memo_extras = []
          middle = fields[3..-2]
          if middle && middle.first =~ CURRENCY_RX
            currency = middle.shift
            foreign_amount = middle.shift
            memo_extras << "#{currency} #{foreign_amount}" if foreign_amount
          end

          memo = ([merchant] + memo_extras).join(" | ")
          key = [bokfort, nok_amount, merchant]
          same_day_seen[key] += 1
          fitid = fitid_for(bokfort, nok_amount, merchant, same_day_seen[key])

          Transaction.new(
            date: bokfort,
            amount: nok_amount,
            payee: merchant[0, 32],
            memo: memo,
            fitid: fitid
          )
        end
      end

      def parse_short_date(str)
        Date.strptime(str, "%d.%m.%y")
      end
    end
  end
end
