/* $Id: informix.ec,v 1.55 2006/12/13 08:02:06 santana Exp $ */
/*
* Copyright (c) 2006, Gerardo Santana Gomez Garrido <gerardo.santana@gmail.com>
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

#include "ruby.h"

#include <sqlstype.h>
#include <sqltypes.h>

static VALUE rb_cDate;

static VALUE rb_mInformix;
static VALUE rb_mSequentialCursor;
static VALUE rb_mScrollCursor;
static VALUE rb_mInsertCursor;

static VALUE rb_cSlob;
static VALUE rb_cDatabase;
static VALUE rb_cStatement;
static VALUE rb_cCursor;

static ID s_read, s_new, s_utc, s_day, s_month, s_year;
static ID s_hour, s_min, s_sec, s_usec, s_to_s, s_to_i;
static VALUE sym_name, sym_type, sym_nullable, sym_stype, sym_length;
static VALUE sym_precision, sym_scale, sym_default, sym_xid;
static VALUE sym_scroll, sym_hold;
static VALUE sym_col_info, sym_sbspace, sym_estbytes, sym_extsz;
static VALUE sym_createflags, sym_openflags;

#define IDSIZE 30

static char *currentdid = NULL;

typedef struct {
	short is_select, is_open;
	struct sqlda daInput, *daOutput;
	short *indInput, *indOutput;
	char *bfOutput;
	char cursor_id[IDSIZE];
	char stmt_id[IDSIZE];
	VALUE db, array, hash, field_names;
	char *database_id;
} cursor_t;

typedef struct {
	mint fd;
	ifx_lo_t lo;
	ifx_lo_create_spec_t *spec;
	short type; /* XID_CLOB/XID_BLOB */
	VALUE db;
	char *database_id;
} slob_t;

#define NUM2INT8(num, int8addr) do { \
	VALUE str = rb_funcall(num, s_to_s, 0); \
	char *c_str = StringValueCStr(str); \
	mint ret = ifx_int8cvasc(c_str, strlen(c_str), (int8addr)); \
	if (ret < 0) \
		rb_raise(rb_eRuntimeError, "Could not convert %s to int8", c_str); \
}while(0)

#define INT82NUM(int8addr, num) do { \
	char str[21]; \
	mint ret = ifx_int8toasc((int8addr), str, sizeof(str) - 1); \
	str[sizeof(str) - 1] = 0; \
	num = rb_cstr2inum(str, 10); \
}while(0)

/* class Slob ------------------------------------------------------------ */

static void
slob_mark(slob_t *slob)
{
	rb_gc_mark(slob->db);
}

static void
slob_free(slob_t *slob)
{
	if (slob->fd != -1) {
		EXEC SQL begin declare section;
			char *did;
		EXEC SQL end   declare section;

		did = slob->database_id;
		if (currentdid != did) {
			EXEC SQL set connection :did;
			if (SQLCODE < 0)
				goto exit;
			currentdid = did;
		}
		ifx_lo_close(slob->fd);
	}

exit:
	if (slob->spec)
		ifx_lo_spec_free(slob->spec);

	xfree(slob);
}

static VALUE
slob_alloc(VALUE klass)
{
	slob_t *slob;

	slob = ALLOC(slob_t);
	slob->spec = NULL;
	slob->fd = -1;
	slob->type = XID_CLOB;

	return Data_Wrap_Struct(klass, slob_mark, slob_free, slob);
}

/*
 * call-seq:
 * Slob.new(database, type = Slob::CLOB, options = nil)  => slob
 *
 * Creates a Smart Large Object of type <i>type</i> in <i>database</i>.
 * Returns a <code>Slob</code> object pointing to it.
 *
 * <i>type</i> can be Slob::BLOB or Slob::CLOB
 *
 * <i>options</i> must be a hash with the following possible keys:
 *
 *   :sbspace     => Sbspace name
 *   :estbytes    => Estimated size, in bytes
 *   :extsz       => Allocation extent size
 *   :createflags => Create-time flags
 *   :openflags   => Access mode
 *   :maxbytes    => Maximum size
 *   :col_info    => Get the previous values from the column-level storage
 *                   characteristics for the specified database column
 */
static VALUE
slob_initialize(int argc, VALUE *argv, VALUE self)
{
	mint ret, error;
	slob_t *slob;
	VALUE db, type, options;
	VALUE col_info, sbspace, estbytes, extsz, createflags, openflags, maxbytes;
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	rb_scan_args(argc, argv, "12", &db, &type, &options);
	Data_Get_Struct(db, char, did);

	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	Data_Get_Struct(self, slob_t, slob);
	slob->db = db;
	slob->database_id = did;

	if (RTEST(type)) {
		int t = FIX2INT(type);
		if (t != XID_CLOB && t != XID_BLOB)
			rb_raise(rb_eRuntimeError, "Invalid type %d for an SLOB", t);
		slob->type = t;
	}

	col_info = sbspace = estbytes = extsz = createflags = openflags = maxbytes = Qnil;

	if (RTEST(options)) {
		col_info = rb_hash_aref(options, sym_col_info);
		sbspace = rb_hash_aref(options, sym_sbspace);
		estbytes = rb_hash_aref(options, sym_estbytes);
		extsz = rb_hash_aref(options, sym_extsz);
		createflags = rb_hash_aref(options, sym_createflags);
		openflags = rb_hash_aref(options, sym_openflags);
	}

	ret = ifx_lo_def_create_spec(&slob->spec);
	if (ret < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", ret);

	if (RTEST(col_info)) {
		ret = ifx_lo_col_info(StringValueCStr(col_info), slob->spec);

		if (ret < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", ret);
	}
	if (RTEST(sbspace)) {
		char *c_sbspace = StringValueCStr(sbspace);
		ret = ifx_lo_specset_sbspace(slob->spec, c_sbspace);
		if (ret == -1)
			rb_raise(rb_eRuntimeError, "Could not set sbspace name to %s", c_sbspace);
	}
	if (RTEST(estbytes)) {
		ifx_int8_t estbytes8;

		NUM2INT8(estbytes, &estbytes8);
		ret = ifx_lo_specset_estbytes(slob->spec, &estbytes8);
		if (ret == -1)
			rb_raise(rb_eRuntimeError, "Could not set estbytes");
	}
	if (RTEST(extsz)) {
		ret = ifx_lo_specset_extsz(slob->spec, FIX2LONG(extsz));
		if (ret == -1)
			rb_raise(rb_eRuntimeError, "Could not set extsz to %d", FIX2LONG(extsz));
	}
	if (RTEST(createflags)) {
		ret = ifx_lo_specset_flags(slob->spec, FIX2LONG(createflags));
		if (ret == -1)
			rb_raise(rb_eRuntimeError, "Could not set crate-time flags to 0x%X", FIX2LONG(createflags));
	}
	if (RTEST(maxbytes)) {
		ifx_int8_t maxbytes8;

		NUM2INT8(maxbytes, (&maxbytes8));
		ret = ifx_lo_specset_maxbytes(slob->spec, &maxbytes8);
		if (ret == -1)
			rb_raise(rb_eRuntimeError, "Could not set maxbytes");
	}
	slob->fd = ifx_lo_create(slob->spec, RTEST(openflags)? FIX2LONG(openflags): LO_RDWR, &slob->lo, &error);
	if (slob->fd == -1) {
		rb_raise(rb_eRuntimeError, "Informix Error: %d\n", error);
	}
	return self;
}

/*
 * call-seq:
 * slob.open(access = Slob::RDONLY)  => slob
 *
 * Opens the Smart Large Object in <i>access</i> mode.
 *
 * access modes:
 * 
 * Slob::RDONLY::		Read only
 * Slob::DIRTY_READ::	Read uncommitted data
 * Slob::WRONLY::	Write only
 * Slob::APPEND::	Append data to the end, if combined with RDRW or WRONLY; read only otherwise
 * Slob::RDRW::		Read/Write
 * Slob::BUFFER::	Use standard database server buffer pool
 * Slob::NOBUFFER::	Use private buffer from the session pool of the database server
 * Slob::LOCKALL::		Lock the entire Smart Large Object
 * Slob::LOCKRANGE::	Lock a range of bytes
 *
 * Returns __self__.
 */
static VALUE
slob_open(int argc, VALUE *argv, VALUE self)
{
	VALUE access;
	slob_t *slob;
	mint error;
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, slob_t, slob);

	if (slob->fd != -1) /* Already open */
		return self;

	did = slob->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	rb_scan_args(argc, argv, "01", &access);

	slob->fd = ifx_lo_open(&slob->lo, NIL_P(access)? LO_RDONLY: FIX2INT(access), &error);

	if (slob->fd == -1)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", error);

	return self;
}

/*
 * call-seq:
 * slob.close  => slob
 * 
 * Closes the Smart Large Object and returns __self__.
 */
static VALUE
slob_close(VALUE self)
{
	slob_t *slob;

	Data_Get_Struct(self, slob_t, slob);
	if (slob->fd != -1) {
		EXEC SQL begin declare section;
			char *did;
		EXEC SQL end   declare section;

		did = slob->database_id;
		if (currentdid != did) {
			EXEC SQL set connection :did;
			if (SQLCODE < 0)
				return self;
			currentdid = did;
		}

		ifx_lo_close(slob->fd);
		slob->fd = -1;
	}

	return self;
}

/*
 * call-seq:
 * slob.read(nbytes)  => string
 * 
 * Reads at most <i>nbytes</i> bytes from the Smart Large Object.
 *
 * Returns the bytes read as a String object.
 */
static VALUE
slob_read(VALUE self, VALUE nbytes)
{
	slob_t *slob;
	mint error, ret;
	char *buffer;
	long c_nbytes;
	VALUE str;
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;


	Data_Get_Struct(self, slob_t, slob);

	if (slob->fd == -1)
		rb_raise(rb_eRuntimeError, "Open the Slob object before reading");

	did = slob->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	c_nbytes = FIX2LONG(nbytes);
	buffer = ALLOC_N(char, c_nbytes);
	ret = ifx_lo_read(slob->fd, buffer, c_nbytes, &error);

	if (ret == -1)
		rb_raise(rb_eRuntimeError, "Informix Error: %d\n", error);

	str = rb_str_new(buffer, ret);
	xfree(buffer);

	return str;
}

/*
 * call-seq:
 * slob.write(data)  => fixnum or bignum
 * 
 * Writes <i>data</i> to the Smart Large Object.
 *
 * Returns the number of bytes written.
 */
static VALUE
slob_write(VALUE self, VALUE data)
{
	slob_t *slob;
	mint error, ret;
	char *buffer;
	long nbytes;
	VALUE str;
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, slob_t, slob);

	if (slob->fd == -1)
		rb_raise(rb_eRuntimeError, "Open the Slob object before writing");

	did = slob->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	str = StringValue(data);
	buffer = RSTRING(str)->ptr;
	nbytes = RSTRING(str)->len;

	ret = ifx_lo_write(slob->fd, buffer, nbytes, &error);

	if (ret == -1)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", error);

	return LONG2NUM(ret);
}

