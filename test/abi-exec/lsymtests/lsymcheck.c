/* lsymcheck MODULE: checks the module elf2mod made from lsym.S.  Every
   reference to btext, bname and etext must arrive at the module's start
   (offset 0), its name and its end: PC-relative ones directly
   (lea d(pc),An), far ones through the jump table (movea.l d(a6),An, then
   the entry's address in the initialized data), and the pointers in the
   data.  The end is etext as both Microware linkers make it: the module's
   size, plus 4 when exactly one of the two initialized data reference
   tables (pointers to code, pointers to data) has entries.  Prints each
   check; exits with the number of failures.  */

#include <stdio.h>
#include <stdlib.h>

static unsigned char *m;
static long msize;

static unsigned long u32(long o)
{
	return (unsigned long)m[o] << 24 | (unsigned long)m[o + 1] << 16 | m[o + 2] << 8 | m[o + 3];
}

static int s16(long o)
{
	int v = m[o] << 8 | m[o + 1];
	return v >= 0x8000 ? v - 0x10000 : v;
}

static unsigned long idoff, idlen;
static long idbytes;

/* The long at offset DOFF of the data area, from the initialized data.  */
static long data_long(long doff)
{
	long o = idbytes + doff - (long)idoff;
	if (doff < (long)idoff || doff + 4 > (long)(idoff + idlen))
		return -1;
	return (long)u32(o);
}

/* The number of entries in the reference table at offset *AT (groups of a
   word, a count and the count's offsets, ended by a zero count); *AT moves
   past it.  */
static long table_entries(long *at)
{
	long n = 0, count;
	while ((count = m[*at + 2] << 8 | m[*at + 3]) != 0) {
		n += count;
		*at += 4 + 2 * count;
	}
	*at += 4;
	return n;
}

int main(int argc, char **argv)
{
	FILE *f;
	long size, name, itext, i, etext, refs, ncode, ndata;
	int fails = 0;
	static const struct { long at; const char *sym; } code[] = {
		{ 0, "btext" }, { 4, "bname" }, { 8, "etext" }, { 12, "btext" },
		{ 40016, "btext" }, { 40020, "bname" }, { 40024, "etext" },
	};
	static const char *const data[] = { "btext", "bname", "etext", "bname" };

	if (argc != 2 || !(f = fopen(argv[1], "rb"))) {
		fprintf(stderr, "usage: lsymcheck MODULE\n");
		return 2;
	}
	m = malloc(1 << 20);
	msize = (long)fread(m, 1, 1 << 20, f);
	fclose(f);
	size = (long)u32(4);
	name = (long)u32(12);
	itext = (long)u32(0x30);		/* _start is the first code */
	idbytes = (long)u32(0x40) + 8;
	idoff = u32(idbytes - 8);
	idlen = u32(idbytes - 4);
	if (size != msize) {
		printf("FAIL: module size %ld, file %ld\n", size, msize);
		return 1;
	}

	refs = (long)u32(0x44);
	ncode = table_entries(&refs);
	ndata = table_entries(&refs);
	etext = size + ((ncode > 0) != (ndata > 0) ? 4 : 0);

/* btext: 0, bname: the name's offset, etext: as above.  */
#define WANT(sym) ((sym)[0] == 'e' ? etext : (sym)[1] == 'n' ? name : 0)
	for (i = 0; i < (long)(sizeof code / sizeof code[0]); i++) {
		long p = itext + code[i].at, got;
		int op = m[p] << 8 | m[p + 1];
		const char *how;
		if ((op & 0xF1FF) == 0x41FA) {
			how = "lea d(pc)";
			got = p + 2 + s16(p + 2);
		} else if ((op & 0xF1FF) == 0x206E) {
			how = "jump table";
			got = data_long(s16(p + 2) + 0x8000);
		} else {
			how = "?";
			got = -1;
		}
		if (got != WANT(code[i].sym))
			fails++;
		printf("%s: code +%ld %s via %s: %ld (want %ld)\n", got == WANT(code[i].sym) ? "ok" : "FAIL",
		       code[i].at, code[i].sym, how, got, (long)WANT(code[i].sym));
	}
	for (i = 0; i < 4; i++) {
		long got = data_long(4 * i);
		if (got != WANT(data[i]))
			fails++;
		printf("%s: data %ld %s pointer: %ld (want %ld)\n", got == WANT(data[i]) ? "ok" : "FAIL",
		       4 * i, data[i], got, (long)WANT(data[i]));
	}
	return fails;
}
