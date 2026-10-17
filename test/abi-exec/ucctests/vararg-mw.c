/* The Ultra C side of vararg.c: compiled by Microware Ultra C's xcc
   (ANSI mode, no stack checking) at test time, never stored.  */

#include <stdarg.h>

int gcc_sum (int n, ...);
int gcc_len (const char *s, ...);

int
mw_sum (int n, ...)
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
mw_second (const char *s, ...)
{
  va_list ap;
  int c;
  va_start (ap, s);
  c = va_arg (ap, int);
  c = va_arg (ap, int);
  va_end (ap);
  return c;
}

int
mw_call_gcc (void)
{
  return gcc_sum (3, 10, 20, 30);
}

int
mw_call_gcc_ptr (void)
{
  return gcc_len ("abc", "xy");
}
