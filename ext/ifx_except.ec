/* $Id: ifx_except.ec,v 1.2 2007/10/20 10:17:35 santana Exp $ */
/*
* Copyright (c) 2006, 2007 Edwin M. Fine <efine@finecomputerconsultants.com>
* All rights reserved.
* 
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions
* are met:
* 
* 1. Redistributions of source code must retain the above copyright
*    notice, this list of conditions and the following disclaimer.
* 2. Redistributions in binary form must reproduce the above copyright
*    notice, this list of conditions and the following disclaimer in the
*    documentation and/or other materials provided with the distribution.
* 3. The name of the author may not be used to endorse or promote products
*    derived from this software without specific prior written permission.
* 
* THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
* IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
* DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
* SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
* HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
* STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
* ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

#include "ifx_except.h"
#include "ifx_assert.h"

#include <ruby.h>
#include <stdlib.h>
#include <stdio.h>
#include <sqlstype.h>
#include <sqltypes.h>

/* Convenience macros */
#define TRIM_BLANKS(s) ((s)[byleng(s, stleng(s))] = '\0')
#define NUM_ELEMS(arr) (sizeof(arr) / sizeof(*arr))

/* Future use: definition of interpretation of sql_state */
#define IS_SQL_SUCCESS(sql_state)       ((sql_state)[0] == '0' && (sql_state)[1] == '0')
#define IS_SQL_WARNING(sql_state)       ((sql_state)[0] == '0' && (sql_state)[1] == '1')
#define IS_SQL_NO_DATA_FOUND(sql_state) ((sql_state)[0] == '0' && (sql_state)[1] == '2')
#define IS_SQL_ERROR(sql_state)         ((sql_state)[0]  > '0' || (sql_state)[1]  > '2')

/* Constants */
#define NUM_SQL_EXCEPTION_ARGS          7    /* Number of things we get from GET EXCEPTION */

static const char * const vcs_id = "$Id: ifx_except.ec,v 1.2 2007/10/20 10:17:35 santana Exp $";

/*
 * Ruby object/class/module handles
 */
static ifx_except_symbols_t sym;

/**
 * Implementation
 */

/* class Informix::Error ------------------------------------------------ */

/**
 * call-seq:
 * Informix::Error.new([string|array]) => obj
 *
 * Optional string is the exception message.
 * Optional array must contain only instances of Informix::ExcInfo structs.
 *
 * Examples:
 * exc = Informix::Error.new
 * arr = [ExcInfo.new(x,y,z...), ExcInfo.new(a,b,c...)]
 * exc = Informix::Error.new(arr)
 */
static VALUE ifx_exc_init(int argc, VALUE *argv, VALUE self)
{
    VALUE arr;
    VALUE arg;

    if (rb_scan_args(argc, argv, "01", &arg) == 0) {
        arr = rb_ary_new();
    }
    else if (TYPE(arg) == T_STRING) {
        arr = rb_ary_new();
        rb_call_super(argc, argv);
    }
    else if (TYPE(arg) == T_ARRAY) {
        arr = arg;
        if (RARRAY(arg)->len > 0) {
            long i;
            for (i = 0; i < RARRAY(arg)->len; ++i)
                if (!rb_obj_is_instance_of(rb_ary_entry(arg, i), sym.sExcInfo))
                    rb_raise(rb_eTypeError, "Array may contain only Informix::ExcInfo structs");
        }
    }
    else {
        rb_raise(rb_eTypeError, 
                "Expected string, or array of Informix::ExcInfo, as argument");
    }
    
    rb_iv_set(self, "@info", arr);

    return self;
}

/* Implementation note:
 * argv must contain the following values in the order given:
 *   sql_code           FIXNUM 
 *   sql_state          STRING
 *   class_origin       STRING
 *   subclass_origin    STRING
 *   message            STRING
 *   server_name        STRING
 *   connection_name    STRING
 */

/**
 * call-seq:
 * exc.add_info(sql_code, sql_state, class_origin, subclass_origin, message, server_name, connection_name) =>  self
 *
 * Appends the given information to the exception.
 */