/*
 * call-seq:
 * slob.seek(offset, whence)  => fixnum or bignum
 * 
 * Sets the file position for the next read or write
 * operation on the open Smart Large Object.
 *
 *
 * <i>offset</i>	offset from the starting seek position
 * <i>whence</i>	identifies the starting seek position
 * 
 * Values for <i>whence</i>:
 *
 * Slob::SEEK_SET::	The start of the Smart Large Object
 * Slob::SEEK_CUR::	The current seek position in the Smart Large Object
 * Slob::SEEK_END::	The end of the Smart Large Object
 *
 * Returns the new position.
 */
static VALUE
slob_seek(VALUE self, VALUE offset, VALUE whence)
{
	slob_t *slob;
	mint ret;
	VALUE seek_pos;
	ifx_int8_t offset8, seek_pos8;
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, slob_t, slob);

	if (slob->fd == -1)
		rb_raise(rb_eRuntimeError, "Open the Slob object first");

	did = slob->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	NUM2INT8(offset, &offset8);
	ret = ifx_lo_seek(slob->fd, &offset8, FIX2INT(whence), &seek_pos8);
	if (ret < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", ret);

	INT82NUM(&seek_pos8, seek_pos);

	return seek_pos;
}

/*
 * call-seq:
 * slob.tell  => fixnum or bignum
 * 
 * Returns the current file or seek position for an
 * open Smart Large Object
 */
static VALUE
slob_tell(VALUE self)
{
	slob_t *slob;
	mint ret;
	VALUE seek_pos;
	ifx_int8_t seek_pos8;
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, slob_t, slob);

	if (slob->fd == -1)
		rb_raise(rb_eRuntimeError, "Open the Slob object first");

	did = slob->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	ret = ifx_lo_tell(slob->fd, &seek_pos8);
	if (ret < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", ret);

	INT82NUM(&seek_pos8, seek_pos);

	return seek_pos;
}

/*
 * call-seq:
 * slob.truncate(offset)  => slob
 * 
 * Truncates a Smart Large Object at a specified byte position.
 *
 * Returns __self__.
 */
static VALUE
slob_truncate(VALUE self, VALUE offset)
{
	slob_t *slob;
	mint ret;
	ifx_int8_t offset8;
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, slob_t, slob);

	if (slob->fd == -1)
		rb_raise(rb_eRuntimeError, "Open the Slob object first");

	did = slob->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	NUM2INT8(offset, &offset8);
	ret = ifx_lo_truncate(slob->fd, &offset8);
	if (ret < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", ret);

	return self;
}

/* Helper functions ------------------------------------------------------- */

/*
 * Counts the number of markers '?' in the query
 */
static int count_markers(const char *query)
{
	register char c, quote = 0;
	register int count = 0;

	while((c = *query++)) {
		if (quote && c != quote)
			;
		else if (quote == c) {
			quote = 0;
		}
		else if (c == '\'' || c == '"') {
			quote = c;
		}
		else if (c == '?') {
			++count;
		}
	}
	return count;
}

/*
 * Allocates memory for the indicators array and slots for the input
 * parameters, if any. Freed by free_input_slots.
 */
static void
alloc_input_slots(cursor_t *c, const char *query)
{
	register int n;

	n = count_markers(query);
	c->daInput.sqld = n;
	if (n) {
		c->daInput.sqlvar = ALLOC_N(struct sqlvar_struct, n);
		memset(c->daInput.sqlvar, 0, n*sizeof(struct sqlvar_struct));
		c->indInput = ALLOC_N(short, n);
		while(n--)
			c->daInput.sqlvar[n].sqlind = &c->indInput[n];
	}
	else {
		c->daInput.sqlvar = NULL;
		c->indInput = NULL;
	}
}

/*
 * Allocates memory for the output data slots and its indicators array.
 * Freed by free_output_slots.
 */
static void
alloc_output_slots(cursor_t *c)
{
	register int i, count;
	register short *ind;
	struct sqlvar_struct *var;
	register char *buffer;

	c->field_names = rb_ary_new2(c->daOutput->sqld);

	ind = c->indOutput = ALLOC_N(short, c->daOutput->sqld);

	var = c->daOutput->sqlvar;
	for (i = count = 0; i < c->daOutput->sqld; i++, ind++, var++) {
		var->sqlind = ind;
		rb_ary_store(c->field_names, i, rb_str_new2(var->sqlname));
		if (ISSMARTBLOB(var->sqltype, var->sqlxid)) {
			var->sqldata = (char *)ALLOC(ifx_lo_t);
			continue;
		}
		var->sqllen = rtypmsize(var->sqltype, var->sqllen);
		count = rtypalign(count, var->sqltype) + var->sqllen;
	}

	buffer = c->bfOutput = ALLOC_N(char, count);
	memset(buffer, 0, count);

	var = c->daOutput->sqlvar;
	for (i = count = 0; i < c->daOutput->sqld; i++, var++) {
		if (var->sqldata)
			continue;
		count = rtypalign(count, var->sqltype);
		var->sqldata = buffer + count;
		count += var->sqllen;
		if (ISBYTESTYPE(var->sqltype) || ISTEXTTYPE(var->sqltype)) {
			loc_t *p;
			p = (loc_t *)var->sqldata;
			byfill((char *)p, sizeof(loc_t), 0);
			p->loc_loctype = LOCMEMORY;
			p->loc_bufsize = -1;
		}
		if (var->sqltype == SQLDTIME) {
			var->sqllen = 0;
		}
	}
}

/*
 * Frees the allocated memory of the input parameters, but not the slots
 * nor the indicators array. Allocated by bind_input_params.
 */
static void
clean_input_slots(cursor_t *c)
{
	register int count;
	register struct sqlvar_struct *var;

	if (c->daInput.sqlvar == NULL)
		return;
	var = c->daInput.sqlvar;
	count = c->daInput.sqld;
	while(count--) {
		if (var->sqldata != NULL) {
			if (var->sqltype == CLOCATORTYPE) {
				loc_t *p = (loc_t *)var->sqldata;
				if (p->loc_buffer != NULL) {
					xfree(p->loc_buffer);
				}
			}
			xfree(var->sqldata);
			var->sqldata = NULL;
			var++;
		}
	}
}

/*
 * Frees the memory for the input parameters, their slots, and the indicators
 * array. Allocated by alloc_input_slots and bind_input_params.
 */
static void
free_input_slots(cursor_t *c)
{
	clean_input_slots(c);
	if (c->daInput.sqlvar) {
		xfree(c->daInput.sqlvar);
		c->daInput.sqlvar = NULL;
		c->daInput.sqld = 0;
	}
	if (c->indInput) {
		xfree(c->indInput);
		c->indInput = NULL;
	}
}

/*
 * Frees the memory for the output parameters, their slots, and the indicators
 * array. Allocated by alloc_output_slots.
 */
static void
free_output_slots(cursor_t *c)
{
	if (c->daOutput != NULL) {
		struct sqlvar_struct *var = c->daOutput->sqlvar;
		if (var) {
			register int i;
			for (i = 0; i < c->daOutput->sqld; i++, var++) {
				if (ISBLOBTYPE(var->sqltype)) {
					loc_t *p = (loc_t *) var->sqldata;
					if(p -> loc_buffer)
						xfree(p->loc_buffer);
				}
				if (ISSMARTBLOB(var->sqltype, var->sqlxid))
					xfree(var->sqldata);
			}
		}
		xfree(c->daOutput);
		c->daOutput = NULL;
	}
	if (c->indOutput != NULL) {
		xfree(c->indOutput);
		c->indOutput = NULL;
	}
	if (c->bfOutput != NULL) {
		xfree(c->bfOutput);
		c->bfOutput = NULL;
	}
}

/*
 * Gets an array of Ruby objects as input parameters and place them in input
 * slots, converting data types and allocating memory as needed.
 */
