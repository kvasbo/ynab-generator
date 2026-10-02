require "csv"
require "bigdecimal"
require "date"

module YnabOfx
  module Parsers
    class BulderCsv < Base
      self.extensions = %w[.csv].freeze
      self.signature = /Originalt Bel\S+p;Original Valuta;Til konto;Til kontonummer;Fra konto;Fra kontonummer/i

      def read_statements(path)
        rows = read_rows(path)
        raise EmptyStatementError, "no transactions in #{path}" if rows.empty?

        grouped = group_by_owning_account(rows)
        raise ParseError, "no account identifiable in #{path}" if grouped.empty?

        grouped.map { |(account_id, account_name), grp| build_statement(account_id, account_name, grp) }
      end

      private

      def read_rows(path)
        raw = File.read(path, mode: "rb").force_encoding("UTF-8")
        CSV.parse(raw, col_sep: ";", headers: true).map(&:to_h)
      end

      # Each row's owning account is the side that the amount sign refers to:
      #   positive Beløp -> "Til konto" (money came in)
      #   negative Beløp -> "Fra konto" (money went out)
      # Internal transfers appear as two rows with opposite signs; this routes
      # each row to exactly one account, so importing both files to YNAB leaves
      # a proper transfer pair without duplicates.
      def group_by_owning_account(rows)
        rows.each_with_object({}) do |row, acc|
          key = owning_account_key(row) or next
          acc[key] ||= []
          acc[key] << row
        end
      end

      def owning_account_key(row)
        amount = parse_norwegian_amount(row["Beløp"].to_s)
        side = amount.positive? ? "Til" : "Fra"
        number = row["#{side} kontonummer"].to_s.strip
        name = row["#{side} konto"].to_s.strip
        return nil if number.empty?
        [number, name]
      end

      def build_statement(account_id, account_name, rows)
        txns = build_transactions(rows)
        dates = txns.map(&:date)
        Statement.new(
          account_id: account_id,
          account_name: account_name.empty? ? nil : account_name,
          account_type: :bank,
          currency: "NOK",
          transactions: txns,
          balance: nil,
          balance_date: dates.max,
          start_date: dates.min,
          end_date: dates.max
        )
      end

      def build_transactions(rows)
        same_day_seen = Hash.new(0)

        rows.map do |row|
          date = Date.parse(row["Dato"])
          amount = parse_norwegian_amount(row["Beløp"].to_s)
          tekst = row["Tekst"].to_s.strip
          type = row["Type"].to_s.strip

          if amount.negative?
            counter_name = row["Til konto"].to_s.strip
            counter_number = row["Til kontonummer"].to_s.strip
          else
            counter_name = row["Fra konto"].to_s.strip
            counter_number = row["Fra kontonummer"].to_s.strip
          end

          payee = first_non_empty(tekst, counter_name, counter_number, type)

          memo_parts = [
            tekst,
            [counter_name, counter_number].reject(&:empty?).join(" "),
            type,
            row["Hovedkategori"].to_s.strip,
            row["Underkategori"].to_s.strip
          ]
          memo = memo_parts.reject(&:empty?).uniq.join(" | ")

          key = [date, amount, payee]
          same_day_seen[key] += 1
          fitid = fitid_for(date, amount, payee, same_day_seen[key])

          Transaction.new(
            date: date,
            amount: amount,
            payee: payee[0, 32],
            memo: memo,
            fitid: fitid
          )
        end
      end

      def first_non_empty(*values)
        values.map(&:to_s).map(&:strip).reject(&:empty?).first || ""
      end
    end
  end
end