static VALUE ifx_exc_add_info(int argc, VALUE *argv, VALUE self)
{
    VALUE info_arr = rb_iv_get(self, "@info");
    VALUE sInfo;

#if defined(DEBUG)
    printf("%s:%d argc = %d\n", "ifx_exc_add_info", __LINE__, argc);
#endif

    if (argc != NUM_SQL_EXCEPTION_ARGS)
        rb_raise(rb_eArgError, "Invalid number of arguments (got %d, need %d)", argc, NUM_SQL_EXCEPTION_ARGS); 
    if (info_arr == Qnil) { /* Add the array if missing */
        info_arr = rb_ary_new();
        rb_iv_set(self, "@info", info_arr);
    }
        
    sInfo = 
        rb_struct_new(sym.sExcInfo, 
                      argv[0], argv[1], argv[2], argv[3],
                      argv[4], argv[5], argv[6], NULL);
    
    /* Add the new struct instance to end of our array */
    rb_ary_push(info_arr, sInfo);
    
    return self;
}

/**
 * call-seq:
 * exc.size => num
 *
 * Returns the number of Informix exception messages in the exception.
 */
static VALUE ifx_exc_size(VALUE self)
{
    VALUE info_arr = rb_iv_get(self, "@info");
    return info_arr != Qnil ? LONG2NUM(RARRAY(info_arr)->len) : Qnil;
}

/**
 * call-seq:
 * exc.each {|exc_info| block } => exc_info
 *
 * Calls block once for each Informix::ExcInfo object in the exception.
 */
static VALUE ifx_exc_each(VALUE self)
{
    VALUE info_arr = rb_iv_get(self, "@info");
    return info_arr != Qnil ? rb_iterate(rb_each, info_arr, rb_yield, 0) : Qnil;
}

/**
 * call-seq:
 * exc.at(index) => info
 *
 * Returns the ExcInfo object at index.
 */
static VALUE ifx_exc_at(VALUE self, VALUE index)
{
    VALUE info_arr = rb_iv_get(self, "@info");
    long n = NUM2LONG(rb_Integer(index));

#if defined(DEBUG)
    printf("Getting value at %ld\n", n);
#endif
    
    return info_arr != Qnil ? rb_ary_entry(info_arr, n) : Qnil;
}

/**
 * call-seq:
 * exc.to_s => string
 *
 * Returns a string representation of self.
 */
static VALUE ifx_exc_to_s(VALUE self)
{
    const VALUE nl = rb_str_new2("\n");
    VALUE s;
    VALUE info_arr = rb_iv_get(self, "@info");
    long info_arr_len;
    VALUE sInfo;
    long i;
    size_t j;

    info_arr_len = info_arr == Qnil ? 0 : RARRAY(info_arr)->len;

    if (info_arr_len > 0) {
        VALUE fmt_str = rb_str_new2("%-15s: %s\n");

        ID fields[] = { /* Fields will be displayed in this order */
            sym.id_message, 
            sym.id_sql_code, 
            sym.id_sql_state, 
            sym.id_class_origin, 
            sym.id_subclass_origin, 
            sym.id_server_name, 
            sym.id_connection_name
        };

        s = rb_str_new2("\n");

        for (i = 0; i < info_arr_len; ++i) {
            sInfo = RARRAY(info_arr)->ptr[i];

            for (j = 0; j < NUM_ELEMS(fields); ++j) {
                ID field = fields[j];
                VALUE struct_ref = rb_struct_getmember(sInfo, field);
                VALUE item_value = rb_String(struct_ref);
                VALUE args[] = { fmt_str, rb_String(ID2SYM(field)), item_value };

                if (RSTRING(item_value)->len != 0) { /* Skip empty fields */
                    rb_str_concat(s, rb_f_sprintf(NUM_ELEMS(args), args));
                }
            }

            rb_str_concat(s, nl);
        }
    }
    else { /* Call super's to_s */
        s = rb_call_super(0, 0);
    }

    return s;
}

/**
 * Overrides Exception#message. Returns first message in ExcInfo array,
 * or if the array is empty, delegates back to the parent class.
 */