static void
bind_input_params(cursor_t *c, VALUE *argv)
{
	VALUE data, klass;
	register int i;
	register struct sqlvar_struct *var;

	var = c->daInput.sqlvar;
	for (i = 0; i < c->daInput.sqld; i++, var++) {
		data = argv[i];

		switch(TYPE(data)) {
		case T_NIL:
			var->sqltype = CSTRINGTYPE;
			var->sqldata = NULL;
			var->sqllen = 0;
			*var->sqlind = -1;
			break;
		case T_FIXNUM:
			var->sqldata = (char *)ALLOC(long);
			*((long *)var->sqldata) = FIX2LONG(data);
			var->sqltype = CLONGTYPE;
			var->sqllen = sizeof(long);
			*var->sqlind = 0;
			break;
		case T_FLOAT:
			var->sqldata = (char *)ALLOC(double);
			*((double *)var->sqldata) = NUM2DBL(data);
			var->sqltype = CDOUBLETYPE;
			var->sqllen = sizeof(double);
			*var->sqlind = 0;
			break;
		case T_TRUE:
		case T_FALSE:
			var->sqldata = ALLOC(char);
			*var->sqldata = TYPE(data) == T_TRUE? 't': 'f';
			var->sqltype = CCHARTYPE;
			var->sqllen = sizeof(char);
			*var->sqlind = 0;
			break;
		default:
			klass = rb_obj_class(data);
			if (klass == rb_cDate) {
				int2 mdy[3];
				int4 date;

				mdy[0] = FIX2INT(rb_funcall(data, s_month, 0));
				mdy[1] = FIX2INT(rb_funcall(data, s_day, 0));
				mdy[2] = FIX2INT(rb_funcall(data, s_year, 0));
				rmdyjul(mdy, &date);

				var->sqldata = (char *)ALLOC(int4);
				*((int4 *)var->sqldata) = date;
				var->sqltype = CDATETYPE;
				var->sqllen = sizeof(int4);
				*var->sqlind = 0;
				break;
			}
			if (klass == rb_cTime) {
				char buffer[30];
				short year, month, day, hour, minute, second;
				int usec;
				dtime_t *dt;

				year = FIX2INT(rb_funcall(data, s_year, 0));
				month = FIX2INT(rb_funcall(data, s_month, 0));
				day = FIX2INT(rb_funcall(data, s_day, 0));
				hour = FIX2INT(rb_funcall(data, s_hour, 0));
				minute = FIX2INT(rb_funcall(data, s_min, 0));
				second = FIX2INT(rb_funcall(data, s_sec, 0));
				usec = FIX2INT(rb_funcall(data, s_usec, 0));

				dt = ALLOC(dtime_t);

				dt->dt_qual = TU_DTENCODE(TU_YEAR, TU_F5);
				snprintf(buffer, sizeof(buffer), "%d-%d-%d %d:%d:%d.%d",
					year, month, day, hour, minute, second, usec/10);
				dtcvasc(buffer, dt);

				var->sqldata = (char *)dt;
				var->sqltype = CDTIMETYPE;
				var->sqllen = sizeof(dtime_t);
				*var->sqlind = 0;
				break;
			}
			if (klass == rb_cSlob) {
				slob_t *slob;

				Data_Get_Struct(data, slob_t, slob);

				var->sqldata = (char *)ALLOC(ifx_lo_t);
				memcpy(var->sqldata, &slob->lo, sizeof(slob->lo));
				var->sqltype = SQLUDTFIXED;
				var->sqlxid = slob->type;
				var->sqllen = sizeof(ifx_lo_t);
				*var->sqlind = 0;
				break;
			}
			if (rb_respond_to(data, s_read)) {
				char *str;
				loc_t *loc;
				long len;

				data = rb_funcall(data, s_read, 0);
				data = StringValue(data);
				str = RSTRING(data)->ptr;
				len = RSTRING(data)->len;

				loc = (loc_t *)ALLOC(loc_t);
				byfill((char *)loc, sizeof(loc_t), 0);
				loc->loc_loctype = LOCMEMORY;
				loc->loc_buffer = (char *)ALLOC_N(char, len);
				memcpy(loc->loc_buffer, str, len);
				loc->loc_bufsize = loc->loc_size = len;

				var->sqldata = (char *)loc;
				var->sqltype = CLOCATORTYPE;
				var->sqllen = sizeof(loc_t);
				*var->sqlind = 0;
				break;
			}
			{
			VALUE str;
			str = rb_check_string_type(data);
			if (NIL_P(str)) {
				data = rb_obj_as_string(data);
			}
			else {
				data = str;
			}
			}
		case T_STRING: {
			char *str;
			long len;

			str = RSTRING(data)->ptr;
			len = RSTRING(data)->len;
			var->sqldata = ALLOC_N(char, len + 1);
			memcpy(var->sqldata, str, len);
			var->sqldata[len] = 0;
			var->sqltype = CSTRINGTYPE;
			var->sqllen = len;
			*var->sqlind = 0;
			break;
		}
		}
	}
}

/*
 * Returns an array or a hash  of Ruby objects containing the record fetched.
 */
static VALUE
make_result(cursor_t *c, VALUE record)
{
	VALUE item;
	register int i;
	register struct sqlvar_struct *var;

	var = c->daOutput->sqlvar;
	for (i = 0; i < c->daOutput->sqld; i++, var++) {
		if (*var->sqlind == -1) {
			item = Qnil;
		} else {
		switch(var->sqltype) {
		case SQLCHAR:
		case SQLVCHAR:
		case SQLNCHAR:
		case SQLNVCHAR:
			item = rb_str_new2(var->sqldata);
			break;
		case SQLSMINT:
			item = INT2FIX(*(int2 *)var->sqldata);
			break;
		case SQLINT:
		case SQLSERIAL:
			item = INT2NUM(*(int4 *)var->sqldata);
			break;
		case SQLINT8:
		case SQLSERIAL8:
			INT82NUM((ifx_int8_t *)var->sqldata, item);
			break;
		case SQLSMFLOAT:
			item = rb_float_new(*(float *)var->sqldata);
			break;
		case SQLFLOAT:
			item = rb_float_new(*(double *)var->sqldata);
			break;
		case SQLDATE: {
			VALUE year, month, day;
			int2 mdy[3];

			rjulmdy(*(int4 *)var->sqldata, mdy);
			year = INT2FIX(mdy[2]);
			month = INT2FIX(mdy[0]);
			day = INT2FIX(mdy[1]);
			item = rb_funcall(rb_cDate, s_new, 3, year, month, day);
			break;
		}
		case SQLDTIME: {
			register short qual;
			short year, month, day, hour, minute, second;
			int usec;
			dtime_t *dt;
			register char *dgts;

			month = day = 1;
			year = hour = minute = second = usec = 0;
			dt = (dtime_t *)var->sqldata;
			dgts = dt->dt_dec.dec_dgts;

			qual = TU_START(dt->dt_qual);
			for (; qual <= TU_END(dt->dt_qual); qual++) {
				switch(qual) {
				case TU_YEAR:
					year = 100**dgts++;
					year += *dgts++;
					break;
				case TU_MONTH:
					month = *dgts++;
					break;
				case TU_DAY:
					day = *dgts++;
					break;
				case TU_HOUR:
					hour = *dgts++;
					break;
				case TU_MINUTE:
					minute = *dgts++;
					break;
				case TU_SECOND:
					second = *dgts++;
					break;
				case TU_F1:
					usec = 10000**dgts++;
					break;
				case TU_F3:
					usec += 100**dgts++;
					break;
				case TU_F5:
					usec += *dgts++;
					break;
				}
			}

			item = rb_funcall(rb_cTime, s_utc, 7,
				INT2FIX(year), INT2FIX(month), INT2FIX(day),
				INT2FIX(hour), INT2FIX(minute), INT2FIX(second),
				INT2FIX(usec));

			/* Clean the buffer for DATETIME columns because
			 * ESQL/C leaves the previous content when a
			 * a time field is zero.
			 */
			memset(dt, 0, sizeof(dtime_t));
			break;
		}
		case SQLDECIMAL:
		case SQLMONEY: {
			double dblValue;
			dectodbl((dec_t *)var->sqldata, &dblValue);
			item = rb_float_new(dblValue);
			break;
		}
		case SQLBOOL:
			item = var->sqldata[0]? Qtrue: Qfalse;
			break;
		case SQLBYTES:
		case SQLTEXT: {
			loc_t *loc;
			loc = (loc_t *)var->sqldata;
			item = rb_str_new(loc->loc_buffer, loc->loc_size);
			break;
		}
		case SQLUDTFIXED:
			if (ISSMARTBLOB(var->sqltype, var->sqlxid)) {
				slob_t *slob;

				item = slob_alloc(rb_cSlob);
				Data_Get_Struct(item, slob_t, slob);
				memcpy(&slob->lo, var->sqldata, sizeof(ifx_lo_t));
				slob->type = var->sqlxid;
				break;
			}
		case SQLSET:
		case SQLMULTISET:
		case SQLLIST:
		case SQLROW:
		case SQLCOLLECTION:
		case SQLROWREF:
		case SQLUDTVAR:
		case SQLREFSER8:
		case SQLLVARCHAR:
		case SQLSENDRECV:
		case SQLIMPEXP:
		case SQLIMPEXPBIN:
		case SQLUNKNOWN:
		default:
			item = Qnil;
			break;
		}
		}
		if (BUILTIN_TYPE(record) == T_ARRAY) {
			rb_ary_store(record, i, item);
		}
        else {
			rb_hash_aset(record, RARRAY(c->field_names)->ptr[i], item);
		}
	}
	return record;
}

/* module Informix -------------------------------------------------------- */

/*
 * call-seq:
 * Informix.connect(dbname, user = nil, password = nil)  => database
 *
 * Returns a <code>Database</code> object connected to <i>dbname</i> as
 * <i>user</i> with <i>password</i>. If these are not given, connects to
 * <i>dbname</i> as the current user.
 */
static VALUE
informix_connect(int argc, VALUE *argv, VALUE self)
{
	return rb_class_new_instance(argc, argv, rb_cDatabase);
}


/* class Database --------------------------------------------------------- */

static void
database_free(void *p)
{
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	did = p;
	EXEC SQL disconnect :did;
	if (currentdid == did)
		currentdid = NULL;
	xfree(p);
}

static VALUE
database_alloc(VALUE klass)
{
	char *did;

	did = ALLOC_N(char, IDSIZE);
	did[0] = 0;
	return Data_Wrap_Struct(klass, 0, database_free, did);
}

/*
 * call-seq:
 * Database.new(dbname, user = nil, password = nil)  => database
 *
 * Returns a <code>Database</code> object connected to <i>dbname</i> as
 * <i>user</i> with <i>password</i>. If these are not given, connects to
 * <i>dbname</i> as the current user.
 */
static VALUE
database_initialize(int argc, VALUE *argv, VALUE self)
{
	VALUE arg[3];

	EXEC SQL begin declare section;
		char *dbname, *user = NULL, *pass = NULL, *did;
	EXEC SQL end   declare section;

	rb_scan_args(argc, argv, "12", &arg[0], &arg[1], &arg[2]);

	if (NIL_P(arg[0]))
		rb_raise(rb_eRuntimeError, "A database name must be specified");

	Data_Get_Struct(self, char, did);

	dbname  = StringValueCStr(arg[0]);
	snprintf(did, IDSIZE, "DB%lX", self);

	if (!NIL_P(arg[1]))
		user = StringValueCStr(arg[1]);

	if (!NIL_P(arg[2]))
		pass = StringValueCStr(arg[2]);

	if (user && pass)
		EXEC SQL connect to :dbname as :did user :user
			using :pass with concurrent transaction;
	else
		EXEC SQL connect to :dbname as :did with concurrent transaction;

	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	currentdid = did;

	return self;
}

/*
 * call-seq:
 * db.close  => db
 *
 * Disconnects <i>db</i> and returns __self__
 */
static VALUE
database_close(VALUE self)
{
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, char, did);
	EXEC SQL disconnect :did;
	if (did == currentdid)
		currentdid = NULL;

	return self;
}

