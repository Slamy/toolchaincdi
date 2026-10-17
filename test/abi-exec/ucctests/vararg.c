/* GCC code (-mos9call=ucc) and code Microware Ultra C compiled
   (vararg-mw.c, by Ultra C's own xcc at test time) calling each other's
   variadic functions: Ultra C passes a variadic call's unnamed arguments
   on the stack, even when d1 is free.  main returns a bit mask of the
   failed checks.  */

#include <stdarg.h>

/* Ultra C's.  */
extern int mw_sum (int n, ...);
extern int mw_second (const char *s, ...);
extern int mw_call_gcc (void);
extern int mw_call_gcc_ptr (void);

static unsigned long fails;
static void check (int ok, int n) { if (!ok) fails |= 1UL << n; }

/* Called by Ultra C code.  */
int
gcc_sum (int n, ...)
{
  va_list ap;
  int s = 0;
  va_start (ap, n);
  while (n-- > 0)
    s += va_arg (ap, int);
  va_end (ap);
  return s;
}

int
gcc_len (const char *s, ...)
{
  va_list ap;
  const char *t;
  int n = 0;
  va_start (ap, s);
  t = va_arg (ap, const char *);
  while (*s++)
    n++;
  while (*t++)
    n += 10;
  va_end (ap);
  return n;
}

int
main (void)
{
  check (mw_sum (3, 1, 2, 3) == 6, 1);
  check (mw_sum (1, 41) == 41, 2);
  check (mw_sum (5, 1, 2, 3, 4, 5) == 15, 3);
  check (mw_second ("x", 'a', 'b') == 'b', 4);
  check (mw_call_gcc () == 60, 5);
  check (mw_call_gcc_ptr () == 23, 6);
  return (int) fails;
}
