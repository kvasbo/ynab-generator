#!/usr/bin/env ruby
# Generates fictional Handelsbanken Platinum Kredittkort statements laid out
# like the real thing (same labels, column positions and number formats), so
# the parser can be tested without real account data:
#
#   handelsbank-mc.pdf        a month of ordinary card use over three pages
#   handelsbank-mc-short.pdf  a credit balance carried over ("tilgode"), a
#                             refund and a payout of the credit to a bank account
#
#   ruby spec/fixtures/build_handelsbank_mc_pdf.rb
#
# Writes a minimal PDF by hand using the built-in Helvetica font, so it needs
# no gems.

require "bigdecimal"

ACCOUNT = "90001234575".freeze

# [bruksdato, bokført, brukersted, valuta, beløp i valuta, beløp kr]
MONTH = [
  ["28.02.26", "01.03.26", "Kebabsjappa Oslo", nil, nil, "-189,00"],
  ["28.02.26", "01.03.26", "TM *TICKETMASTER BERLIN", "EUR", "-89,50", "-1.031,23"],
  ["01.03.26", "02.03.26", "NETTBUTIKKEN AS Oslo", nil, nil, "-412,00"],
  ["01.03.26", "02.03.26", "SVOMMEHALLEN Oslo", nil, nil, "-60,00"],
  ["01.03.26", "02.03.26", "SVOMMEHALLEN Oslo", nil, nil, "-60,00"],
  ["02.03.26", "02.03.26", "EasyPark AS easypark.no", nil, nil, "-38,00"],
  ["03.03.26", "04.03.26", "PAYPAL *STREAMING 35314369001", nil, nil, "-129,00"],
  ["03.03.26", "04.03.26", "RUTERAPPEN Oslo", nil, nil, "-44,00"],
  ["04.03.26", "05.03.26", "VINMONOPOLET OSLO", nil, nil, "-299,90"],
  ["05.03.26", "06.03.26", "BURGERBAREN Oslo", nil, nil, "-245,00"],
  ["05.03.26", "06.03.26", "BURGERBAREN Oslo", nil, nil, "-245,00"],
  ["06.03.26", "06.03.26", "APPLE.COM/BILL CORK", nil, nil, "-99,00"],
  ["08.03.26", "08.03.26", "Vipps*Elektronikk AS Oslo", nil, nil, "-2.199,00"],
  ["10.03.26", "10.03.26", "CIRCLE K Oslo", nil, nil, "-655,40"],
  ["11.03.26", "12.03.26", "CLAS OHL OSLO", nil, nil, "-317,80"],
  ["13.03.26", "14.03.26", "Mcompany ApS +4500000000", nil, nil, "-899,00"],
  ["14.03.26", "16.03.26", "FERJESELSKAPET OSLO", nil, nil, "-1.875,00"],
  ["15.03.26", "18.03.26", "FLY1000000000101 GARDERMOEN", nil, nil, "-1.499,00"],
  ["15.03.26", "18.03.26", "FLY1000000000102 GARDERMOEN", nil, nil, "-1.499,00"],
  ["17.03.26", "17.03.26", "90001234567", nil, nil, "5.000,00"],
  ["18.03.26", "19.03.26", "IKEA OSLO", nil, nil, "-2.345,00"],
  ["20.03.26", "20.03.26", "Kindle Svcs*AB1234567 SEATTLE", "USD", "-9,99", "-104,37"],
  ["21.03.26", "22.03.26", "APOTEK 1,SENTRUM OSLO", nil, nil, "-87,50"],
  ["22.03.26", "23.03.26", "GODISBUTIKKEN GOTEBORG", "SEK", "-450,00", "-462,15"],
  ["22.03.26", "25.03.26", "SPILLEHALLEN OSLO", nil, nil, "-20,00"],
  ["22.03.26", "25.03.26", "SPILLEHALLEN OSLO", nil, nil, "-20,00"],
  ["22.03.26", "25.03.26", "SPILLEHALLEN OSLO", nil, nil, "-20,00"],
  ["25.03.26", "26.03.26", "FLYSELSKAPET-000000000 Norway", nil, nil, "-8.450,00"],
  ["28.03.26", "29.03.26", "Kindle Svcs*CD7654321 SEATTLE", "USD", "-4,99", "-52,14"],
  ["31.03.26", "31.03.26", "EasyPark AS easypark.no", nil, nil, "-72,00"]
].freeze