/*
 * call-seq:
 * db.immediate(query)  => fixnum
 *
 * Executes <i>query</i> and returns the number of rows affected.
 * <i>query</i> must not return rows. Executes efficiently any
 * non-parameterized or DQL statement.
 */

static VALUE
database_immediate(VALUE self, VALUE arg)
{
	EXEC SQL begin declare section;
		char *query, *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, char, did);

	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	query = StringValueCStr(arg);
	EXEC SQL execute immediate :query;
	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	return INT2FIX(sqlca.sqlerrd[2]);
}

/*
 * call-seq:
 * db.rollback  => db
 *
 * Rolls back a transaction and returns __self__.
 */
static VALUE
database_rollback(VALUE self)
{
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, char, did);

	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	EXEC SQL rollback;
	return self;
}

/*
 * call-seq:
 * db.commit  => db
 *
 * Commits a transaction and returns __self__.
 */
static VALUE
database_commit(VALUE self)
{
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, char, did);

	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	EXEC SQL commit;
	return self;
}

static VALUE
database_transfail(VALUE self)
{
	database_rollback(self);
	return Qundef;
}

/*
 * call-seq:
 * db.transaction {|db| block }  => db
 *
 * Opens a transaction and executes <i>block</i>, passing __self__ as parameter.
 * If an exception is raised, the transaction is rolled back. It is commited
 * otherwise.
 *
 * Returns __self__.
 */
static VALUE
database_transaction(VALUE self)
{
	VALUE ret;
	EXEC SQL begin declare section;
		char *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, char, did);

	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	EXEC SQL commit;

	EXEC SQL begin work;
	ret = rb_rescue(rb_yield, self, database_transfail, self);
	if (ret == Qundef)
		rb_raise(rb_eRuntimeError, "Transaction rolled back");
	EXEC SQL commit;
	return self;
}

/*
 * call-seq:
 * db.prepare(query)  => statement
 *
 * Returns a <code>Statement</code> object based on <i>query</i>.
 * <i>query</i> may contain '?' placeholders for input parameters;
 * it must not be a query returning more than one row
 * (use <code>Database#cursor</code> instead.)
 */
static VALUE
database_prepare(VALUE self, VALUE query)
{
	VALUE argv[2];

	argv[0] = self; argv[1] = query;
	return rb_class_new_instance(2, argv, rb_cStatement);
}

/*
 * call-seq:
 * db.cursor(query, options = nil) => cursor
 *
 * Returns a <code>Cursor</code> object based on <i>query</i>.
 * <i>query</i> may contain '?' placeholders for input parameters.
 *
 * <i>options</i> must be a hash with the following possible keys:
 *
 *   :scroll => true or false
 *   :hold   => true or false
 *
 */
static VALUE
database_cursor(int argc, VALUE *argv, VALUE self)
{
	VALUE arg[3];

	arg[0] = self;
	rb_scan_args(argc, argv, "11", &arg[1], &arg[2]);
	return rb_class_new_instance(3, arg, rb_cCursor);
}

/*
 * call-seq:
 * db.columns(tablename)  => array
 *
 * Returns an array with information for every column of the given table.
 */
static VALUE
database_columns(VALUE self, VALUE tablename)
{
	VALUE v, column, result;
	char *stype;
	static char *stypes[] = {
		"CHAR", "SMALLINT", "INTEGER", "FLOAT", "SMALLFLOAT", "DECIMAL",
		"SERIAL", "DATE", "MONEY", "NULL", "DATETIME", "BYTE",
		"TEXT", "VARCHAR", "INTERVAL", "NCHAR", "NVARCHAR", "INT8",
		"SERIAL8", "SET", "MULTISET", "LIST", "UNNAMED ROW", "NAMED ROW",
		"VARIABLE-LENGTH OPAQUE TYPE"
	};

	static char *qualifiers[] = {
		"YEAR", "MONTH", "DAY", "HOUR", "MINUTE", "SECOND"
	};

	EXEC SQL begin declare section;
		char *did;
		char *tabname;
		int tabid, xid;
		varchar colname[129];
		short coltype, collength;
		char deftype[2];
		varchar defvalue[257];
	EXEC SQL end   declare section;

	Data_Get_Struct(self, char, did);

	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	tabname = StringValueCStr(tablename);

	EXEC SQL select tabid into :tabid from systables where tabname = :tabname;

	if (SQLCODE == SQLNOTFOUND)
		rb_raise(rb_eRuntimeError, "Table '%s' doesn't exist", tabname);

	result = rb_ary_new();

	EXEC SQL declare cur cursor for
		select colname, coltype, collength, extended_id, type, default, c.colno
		from syscolumns c, outer sysdefaults d
		where c.tabid = :tabid and c.tabid = d.tabid and c.colno = d.colno
		order by c.colno;

	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	EXEC SQL open cur;
	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	for(;;) {
		EXEC SQL fetch cur into :colname, :coltype, :collength, :xid,
			:deftype, :defvalue;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

		if (SQLCODE == SQLNOTFOUND)
			break;

		column = rb_hash_new();
		rb_hash_aset(column, sym_name, rb_str_new2(colname));
		rb_hash_aset(column, sym_type, INT2FIX(coltype));
		rb_hash_aset(column, sym_nullable, coltype&0x100? Qfalse: Qtrue);
		rb_hash_aset(column, sym_xid, INT2FIX(xid));

		if ((coltype&0xFF) < 23) {
			stype = coltype == 4118? stypes[23]: stypes[coltype&0xFF];
		}
		else {
			stype = stypes[24];
		}
		rb_hash_aset(column, sym_stype, rb_str_new2(stype));
		rb_hash_aset(column, sym_length, INT2FIX(collength));

		switch(coltype&0xFF) {
		case SQLVCHAR:
		case SQLNVCHAR:
		case SQLMONEY:
		case SQLDECIMAL:
			rb_hash_aset(column, sym_precision, INT2FIX(collength >> 8));
			rb_hash_aset(column, sym_scale, INT2FIX(collength&0xFF));
			break;
		case SQLDATE:
		case SQLDTIME:
		case SQLINTERVAL:
			rb_hash_aset(column, sym_length, INT2FIX(collength >> 8));
			rb_hash_aset(column, sym_precision, INT2FIX((collength&0xF0) >> 4));
			rb_hash_aset(column, sym_scale, INT2FIX(collength&0xF));
			break;
		default:
			rb_hash_aset(column, sym_precision, INT2FIX(0));
			rb_hash_aset(column, sym_scale, INT2FIX(0));
		}

		if (!deftype[0]) {
			v = Qnil;
		}
		else {
			switch(deftype[0]) {
			case 'C': {
				char current[28];
				snprintf(current, sizeof(current), "CURRENT %s TO %s",
					qualifiers[(collength&0xF0) >> 5],
					qualifiers[(collength&0xF)>>1]);
				v = rb_str_new2(current);
				break;
			}
			case 'L':
				switch (coltype & 0xFF) {
				case SQLCHAR:
				case SQLNCHAR:
				case SQLVCHAR:
				case SQLNVCHAR:
					v = rb_str_new2(defvalue);
					break;
				default: {
					char *s = defvalue;
					while(*s++ != ' ');
					if ((coltype&0xFF) == SQLFLOAT ||
						(coltype&0xFF) == SQLSMFLOAT ||
						(coltype&0xFF) == SQLMONEY ||
						(coltype&0xFF) == SQLDECIMAL)
						v = rb_float_new(atof(s));
					else
						v = LONG2FIX(atol(s));
				}
				}
				break;
			case 'N':
				v = rb_str_new2("NULL");
				break;
			case 'T':
				v = rb_str_new2("today");
				break;
			case 'U':
				v = rb_str_new2("user");
				break;
			case 'S':
			default: /* XXX */
				v = Qnil;
			}
		}
		rb_hash_aset(column, sym_default, v);
		rb_ary_push(result, column);
	}

	EXEC SQL close cur;
	EXEC SQL free cur;

	return result;
}

/* class Statement ------------------------------------------------------- */

static void
statement_mark(cursor_t *c)
{
	rb_gc_mark(c->db);
	if (c->array)
		rb_gc_mark(c->array);
	if (c->hash)
		rb_gc_mark(c->hash);
	if (c->field_names)
		rb_gc_mark(c->field_names);
}

static void
statement_free(void *p)
{
	EXEC SQL begin declare section;
		char *sid, *did;
	EXEC SQL end   declare section;

	free_input_slots(p);
	free_output_slots(p);

	did = ((cursor_t *)p)->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			goto exit;
		currentdid = did;
	}

	sid = ((cursor_t *)p)->stmt_id;
	EXEC SQL free :sid;

exit:
	xfree(p);
}

static VALUE
statement_alloc(VALUE klass)
{
	cursor_t *c;

	c = ALLOC(cursor_t);
	memset(c, 0, sizeof(cursor_t));
	return Data_Wrap_Struct(klass, statement_mark, statement_free, c);
}

/*
 * call-seq:
 * Statement.new(database, query) => statement
 *
 * Prepares <i>query</i> in the context of <i>database</i> and returns
 * a <code>Statement</code> object.
 */
static VALUE
statement_initialize(VALUE self, VALUE db, VALUE query)
{
	struct sqlda *output;
	cursor_t *c;
	EXEC SQL begin declare section;
		char *c_query, *sid, *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(db, char, did);
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	Data_Get_Struct(self, cursor_t, c);
	c->db = db;
	c->database_id = did;
	output = c->daOutput;
	snprintf(c->stmt_id, sizeof(c->stmt_id), "STMT%lX", self);
	sid = c->stmt_id;
	c_query = StringValueCStr(query);

	EXEC SQL prepare :sid from :c_query;
	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	alloc_input_slots(c, c_query);
	EXEC SQL describe :sid into output;
	c->daOutput = output;

	c->is_select = (SQLCODE == 0 || SQLCODE == SQ_EXECPROC);

	if (c->is_select)
		alloc_output_slots(c);
	else {
		xfree(c->daOutput);
		c->daOutput = NULL;
	}

	return self;
}


/*
 * call-seq:
 * stmt[*params]  => fixnum or hash
 *
 * Executes the previously prepared statement, binding <i>params</i> as
 * input parameters.
 *
 * Returns the record retrieved, in the case of a singleton select, or the
 * number of rows affected, in the case of any other statement.
 */
