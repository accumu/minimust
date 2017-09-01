#!/usr/local/bin/perl

open(OUT,">/home/projects/must/minimust/input/".time.".log") || die "kvack";
open(OOUT,"|/home/projects/must/minimust/minimust.pl") || die "kvåck";

while(<STDIN>) {
	print OUT;
	print OOUT;
}

close(OOUT);
close(OUT);