SHORT = [
  ["29.08.26", "03.09.26", "FLYSELSKAPET Norway", nil, nil, "3.200,00"],
  ["03.09.26", "03.09.26", "90001234567", nil, nil, "-3.950,00"],
  ["19.09.26", "20.09.26", "NETTBUTIKKEN.FR PARIS", nil, nil, "-12,40"]
].freeze

STATEMENTS = [
  { file: "handelsbank-mc.pdf", from: "01.03.26", to: "31.03.26", due: "15.04.26",
    previous: BigDecimal("-2500.00"), minimum: "1.000,00", transactions: MONTH, per_page: [18, 12] },
  { file: "handelsbank-mc-short.pdf", from: "21.08.26", to: "20.09.26", due: "05.10.26",
    previous: BigDecimal("750.00"), minimum: "0,00", transactions: SHORT, per_page: [3] }
].freeze

def nok(str) = BigDecimal(str.delete(".").tr(",", "."))

def fmt(amount)
  sign = amount.negative? ? "-" : ""
  whole, frac = format("%.2f", amount.abs).split(".")
  "#{sign}#{whole.reverse.scan(/\d{1,3}/).join('.').reverse},#{frac}"
end

# Helvetica glyph widths (1/1000 em) for the characters used in amounts.
WIDTHS = Hash.new(556).merge("," => 278, "." => 278, "-" => 333, " " => 278).freeze
def text_width(str, size) = str.each_char.sum { |c| WIDTHS[c] } * size / 1000.0

class Page
  attr_reader :ops

  def initialize = @ops = []

  def text(x, y, str, size: 8, bold: false, align: :left)
    x -= text_width(str, size) if align == :right
    escaped = str.encode("Windows-1252").b.gsub(/[()\\]/) { |c| "\\#{c}" }
    @ops << "BT /#{bold ? 'F2' : 'F1'} #{size} Tf 1 0 0 1 #{x.round(2)} #{y.round(2)} Tm (#{escaped}) Tj ET"
  end
end

def header(page, st, number, total)
  page.text(496, 777, "Platinum Kredittkort", bold: true)
  [["Fakturanr.:", "10000000000001"], ["Fakturadato:", st[:to]], ["Forfallsdato:", st[:due]],
   ["Periode", "#{st[:from]} - #{st[:to]}"], ["Kontonr.:", ACCOUNT], ["Side", "#{number} av #{total}"]]
    .each_with_index do |(label, value), i|
      y = 768 - (i * 9)
      page.text(383, y, label)
      page.text(553, y, value, align: :right)
    end
end

def transaction_table(page, rows, y)
  page.text(43, y, "Bruks")
  page.text(85, y, "Bokført")
  page.text(133, y, "Brukersted")
  page.text(330, y, "Valuta")
  page.text(410, y, "Beløp", align: :right)
  page.text(450, y, "Gebyr", align: :right)
  page.text(553, y, "Beløp kr", align: :right)
  page.text(43, y - 7, "dato")
  page.text(85, y - 7, "dato")
  y -= 20
  rows.each do |used, booked, merchant, currency, foreign, amount|
    page.text(43, y, used)
    page.text(85, y, booked)
    page.text(133, y, merchant)
    page.text(330, y, currency) if currency
    page.text(410, y, foreign || amount, align: :right)
    page.text(553, y, amount, align: :right)
    y -= 11
  end
  y
end