static VALUE
statement_call(int argc, VALUE *argv, VALUE self)
{
	struct sqlda *input, *output;
	cursor_t *c;
	EXEC SQL begin declare section;
		char *sid, *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, cursor_t, c);

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	output = c->daOutput;
	input = &c->daInput;
	sid = c->stmt_id;

	if (argc != input->sqld)
		rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
			argc, input->sqld);

	if (c->is_select) {
		if (argc) {
			bind_input_params(c, argv);
			EXEC SQL execute :sid into descriptor output
				using descriptor input;
			clean_input_slots(c);
		}
		else
			EXEC SQL execute :sid into descriptor output;

		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

		if (SQLCODE == SQLNOTFOUND)
			return Qnil;
		return make_result(c, rb_hash_new());
	}
	else {
		if (argc)  {
			bind_input_params(c, argv);
			EXEC SQL execute :sid using descriptor input;
			clean_input_slots(c);
		}
		else
			EXEC SQL execute :sid;
	}
	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	return INT2FIX(sqlca.sqlerrd[2]);
}

/*
 * call-seq:
 * stmt.drop
 *
 * Frees the statement and the memory associated with it.
 */
static VALUE
statement_drop(VALUE self)
{
	cursor_t *c;
	EXEC SQL begin declare section;
		char *sid, *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, cursor_t, c);
	free_input_slots(c);
	free_output_slots(c);

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			return Qnil;
		currentdid = did;
	}
	sid = c->stmt_id;
	EXEC SQL free :sid;

	return Qnil;
}


/* module SequentialCursor ----------------------------------------------- */

/* Decides whether to use an Array or a Hash, and instantiate a new
 * object or reuse an existing one.
 */
#define RECORD(c, type, bang, record) do {\
	if (type == T_ARRAY) {\
		if (bang) {\
			if (!c->array)\
				c->array = rb_ary_new2(c->daOutput->sqld);\
			record = c->array;\
		}\
		else\
			record = rb_ary_new2(c->daOutput->sqld);\
	}\
	else {\
		if (bang) {\
			if (!c->hash)\
				c->hash = rb_hash_new();\
			record = c->hash;\
		}\
		else\
			record = rb_hash_new();\
	}\
}while(0)

/*
 * Base function for fetch* methods, except *_many
 */
static VALUE
fetch(VALUE self, VALUE type, int bang)
{
	EXEC SQL begin declare section;
		char *cid, *did;
	EXEC SQL end   declare section;
	cursor_t *c;
	struct sqlda *output;
	VALUE record;

	Data_Get_Struct(self, cursor_t, c);
	if (!c->is_open)
		rb_raise(rb_eRuntimeError, "Open the cursor object first");

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	output = c->daOutput;
	cid = c->cursor_id;

	EXEC SQL fetch :cid using descriptor output;
	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	if (SQLCODE == SQLNOTFOUND)
		return Qnil;

	RECORD(c, type, bang, record);
	return make_result(c, record);
}

/*
 * call-seq:
 * cursor.fetch  => array or nil
 *
 * Fetches the next record.
 *
 * Returns the record fetched as an array, or nil if there are no
 * records left.
 */
static VALUE
seqcur_fetch(VALUE self)
{
	return fetch(self, T_ARRAY, 0);
}

/*
 * call-seq:
 * cursor.fetch!  => array or nil
 *
 * Fetches the next record, storing it in the same Array object every time
 * it is called.
 * 
 * Returns the record fetched as an array, or nil if there are no
 * records left.
 */
static VALUE
seqcur_fetch_bang(VALUE self)
{
	return fetch(self, T_ARRAY, 1);
}

/*
 * call-seq:
 * cursor.fetch_hash  => hash or nil
 *
 * Fetches the next record.
 *
 * Returns the record fetched as a hash, or nil if there are no
 * records left.
 */
static VALUE
seqcur_fetch_hash(VALUE self)
{
	return fetch(self, T_HASH, 0);
}

/*
 * call-seq:
 * cursor.fetch_hash!  => hash or nil
 *
 * Fetches the next record, storing it in the same Hash object every time
 * it is called.
 * 
 * Returns the record fetched as a hash, or nil if there are no
 * records left.
 */
static VALUE
seqcur_fetch_hash_bang(VALUE self)
{
	return fetch(self, T_HASH, 1);
}

/*
 * Base function for fetch*_many, fetch*_all and each_by methods
 */
static VALUE
fetch_many(VALUE self, VALUE n, VALUE type)
{
	EXEC SQL begin declare section;
		char *cid, *did;
	EXEC SQL end   declare section;
	cursor_t *c;
	struct sqlda *output;
	VALUE record, records;
	register long i, max;
	register int all = n == Qnil;

	Data_Get_Struct(self, cursor_t, c);
	if (!c->is_open)
		rb_raise(rb_eRuntimeError, "Open the cursor object first");

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	output = c->daOutput;
	cid = c->cursor_id;

	if (!all) {
		max = FIX2LONG(n);
		records = rb_ary_new2(max);
	}
	else {
		records = rb_ary_new();
	}

	for(i = 0; all || i < max; i++) {
		EXEC SQL fetch :cid using descriptor output;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

		if (SQLCODE == SQLNOTFOUND)
			break;

		if (type == T_ARRAY)
			record = rb_ary_new2(c->daOutput->sqld);
		else
			record = rb_hash_new();
		rb_ary_store(records, i, make_result(c, record));
	}

	return records;
}

/*
 * call-seq:
 * cursor.fetch_many(n)  => array
 *
 * Reads at most <i>n</i> records.
 *
 * Returns the records read as an array of arrays
 */
static VALUE
seqcur_fetch_many(VALUE self, VALUE n)
{
	return fetch_many(self, n, T_ARRAY);
}

/*
 * call-seq:
 * cursor.fetch_hash_many(n)  => array
 *
 * Reads at most <i>n</i> records.
 * Returns the records read as an array of hashes.
 */
static VALUE
seqcur_fetch_hash_many(VALUE self, VALUE n)
{
	return fetch_many(self, n, T_HASH);
}

/*
 * call-seq:
 * cursor.fetch_all  => array
 *
 * Returns all the records left as an array of arrays
 */
static VALUE
seqcur_fetch_all(VALUE self)
{
	return fetch_many(self, Qnil, T_ARRAY);
}

/*
 * call-seq:
 * cursor.fetch_hash_all  => array
 *
 * Returns all the records left as an array of hashes
 */
static VALUE
seqcur_fetch_hash_all(VALUE self)
{
	return fetch_many(self, Qnil, T_HASH);
}

/*
 * Base function for each* methods, except each*_by
 */
static VALUE
each(VALUE self, VALUE type, int bang)
{
	cursor_t *c;
	EXEC SQL begin declare section;
		char *cid, *did;
	EXEC SQL end   declare section;
	struct sqlda *output;
	VALUE record;

	Data_Get_Struct(self, cursor_t, c);
	if (!c->is_open)
		rb_raise(rb_eRuntimeError, "Open the cursor object first");

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	output = c->daOutput;
	cid = c->cursor_id;

	for(;;) {
		EXEC SQL fetch :cid using descriptor output;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

		if (SQLCODE == SQLNOTFOUND)
			return self;
		RECORD(c, type, bang, record);
		rb_yield(make_result(c, record));
	}
}

/*
 * Base function for each*_by methods
 */
static VALUE
each_by(VALUE self, VALUE n, VALUE type)
{
	VALUE records;

	for(;;) {
		records = fetch_many(self, n, type);
		if (RARRAY(records)->len == 0)
			return self;
		rb_yield(records);
	}
}

/*
 * call-seq:
 * cursor.each {|record| block } => cursor
 *
 * Iterates over the remaining records, passing each <i>record</i> to the
 * <i>block</i> as an array.
 *
 * Returns __self__.
 */
static VALUE
seqcur_each(VALUE self)
{
	return each(self, T_ARRAY, 0);
}

/*
 * call-seq:
 * cursor.each! {|record| block } => cursor
 *
 * Iterates over the remaining records, passing each <i>record</i> to the
 * <i>block</i> as an array. No new Array objects are created for each record.
 * The same Array object is reused in each call.
 *
 * Returns __self__.
 */
static VALUE
seqcur_each_bang(VALUE self)
{
	return each(self, T_ARRAY, 1);
}

/*
 * call-seq:
 * cursor.each_hash {|record| block } => cursor
 *
 * Iterates over the remaining records, passing each <i>record</i> to the
 * <i>block</i> as a hash.
 *
 * Returns __self__.
 */
static VALUE
seqcur_each_hash(VALUE self)
{
	return each(self, T_HASH, 0);
}

/*
 * call-seq:
 * cursor.each_hash! {|record| block } => cursor
 *
 * Iterates over the remaining records, passing each <i>record</i> to the
 * <i>block</i> as a hash. No new Hash objects are created for each record.
 * The same Hash object is reused in each call.
 *
 * Returns __self__.
 */
static VALUE
seqcur_each_hash_bang(VALUE self)
{
	return each(self, T_HASH, 1);
}

/*
 * call-seq:
 * cursor.each_by(n) {|records| block } => cursor
 *
 * Iterates over the remaining records, passing at most <i>n</i> <i>records</i>
 * to the <i>block</i> as arrays.
 *
 * Returns __self__.
 */
static VALUE
seqcur_each_by(VALUE self, VALUE n)
{
	return each_by(self, n, T_ARRAY);
}

/*
 * call-seq:
 * cursor.each_hash_by(n) {|records| block } => cursor
 *
 * Iterates over the remaining records, passing at most <i>n</i> <i>records</i>
 * to the <i>block</i> as hashes.
 *
 * Returns __self__.
 */
static VALUE
seqcur_each_hash_by(VALUE self, VALUE n)
{
	return each_by(self, n, T_HASH);
}

/* module InsertCursor --------------------------------------------------- */

/*
 * call-seq:
 * cursor.put(*params)
 *
 * Binds <i>params</i> as input parameters and executes the insert statement.
 * The records are not written immediatly to disk, unless the insert buffer
 * is full, the <code>flush</code> method is called, the cursor is closed or
 * the transaction is commited.
 */
