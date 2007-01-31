/* $Id: ifx_assert.h,v 1.1 2007/01/31 02:16:32 santana Exp $ */
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

#if !defined(IFX_ASSERT_H_INCLUDED)
#define IFX_ASSERT_H_INCLUDED

#define RBIFX_ASSERT(x) \
    do { if (!(x)) ifx_assertion_exception("Assertion", #x, __FILE__, __LINE__) } while(0)
#define RBIFX_PRECOND(x) \
    do { if (!(x)) ifx_assertion_exception("Precondition", #x, __FILE__, __LINE__) } while(0)

/* Correctness (DBC) support */
void ifx_assertion_exception(const char *failure_type, 
                             const char *what_failed,
                             const char *file,
                             int line);

#endif