static VALUE ifx_exc_message(VALUE self)
{
    VALUE info_arr = rb_iv_get(self, "@info");

    return (info_arr != Qnil && RARRAY(info_arr)->len > 0)
        ? rb_struct_getmember(RARRAY(info_arr)->ptr[0], sym.id_message)
        : rb_call_super(0, 0);
}

/**
 * call-seq:
 * exc.sqlcode => fixnum
 *
 * Returns the SQLCODE for the first stored ExcInfo struct, or 0
 * if none are stored.
 */
static VALUE ifx_exc_sql_code(VALUE self)
{
    VALUE info_arr = rb_iv_get(self, "@info");

    return (info_arr != Qnil && RARRAY(info_arr)->len > 0)
        ? rb_struct_getmember(RARRAY(info_arr)->ptr[0], sym.id_sql_code)
        : INT2FIX(0);
}

/*
 * C helper functions (see ifx_except.h for documentation)
 */
void raise_ifx_extended(void)
{
    rb_exc_raise(rbifx_ext_exception(sym.eDatabaseError));
}

VALUE rbifx_ext_exception(VALUE exception_class)
{
    VALUE new_instance;

    EXEC SQL BEGIN DECLARE SECTION;
    /* All field sizes defined in IBM Informix ESQL/C Programmer's Manual */
    int4 sql_code;

    char sql_state[5 + 1];
    char class_origin_val[255 + 1];
    char subclass_origin_val[255 + 1];
    char message[8191 + 1];
    char server_name[255 + 1];
    char connection_name[255 + 1];

    mint sql_exception_number;
    mint exc_count = 0;
    mint message_len;
    mint i;
    EXEC SQL END DECLARE SECTION;

    new_instance = rb_class_new_instance(0, 0, exception_class);

    /* Check that instance of exception_class is derived from
     * Informix::Error
     */
    if (!rb_obj_is_kind_of(new_instance, sym.eError) &&
        !rb_obj_is_kind_of(new_instance, sym.eWarning)) {
        rb_raise(rb_eRuntimeError,
                "Can't instantiate exception from %s, only from %s or %s or their children",
                rb_class2name(exception_class),
                rb_class2name(sym.eWarning),
                rb_class2name(sym.eError));
    }
    
    EXEC SQL GET DIAGNOSTICS :exc_count = NUMBER;

    if (exc_count == 0) { /* Something went wrong */
        char message[128];
        snprintf(message,
                 sizeof(message),
                 "SQL ERROR: SQLCODE %d (sorry, no GET DIAGNOSTICS information available)",
                 SQLCODE);

        {
            VALUE argv[] = { rb_str_new2(message) };
            return rb_class_new_instance(NUM_ELEMS(argv), argv, sym.eOperationalError);
        }
    }

    for (i = 0; i < exc_count; ++i) {
        sql_exception_number = i + 1;

        EXEC SQL GET DIAGNOSTICS EXCEPTION :sql_exception_number
            :sql_code            = INFORMIX_SQLCODE,
            :sql_state           = RETURNED_SQLSTATE,
            :class_origin_val    = CLASS_ORIGIN,
            :subclass_origin_val = SUBCLASS_ORIGIN,
            :message             = MESSAGE_TEXT,
            :message_len         = MESSAGE_LENGTH,
            :server_name         = SERVER_NAME,
            :connection_name     = CONNECTION_NAME
            ;
        
        TRIM_BLANKS(class_origin_val);
        TRIM_BLANKS(subclass_origin_val);
        TRIM_BLANKS(server_name);
        TRIM_BLANKS(connection_name);
        message[message_len - 1] = '\0';
        TRIM_BLANKS(message);

        {
            VALUE sprintf_args[] = { rb_str_new2(message), rb_str_new2(sqlca.sqlerrm) };
            VALUE argv[] = {
                INT2FIX(sql_code),
                rb_str_new2(sql_state),
                rb_str_new2(class_origin_val),
                rb_str_new2(subclass_origin_val),
                rb_f_sprintf(NUM_ELEMS(sprintf_args), sprintf_args),
                rb_str_new2(server_name),
                rb_str_new2(connection_name)
            };

            ifx_exc_add_info(NUM_ELEMS(argv), argv, new_instance);
        }
    }
    
    return new_instance;
}