static VALUE
inscur_put(int argc, VALUE *argv, VALUE self)
{
	struct sqlda *input;
	cursor_t *c;
	EXEC SQL begin declare section;
		char *cid, *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, cursor_t, c);
	if (!c->is_open)
		rb_raise(rb_eRuntimeError, "Open the cursor object first");

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	input = &c->daInput;
	cid = c->cursor_id;

	bind_input_params(c, argv);
	if (argc != input->sqld)
		rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
			argc, input->sqld);

	EXEC SQL put :cid using descriptor input;
	clean_input_slots(c);
	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	/* XXX 2-448, Guide to SQL: Sytax*/
	return INT2FIX(sqlca.sqlerrd[2]);
}

/*
 * call-seq:
 * cursor.flush => cursor
 *
 * Flushes the insert buffer, writing data to disk.
 *
 * Returns __self__.
 */
static VALUE
inscur_flush(VALUE self)
{
	cursor_t *c;
	EXEC SQL begin declare section;
		char *cid, *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, cursor_t, c);
	if (!c->is_open)
		rb_raise(rb_eRuntimeError, "Open the cursor object first");

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	cid = c->cursor_id;
	EXEC SQL flush :cid;
	return self;
}

/* module ScrollCursor --------------------------------------------------- */

/*
 * Provides the Array-like functionality for scroll cursors when using the
 * cursor[index] syntax
 */
static VALUE
scrollcur_entry(VALUE self, VALUE index, VALUE type, int bang)
{
	cursor_t *c;
	struct sqlda *output;
	VALUE record;
	EXEC SQL begin declare section;
		char *cid, *did;
		long pos;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, cursor_t, c);
	if (!c->is_open)
		rb_raise(rb_eRuntimeError, "Open the cursor object first");

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			return Qnil;
		currentdid = did;
	}

	output = c->daOutput;
	cid = c->cursor_id;

	if (NIL_P(index))
		EXEC SQL fetch current :cid using descriptor output;
	else if ((pos = NUM2LONG(index) + 1) > 0)
		EXEC SQL fetch absolute :pos :cid using descriptor output;
	else {
		EXEC SQL fetch last :cid;
		EXEC SQL fetch relative :pos :cid using descriptor output;
	}

	if (SQLCODE == SQLNOTFOUND)
		return Qnil;

	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	RECORD(c, type, bang, record);
	return make_result(c, record);
}

/*
 * Provides the Array-like functionality for scroll cursors when using the
 * cursor[start, length] syntax
 */
static VALUE
scrollcur_subseq(VALUE self, VALUE start, VALUE length, VALUE type)
{
	cursor_t *c;
	struct sqlda *output;
	VALUE first, records;
	EXEC SQL begin declare section;
		char *cid, *did;
		long pos;
	EXEC SQL end   declare section;

	first = scrollcur_entry(self, start, type, 0);
	if (NIL_P(first))
		return Qnil;

	pos = NUM2LONG(length) - 1;

	if (pos > 0) {
		length = LONG2NUM(pos);
		records = fetch_many(self, length, type);
	}
	else
		records = rb_ary_new();

	rb_ary_unshift(records, first);

	return records;
}

/*
 * Base function for slice and slice_hash methods
 */
static VALUE
slice(int argc, VALUE *argv, VALUE self, VALUE type)
{
	if (argc == 2) {
		if (NUM2LONG(argv[1]) <= 0)
			rb_raise(rb_eArgError, "length must be positive");
		return scrollcur_subseq(self, argv[0], argv[1], type);
	}
	if (argc != 1)
		rb_scan_args(argc, argv, "11", 0, 0);

	return scrollcur_entry(self, argv[0], type, 0);
}

/*
 * call-seq:
 *
 * cursor[index]  => array or nil
 * cursor[start, length]  => array or nil
 * cursor.slice(index)  => array or nil
 * cursor.slice(start, length)  => array or nil
 *
 * Returns the record at _index_, or returns a subarray starting at _start_
 * and continuing for _length_ records. Negative indices count backward from
 * the end of the cursor (-1 is the last element). Returns nil if the
 * (starting) index is out of range.
 *
 * <b>Warning</b>: if the (starting) index is negative and out of range, the
 * position in the cursor is set to the last record. Otherwise the current
 * position in the cursor is preserved.
 */
static VALUE
scrollcur_slice(int argc, VALUE *argv, VALUE self)
{
	return slice(argc, argv, self, T_ARRAY);
}

/*
 * call-seq:
 * cursor.slice!(index)  => array or nil
 *
 * Returns the record at _index_. Negative indices count backward from
 * the end of the cursor (-1 is the last element). Returns nil if the index
 * is out of range.
 *
 * Stores the record fetched always in the same Array object.
 *
 * <b>Warning</b>: if the index is negative and out of range, the
 * position in the cursor is set to the last record. Otherwise the current
 * position in the cursor is preserved.
 */
static VALUE
scrollcur_slice_bang(VALUE self, VALUE index)
{
	return scrollcur_entry(self, index, T_ARRAY, 1);
}

/*
 * call-seq:
 *
 * cursor.slice_hash(index)  => hash or nil
 * cursor.slice_hash(start, length)  => array or nil
 *
 * Returns the record at _index_, or returns a subarray starting at _start_
 * and continuing for _length_ records. Negative indices count backward from
 * the end of the cursor (-1 is the last element). Returns nil if the
 * (starting) index is out of range.
 *
 * <b>Warning</b>: if the (starting) index is negative and out of range, the
 * position in the cursor is set to the last record. Otherwise the current
 * position in the cursor is preserved.
 */
static VALUE
scrollcur_slice_hash(int argc, VALUE *argv, VALUE self)
{
	return slice(argc, argv, self, T_HASH);
}

/*
 * call-seq:
 * cursor.slice_hash!(index)  => hash or nil
 *
 * Returns the record at _index_. Negative indices count backward from
 * the end of the cursor (-1 is the last element). Returns nil if the index
 * is out of range.
 *
 * Stores the record fetched always in the same Hash object.
 *
 * <b>Warning</b>: if the index is negative and out of range, the
 * position in the cursor is set to the last record. Otherwise the current
 * position in the cursor is preserved.
 */
static VALUE
scrollcur_slice_hash_bang(VALUE self, VALUE index)
{
	return scrollcur_entry(self, index, T_HASH, 1);
}

/*
 * Base function for prev* and next* methods
 */
static VALUE
scrollcur_rel(int argc, VALUE *argv, VALUE self, int dir, VALUE type, int bang)
{
	cursor_t *c;
	struct sqlda *output;
	VALUE offset, record;
	EXEC SQL begin declare section;
		char *cid, *did;
		long pos;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, cursor_t, c);
	if (!c->is_open)
		rb_raise(rb_eRuntimeError, "Open the cursor object first");

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			return Qnil;
		currentdid = did;
	}

	rb_scan_args(argc, argv, "01", &offset);
	pos = dir*(NIL_P(offset)? 1: NUM2LONG(offset));

	output = c->daOutput;
	cid = c->cursor_id;
	EXEC SQL fetch relative :pos :cid using descriptor output;

	if (SQLCODE == SQLNOTFOUND)
		return Qnil;

	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	RECORD(c, type, bang, record);
	return make_result(c, record);
}

/* call-seq:
 * cursor.prev(offset = 1)  => array or nil
 *
 * Returns the previous _offset_<sup>th</sup> record. Negative indices count
 * forward from the current position. Returns nil if the _offset_ is out of
 * range.
 */
static VALUE
scrollcur_prev(int argc, VALUE *argv, VALUE self)
{
	return scrollcur_rel(argc, argv, self, -1, T_ARRAY, 0);
}

/* call-seq:
 * cursor.prev!(offset = 1)  => array or nil
 *
 * Returns the previous _offset_<sup>th</sup> record. Negative indices count
 * forward from the current position. Returns nil if the _offset_ is out of
 * range.
 *
 * Stores the record fetched always in the same Array object.
 */
static VALUE
scrollcur_prev_bang(int argc, VALUE *argv, VALUE self)
{
	return scrollcur_rel(argc, argv, self, -1, T_ARRAY, 1);
}

/* call-seq:
 * cursor.prev_hash(offset = 1)  => hash or nil
 *
 * Returns the previous _offset_<sup>th</sup> record. Negative indices count
 * forward from the current position. Returns nil if the _offset_ is out of
 * range.
 */
static VALUE
scrollcur_prev_hash(int argc, VALUE *argv, VALUE self)
{
	return scrollcur_rel(argc, argv, self, -1, T_HASH, 0);
}

/* call-seq:
 * cursor.prev_hash!(offset = 1)  => hash or nil
 *
 * Returns the previous _offset_<sup>th</sup> record. Negative indices count
 * forward from the current position. Returns nil if the _offset_ is out of
 * range.
 *
 * Stores the record fetched always in the same Hash object.
 */
static VALUE
scrollcur_prev_hash_bang(int argc, VALUE *argv, VALUE self)
{
	return scrollcur_rel(argc, argv, self, -1, T_HASH, 1);
}

/* call-seq:
 * cursor.next(offset = 1)  => array or nil
 *
 * Returns the next _offset_<sup>th</sup> record. Negative indices count
 * backward from the current position. Returns nil if the _offset_ is out of
 * range.
 */
static VALUE
scrollcur_next(int argc, VALUE *argv, VALUE self)
{
	return scrollcur_rel(argc, argv, self, 1, T_ARRAY, 0);
}

/* call-seq:
 * cursor.next!(offset = 1)  => array or nil
 *
 * Returns the next _offset_<sup>th</sup> record. Negative indices count
 * backward from the current position. Returns nil if the _offset_ is out of
 * range.
 *
 * Stores the record fetched always in the same Array object.
 */
static VALUE
scrollcur_next_bang(int argc, VALUE *argv, VALUE self)
{
	return scrollcur_rel(argc, argv, self, 1, T_ARRAY, 1);
}

/* call-seq:
 * cursor.next_hash(offset = 1)  => hash or nil
 *
 * Returns the next _offset_<sup>th</sup> record. Negative indices count
 * backward from the current position. Returns nil if the _offset_ is out of
 * range.
 */
static VALUE
scrollcur_next_hash(int argc, VALUE *argv, VALUE self)
{
	return scrollcur_rel(argc, argv, self, 1, T_HASH, 0);
}

/* call-seq:
 * cursor.next_hash!(offset = 1)  => hash or nil
 *
 * Returns the next _offset_<sup>th</sup> record. Negative indices count
 * backward from the current position. Returns nil if the _offset_ is out of
 * range.
 *
 * Stores the record fetched always in the same Hash object.
 */
