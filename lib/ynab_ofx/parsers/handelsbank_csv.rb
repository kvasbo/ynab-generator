require "csv"
require "bigdecimal"

module YnabOfx
  module Parsers
    class HandelsbankCsv < Base
      self.extensions = %w[.csv].freeze
      self.signature = /Bokf\S+rt dato;Rentedato;Beskrivelse/

      DATE_RX    = /\A\d{2}\.\d{2}\.\d{4}\z/
      OPENING_RX = /Inng\S+ende saldo pr\.\s*(\d{2}\.\d{2}\.\d{4})/
      CLOSING_RX = /Utg\S+ende\s+saldo pr\.\s*(\d{2}\.\d{2}\.\d{4})/

      def read_statements(path)
        rows = read_rows(path)
        txn_rows, summary_rows = partition_rows(rows)
        raise EmptyStatementError, "no transactions in #{path}" if txn_rows.empty?

        account_id = detect_account(txn_rows) or raise ParseError, "no account in #{path}"
        period = extract_period_and_balance(summary_rows, txn_rows)

        Statement.new(
          account_id: account_id,
          account_type: :bank,
          currency: "NOK",
          transactions: build_transactions(txn_rows),
          balance: period[:balance],
          balance_date: period[:balance_date],
          start_date: period[:start_date],
          end_date: period[:end_date]
        )
      end

      private

      def read_rows(path)
        raw = File.read(path, mode: "rb").force_encoding("ISO-8859-1").encode("UTF-8")
        CSV.parse(raw, col_sep: ";", headers: true).map(&:fields)
      end

      def partition_rows(rows)
        txn = []
        summary = []
        rows.each do |f|
          next if f.all? { |c| c.nil? || c.to_s.strip.empty? }
          if f[0].to_s =~ DATE_RX && f[1].to_s =~ DATE_RX
            txn << f
          elsif f[0].to_s.include?(":")
            summary << f
          end
        end
        [txn, summary]
      end

      def detect_account(rows)
        counts = Hash.new(0)
        rows.each do |f|
          [f[6], f[8]].each do |acc|
            s = acc.to_s.strip
            counts[s] += 1 unless s.empty?
          end
        end
        counts.max_by { |_, c| c }&.first
      end

      def extract_period_and_balance(summary, txn_rows)
        opening_date = closing_date = closing_balance = nil

        summary.each do |f|
          label = f[0].to_s
          value = f[2].to_s
          if (m = label.match(OPENING_RX))
            opening_date = Date.strptime(m[1], "%d.%m.%Y")
          elsif (m = label.match(CLOSING_RX))
            closing_date = Date.strptime(m[1], "%d.%m.%Y")
            closing_balance = parse_balance(value)
          end
        end

        dates = txn_rows.map { |f| Date.strptime(f[1], "%d.%m.%Y") }
        {
          start_date: opening_date || dates.min,
          end_date: closing_date || dates.max,
          balance: closing_balance,
          balance_date: closing_date || dates.max
        }
      end

      def parse_balance(str)
        cleaned = str.sub(/\s*NOK\s*\z/i, "")
        parse_norwegian_amount(cleaned)
      rescue StandardError
        nil
      end

      def build_transactions(rows)
        same_day_seen = Hash.new(0)

        rows.map do |f|
          date = Date.strptime(f[1], "%d.%m.%Y")
          desc = f[3].to_s.strip
          amount = amount_or_zero(f[10]) + amount_or_zero(f[11])

          counterparty = [f[7], f[9]].map { |x| x.to_s.strip }.reject(&:empty?)
          melding = f[14].to_s.tr("\n", " ").squeeze(" ").strip
          memo = ([desc] + counterparty + [melding]).reject(&:empty?).uniq.join(" | ")

          key = [date, amount, desc]
          same_day_seen[key] += 1
          fitid = fitid_for(date, amount, desc, same_day_seen[key])

          Transaction.new(
            date: date,
            amount: amount,
            payee: desc[0, 32],
            memo: memo,
            fitid: fitid
          )
        end
      end

      def amount_or_zero(str)
        s = str.to_s.strip
        return BigDecimal("0") if s.empty?
        BigDecimal(s)
      end
    end
  end
end