STATEMENTS.each do |st|
  transactions = st[:transactions]
  spent = transactions.sum { |t| nok(t[5]) }
  balance = st[:previous] + spent
  pages = Array.new(st[:per_page].size + 1) { Page.new }

  # Page 1: invoice summary.
  p1 = pages[0]
  p1.text(496, 790, "Platinum Kredittkort", bold: true)
  p1.text(57, 775, "Retur: Handelsbanken, Postboks 1342 Vika, 0113 Oslo")
  [["Fakturanr.:", "10000000000001"], ["Fakturadato:", st[:to]], ["Forfallsdato:", st[:due]],
   ["Periode:", "#{st[:from]} - #{st[:to]}"], ["KID", "100000000001"], ["Bankkonto", ACCOUNT],
   ["Side", "1 av #{pages.size}"]]
    .each_with_index do |(label, value), i|
      y = 766 - (i * 9)
      p1.text(383, y, label)
      p1.text(553, y, value, align: :right)
    end
  p1.text(57, 730, "Kari Nordmann")
  p1.text(57, 721, "Storgata 1")
  p1.text(57, 712, "0155 OSLO")
  p1.text(392, 690, "Kredittramme         kr")
  p1.text(553, 690, "50.000,00", align: :right)
  p1.text(383, 681, "- Benyttet kreditt      kr")
  p1.text(553, 681, fmt(balance), align: :right)
  y = 640
  p1.text(52, y, "Overført saldo fra forrige periode")
  if st[:previous].positive?
    # A credit balance is shown as "(tilgode)" with the amount on the next line.
    p1.text(553, y, "(tilgode)", align: :right)
    y -= 9
    p1.text(553, y, fmt(st[:previous]), align: :right)
  else
    p1.text(553, y, fmt(st[:previous]), align: :right)
  end
  y -= 9
  [["Innbetalinger denne periode", BigDecimal("0")], ["Forbruk denne periode", spent]].each do |label, amount|
    p1.text(52, y, label)
    p1.text(553, y, fmt(amount), align: :right)
    y -= 9
  end
  p1.text(57, y, "=  Saldo i vår favør", bold: true)
  p1.text(553, y, fmt(balance), align: :right, bold: true)
  p1.text(52, y - 18, "Minimum å betale - forfall #{st[:due]}")
  p1.text(553, y - 18, st[:minimum], align: :right)

  # Page 2: interest example table (noise the parser must skip), then the
  # transactions, continued on later pages, then the period total.
  p2 = pages[1]
  header(p2, st, 2, pages.size)
  p2.text(44, 690, "Nominell rente er 15,9%", size: 6, bold: true)
  [["Betaler alt ved første faktura", "0", "0", "15.000", "15.000", "0"],
   ["Betaling over 3 måneder", "396", "0", "15.396", "5.132", "17.07%"]].each_with_index do |row, i|
    y = 675 - (i * 9)
    p2.text(44, y, row[0], size: 6)
    [225, 377, 430, 495, 566].each_with_index { |x, j| p2.text(x, y, row[j + 1], size: 6, align: :right) }
  end
  p2.text(44, 640, "Kari Nordmann, Transaksjoner denne periode", bold: true)

  remaining = transactions.dup
  y = nil
  st[:per_page].each_with_index do |count, i|
    page = pages[i + 1]
    header(page, st, i + 2, pages.size) unless i.zero?
    y = transaction_table(page, remaining.shift(count), i.zero? ? 625 : 700)
  end
  last = pages.last
  last.text(43, y - 5, "Sum denne periode for Kari Nordmann", bold: true)
  last.text(553, y - 5, fmt(spent), align: :right, bold: true)

  # Assemble the PDF.
  objects = []
  objects << "<< /Type /Catalog /Pages 2 0 R >>"
  page_ids = pages.each_index.map { |i| 6 + (i * 2) }
  objects << "<< /Type /Pages /Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{pages.size} >>"
  objects << "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
  objects << "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"
  objects << "<< /Producer (ynab-ofx fixture builder) >>"
  pages.each_with_index do |page, i|
    stream = page.ops.join("\n")
    objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] " \
               "/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents #{page_ids[i] + 1} 0 R >>"
    objects << "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
  end

  pdf = +"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
  offsets = objects.each_with_index.map do |obj, i|
    offset = pdf.bytesize
    pdf << "#{i + 1} 0 obj\n#{obj}\nendobj\n".b
    offset
  end
  xref = pdf.bytesize
  pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
  offsets.each { |o| pdf << format("%010d 00000 n \n", o) }
  pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R /Info 5 0 R >>\nstartxref\n#{xref}\n%%EOF\n"

  out = File.join(__dir__, st[:file])
  File.binwrite(out, pdf)
  puts "wrote #{st[:file]}: #{transactions.size} transactions, spent #{fmt(spent)}, balance #{fmt(balance)}"
end