static VALUE
scrollcur_next_hash_bang(int argc, VALUE *argv, VALUE self)
{
	return scrollcur_rel(argc, argv, self, 1, T_HASH, 1);
}

/*
 * call-seq:
 * cursor.first  => array or nil
 *
 * Returns the first record of the cursor. If the cursor is empty,
 * returns nil.
 */
static VALUE
scrollcur_first(VALUE self)
{
	return scrollcur_entry(self, INT2FIX(0), T_ARRAY, 0);
}

/*
 * call-seq:
 * cursor.first!  => array or nil
 *
 * Returns the first record of the cursor. If the cursor is empty,
 * returns nil.
 *
 * Stores the record fetched always in the same Array object.
 */
static VALUE
scrollcur_first_bang(VALUE self)
{
	return scrollcur_entry(self, INT2FIX(0), T_ARRAY, 1);
}

/*
 * call-seq:
 * cursor.first_hash  => hash or nil
 *
 * Returns the first record of the cursor. If the cursor is empty,
 * returns nil.
 */
static VALUE
scrollcur_first_hash(VALUE self)
{
	return scrollcur_entry(self, INT2FIX(0), T_HASH, 0);
}

/*
 * call-seq:
 * cursor.first_hash!  => hash or nil
 *
 * Returns the first record of the cursor. If the cursor is empty,
 * returns nil.
 *
 * Stores the record fetched always in the same Hash object.
 */
static VALUE
scrollcur_first_hash_bang(VALUE self)
{
	return scrollcur_entry(self, INT2FIX(0), T_HASH, 1);
}

/*
 * call-seq:
 * cursor.last  => array or nil
 *
 * Returns the last record of the cursor. If the cursor is empty,
 * returns nil.
 */
static VALUE
scrollcur_last(VALUE self)
{
	return scrollcur_entry(self, INT2FIX(-1), T_ARRAY, 0);
}

/*
 * call-seq:
 * cursor.last!  => array or nil
 *
 * Returns the last record of the cursor. If the cursor is empty,
 * returns nil.
 *
 * Stores the record fetched always in the same Array object.
 */
static VALUE
scrollcur_last_bang(VALUE self)
{
	return scrollcur_entry(self, INT2FIX(-1), T_ARRAY, 1);
}

/*
 * call-seq:
 * cursor.last_hash  => hash or nil
 *
 * Returns the last record of the cursor. If the cursor is empty,
 * returns nil.
 */
static VALUE
scrollcur_last_hash(VALUE self)
{
	return scrollcur_entry(self, INT2FIX(-1), T_HASH, 0);
}

/*
 * call-seq:
 * cursor.last_hash!  => hash or nil
 *
 * Returns the last record of the cursor. If the cursor is empty,
 * returns nil.
 *
 * Stores the record fetched always in the same Hash object.
 */
static VALUE
scrollcur_last_hash_bang(VALUE self)
{
	return scrollcur_entry(self, INT2FIX(-1), T_HASH, 1);
}

/*
 * call-seq:
 * cursor.current  => array or nil
 *
 * Returns the current record of the cursor. If the cursor is empty,
 * returns nil.
 */
static VALUE
scrollcur_current(VALUE self)
{
	return scrollcur_entry(self, Qnil, T_ARRAY, 0);
}

/*
 * call-seq:
 * cursor.current!  => array or nil
 *
 * Returns the current record of the cursor. If the cursor is empty,
 * returns nil.
 *
 * Stores the record fetched always in the same Array object.
 */
static VALUE
scrollcur_current_bang(VALUE self)
{
	return scrollcur_entry(self, Qnil, T_ARRAY, 1);
}

/*
 * call-seq:
 * cursor.current_hash  => hash or nil
 *
 * Returns the current record of the cursor. If the cursor is empty,
 * returns nil.
 */
static VALUE
scrollcur_current_hash(VALUE self)
{
	return scrollcur_entry(self, Qnil, T_HASH, 0);
}

/*
 * call-seq:
 * cursor.current_hash!  => hash or nil
 *
 * Returns the current record of the cursor. If the cursor is empty,
 * returns nil.
 *
 * Stores the record fetched always in the same Hash object.
 */
static VALUE
scrollcur_current_hash_bang(VALUE self)
{
	return scrollcur_entry(self, Qnil, T_HASH, 1);
}

/* class Cursor ---------------------------------------------------------- */
static void
cursor_close_or_free(cursor_t *c, short op)
{
	EXEC SQL begin declare section;
		char *cid, *sid, *did;
	EXEC SQL end   declare section;

	if (op == 1 && !c->is_open)
		return;

	c->is_open = 0;
	if (op == 1)
		clean_input_slots(c);
	else {
		free_input_slots(c);
		free_output_slots(c);
	}

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			return;
		currentdid = did;
	}

	cid = c->cursor_id;
	EXEC SQL close :cid;

	if (op == 2) {
		sid = c->stmt_id;
		EXEC SQL free :cid; EXEC SQL free :sid;
	}
}

static void
cursor_mark(cursor_t *c)
{
	rb_gc_mark(c->db);
	if (c->array)
		rb_gc_mark(c->array);
	if (c->hash)
		rb_gc_mark(c->hash);
	if (c->field_names)
		rb_gc_mark(c->field_names);
}

static void
cursor_free(void *p)
{
	cursor_close_or_free(p, 2);
	xfree(p);
}

static VALUE
cursor_alloc(VALUE klass)
{
	cursor_t *c;

	c = ALLOC(cursor_t);
	memset(c, 0, sizeof(cursor_t));
	return Data_Wrap_Struct(klass, cursor_mark, cursor_free, c);
}

/*
 * call-seq:
 * Cursor.new(database, query, options) => cursor
 *
 * Prepares <i>query</i> in the context of <i>database</i> with <i>options</i>
 * and returns a <code>Cursor</code> object.
 *
 * <i>options</i> can be nil or a hash with the following possible keys:
 *
 *   :scroll => true or false
 *   :hold => true or false
 */
static VALUE
cursor_initialize(VALUE self, VALUE db, VALUE query, VALUE options)
{
	VALUE scroll, hold;
	struct sqlda *output;
	cursor_t *c;
	EXEC SQL begin declare section;
		char *c_query;
		char *cid, *sid, *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(db, char, did);

	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	Data_Get_Struct(self, cursor_t, c);
	c->db = db;
	c->database_id = did;
	scroll = hold = Qfalse;
	snprintf(c->cursor_id, sizeof(c->cursor_id), "CUR%lX", self);
	snprintf(c->stmt_id, sizeof(c->stmt_id), "STMT%lX", self);
	cid = c->cursor_id; sid = c->stmt_id;
	c_query = StringValueCStr(query);

	if (RTEST(options)) {
		scroll = rb_hash_aref(options, sym_scroll);
		hold = rb_hash_aref(options, sym_hold);
	}

	EXEC SQL prepare :sid from :c_query;
	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	if (RTEST(scroll) && RTEST(hold))
		EXEC SQL declare :cid scroll cursor with hold for :sid;
	else if (RTEST(hold))
		EXEC SQL declare :cid cursor with hold for :sid;
	else if (RTEST(scroll))
		EXEC SQL declare :cid scroll cursor for :sid;
	else
		EXEC SQL declare :cid cursor for :sid;

	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	alloc_input_slots(c, c_query);
	EXEC SQL describe :sid into output;
	c->daOutput = output;

	c->is_select = (SQLCODE == 0 || SQLCODE == SQ_EXECPROC);

	if (c->is_select) {
		alloc_output_slots(c);
		rb_extend_object(self, rb_mSequentialCursor);
		if (scroll)
			rb_extend_object(self, rb_mScrollCursor);
	}
	else {
		xfree(c->daOutput);
		c->daOutput = NULL;
		rb_extend_object(self, rb_mInsertCursor);
	}
	return self;
}

/*
 * call-seq:
 * cursor.id  => string
 *
 * Returns the cursor ID
 */
static VALUE
cursor_id(VALUE self)
{
	cursor_t *c;

	Data_Get_Struct(self, cursor_t, c);
	return rb_str_new2(c->cursor_id);
}

/*
 * call-seq:
 * cursor.open(*params)  => cursor
 *
 * Executes the previously prepared select statement, binding <i>params</i> as
 * input parameters.
 *
 * Returns __self__.
 */
static VALUE
cursor_open(int argc, VALUE *argv, VALUE self)
{
	struct sqlda *input;
	cursor_t *c;
	EXEC SQL begin declare section;
		char *cid, *did;
	EXEC SQL end   declare section;

	Data_Get_Struct(self, cursor_t, c);

	if (c->is_open)
		return self;

	did = c->database_id;
	if (currentdid != did) {
		EXEC SQL set connection :did;
		if (SQLCODE < 0)
			rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);
		currentdid = did;
	}

	input = &c->daInput;
	cid = c->cursor_id;

	if (c->is_select) {
		if (argc != input->sqld) {
			rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
				argc, input->sqld);
		}
		if (argc) {
			bind_input_params(c, argv);
			EXEC SQL open :cid using descriptor input
				with reoptimization;
			clean_input_slots(c);
		}
		else
			EXEC SQL open :cid with reoptimization;
	}
	else
		EXEC SQL open :cid;

	if (SQLCODE < 0)
		rb_raise(rb_eRuntimeError, "Informix Error: %d", SQLCODE);

	c->is_open = 1;
	return self;
}

/*
 * call-seq:
 * cursor.close  => cursor
 *
 * Closes the cursor and returns __self__.
 */
static VALUE
cursor_close(VALUE self)
{
	cursor_t *c;

	Data_Get_Struct(self, cursor_t, c);
	cursor_close_or_free(c, 1);
	return self;
}

/*
 * call-seq:
 * cursor.drop => nil
 *
 * Closes the cursor and frees the memory associated with it. The cursor
 * cannot be opened again.
 */
static VALUE
cursor_drop(VALUE self)
{
	cursor_t *c;

	Data_Get_Struct(self, cursor_t, c);
	cursor_close_or_free(c, 2);

	return Qnil;
}

/* Entry point ------------------------------------------------------------ */

