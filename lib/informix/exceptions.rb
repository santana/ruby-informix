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

#--
# The following code is a translation of the original C code written
# by Edwin M. Fine <emofine at finecomputerconsultants dot com>
#++

module Informix
  ExcInfo = Struct.new(:sql_code, :sql_state, :class_origin, :subclass_origin,
                       :message, :server_name, :connection_name)

  # The +ExcInfo+ class works as an object representation of an Informix
  # error state
  class ExcInfo
    FORMAT = "%-15s: %s\n".freeze

    # excinfo.to_s => string
    #
    # Returns a string representation of the error.
    def to_s
      ret = "\n"
      each_pair do |member, value|
        ret += sprintf(FORMAT, member.to_s, value)
      end
      ret
    end
  end # class ExcInfo

  # The +Error+ class is the base class for the rest of the exception classes
  # used in this extension. It works as a collection of +ExcInfo+ objects
  # when an error condition occurs.
  class Error < StandardError
    include Enumerable

    # Informix::Error.new([string|array]) => obj
    #
    # Optional string is the exception message.
    # Optional array must contain only instances of Informix::ExcInfo structs.
    #
    # Examples:
    # exc = Informix::Error.new
    # arr = [ExcInfo.new(x,y,z...), ExcInfo.new(a,b,c...)]
    # exc = Informix::Error.new(arr)
    def initialize(v = nil)
      case v
      when NilClass
        @info = []
      when String
        @info = []
        super
      when Array
        return @info = v if v.all? {|e| ExcInfo === e}
        raise(TypeError, "Array may contain only Informix::ExcInfo structs")
      else
        raise(TypeError,
                 "Expected string, or array of Informix::ExcInfo, as argument")
      end
    end

    # exc.add_info(sql_code, sql_state, class_origin, subclass_origin,
    #              message, server_name, connection_name)           =>  self
    #
    # Appends the given information to the exception.
    def add_info(*v)
      v.flatten!
      raise(ArgumentError,
        "Invalid number of arguments (got %d, need %d)", v.size, 7) \
        if v.size != 7
      @info.push ExcInfo.new(*v)
    end

    # exc.size => num
    #
    # Returns the number of Informix exception messages in the exception.
    def size
      @info.size
    end

    alias length size

    # exc.each {|exc_info| block } => exc_info
    #
    # Calls block once for each Informix::ExcInfo object in the exception.
    def each(&block)
      @info.each(&block)
    end

    # exc[index] => info
    #
    # Returns the ExcInfo object at index.
    def [](index)
      @info[index]
    end

    # exc.to_s => string
    #
    # Returns a string representation of self.
    def to_s
      return super if @info.size == 0
      ret = ""
      @info.each do |info|
        ret += info.to_s
      end
      ret
    end

    # exc.message   => string
    #
    # Overrides Exception#message. Returns first message in ExcInfo array,
    # or if the array is empty, delegates back to the parent class.
    def message
      @info.size > 0 ? @info[0].message : super
    end

    # exc.sqlcode => fixnum
    #
    # Returns the SQLCODE for the first stored ExcInfo struct, or 0
    # if none are stored.
    def sql_code
      @info.size > 0 ? @info[0].sql_code : 0
    end
  end # class Error

  class Warning < StandardError; end  

  class InterfaceError < Error; end
  class DatabaseError < Error; end
  class DataError < Error; end
  class OperationalError < Error; end
  class IntegrityError < Error; end
  class InternalError < Error; end
  class ProgrammingError < Error; end
  class NotSupportedError < Error; end
end # module Informix
