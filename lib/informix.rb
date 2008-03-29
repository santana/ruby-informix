# $Id: informix.rb,v 1.5 2008/03/29 06:10:25 santana Exp $
#
# Copyright (c) 2008, Gerardo Santana Gomez Garrido <gerardo.santana@gmail.com>
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

require 'informixc'
require 'informix/seqcursor'
require 'informix/scrollcursor'

module Informix
  VERSION = "0.7.0"
  VERSION.freeze

  # Creates a <code>Database</code> object connected to <i>dbname</i> as
  # <i>user</i> with <i>password</i>. If these are not given, connects to
  # <i>dbname</i> as the current user.
  #
  # The Database object is passed to the block if it's given, and automatically
  # closes the connection when the block terminates, returning the value of
  # the block.
  #
  #   Informix.connect(dbname,user = nil, password = nil)              => db
  #   Informix.connect(dbname,user = nil,password = nil) {|db| block}  => obj
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

  # The +Database+ class
  class Database
    private_class_method :new

    alias disconnect close
    alias do immediate
    alias execute immediate

    # Creates a <code>Database</code> object connected to <i>dbname</i> as
    # <i>user</i> with <i>password</i>. If these are not given, connects to
    # <i>dbname</i> as the current user.
    #
    # The Database object is passed to the block if it's given, and
    # automatically closes the connection when the block terminates, returning
    # the value of the block.
    #
    #   Database.open(dbname, user = nil, password = nil)               => db
    #   Database.open(dbname, user = nil, password = nil) {|db| block}  => obj
    def self.open(dbname, user=nil, password=nil)
      db = new(dbname, user, password)
      return db unless block_given?
      begin
        yield db
      ensure
        db.close
      end
    end

    # Creates a <code>Statement</code> object based on <i>query</i>.
    #
    # In the first form the Statement object is returned.
    # In the second form the Statement object is passed to the block and when it
    # terminates, the Statement object is dropped, returning the value of the
    # block.
    #
    # <i>query</i> may contain '?' placeholders for input parameters;
    # it must NOT be a query returning more than one row
    # (use <code>Database#cursor</code> instead.)
    #
    #   db.prepare(query)                  => statement
    #   db.prepare(query) {|stmt| block }  => obj
    def prepare(query, &block)
      Statement.new(self, query, &block)
    end

    # Returns a <code>Cursor</code> object based on <i>query</i>.
    # <i>query</i> may contain '?' placeholders for input parameters.
    #
    # <i>options</i> must be a hash with the following possible keys:
    #
    #   :scroll => true or false
    #   :hold   => true or false
    #
    #   db.cursor(query, options = nil) => cursor
    def cursor(query, options = nil, &block)
      Cursor.new(self, query, options, &block)
    end

    def each(query, options = nil, &block)
      Cursor.open(self, query, options) {|cur| cur.each(&block)}
    end
 
    def each_hash(query, options = nil, &block)
      Cursor.open(self, query, options) {|cur| cur.each_hash(&block)}
    end

    # Creates a Smart Large Object of type <i>type</i>.
    # Returns a <code>Slob</code> object pointing to it.
    #
    # <i>type</i> can be Slob::BLOB or Slob::CLOB
    #
    # <i>options</i> can be nil or a Hash object with the following possible
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
    #   db.slob(type = Slob::CLOB, options = nil)                  => slob
    #   db.slob(type = Slob::CLOB, options = nil) {|slob| block }  => obj
    def slob(type = Slob::CLOB, options = nil, &block)
      Slob.new(self, type, options, &block)
    end
  end # class Database

  # The +Statement+ class
  class Statement
    alias call []
    alias execute []

    class << self
      alias _new new
    end

    # Creates a <code>Statement</code> object based on <i>query</i> in the
    # context of the <i>db</i> <code>Database</code> object.
    #
    # In the first form the <code>Statement</code> object is returned.
    # In the second form the Statement object is passed to the block and when it
    # terminates, the Statement object is dropped, returning the value of the
    # block.
    #
    # <i>query</i> may contain '?' placeholders for input parameters;
    # it must not be a query returning more than one row
    # (use <code>Cursor</code> instead.)
    #
    #   Statement.new(db, query)                 => statement
    #   Statement.new(db, query) {|stmt| block } => obj
    def self.new(dbname, query)
      stmt = _new(dbname, query)
      return stmt if !block_given?
      begin
        yield stmt
      ensure
        stmt.drop
      end
    end
  end # class Statement

  # The +Slob+ class
  class Slob
    alias pos tell

    class << self
      alias _new new
    end

    # Creates a Smart Large Object of type <i>type</i> in the <i>db</i>
    # <code>Database</code> object.
    #
    # Returns an <code>Slob</code> object pointing to it.
    #
    # <i>type</i> can be Slob::BLOB or Slob::CLOB
    #
    # <i>options</i> can be nil or a Hash object with the following possible
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
    #   Slob.new(db, type = Slob::CLOB, options = nil)                  => slob
    #   Slob.new(db, type = Slob::CLOB, options = nil) {|slob| block }  => obj
    def self.new(dbname, query)
      slob = _new(dbname, query)
      return slob if !block_given?
      begin
        yield slob
      ensure
        slob.close
      end
    end
  end # class Slob

  module Cursor
    # Creates a Cursor object based on <i>query</i> using <i>options</i>
    # in the context of <i>database</i> but does not open it.
    #
    # In the first form the Cursor object is returned.
    # In the second form the Cursor object is passed to the block and when it
    # terminates, the Cursor object is dropped, returning the value of the
    # block.
    #
    # <i>options</i> can be nil or a Hash object with the following possible
    # keys:
    #
    #   :scroll => true or false
    #   :hold   => true or false
    #
    #   Cursor.new(database, query, options)                    => cursor
    #   Cursor.new(database, query, options) {|cursor| block }  => obj
    def self.new(db, query, options = nil, &block)
      if options
        Hash === options||raise(TypeError,"options must be supplied as a Hash")
      end
      cur = new0(db, query, options, &block)
      return cur unless block_given?
      begin yield cur ensure cur.drop end
    end

    # Creates and opens a Cursor object based on <i>query</i> using
    # <i>options</i> in the context of the Database object <i>db</i>.
    #
    # In the first form the Cursor object is returned.
    # In the second form the Cursor object is passed to the block and when it
    # terminates, the Cursor object is dropped, returning the value of the
    # block.
    #
    # <i>options</i> can be nil or a Hash object with the following possible
    # keys:
    #
    #   :scroll => true or false
    #   :hold   => true or false
    #   :params => input parameters as an Array or nil
    #
    #   Cursor.open(db, query, options)                    => cursor
    #   Cursor.open(db, query, options) {|cursor| block }  => obj
    def self.open(db, query, options = nil, &block)
      params = nil
      if options
        Hash === options||raise(TypeError,"options must be supplied as a Hash")
        (params = options[:params]) && (Array === params ||
                   raise(TypeError,"params must be supplied as an Array"))
      end
      cur = new(db, query, options)
      params ? cur.open(*params) : cur.open
      return cur unless block_given?
      begin yield cur ensure cur.drop end
    end
  end # module Cursor
end # module Informix
