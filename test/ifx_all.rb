require 'informix'
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
  require 'test/unit/ui/console/testrunner'
  Dir.glob("ifx_test*.rb").each do |testcase|
    require "#{testcase}"
  end
  Test::Unit::UI::Console::TestRunner.run(IfxAll)
end
