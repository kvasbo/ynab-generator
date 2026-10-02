require "csv"
require "bigdecimal"
require "date"

module YnabOfx
  module Parsers
    class Sparebank1Csv < Base
      self.extensions = %w[.csv].freeze
      self.signature = /Dato;Beskrivelse;Rentedato;Inn;Ut;Til konto;Fra konto/i

      def read_statements(path)
        rows = read_rows(path)
        raise EmptyStatementError, "no transactions in #{path}" if rows.empty?

        grouped = group_by_owning_account(rows)
        raise ParseError, "no account identifiable in #{path}" if grouped.empty?

        grouped.map { |account_id, grp| build_statement(account_id, grp) }
      end

      private

      def read_rows(path)
        raw = File.read(path, mode: "rb").force_encoding("UTF-8").sub("﻿", "")
        CSV.parse(raw, col_sep: ";", headers: true).map(&:to_h)
      end

      # The owning account is the side the amount sign refers to:
      #   money in  (Inn) -> "Til konto" owns the row
      #   money out (Ut)  -> "Fra konto" owns the row
      # Internal transfers appear in both account exports with opposite signs,
      # so routing each row to one account leaves a proper YNAB transfer pair.
      def group_by_owning_account(rows)
        rows.each_with_object({}) do |row, acc|
          next unless row_amount(row)
          key = owning_account_key(row) or next
          acc[key] ||= []
          acc[key] << row
        end
      end

      def owning_account_key(row)
        amount = row_amount(row)
        primary, fallback = amount.negative? ? %w[Fra\ konto Til\ konto] : %w[Til\ konto Fra\ konto]
        number = row[primary].to_s.strip
        number = row[fallback].to_s.strip if number.empty?
        number.empty? ? nil : number
      end

      def build_statement(account_id, rows)
        txns = build_transactions(rows)
        dates = txns.map(&:date)
        Statement.new(
          account_id: account_id,
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
          date = Date.strptime(row["Dato"].to_s.strip, "%d.%m.%Y")
          amount = row_amount(row)
          payee = row["Beskrivelse"].to_s.strip

          counter = amount.negative? ? row["Til konto"] : row["Fra konto"]
          memo = [payee, counter.to_s.strip].reject(&:empty?).uniq.join(" | ")

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

      def row_amount(row)
        inn = row["Inn"].to_s.strip
        ut = row["Ut"].to_s.strip
        raw = inn.empty? ? ut : inn
        return nil if raw.empty?
        parse_norwegian_amount(raw)
      end
    end
  end
end
