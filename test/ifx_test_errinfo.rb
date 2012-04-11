testdir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift testdir

require 'testcase'

# Informix::ExcInfo is just a struct, not much testing needed
class IfxTestExcInfo < Informix::TestCase
  # Don't need an Informix database for these tests
  def setup; end
  
  def test_initialize
    sql_code, sql_state, class_origin, subclass_origin, message, server_name, connection_name = 
      -987, "IX111", "IX", "000", "Some message", "server", "conn"

    info = Informix::ExcInfo.new(sql_code,
                                 sql_state,
                                 class_origin,
                                 subclass_origin,
                                 message,
                                 server_name,
                                 connection_name)

    assert_equal sql_code, info.sql_code
    assert_equal sql_state, info.sql_state
    assert_equal class_origin, info.class_origin
    assert_equal subclass_origin, info.subclass_origin
    assert_equal message, info.message
    assert_equal server_name, info.server_name
    assert_equal connection_name, info.connection_name
  end

end


