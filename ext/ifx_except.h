/* $Id: ifx_except.h,v 1.1 2007/01/31 02:16:32 santana Exp $ */
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

#if !defined(IFX_EXCEPT_H_INCLUDED)
#define IFX_EXCEPT_H_INCLUDED

#include <ruby.h>

typedef struct ifx_except_symbols_t {
    VALUE mInformix;
    VALUE sExcInfo;

    VALUE eError;
    VALUE eInterfaceError;
    VALUE eDatabaseError;
    VALUE eDataError;
    VALUE eOperationalError;
    VALUE eIntegrityError;
    VALUE eInternalError;
    VALUE eProgrammingError;
    VALUE eNotSupportedError;
    VALUE eWarning;

    VALUE lib_eAssertion;

    /* Symbols for the ErrorInfo struct */
    ID id_sql_code;
    ID id_sql_state;
    ID id_class_origin;
    ID id_subclass_origin;
    ID id_message;
    ID id_server_name;
    ID id_connection_name;
} ifx_except_symbols_t;

/**
 * Initializes this module. MUST be called from within
 * Informix_init(). If syms is not null, the struct it points
 * to will be set to the value of the corresponding symbols.
 */
void rbifx_except_init(VALUE mInformix, ifx_except_symbols_t *syms);

/**
 * Creates and returns an instance of any class derived from
 * Informix::Error or Informix::Warning, using extended data from
 * the SQL GET DIAGNOSTICS statement.
 */
VALUE rbifx_ext_exception(VALUE exception_class);

/**
 * Raises an error with extended GET DIAGNOSTICS information
 */
void raise_ifx_extended(void); /* Raises Informix::DatabaseError */

#endif
