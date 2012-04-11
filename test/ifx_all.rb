testdir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift testdir
$LOAD_PATH.unshift File.expand_path(File.join(testdir, "..", "lib"))
$LOAD_PATH.unshift File.expand_path(File.join(testdir, "..", "ext"))

require 'informix'
gem 'test-unit'
require 'test/unit'

class IfxAll
  def IfxAll.suite
    suite = Test::Unit::TestSuite.new "Ruby Informix Test Suite"
    Object.constants.grep(/^IfxTest/).sort.each do |const_name|
      if (c = Object.const_get(const_name)).kind_of?(Class) && c.respond_to?(:suite)
        puts "Adding #{const_name}"
        suite << c.suite
      end
    end
    suite
  end
end

if __FILE__ == $0
  if ARGV.size == 0
    STDERR.puts "Usage:
ruby #{$0} database [username password]"
    exit 1
  end
  Dir.glob(File.join(testdir, "ifx_test*.rb")).each do |testcase|
    require "#{testcase}"
  end
end
