testdir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift testdir

require 'testcase'

class IfxTestXFetchNEach < Informix::TestCase
  def setup
    connect_string, username, password = ARGV[0..2]
    super connect_string, username, password
    drop_test_table
    create_test_table
    populate_test_table

    assert_nothing_raised(Informix::Error, "Selecting records") do
      @c = @db.cursor("select * from #{TEST_TABLE_NAME}").open
    end
  end

  def teardown
    @c.free
  end

  def test_fetch_each_each_by
    fetch = []
    while r = @c.fetch; fetch << r; end
    @c.close

    each = []
    @c.open.each {|r| each << r }.close

    each_by = []
    @c.open.each_by(2) {|a, b|
      each_by << a if a
      each_by << b if b
    }
    assert_equal(fetch.flatten, each.flatten, "fetch & each")
    assert_equal(fetch.flatten, each_by.flatten, "fetch & each_by")
  end

  def test_fetch_each_each_by_hash
    fetch_hash = []
    @c.open
    while r = @c.fetch_hash; fetch_hash << r; end
    @c.close

    each_hash = []
    @c.open.each_hash {|r| each_hash << r }.close

    each_hash_by = []
    @c.open.each_hash_by(2) {|a, b|
      each_hash_by << a if a
      each_hash_by << b if b
    }
    assert_equal(fetch_hash.flatten, each_hash.flatten,
      "fetch_hash & each_hash")
    assert_equal(fetch_hash.flatten, each_hash_by.flatten,
      "fetch_hash & each_hash_by")
  end
end
