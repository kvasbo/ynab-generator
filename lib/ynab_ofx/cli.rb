require "fileutils"
require "pathname"

module YnabOfx
  class CLI
    SUPPORTED_EXT = %w[.pdf .xlsx .csv].freeze
    DEFAULT_INPUT = "data".freeze
    DEFAULT_OUTPUT = "output".freeze

    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      if argv.size > 2
        warn "usage: convert [input_dir] [output_dir] (defaults: #{DEFAULT_INPUT} #{DEFAULT_OUTPUT})"
        return 64
      end

      input_dir = argv[0] || DEFAULT_INPUT
      output_dir = argv[1] || DEFAULT_OUTPUT
      unless File.directory?(input_dir)
        warn "input dir not found: #{input_dir}"
        return 66
      end
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)

      input_root = Pathname.new(input_dir)
      files = Dir.glob(File.join(input_dir, "**", "*")).sort.select do |p|
        File.file?(p) && SUPPORTED_EXT.include?(File.extname(p).downcase)
      end

      ok = 0
      failed = 0
      files.each do |path|
        begin
          parser = Detector.for(path)
        rescue UnknownFileTypeError => e
          puts "SKIP #{File.basename(path)}: #{e.message}"
          next
        end

        begin
          result = parser.parse(path)
          statements = (result.is_a?(Array) ? result : [result]).select { |s| s.transactions.any? }
          if statements.empty?
            puts "SKIP #{File.basename(path)}: no transactions"
            next
          end
          base = File.basename(path, ".*")
          multi = statements.size > 1
          target_dir = mirrored_dir(output_dir, input_root, path)
          FileUtils.mkdir_p(target_dir)

          statements.each do |statement|
            suffix = multi ? "_#{slugify(statement.account_name || statement.account_id)}" : ""
            out_path = File.join(target_dir, "#{base}#{suffix}.ofx")
            File.write(out_path, OfxWriter.render(statement))
            puts "OK   #{File.basename(path)} -> #{out_path} (#{statement.transactions.size} txns)"
          end
          ok += 1
        rescue EmptyStatementError
          puts "SKIP #{File.basename(path)}: no transactions"
          next
        rescue => e
          warn "FAIL #{File.basename(path)}: #{e.class}: #{e.message}"
          warn e.backtrace.first(3).join("\n")
          failed += 1
        end
      end

      ok > 0 ? 0 : 1
    end

    private

    def mirrored_dir(output_dir, input_root, path)
      rel = Pathname.new(path).relative_path_from(input_root).dirname
      rel.to_s == "." ? output_dir : File.join(output_dir, rel.to_s)
    end

    def slugify(str)
      str.to_s
        .tr("ÆØÅæøå", "AOAaoa")
        .gsub(/[^A-Za-z0-9]+/, "_")
        .gsub(/\A_+|_+\z/, "")
    end
  end
end
