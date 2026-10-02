require "csv"
require "rubyXL"
require "bigdecimal"
require "date"

module YnabOfx
  module Parsers
    # DNB account exports: the "Last ned fil" .txt (semicolon CSV) and the
    # .xlsx download share the same columns. Neither includes the account
    # number, so every DNB statement gets the same placeholder account ID.
    class Dnb < Base
      self.extensions = %w[.txt .xlsx].freeze
      self.signature = /Dato\W+Forklaring\W+Rentedato\W+Ut fra konto/

      RESERVED_RX = /Reservert transaksjon/i
      PURCHASE_PREFIX_RX = /\A(?:E-)?varekjøp /i
      CARD_TIME_RX = / Dato \d{2}\.\d{2} kl\. \d{2}\.\d{2}\z/

      def read_statements(path)
        rows = File.extname(path).downcase == ".xlsx" ? xlsx_rows(path) : txt_rows(path)
        txns = build_transactions(rows)
        dates = txns.map(&:date)

        Statement.new(
          account_id: "DNB",
          account_type: :bank,
          currency: "NOK",
          transactions: txns,
          balance: nil,
          balance_date: dates.max,
          start_date: dates.min,
          end_date: dates.max
        )
      end

      private

      # Each row is [date, description, out, in].
      def txt_rows(path)
        raw = File.read(path, mode: "rb").force_encoding("UTF-8").sub("﻿", "")
        CSV.parse(raw, col_sep: ";", headers: true).map do |r|
          [Date.strptime(r["Dato"].to_s.strip, "%d.%m.%Y"), r["Forklaring"], r[3], r[4]]
        end
      end

      def xlsx_rows(path)
        RubyXL::Parser.parse(path)[0].sheet_data.rows.filter_map do |row|
          next unless row
          date, desc, _rentedato, out, inn = row.cells.map { |c| c&.value }
          next unless date.is_a?(DateTime)
          [date.to_date, desc, out, inn]
        end
      end

      def build_transactions(rows)
        same_day_seen = Hash.new(0)

        rows.filter_map do |date, desc, out, inn|
          desc = desc.to_s.squeeze(" ").strip
          next if desc.match?(RESERVED_RX)

          amount = amount_or_zero(inn) - amount_or_zero(out)
          payee = desc.sub(PURCHASE_PREFIX_RX, "").sub(CARD_TIME_RX, "")

          key = [date, amount, desc]
          same_day_seen[key] += 1
          fitid = fitid_for(date, amount, desc, same_day_seen[key])

          Transaction.new(
            date: date,
            amount: amount,
            payee: payee[0, 32],
            memo: desc,
            fitid: fitid
          )
        end
      end

      def amount_or_zero(value)
        s = value.to_s.strip
        s.empty? ? BigDecimal("0") : BigDecimal(s)
      end
    end
  end
end
