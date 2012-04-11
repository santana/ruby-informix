testdir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift testdir

require 'testcase'

class IfxTestCreate < Informix::TestCase
  def setup
    connect_string, username, password = ARGV[0..2]
    super connect_string, username, password
  end
  
  def test_create_table
    drop_test_table

    assert_nothing_raised(Informix::Error, "Creating table #{TEST_TABLE_NAME}") do
      begin
        create_test_table
      ensure
        drop_test_table
      end
    end
  end
end
