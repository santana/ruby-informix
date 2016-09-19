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

module Informix
  class SequentialCursor < CursorBase
    include Enumerable

    # Fetches the next record.
    #
    # Returns the record fetched as an array, or nil if there are no
    # records left.
    #
    #   cursor.fetch  => array or nil
    def fetch
      fetch0(Array, false)
    end

    # Fetches the next record, storing it in the same Array object every time
    # it is called.
    #
    # Returns the record fetched as an array, or nil if there are no
    # records left.
    #
    #   cursor.fetch!  => array or nil
    def fetch!
      fetch0(Array, true)
    end

    # Fetches the next record.
    #
    # Returns the record fetched as a hash, or nil if there are no
    # records left.
    #
    #   cursor.fetch_hash  => hash or nil
    def fetch_hash
      fetch0(Hash, false)
    end

    # Fetches the next record, storing it in the same Hash object every time
    # it is called.
    #
    # Returns the record fetched as a hash, or nil if there are no
    # records left.
    #
    #   cursor.fetch_hash!  => hash or nil
    def fetch_hash!
      fetch0(Hash, true)
    end

    # Reads at most <i>n</i> records.
    #
    # Returns the records read as an array of arrays
    #
    #   cursor.fetch_many(n)  => array
    def fetch_many(n)
      fetch_many0(n, Array)
    end

    # Reads at most <i>n</i> records.
    # Returns the records read as an array of hashes.
    #
    #   cursor.fetch_hash_many(n)  => array
    def fetch_hash_many(n)
      fetch_many0(n, Hash)
    end

    # Returns all the records left as an array of arrays
    #
    #   cursor.fetch_all  => array
    def fetch_all
      fetch_many0(nil, Array)
    end

    # Returns all the records left as an array of hashes
    #
    #   cursor.fetch_hash_all  => array
    def fetch_hash_all
      fetch_many0(nil, Hash)
    end

    # Iterates over the remaining records, passing each <i>record</i> to the
    # <i>block</i> as an array.
    #
    # Returns __self__.
    #
    #   cursor.each {|record| block } => cursor
    def each(&block)
      each0(Array, false, &block)
    end

    # Iterates over the remaining records, passing each <i>record</i> to the
    # <i>block</i> as an array. No new Array objects are created for each
    # record. The same Array object is reused in each call.
    #
    # Returns __self__.
    #
    #   cursor.each! {|record| block } => cursor
    def each!(&block)
      each0(Array, true, &block)
    end

    # Iterates over the remaining records, passing each <i>record</i> to the
    # <i>block</i> as a hash.
    #
    #   cursor.each_hash {|record| block } => cursor
    def each_hash(&block)
      each0(Hash, false, &block)
    end

    # Iterates over the remaining records, passing each <i>record</i> to the
    # <i>block</i> as a hash. No new Hash objects are created for each record.
    # The same Hash object is reused in each call.
    #
    # Returns __self__.
    #
    #   cursor.each_hash! {|record| block } => cursor
    def each_hash!(&block)
      each0(Hash, true, &block)
    end

    # Iterates over the remaining records, passing at most <i>n</i>
    # <i>records</i> to the <i>block</i> as arrays.
    #
    # Returns __self__.
    #
    #   cursor.each_by(n) {|records| block } => cursor
    def each_by(n, &block)
      each_by0(n, Array, &block)
    end

    # Iterates over the remaining records, passing at most <i>n</i>
    # <i>records</i> to the <i>block</i> as hashes.
    #
    # Returns __self__.
    #
    #   cursor.each_hash_by(n) {|records| block } => cursor
    def each_hash_by(n, &block)
      each_by0(n, Hash, &block)
    end
  end # class SequentialCursor
end # module Informix