void Init_informix(void)
{
	/* module Informix ---------------------------------------------------- */
	rb_mInformix = rb_define_module("Informix");
	rb_mScrollCursor = rb_define_module_under(rb_mInformix, "ScrollCursor");
	rb_mInsertCursor = rb_define_module_under(rb_mInformix, "InsertCursor");
	rb_define_module_function(rb_mInformix, "connect", informix_connect, -1);

	/* class Slob --------------------------------------------------------- */
	rb_cSlob = rb_define_class_under(rb_mInformix, "Slob", rb_cObject);
	rb_define_alloc_func(rb_cSlob, slob_alloc);
	rb_define_method(rb_cSlob, "initialize", slob_initialize, -1);
	rb_define_method(rb_cSlob, "open", slob_open, -1);
	rb_define_method(rb_cSlob, "close", slob_close, 0);
	rb_define_method(rb_cSlob, "read", slob_read, 1);
	rb_define_method(rb_cSlob, "write", slob_write, 1);
	rb_define_method(rb_cSlob, "seek", slob_seek, 2);
	rb_define_method(rb_cSlob, "tell", slob_tell, 0);
	rb_define_method(rb_cSlob, "truncate", slob_truncate, 1);

	rb_define_const(rb_cSlob, "CLOB", INT2FIX(XID_CLOB));
	rb_define_const(rb_cSlob, "BLOB", INT2FIX(XID_BLOB));

	#define DEF_SLOB_CONST(k) rb_define_const(rb_cSlob, #k, INT2FIX(LO_##k))

	DEF_SLOB_CONST(RDONLY);
	DEF_SLOB_CONST(DIRTY_READ);
	DEF_SLOB_CONST(WRONLY);
	DEF_SLOB_CONST(APPEND);
	DEF_SLOB_CONST(RDWR);
	DEF_SLOB_CONST(BUFFER);
	DEF_SLOB_CONST(NOBUFFER);
	DEF_SLOB_CONST(LOCKALL);
	DEF_SLOB_CONST(LOCKRANGE);
	DEF_SLOB_CONST(SEEK_SET);
	DEF_SLOB_CONST(SEEK_CUR);
	DEF_SLOB_CONST(SEEK_END);

	/* class Database ----------------------------------------------------- */
	rb_cDatabase = rb_define_class_under(rb_mInformix, "Database", rb_cObject);
	rb_define_alloc_func(rb_cDatabase, database_alloc);
	rb_define_method(rb_cDatabase, "initialize", database_initialize, -1);
	rb_define_alias(rb_cDatabase, "open", "initialize");
	rb_define_method(rb_cDatabase, "close", database_close, 0);
	rb_define_method(rb_cDatabase, "immediate", database_immediate, 1);
	rb_define_alias(rb_cDatabase, "do", "immediate");
	rb_define_method(rb_cDatabase, "rollback", database_rollback, 0);
	rb_define_method(rb_cDatabase, "commit", database_commit, 0);
	rb_define_method(rb_cDatabase, "transaction", database_transaction, 0);
	rb_define_method(rb_cDatabase, "prepare", database_prepare, 1);
	rb_define_method(rb_cDatabase, "columns", database_columns, 1);
	rb_define_method(rb_cDatabase, "cursor", database_cursor, -1);

	/* class Statement ---------------------------------------------------- */
	rb_cStatement = rb_define_class_under(rb_mInformix, "Statement", rb_cObject);
	rb_define_alloc_func(rb_cStatement, statement_alloc);
	rb_define_method(rb_cStatement, "initialize", statement_initialize, 2);
	rb_define_method(rb_cStatement, "[]", statement_call, -1);
	rb_define_alias(rb_cStatement, "call", "[]");
	rb_define_alias(rb_cStatement, "execute", "[]");
	rb_define_method(rb_cStatement, "drop", statement_drop, 0);

	/* module SequentialCursor -------------------------------------------- */
	rb_mSequentialCursor = rb_define_module_under(rb_mInformix, "SequentialCursor");
	rb_define_method(rb_mSequentialCursor, "fetch", seqcur_fetch, 0);
	rb_define_method(rb_mSequentialCursor, "fetch!", seqcur_fetch_bang, 0);
	rb_define_method(rb_mSequentialCursor, "fetch_hash", seqcur_fetch_hash, 0);
	rb_define_method(rb_mSequentialCursor, "fetch_hash!", seqcur_fetch_hash_bang, 0);
	rb_define_method(rb_mSequentialCursor, "fetch_many", seqcur_fetch_many, 1);
	rb_define_method(rb_mSequentialCursor, "fetch_hash_many", seqcur_fetch_hash_many, 1);
	rb_define_method(rb_mSequentialCursor, "fetch_all", seqcur_fetch_all, 0);
	rb_define_method(rb_mSequentialCursor, "fetch_hash_all", seqcur_fetch_hash_all, 0);
	rb_define_method(rb_mSequentialCursor, "each", seqcur_each, 0);
	rb_define_method(rb_mSequentialCursor, "each!", seqcur_each_bang, 0);
	rb_define_method(rb_mSequentialCursor, "each_hash", seqcur_each_hash, 0);
	rb_define_method(rb_mSequentialCursor, "each_hash!", seqcur_each_hash_bang, 0);
	rb_define_method(rb_mSequentialCursor, "each_by", seqcur_each_by, 1);
	rb_define_method(rb_mSequentialCursor, "each_hash_by", seqcur_each_hash_by, 1);

	/* InsertCursor ------------------------------------------------------- */
	rb_define_method(rb_mInsertCursor, "put", inscur_put, -1);
	rb_define_method(rb_mInsertCursor, "flush", inscur_flush, 0);

	/* ScrollCursor ------------------------------------------------------- */
	rb_define_method(rb_mScrollCursor, "[]", scrollcur_slice, -1);
	rb_define_alias(rb_mScrollCursor, "slice", "[]");
	rb_define_method(rb_mScrollCursor, "slice!", scrollcur_slice_bang, 1);
	rb_define_method(rb_mScrollCursor, "slice_hash", scrollcur_slice_hash, -1);
	rb_define_method(rb_mScrollCursor, "slice_hash!", scrollcur_slice_hash_bang, 1);
	rb_define_method(rb_mScrollCursor, "prev", scrollcur_prev, -1);
	rb_define_method(rb_mScrollCursor, "prev!", scrollcur_prev_bang, -1);
	rb_define_method(rb_mScrollCursor, "prev_hash", scrollcur_prev_hash, -1);
	rb_define_method(rb_mScrollCursor, "prev_hash!", scrollcur_prev_hash_bang, -1);
	rb_define_method(rb_mScrollCursor, "next", scrollcur_next, -1);
	rb_define_method(rb_mScrollCursor, "next!", scrollcur_next_bang, -1);
	rb_define_method(rb_mScrollCursor, "next_hash", scrollcur_next_hash, -1);
	rb_define_method(rb_mScrollCursor, "next_hash!", scrollcur_next_hash_bang, -1);
	rb_define_method(rb_mScrollCursor, "first", scrollcur_first, 0);
	rb_define_method(rb_mScrollCursor, "first!", scrollcur_first_bang, 0);
	rb_define_method(rb_mScrollCursor, "first_hash", scrollcur_first_hash, 0);
	rb_define_method(rb_mScrollCursor, "first_hash!", scrollcur_first_hash_bang, 0);
	rb_define_method(rb_mScrollCursor, "last", scrollcur_last, 0);
	rb_define_method(rb_mScrollCursor, "last!", scrollcur_last_bang, 0);
	rb_define_method(rb_mScrollCursor, "last_hash", scrollcur_last_hash, 0);
	rb_define_method(rb_mScrollCursor, "last_hash!", scrollcur_last_hash_bang, 0);
	rb_define_method(rb_mScrollCursor, "current", scrollcur_current, 0);
	rb_define_method(rb_mScrollCursor, "current!", scrollcur_current_bang, 0);
	rb_define_method(rb_mScrollCursor, "current_hash", scrollcur_current_hash, 0);
	rb_define_method(rb_mScrollCursor, "current_hash!", scrollcur_current_hash_bang, 0);

	/* class Cursor ------------------------------------------------------- */
	rb_cCursor = rb_define_class_under(rb_mInformix, "Cursor", rb_cObject);
	rb_define_alloc_func(rb_cCursor, cursor_alloc);
	rb_define_method(rb_cCursor, "initialize", cursor_initialize, 3);
	rb_define_method(rb_cCursor, "id", cursor_id, 0);
	rb_define_method(rb_cCursor, "open", cursor_open, -1);
	rb_define_method(rb_cCursor, "close", cursor_close, 0);
	rb_define_method(rb_cCursor, "drop", cursor_drop, 0);

	/* Global constants --------------------------------------------------- */
	rb_require("date");
	rb_cDate = rb_const_get(rb_cObject, rb_intern("Date"));

	/* Global symbols ----------------------------------------------------- */
	s_read = rb_intern("read");
	s_new = rb_intern("new");
	s_utc = rb_intern("utc");
	s_day = rb_intern("day");
	s_month = rb_intern("month");
	s_year = rb_intern("year");
	s_hour = rb_intern("hour");
	s_min = rb_intern("min");
	s_sec = rb_intern("sec");
	s_usec = rb_intern("usec");
	s_to_s = rb_intern("to_s");
	s_to_i = rb_intern("to_i");

	sym_name = ID2SYM(rb_intern("name"));
	sym_type = ID2SYM(rb_intern("type"));
	sym_nullable = ID2SYM(rb_intern("nullable"));
	sym_stype = ID2SYM(rb_intern("stype"));
	sym_length = ID2SYM(rb_intern("length"));
	sym_precision = ID2SYM(rb_intern("precision"));
	sym_scale = ID2SYM(rb_intern("scale"));
	sym_default = ID2SYM(rb_intern("default"));
	sym_xid = ID2SYM(rb_intern("xid"));

	sym_scroll = ID2SYM(rb_intern("scroll"));
	sym_hold = ID2SYM(rb_intern("hold"));

	sym_col_info = ID2SYM(rb_intern("col_info"));
	sym_sbspace = ID2SYM(rb_intern("sbspace"));
	sym_estbytes = ID2SYM(rb_intern("estbytes"));
	sym_extsz = ID2SYM(rb_intern("extsz"));
	sym_createflags = ID2SYM(rb_intern("createflags"));
	sym_openflags = ID2SYM(rb_intern("openflags"));
}
