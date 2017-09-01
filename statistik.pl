#!/usr/local/bin/perl

use Data::Dumper;

my(%wdays) = (
		0 => 'Söndag',
		1 => 'Måndag',
		2 => 'Tisdag',
		3 => 'Onsdag',
		4 => 'Torsdag',
		5 => 'Fredag',
		6 => 'Lördag',
		7 => 'Söndag',
);

$lastcase = undef;
$firstcase = undef;
$casecount = 0;
$solvedcount = 0;
$usermailcount = 0;
%admincount;
%startm;
%startd;
%startmd;
%startdow;
%starthod;
%solvem;
%solved;
%solvemd;
%solvedow;
%solvehod;

foreach(`/usr/local/sbin/mq Support listall`) {
	#print "> $_";
	if(/\d+\.\d/) {
		addcase("$&");
	}
}
print STDERR "\n";

$days = int(($lastcase-$firstcase)/60/60/24);

print "\nStart of minimust report: ",scalar localtime(time),"\n\n";

print "Dates:\n";
print scalar localtime($firstcase)," -> ",scalar localtime($lastcase)," ($days days)\n\n";
print "User          count    %        solved   %\n";
print "---------------------------------------------\n";
foreach(sort {$admincount{$b} <=> $admincount{$a}} keys %admincount) {
	my($u) = $_;
	$u = "unassign" unless length;
	printf("%-8s  %8d  %5.2f ",$u,$admincount{$_},100*$admincount{$_}/$casecount);
	printf(" %8d  %5.2f\n",$adminsolvecount{$_},100*$adminsolvecount{$_}/$solvedcount);
}
print "---------------------------------------------\n";
printf("%-8s  %8d  %5.2f/day %6d  %5.2f/day","Total:",$casecount,$casecount/$days,$solvedcount,$solvedcount/$days);

print "\n\n";
printf("Average %.2f mail used/case\n",$usermailcount/$casecount);

print "\n\n";
print "Call issued (hour of day) - Call solved (hour of day)\n";
print "------------------------------------------------------\n";
foreach(0..23) {
	printf("%02d  %8d  %5.2f",$_,$starthod{$_},100*$starthod{$_}/$casecount);
	printf("       - %8d  %5.2f\n",$solvehod{$_},100*$solvehod{$_}/$solvedcount);
}

print "\n\n";
print "Call issued (day of week) - Call solved (day of week)\n";
print "------------------------------------------------------\n";
foreach(0..6) {
	printf("%-8s  %5d  %5.2f   ",$wdays{$_},$startdow{$_},100*$startdow{$_}/$casecount);
	printf(" - %5d  %5.2f\n",$solvedow{$_},100*$solvedow{$_}/$solvedcount);
}

print "\n\n";
print "Call issued (month) - Call solved (month)\n";
print "------------------------------------------\n";
foreach(1..12) {
	$_ = sprintf("%02d",$_);
	printf("%2d  %5d  %5.2f   ",int($_),$startm{$_},100*$startm{$_}/$casecount);
	printf(" - %5d  %5.2f\n",$solvem{$_},100*$solvem{$_}/$solvedcount);
}

print "\n-- \n";
print "End of minimust report\n";

exit;

#print Dumper($casecount);
#print Dumper($solvedcount);
#print Dumper($usermailcount);
#print Dumper(\%admincount);
#print Dumper(\%startm);
######print Dumper(\%startd);
######print Dumper(\%startmd);
#print Dumper(\%solvem);
#print Dumper(\%solved);
#print Dumper(\%solvemd);
#print Dumper(\%solvedow);
#print Dumper(\%solvehod);

sub ymd {
	my($t) = @_;
	my($y,$m,$d) = (localtime($t))[5,4,3];
	$y+=1900;
	$m++;
	return sprintf("%d%02d%02d",$y,$m,$d);
}
sub md {
	my($t) = @_;
	my($y,$m,$d) = (localtime($t))[5,4,3];
	$y+=1900;
	$m++;
	#print "md: ",sprintf("%02d%02d",$m,$d),"\n";
	return sprintf("%02d%02d",$m,$d);
}
sub mon {
	my($t) = @_;
	my($y,$m,$d) = (localtime($t))[5,4,3];
	$y+=1900;
	$m++;
	#print "m: ",sprintf("%02d",$m),"\n";
	return sprintf("%02d",$m);
}
sub d {
	my($t) = @_;
	#print "\$t = $t\n";
	my($y,$m,$d) = (localtime($t))[5,4,3];
	$y+=1900;
	$m++;
	#print "d: ",sprintf("%02d",$d),"\n";
	return sprintf("%02d",$d);
}
sub dow {
	my($t) = @_;
	return (localtime($t))[6];
}
sub hod {
	my($t) = @_;
	return (localtime($t))[2];
}

sub addcase {
	my($caseid) = @_;
	my($user,$solved);

	open(CI,"/usr/local/sbin/mq Support info $caseid|") || die "Broken I say... Broken";
	$casecount++;
	while(<CI>) {
		#print "# $_";
		if(/^owner\s+=\s+(\S+)(\@|unassigned)/) {
			#print "owner = $1\n";
			$user = $1 unless defined $user;
		}
		if(/^solvedby\s+=\s+(\S+)(\@|unassigned)/) {
			#print "solvedby = $1\n";
			$user = $1;
			$solved = $1;
			$solvedcount++;
		}
		if(/^usermailcount\s+=\s+(\d+)/) {
			#print "usermailcount = $1\n";
			$usermailcount+=$1;
		}
		if(/^time\s+=\s+(\d+)/) {
			$firstcase = $1 unless defined $firstcase;
			$lastcase = $1;
			#print "time = $1\n";
			my($t) = $1;
			$startm{mon($t)}++;
			$startd{d($t)}++;
			$startmd{md($t)}++;
			$startdow{dow($t)}++;
			$starthod{hod($t)}++;
		}
		if(/^solvedtime\s+=\s+(\d+)/) {
			#print "solvedtime = $1\n";
			my($t) = $1;
			$solvem{mon($t)}++;
			$solved{d($t)}++;
			$solvemd{md($t)}++;
			$solvedow{dow($t)}++;
			$solvehod{hod($t)}++;
		}
	}
	$admincount{$user}++;
	$adminsolvecount{$solved}++ if defined $solved;
}
