module YnabOfx
  module Detector
    PARSERS = [
      Parsers::HandelsbankMc,
      Parsers::HandelsbankCsv,
      Parsers::BulderCsv,
      Parsers::Sparebank1Csv,
      Parsers::SasMc
    ].freeze

    module_function

    def for(path)
      ext = File.extname(path).downcase
      candidates = PARSERS.select { |p| p.extensions.include?(ext) }
      if candidates.empty?
        raise UnknownFileTypeError, "no parser for #{File.basename(path)} (extension #{ext})"
      end

      fp = fingerprint(path, ext)
      parser = candidates.find { |p| p.signature.match?(fp) }
      unless parser
        raise UnknownFileTypeError, "no parser matched contents of #{File.basename(path)}"
      end
      parser.new
    end

    def fingerprint(path, ext)
      case ext
      when ".pdf"  then pdf_fingerprint(path)
      when ".xlsx" then xlsx_fingerprint(path)
      when ".csv"  then csv_fingerprint(path)
      else ""
      end
    end

    def csv_fingerprint(path)
      File.open(path, "rb") { |f| f.read(2048) }.to_s
    rescue StandardError
      ""
    end

    def pdf_fingerprint(path)
      PDF::Reader.new(path).pages.first(2).map(&:text).join("\n")
    rescue StandardError
      ""
    end

    def xlsx_fingerprint(path)
      sheet = RubyXL::Parser.parse(path)[0]
      rows = []
      sheet.each_with_index do |row, i|
        break if i >= 6
        next unless row
        rows << row.cells.map { |c| c&.value.to_s }.join(" ")
      end
      ([sheet.sheet_name] + rows).join("\n")
    rescue StandardError
      ""
    end
  end
end