/**
 * Raises Informix::AssertionFailure exception
 */
void ifx_assertion_exception(const char *failure_type, 
                             const char *what_failed,
                             const char *file,
                             int line)
{
    VALUE sprintf_args[] = {
        rb_str_new2("%s failed on line %d of file %s: %s"),
        rb_str_new2(failure_type),
        INT2FIX(line),
        rb_str_new2(file),
        rb_str_new2(what_failed)
    };

    VALUE args[] = { rb_f_sprintf(NUM_ELEMS(sprintf_args), sprintf_args) };

    rb_exc_raise(rb_class_new_instance(NUM_ELEMS(args), args, sym.lib_eAssertion));
}

/* Init module with shared value(s) from main informix classes */
void rbifx_except_init(VALUE mInformix, ifx_except_symbols_t *syms)
{
    VALUE sym_ExcInfo;

    sym.mInformix = mInformix; // Informix module object handle

	/* class Error --------------------------------------------------------- */
	sym.eError = rb_define_class_under(mInformix, "Error", rb_eStandardError);
	sym.eWarning = rb_define_class_under(mInformix, "Warning", rb_eStandardError);

    sym.eInterfaceError = rb_define_class_under(mInformix, "InterfaceError", sym.eError);
    sym.eDatabaseError = rb_define_class_under(mInformix, "DatabaseError", sym.eError);
    sym.eDataError = rb_define_class_under(mInformix, "DataError", sym.eError);
    sym.eOperationalError = rb_define_class_under(mInformix, "OperationalError", sym.eError);
    sym.eIntegrityError = rb_define_class_under(mInformix, "IntegrityError", sym.eError);
    sym.eInternalError = rb_define_class_under(mInformix, "InternalError", sym.eError);
    sym.eProgrammingError = rb_define_class_under(mInformix, "ProgrammingError", sym.eError);
    sym.eNotSupportedError = rb_define_class_under(mInformix, "NotSupportedError", sym.eError);

    /* Make base class enumerable */
    rb_include_module(sym.eError, rb_mEnumerable);

    /* Precondition exception class */
    sym.lib_eAssertion = rb_define_class_under(mInformix, "AssertionFailure", rb_eStandardError);

	rb_define_method(sym.eError, "initialize", ifx_exc_init, -1);
    rb_define_method(sym.eError, "message", ifx_exc_message, 0);
    rb_define_method(sym.eError, "sql_code", ifx_exc_sql_code, 0);
	rb_define_method(sym.eError, "add_info", ifx_exc_add_info, -1);
	rb_define_method(sym.eError, "[]", ifx_exc_at, 1);
	rb_define_method(sym.eError, "each", ifx_exc_each, 0);
	rb_define_method(sym.eError, "to_s", ifx_exc_to_s, 0);
	rb_define_method(sym.eError, "size", ifx_exc_size, 0);
	rb_define_alias(sym.eError, "length", "size");
    
    sym_ExcInfo = rb_intern("ExcInfo");

    sym.id_sql_code = rb_intern("sql_code");
    sym.id_sql_state = rb_intern("sql_state");
    sym.id_class_origin = rb_intern("class_origin");
    sym.id_subclass_origin = rb_intern("subclass_origin");
    sym.id_message = rb_intern("message");
    sym.id_server_name = rb_intern("server_name");
    sym.id_connection_name = rb_intern("connection_name");
    
    /* Define ExcInfo as a struct in the Informix module */
    rb_define_const(mInformix,
                    "ExcInfo",
                    rb_struct_define(NULL, 
                                     rb_id2name(sym.id_sql_code), 
                                     rb_id2name(sym.id_sql_state), 
                                     rb_id2name(sym.id_class_origin), 
                                     rb_id2name(sym.id_subclass_origin), 
                                     rb_id2name(sym.id_message), 
                                     rb_id2name(sym.id_server_name), 
                                     rb_id2name(sym.id_connection_name),
                                     NULL));

    sym.sExcInfo = rb_const_get(mInformix, sym_ExcInfo);

    if (syms)
    {
        *syms = sym;
    }
}

