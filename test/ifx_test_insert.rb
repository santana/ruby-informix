testdir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift testdir

require 'testcase'

class IfxTestInsert < Informix::TestCase
  def setup
    connect_string, username, password = ARGV[0..2]
    super connect_string, username, password
    drop_test_table
    create_test_table
  end

  def test_insert
    begin
      populate_test_table
    ensure
      drop_test_table
    end
  end
end

