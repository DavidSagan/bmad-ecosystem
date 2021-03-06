/*
 o-----------------------------------------------------------------------------o
 |
 | TPSA I/O module implementation
 |
 | Methodical Accelerator Design - Copyright (c) 2016+
 | Support: http://cern.ch/mad  - mad at cern.ch
 | Authors: L. Deniau, laurent.deniau at cern.ch
 |          C. Tomoiaga
 | Contrib: -
 |
 o-----------------------------------------------------------------------------o
 | You can redistribute this file and/or modify it under the terms of the GNU
 | General Public License GPLv3 (or later), as published by the Free Software
 | Foundation. This file is distributed in the hope that it will be useful, but
 | WITHOUT ANY WARRANTY OF ANY KIND. See http://gnu.org/licenses for details.
 o-----------------------------------------------------------------------------o
*/

#include <math.h>
#include <ctype.h>
#include <string.h>
#include <assert.h>

#include "mad_mem.h"
#include "mad_desc_impl.h"

#ifdef    MAD_CTPSA_IMPL
#include "mad_ctpsa_impl.h"
#define  SPC "                       "
#else
#include "mad_tpsa_impl.h"
#define  SPC
#endif

// --- local ------------------------------------------------------------------o

static inline int
skip_line(FILE *stream)
{
  int c;
  while ((c = fgetc(stream)) != '\n' && c != EOF) ;
  return c;
}

static inline void
print_ords_sm(int n, const ord_t ords[n], FILE *stream)
{
  assert(ords && stream);
  for (int i=0; i < n; i++)
    if (ords[i]) fprintf(stream, "  %d^%hhu", i+1, ords[i]);
}

static inline void
print_ords(int n, const ord_t ords[n], FILE *stream)
{
  assert(ords && stream);
  for (int i=0; i < n-1; i += 2)
    fprintf(stream, "  %hhu %hhu", ords[i], ords[i+1]);
  if (n % 2)
    fprintf(stream, "  %hhu"     , ords[n-1]);
}

static inline void
read_ords(int n, ord_t ords[n], FILE *stream)
{
  assert(ords && stream);
  idx_t idx;
  ord_t ord;
  char  chr;

  mad_mono_fill(n, ords, 0);
  for (int i=0; i < n; i++) {
    int cnt = fscanf(stream, " %d%c%hhu", &idx, &chr, &ord);

    if (cnt == 3 && chr == '^') {
      ensure(0 < idx && idx <= n, "invalid index (expecting 0 < %d <= %d)", idx, n);
      ords[idx-1] = ord, i = idx-1;
    } else
    if (cnt == 3 && chr == ' ') {
      ords[i] = idx, ords[++i] = ord;
    } else
    if (cnt == 1) {
      ords[i] = idx;
    } else
      error("invalid input (missing order?)");
  }
}

// --- public -----------------------------------------------------------------o

#ifdef MAD_CTPSA_IMPL

extern const D* mad_tpsa_scan_hdr(int*, char[12], FILE*);

const D*
FUN(scan_hdr) (int *kind_, char name_[12], FILE *stream_)
{
  DBGFUN(->); // complex and real header are the same...
  const D* ret = mad_tpsa_scan_hdr(kind_, name_, stream_);
  DBGFUN(<-);
  return ret;
}

#else

const D*
FUN(scan_hdr) (int *kind_, char name_[12], FILE *stream_)
{
  DBGFUN(->);
  int nv=0, nk=0, cnt=0, nc=0, nn, c;
  ord_t mo, ko;
  char name[12]="", typ='?';
  fpos_t fpos;

  if (!stream_) stream_ = stdin;

  // backup stream position
  fgetpos(stream_, &fpos);

  // eat white space
  while ((c=getc(stream_)) != EOF && isspace(c)) ;
  ungetc(c, stream_);

  // check the name (which is 10 chars) and the type
  if ((nn = fscanf(stream_, "%12[^:]: %c%n", name, &typ, &nc)) != 2
      || nc < 4 || !strchr(" RC", typ)
      || (kind_ && *kind_ != -1 && (*kind_ != (typ == 'C'))) ) {

#if DEBUG > 2
    printf("name='%s', typ='%c', nc=%d\n", name,typ,nc);
#endif

    if (name_) { // store error in name_
           if (nc < 4)              strcpy(name_, "INVALIDNAME");
      else if (!strchr(" RC", typ)) strcpy(name_, "INVALIDTYPE");
      else if (kind_ && *kind_ != -1 && (*kind_ != (typ == 'C')))
                                    strcpy(name_, "UNXPCTDTYPE");
    }

    fsetpos(stream_, &fpos); // may fail for non-seekable stream (e.g. pipes)...
    return NULL;
  }

  ensure(!feof(stream_) && !ferror(stream_), "invalid input (file error?)");

  if (kind_) *kind_ = typ == 'C';
  if (name_) strncpy(name_, name, 12), name_[11] = '\0';

  // 1st line (cnt includes typ)
  cnt = 1+fscanf(stream_, ", NV = %d, NO = %hhu, NK = %d, KO = %hhu%n",
                                  &nv,     &mo,       &nk,     &ko,&nc);

  // sanity checks
  ensure(nv > 0 && nv < 100000, "invalid NV=%d", nv);
  ensure(mo > 0 && mo < 64    , "invalid MO=%d", mo);

  if (cnt == 3) {
    // TPSA -- ignore rest of lines
    ensure(skip_line(stream_) != EOF, "invalid input (file error?)"); // finish NV,NO line
    ensure(fscanf(stream_, "%*[*]\n") != 1, "unexpected input (invalid header?)");
    ensure(skip_line(stream_) != EOF, "invalid input (file error?)"); // discard coeff header

    const D* ret = mad_desc_newn(nv, mo);
    DBGFUN(<-);
    return ret;
  }

  if (cnt == 5) {
    // GTPSA -- process rest of lines
    ord_t vo[nv];

    // sanity checks
    ensure(nk > 0 && nk < 100000, "invalid NV=%d", nk);
    ensure(ko > 0 && ko < 64    , "invalid KO=%d", ko);

    ensure(skip_line(stream_) != EOF, "invalid input (file error?)"); // finish NV,NO line

    // read variables orders if present
    if ((cnt += fscanf(stream_, " V%*[O]: ")) == 6) {
      read_ords(nv, vo, stream_);
      ensure(skip_line(stream_) != EOF, "invalid input (file error?)"); // finish VO line
    }

    ensure(fscanf(stream_, "%*[*]\n") != 1, "unexpected input (invalid header?)");
    ensure(skip_line(stream_) != EOF, "invalid input (file error?)"); // discard coeff header
    ensure(!feof(stream_) && !ferror(stream_), "invalid input (file error?)");

    const D* ret = cnt == 5 ? mad_desc_newv(nv, vo, nk, ko)
                            : mad_desc_newk(nv, mo, nk, ko);
    DBGFUN(<-);
    return ret;
  }

       if (cnt < 3) warn("could not read (NV,NO) from header");
  else if (cnt < 5) warn("could not read (NK,KO) from header");
  else              warn("unable to parse GTPSA header");

  fsetpos(stream_, &fpos); // may fail for non-seekable stream (e.g. sockets)...
  return NULL;
}

