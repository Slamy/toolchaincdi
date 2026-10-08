#!/usr/bin/perl
# Print an OS-9 symbol module (.stb) as text: the header fields that
# matter, then one line per symbol: value, type, name.
use strict; use warnings;
local $/; open my $f, '<:raw', $ARGV[0] or die "$ARGV[0]: $!\n"; my $m = <$f>;
my ($size, $owner, $nameoff) = unpack 'x4 N N N', $m;
my ($accs, $typelang, $attrev, $edit, $symbol) = unpack 'x16 n n n n x4 N', $m;
my ($name) = unpack 'Z*', substr($m, $nameoff);
my ($fmt, $crc, $ent, $n) = unpack 'n N N N', substr($m, $symbol);
printf "name=%s owner=%08x accs=%04x typelang=%04x attrev=%04x edition=%d stb=%#x\n",
  $name, $owner, $accs, $typelang, $attrev, $edit, $symbol;
printf "format=%04x entries=%#x count=%d\n", $fmt, $ent, $n;
for my $i (0 .. $n - 1) {
  my ($v, $t, $no) = unpack 'N n N', substr($m, $ent + 10 * $i, 10);
  printf "%08x %04x %s\n", $v, $t, unpack('Z*', substr($m, $no));
}
