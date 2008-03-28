# $Id: scrollcursor.rb,v 1.1 2008/03/28 13:03:39 santana Exp $
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

module Informix
  class ScrollCursor < SequentialCursor
    # Provides the Array-like functionality for scroll cursors when using the
    # cursor[start, length] syntax
    def subseq(start, length, type)
      first = entry(start, type, false)
      return if first.nil?

      records = length > 1 ? fetch_many0(length - 1, type) : []
      records.unshift(first)
    end

    # Base function for slice and slice_hash methods
    def slice0(args, type)
      return entry(args[0], type, false) if args.size == 1
      if args.size == 2
        return subseq(args[0], args[1], type) unless args[1] < 0
        raise(ArgumentError, "length must be positive")
      end
      raise(ArgumentError, "wrong number of arguments (%d for 2)", args.size)
    end

    # cursor[index]  => array or nil
    # cursor[start, length]  => array or nil
    # cursor.slice(index)  => array or nil
    # cursor.slice(start, length)  => array or nil
    #
    # Returns the record at _index_, or returns a subarray starting at _start_
    # and continuing for _length_ records. Negative indices count backward from
    # the end of the cursor (-1 is the last element). Returns nil if the
    # (starting) index is out of range.
    #
    # <b>Warning</b>: if the (starting) index is negative and out of range, the
    # position in the cursor is set to the last record. Otherwise the current
    # position in the cursor is preserved.
    def slice(*args)
      slice0(args, Array)
    end

    alias [] slice

    # cursor.slice!(index)  => array or nil
    #
    # Returns the record at _index_. Negative indices count backward from
    # the end of the cursor (-1 is the last element). Returns nil if the index
    # is out of range.
    #
    # Stores the record fetched always in the same Array object.
    #
    # <b>Warning</b>: if the index is negative and out of range, the
    # position in the cursor is set to the last record. Otherwise the current
    # position in the cursor is preserved.
    def slice!(index)
      entry(index, Array, true)
    end

    # cursor.slice_hash(index)  => hash or nil
    # cursor.slice_hash(start, length)  => array or nil
    #
    # Returns the record at _index_, or returns a subarray starting at _start_
    # and continuing for _length_ records. Negative indices count backward from
    # the end of the cursor (-1 is the last element). Returns nil if the
    # (starting) index is out of range.
    #
    # <b>Warning</b>: if the (starting) index is negative and out of range, the
    # position in the cursor is set to the last record. Otherwise the current
    # position in the cursor is preserved.
    def slice_hash(*args)
      slice0(args, Hash)
    end

    # cursor.slice_hash!(index)  => hash or nil
    #
    # Returns the record at _index_. Negative indices count backward from
    # the end of the cursor (-1 is the last element). Returns nil if the index
    # is out of range.
    #
    # Stores the record fetched always in the same Hash object.
    #
    # <b>Warning</b>: if the index is negative and out of range, the
    # position in the cursor is set to the last record. Otherwise the current
    # position in the cursor is preserved.
    def slice_hash!(index)
      entry(index, Hash, true)
    end

    # cursor.prev(offset = 1)  => array or nil
    #
    # Returns the previous _offset_ th record. Negative indices count
    # forward from the current position. Returns nil if the _offset_ is out of
    # range.
    def prev(offset = 1)
      rel(-offset, Array, false)
    end

    # cursor.prev!(offset = 1)  => array or nil
    #
    # Returns the previous _offset_ th record. Negative indices count
    # forward from the current position. Returns nil if the _offset_ is out of
    # range.
    #
    # Stores the record fetched always in the same Array object.
    def prev!(offset = 1)
      rel(-offset, Array, true)
    end

    # cursor.prev_hash(offset = 1)  => hash or nil
    #
    # Returns the previous _offset_ th record. Negative indices count
    # forward from the current position. Returns nil if the _offset_ is out of
    # range.
    def prev_hash(offset = 1)
      rel(-offset, Hash, false)
    end

    # cursor.prev_hash!(offset = 1)  => hash or nil
    #
    # Returns the previous _offset_ th record. Negative indices count
    # forward from the current position. Returns nil if the _offset_ is out of
    # range.
    #
    # Stores the record fetched always in the same Hash object.
    def prev_hash!(offset = 1)
      rel(-offset, Hash, true)
    end

    # cursor.next(offset = 1)  => array or nil
    #
    # Returns the next _offset_ th record. Negative indices count
    # backward from the current position. Returns nil if the _offset_ is out of
    # range.
    def next(offset = 1)
      rel(offset, Array, false)
    end

    # cursor.next!(offset = 1)  => array or nil
    #
    # Returns the next _offset_ th record. Negative indices count
    # backward from the current position. Returns nil if the _offset_ is out of
    # range.
    #
    # Stores the record fetched always in the same Array object.
    def next!(offset = 1)
      rel(offset, Array, true)
    end

    # cursor.next_hash(offset = 1)  => hash or nil
    #
    # Returns the next _offset_ th record. Negative indices count
    # backward from the current position. Returns nil if the _offset_ is out of
    # range.
    def next_hash(offset = 1)
      rel(offset, Hash, false)
    end

    # cursor.next_hash!(offset = 1)  => hash or nil
    #
    # Returns the next _offset_ th record. Negative indices count
    # backward from the current position. Returns nil if the _offset_ is out of
    # range.
    def next_hash!(offset = 1)
      rel(offset, Hash, true)
    end

    # cursor.first  => array or nil
    #
    # Returns the first record of the cursor. If the cursor is empty,
    # returns nil.
    def first
      entry(0, Array, false)
    end

    # cursor.first!  => array or nil
    #
    # Returns the first record of the cursor. If the cursor is empty,
    # returns nil.
    #
    # Stores the record fetched always in the same Array object.
    def first!
      entry(0, Array, true)
    end

    # cursor.first_hash  => hash or nil
    #
    # Returns the first record of the cursor. If the cursor is empty,
    # returns nil.
    def first_hash
      entry(0, Hash, false)
    end

    # cursor.first_hash!  => hash or nil
    #
    # Returns the first record of the cursor. If the cursor is empty,
    # returns nil.
    #
    # Stores the record fetched always in the same Hash object.
    def first_hash!
      entry(0, Hash, true)
    end

    # cursor.last  => array or nil
    #
    # Returns the last record of the cursor. If the cursor is empty,
    # returns nil.
    def last
      entry(-1, Array, false)
    end

    # cursor.last!  => array or nil
    #
    # Returns the last record of the cursor. If the cursor is empty,
    # returns nil.
    #
    # Stores the record fetched always in the same Array object.
    def last!
      entry(-1, Array, true)
    end

    # cursor.last_hash  => hash or nil
    #
    # Returns the last record of the cursor. If the cursor is empty,
    # returns nil.
    def last_hash
      entry(-1, Hash, false)
    end

    # cursor.last_hash!  => hash or nil
    #
    # Returns the last record of the cursor. If the cursor is empty,
    # returns nil.
    #
    # Stores the record fetched always in the same Hash object.
    def last_hash!
      entry(-1, Hash, true)
    end

    # cursor.current  => array or nil
    #
    # Returns the current record of the cursor. If the cursor is empty,
    # returns nil.
    def current
      entry(nil, Array, false)
    end

    # cursor.current!  => array or nil
    #
    # Returns the current record of the cursor. If the cursor is empty,
    # returns nil.
    #
    # Stores the record fetched always in the same Array object.
    def current!
      entry(nil, Array, true)
    end

    # cursor.current_hash  => hash or nil
    #
    # Returns the current record of the cursor. If the cursor is empty,
    # returns nil.
    def current_hash
      entry(nil, Hash, false)
    end

    # cursor.current_hash!  => hash or nil
    #
    # Returns the current record of the cursor. If the cursor is empty,
    # returns nil.
    #
    # Stores the record fetched always in the same Hash object.
    def current_hash!
      entry(nil, Hash, true)
    end
  end # class ScrollCursor
end # module Informix