#endif // !MAD_CTPSA_IMPL

void
FUN(scan_coef) (T *t, FILE *stream_)
{
  assert(t); DBGFUN(->); DBGTPSA(t);

  if (!stream_) stream_ = stdin;

  NUM c;
  int nv = t->d->nv, cnt = -1;
  ord_t o, ords[nv];
  FUN(reset0)(t);

#ifndef MAD_CTPSA_IMPL
  while ((cnt = fscanf(stream_, "%*d %lG %hhu", &c, &o)) == 2) {
#else
  while ((cnt = fscanf(stream_, "%*d %lG%lGi %hhu", (num_t*)&c, (num_t*)&c+1, &o)) == 3) {
#endif

    #if DEBUG > 2
      printf("c=" FMT ", o=%d\n", VAL(c), o);
    #endif
    read_ords(nv,ords,stream_); // sanity check
    ensure(mad_mono_ord(nv,ords) == o, "invalid input (bad order?)");
    // discard too high mononial
    if (o <= t->mo) FUN(setm)(t,nv,ords,0,c);
  }
  FUN(update0)(t, t->lo, t->hi);
  DBGTPSA(t); DBGFUN(<-);
}

T*
FUN(scan) (char name_[12], FILE *stream_)
{
  DBGFUN(->);
#ifndef MAD_CTPSA_IMPL
  int knd = 0;
#else
  int knd = 1;
#endif
  T *t = NULL;
  const D *d = FUN(scan_hdr)(&knd, name_, stream_);
  if (d) {
    t = FUN(newd)(d, mad_tpsa_default);
    FUN(scan_coef)(t, stream_);
  }
  DBGFUN(<-);
  return t;
}

void
FUN(print) (const T *t, str_t name_, num_t eps_, int nohdr_, FILE *stream_)
{
  assert(t); DBGFUN(->); DBGTPSA(t);

  if (!name_  ) name_   = "-UNNAMED--";
  if (eps_ < 0) eps_    = 1e-16;
  if (!stream_) stream_ = stdout;

#ifndef MAD_CTPSA_IMPL
  const char typ = 'R';
#else
  const char typ = 'C';
#endif

  const D *d = t->d;

  if (nohdr_) goto coeffonly;

  // print header
  fprintf(stream_, d->nk || d->uvo
                 ? "\n %-8s:  %c, NV = %3d, NO = %2hhu, NK = %3d, KO = %2hhu"
                 : "\n %-8s:  %c, NV = %3d, NO = %2hhu",
                      name_, typ,    d->nv,      d->mo,    d->nk,      d->ko);

  if (d->uvo) {
    fprintf(stream_, "\n VO:");
    print_ords(d->nv, d->vo, stream_);
  }
  fprintf(stream_, "\n********************************************************");
#ifdef MAD_CTPSA_IMPL
  fprintf(stream_, "***********************");
#endif

coeffonly:

  // print coefficients
  fprintf(stream_, "\n     I   COEFFICIENT         " SPC "  ORDER   EXPONENTS");
  const idx_t *o2i = d->ord2idx;
  idx_t idx = 0;
  for (ord_t o = t->lo; o <= t->hi ; ++o) {
    if (!mad_bit_tst(t->nz,o)) continue;
    for (idx_t i = o2i[o]; i < o2i[o+1]; ++i) {
#ifndef MAD_CTPSA_IMPL
      if (fabs(t->coef[i]) < eps_) continue;
      fprintf(stream_, "\n%6d  %21.14lE   %2hhu   "           , ++idx, VALEPS(t->coef[i],eps_), d->ords[i]);
#else
      if (fabs(creal(t->coef[i])) < eps_ && fabs(cimag(t->coef[i])) < eps_) continue;
      fprintf(stream_, "\n%6d  %21.14lE %+21.14lEi   %2hhu   ", ++idx, VALEPS(t->coef[i],eps_), d->ords[i]);
#endif
      (d->nv > 20 ? print_ords_sm : print_ords)(d->nv, d->To[i], stream_);
    }
  }

  if (!idx) fprintf(stream_, "\n          ALL COMPONENTS ZERO");

  fprintf(stream_, "\n\n");

  DBGTPSA(t); DBGFUN(<-);
}

// --- end --------------------------------------------------------------------o
