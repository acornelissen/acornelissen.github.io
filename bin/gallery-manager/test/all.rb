Dir.glob(File.expand_path("*_test.rb", __dir__)).sort.each { |file| require file }
