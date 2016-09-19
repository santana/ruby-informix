#--
# Copyright (c) 2008-2016, Gerardo Santana Gomez Garrido <gerardo.santana@gmail.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#++

require 'informixc'
require 'informix/seqcursor'
require 'informix/scrollcursor'

module Informix
  VERSION = "0.8.1"
  VERSION.freeze

  # Shortcut to create a +Database+ object connected to +dbname+ as
  # +user+ with +password+. If these are not given, connects to
  # +dbname+ as the current user.
  #
  # The +Database+ object is passed to the block if it's given, and
  # automatically closes the connection when the block terminates,
  # returning the value of the block.
  #
  # Examples:
  #
  # Connecting to stores with our current credentials:
  #   db = Informix.connect('stores')
  #
  # Same thing, using a block and using a different server. The connection is
  # closed automatically when the block terminates.
  #   result = Informix.connect('stores@server_shm') do |db|
  #     # do something with db
  #     # the last expression evaluated will be returned
  #   done
  def self.connect(dbname, user = nil, password = nil, &block)
    Database.open(dbname, user, password, &block)
  end

  # Returns the version of this Ruby/Informix driver.
  # Note that this is NOT the Informix database version.
  #
  #   Informix.version => string
  def self.version
    VERSION
  end

  class Database
    private_class_method :new

    alias disconnect close

    # Exact version of the database server to which a Database object is
    # connected
    attr_reader :version 

    # The +IfxVersion+ struct provides the exact version of the database server
    # to which a Database object is connected.
    #
    # Examples:
    #
    #   db.version.server_type #=> "IBM Informix Dynamic Server"
    #   db.version.level       #=> "C6"
    #   db.version.to_s        #=> "IBM Informix Dynamic Server Version 9.40.FC6"
    class IfxVersion
      # Returns the complete version string
      def to_s
        full.rstrip
      end
    end

    # Creates a +Database+ object connected to +dbname+ as
    # +user+ with +password+. If these are not given, connects to
    # +dbname+ as the current user.
    #
    # The +Database+ object is passed to the block if it's given, and
    # automatically closes the connection when the block terminates, returning
    # the value of the block.
    def self.open(dbname, user = nil, password = nil)
      db = new(dbname, user, password)
      return db unless block_given?
      begin
        yield db
      ensure
        db.close
      end
    end

    # Shortcut to create a +Statement+ object from +query+.
    #
    # The +Statement+ object is passed to the block if it's given, and
    # automatically released when the block terminates, returning
    # the value of the block.
    #
    # +query+ may contain '?' placeholders for input parameters;
    # it must <b>NOT</b> be a query returning more than one row
    # (use <tt>Database#cursor</tt> instead.)
    #
    # Examples:
    #
    # Preparing a statement:
    #   st = db.prepare('delete from orders where order_date = ?')
    #
    # Using a block:
    #   query 'update items set quantity = ? where item_num = ?'
    #   db.prepare(query) do |st|
    #     # do something with st
    #     # the last expression evaluated will be returned
    #   end
    def prepare(query, &block)
      Statement.new(self, query, &block)
    end

    # Shortcut to create, <b>execute and release</b> a +Statement+ object from
    # +query+.
    #
    # +query+ may contain '?' placeholders for input parameters;
    # it <b>cannot</b> be a query returning <b>more than one</b> row
    # (use <tt>Database#cursor</tt> instead.)
    #
    # Returns the record retrieved, in the case of a singleton select, or the
    # number of rows affected, in the case of any other statement.
    #
    # Examples:
    #
    # Deleting records:
    #   db.execute('delete from orders where order_date = ?', Date.today)
    #
    # Updating a record:
    #   db.execute('update items set quantity = ? where item_num = ?', 10, 101)
    def execute(query, *args)
      Statement.new(self, query) {|stmt| stmt.execute(*args) }
    end

    # Shortcut to create a cursor object based on +query+ using +options+.
    #
    # The cursor object is passed to the block if it's given, and
    # automatically released when the block terminates, returning
    # the value of the block.
    #
    # +query+ may contain '?' placeholders for input parameters.
    #
    # +options+ can be a Hash object with the following possible keys:
    #
    #   :scroll => true or false
    #   :hold   => true or false
    #
    # Examples:
    #
    # This creates a +SequentialCursor+
    #   cur = db.cursor('select * from orders where order_date > ?')
    # This creates a +ScrollCursor+
    #   cur = db.cursor('select * from customer', :scroll => true)
    # This creates an +InsertCursor+
    #   cur = db.cursor('insert into stock values(?, ?, ?, ?, ?, ?)')
    def cursor(query, options = nil, &block)
      Cursor.new(self, query, options, &block)
    end

    # Shortcut to create, <b>open and iterate</b> a cursor object based on
    # +query+ using +options+. The records are retrieved as arrays.
    #
    # The cursor object is passed to the block and
    # automatically released when the block terminates. Returns __self__.
    #
    # +query+ may contain '?' placeholders for input parameters.
    #
    # +options+ can be a Hash object with the following possible keys:
    #
    #   :scroll => true or false
    #   :hold   => true or false
    #   :params => input parameters as an Array or nil
    #
    # Examples:
    #
    # Iterating over a table:
    #   db.foreach('select * from customer') do |cust|
    #     # do something with cust
    #     puts "#{cust[0] cust[1]}"
    #   end
    # Same thing, using input parameters:
    #   query = 'select * from orders where order_date = ?'
    #   db.foreach(query, :params => [Date.today]) do |order|
    #     # do something with order
    #   end
    def foreach(query, options = nil, &block)
      Cursor.open(self, query, options) {|cur| cur.each(&block)}
      self
    end

    # Similar to +Database#foreach+, except that retrieves records as hashes
    # instead of arrays.
    #
    # Examples:
    #
    # Iterating over a table:
    #   db.foreach_hash('select * from customer') do |cust|
    #     # do something with cust
    #     puts "#{cust['fname'] cust['lname']}"
    #   end
    def foreach_hash(query, options = nil, &block)
      Cursor.open(self, query, options) {|cur| cur.each_hash(&block)}
      self
    end

    # Shortcut to create a +Slob+ object.
    #
    # The +Slob+ object is passed to the block if it's given, and
    # automatically closes it when the block terminates, returning
    # the value of the block.
    #
    # +type+ can be Slob::BLOB or Slob::CLOB
    #
    # +options+ can be a Hash object with the following possible
    # keys:
    #
    #   :sbspace     => Sbspace name
    #   :estbytes    => Estimated size, in bytes
    #   :extsz       => Allocation extent size
    #   :createflags => Create-time flags
    #   :openflags   => Access mode
    #   :maxbytes    => Maximum size
    #   :col_info    => Get the previous values from the column-level storage
    #                   characteristics for the specified database column
    #
    # Examples:
    #
    # Creating a CLOB:
    #   slob = db.slob
    # Creating a BLOB without log and passing it to a block:
    #   slob = db.slob(Slob::BLOB, :createflags=>Slob:NOLOG) do |slob|
    #     # do something with slob
    #   end
    def slob(type = Slob::CLOB, options = nil, &block)
      Slob.new(self, type, options, &block)
    end
  end # class Database

  class Statement
    alias call []
    alias execute []

    class << self
      alias _new new
    end

    # Creates a +Statement+ object from +query+.
    #
    # The +Statement+ object is passed to the block if it's given, and
    # automatically released when the block terminates, returning
    # the value of the block.
    #
    # +query+ may contain '?' placeholders for input parameters;
    # it must <b>NOT</b> be a query returning more than one row
    # (use +Cursor+ instead.)
    def self.new(dbname, query)
      stmt = _new(dbname, query)
      return stmt if !block_given?
      begin
        yield stmt
      ensure
        stmt.free
      end
    end
  end # class Statement

  class Slob
    alias pos tell

    class << self
      alias _new new
    end

    # Creates a +Slob+ object.
    #
    # The +Slob+ object is passed to the block if it's given, and
    # automatically closes it when the block terminates, returning
    # the value of the block.
    #
    # +type+ can be Slob::BLOB or Slob::CLOB
    #
    # +options+ can be a Hash object with the following possible
    # keys:
    #
    #   :sbspace     => Sbspace name
    #   :estbytes    => Estimated size, in bytes
    #   :extsz       => Allocation extent size
    #   :createflags => Create-time flags
    #   :openflags   => Access mode
    #   :maxbytes    => Maximum size
    #   :col_info    => Get the previous values from the column-level storage
    #                   characteristics for the specified database column
    def self.new(dbname, query, options = nil)
      slob = _new(dbname, query, options)
      return slob if !block_given?
      begin
        yield slob
      ensure
        slob.close
      end
    end
  end # class Slob

  module Cursor
    private_class_method :new0

    # Shortcut to create a cursor object based on +query+ using +options+.
    #
    # The cursor object is passed to the block if it's given, and
    # automatically released when the block terminates, returning
    # the value of the block.
    #
    # +options+ can be a Hash object with the following possible keys:
    #
    #   :scroll => true or false
    #   :hold   => true or false
    def self.new(db, query, options = nil)
      if options
        Hash === options||raise(TypeError,"options must be supplied as a Hash")
      end
      cur = new0(db, query, options)
      return cur unless block_given?
      begin
        yield cur
      ensure
        cur.free
      end
    end

    # Shortcut to create <b>and open</b> a cursor object based on +query+
    # using +options+ in a single step.
    #
    # The cursor object is passed to the block if it's given, and
    # automatically released when the block terminates, returning
    # the value of the block.
    #
    # +options+ can be a Hash object with the following possible keys:
    #
    #   :scroll => true or false
    #   :hold   => true or false
    #   :params => input parameters as an Array or nil
    def self.open(db, query, options = nil)
      params = nil
      if options
        Hash === options||raise(TypeError,"options must be supplied as a Hash")
        (params = options[:params]) && (Array === params ||
                   raise(TypeError,"params must be supplied as an Array"))
      end
      cur = new(db, query, options)
      params ? cur.open(*params) : cur.open
      return cur unless block_given?
      begin
        yield cur
      ensure
        cur.free
      end
    end
  end # module Cursor
end # module Informix
