require "rubyXL"
require "date"

module YnabOfx
  module Parsers
    class SasMc < Base
      self.extensions = %w[.xlsx].freeze
      self.signature = /Transaksjonseksport/i

      CARD_HEADER_RX = /\A\d+\*+\d+\z/

      def read_statements(path)
        wb = RubyXL::Parser.parse(path)
        sheet = wb[0]

        transactions = []
        same_day_seen = Hash.new(0)
        active_card = nil
        active_holder = nil

        sheet.each do |row|
          next unless row
          values = row.cells.map { |c| c&.value }

          if (header = card_header(values))
            active_card, active_holder = header
            next
          end

          date = parse_date(values[0])
          next unless date

          posted = parse_date(values[1]) || date
          spesifikasjon = (values[2] || "").to_s.strip
          sted = (values[3] || "").to_s.strip
          valuta = (values[4] || "").to_s.strip
          utl = values[5]
          belop = values[6]

          next if spesifikasjon.empty? || belop.nil?

          source_amount = belop.to_s.tr(",", ".").to_f
          # SAS: positive = charge (debit), negative = payment to card.
          # OFX/YNAB: negative = debit, positive = credit. Flip the sign.
          amount = BigDecimal((-source_amount).to_s)

          payee_parts = [spesifikasjon, sted].reject(&:empty?)
          payee = payee_parts.join(" ")
          memo_extras = []
          memo_extras << "#{valuta} #{utl}" if valuta && !valuta.empty? && valuta != "NOK" && utl
          memo_extras << "card #{active_card}" if active_card
          memo_extras << active_holder.to_s if active_holder
          memo = ([payee] + memo_extras).join(" | ")

          key = [posted, amount, payee]
          same_day_seen[key] += 1
          fitid = fitid_for(posted, amount, payee, same_day_seen[key])

          transactions << Transaction.new(
            date: posted,
            amount: amount,
            payee: payee[0, 32],
            memo: memo,
            fitid: fitid
          )
        end

        dates = transactions.map(&:date)

        Statement.new(
          account_id: "SAS-MC",
          account_type: :creditcard,
          currency: "NOK",
          transactions: transactions,
          balance: nil,
          balance_date: dates.max,
          start_date: dates.min,
          end_date: dates.max
        )
      end

      private

      def card_header(values)
        return nil unless values[0].is_a?(String) && values[0] =~ CARD_HEADER_RX
        [values[0], values[1].to_s.strip]
      end

      def parse_date(val)
        case val
        when DateTime then val.to_date
        when Time     then val.to_date
        when Date     then val
        when String
          return nil unless val =~ /\A\d{4}-\d{2}-\d{2}/
          Date.parse(val)
        end
      end
    end
  end
end
