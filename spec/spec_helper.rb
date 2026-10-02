$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ynab_ofx"
require "tmpdir"

FIXTURES_DIR = File.expand_path("fixtures", __dir__)

module FixtureHelpers
  def fixture_path(name)
    File.join(FIXTURES_DIR, name)
  end

  # Writes `content` to a temp file and returns its path. Pass `encoding:` to
  # store it in something other than UTF-8 (e.g. Handelsbanken's ISO-8859-1).
  def write_temp_file(name, content, encoding: nil)
    path = File.join(@tmp_dir, name)
    data = encoding ? content.encode(encoding) : content
    File.binwrite(path, data)
    path
  end
end

RSpec.configure do |config|
  config.include FixtureHelpers

  config.around do |example|
    Dir.mktmpdir("ynab-ofx-spec") do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.disable_monkey_patching!
  config.order = :random
end
