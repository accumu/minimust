#!/usr/local/bin/perl 

# cfg #
local($basepath) = '/home/projects/must/minimust/';
# cfg #

my($listcfg) = shift @ARGV;
my($listcmd) = shift @ARGV;
my(@cmddata) = @ARGV;

if(!defined $listcfg) {
	print "Available lists:\n";
	foreach(<$basepath/list/*>) {
		if(-d $_ && -r "$_.cfg") {
			/[^\/]+$/;
			print "\t$&\n";
		}
	}
	exit;
}

my($listcfgpath) = "/home/projects/must/minimust/list/$listcfg.cfg";

if(!-f $listcfgpath) {
	warn "'$listcfgpath' does not exist...\n";
	print "Available lists:\n";
	foreach(<$basepath/list/*>) {
		if(-d $_ && -r "$_.cfg") {
			/[^\/]+$/;
			print "\t$&\n";
		}
	}
	exit;
}

local(%listmembers,$list,$listalias,$listname,$defaultadmincmd,$listpath,$firstmsg);

#------------- Read Config ---------------#
my($ret);
unless($ret = do $listcfgpath) {
	die "couldn't parse $listcfgpath: $@" if $@;
	die "couldn't do $listcfgpath: $!"    unless defined $ret;
	die "couldn't run $listcfgpath"       unless $ret;
}
#------------- Read Config ---------------#

if(!defined $listcmd) {
	die <<EOM;
No command. Available commands:
	members              - List members.
	list [u]             - List open cases. (owned by user)
	listall [u]          - List _all_ cases. (owned by user)
	info <c>             - info on a case.
	assign <c> <u>       - assign <c> to <u>
	close <c> [!]        - close <c>
	permanent <c> [!]    - permanent close <c>
	solve <c> [!]        - solve <c>
	take <c> [!]         - take <c> 
	eta <c> <t> [!]      - take <c> 
	discuss <c>          - set discuss mode on <c>
	untake <c> [!]       - untake <c>
	mutt <c>             - mutt:a <c>
	pine <c>             - pine:a <c>
EOM
	# cmd <c> <cmd>        - Do <cmd> on <c> (use with care)
}

if($listcmd =~ /^(assign|eta)$/) {
	my($id) = shift @cmddata;
	my($file) = getcallidfile($id);
	my(%cmd) = (
		'assign' => 'A',
		'eta' => 'ETA',
	);
	if(defined $file) {
		my $data = shift @cmddata;
		die "Missing Parameter!\n" if !defined $data || $data =~ /\!/;
		$user =~ s/[\s:]+//g;
		@cmddata = ($id,"$cmd{$1}$data".($cmddata[0] eq "!"?"!":""));
		$listcmd = 'cmd';
	} else {
		die "Case $id does not exist\n";
	}
}
if($listcmd =~ /^(open|close|solve|take|discuss|untake|permanent)$/) {
	my($id) = shift @cmddata;
	my($file) = getcallidfile($id);
	my(%cmd) = (
		'open' => 'O',
		'close' => 'C',
		'solve' => 'S',
		'take' => 'T',
		'discuss' => 'D',
		'untake' => 'U',
		'permanent' => 'P',
		'eta' => 'E',
	);
	if(defined $file) {
		@cmddata = ($id,$cmd{$listcmd}.($cmddata[0] eq "!"?"!":""));
		$listcmd = 'cmd';
	} else {
		die "Case $id does not exist\n";
	}
}

if($listcmd eq 'cmd') {
	my($id) = shift @cmddata;
	my($file) = getcallidfile($id);
	if(defined $file) {
		my(%hash) = readcase($file);
		if(!defined $cmddata[0]) {
			die "No command\n";
		}
		my($cmdstr) = join('!:',@cmddata);
		open(MAIL,"|/usr/lib/sendmail $list") || die "Can't send mail to $list\n";
		#open(MAIL,"|/bin/cat -");
		print MAIL "To: $listname <$list>\n";
		print MAIL "Subject: [$listname#$id:$cmdstr!] $hash{subject}\n";
		close(MAIL);
		print "Done...\n";
		exit;
	}
	die "Case $id does not exist\n";
}

if($listcmd eq 'members') {
	foreach(sort keys %listmembers) {
		printf "%-20s $listmembers{$_}\n",$_;
	}
	exit;
}

if($listcmd eq 'list') {
	my $count = 0;
	foreach my $list (sort { 
		my($aa,$ab) = $a =~ /(\d+)\.(\d+)/g;
		my($bb,$ba) = $b =~ /(\d+)\.(\d+)/g;
		if($bb <=> $aa) {
			return $aa <=> $bb;
		} else {
			return $ab <=> $ba;
		}
				} <$basepath/list/$listcfg/*.status>) {
		$list =~ /([^\/]+)\.status$/;
		printcaseone($list,$1,$cmddata[0],\$count);
	}
	exit;
}
if($listcmd eq 'info') {
	my($file) = getcallidfile($cmddata[0]);
	die "Must give case id\n" unless scalar @cmddata;
	if(defined $file) {
		printcaseinfo($file,$cmddata[0]);
		exit;
	}
	die "Case $cmddata[0] does not exist\n";
}
if($listcmd eq 'mutt') {
	die "Must give case id\n" unless scalar @cmddata;
	my($file) = getcallidfile($cmddata[0]);
	if(defined $file) {
		$file =~ s/\.status$/.outmail/;
		system("mutt -f $file");
		exit;
	}
	die "Case $cmddata[0] does not exist\n";
}
if($listcmd eq 'pine') {
	die "Must give case id\n" unless scalar @cmddata;
	my($file) = getcallidfile($cmddata[0]);
	if(defined $file) {
		$file =~ s/\.status$/.outmail/;
		system("pine -f $file");
		exit;
	}
	die "Case $cmddata[0] does not exist\n";
}
if($listcmd eq 'listall') {
	my $count = 0;
	foreach my $list (sort { 
		$a =~ /([^\/]+)\.status$/;
		my($d) = $1;
		$b =~ /([^\/]+)\.status$/;
		my($e) = $1;
		$d <=> $e;
	} (<$basepath/list/$listcfg/*/*.status>,<$basepath/list/$listcfg/*.status>)) {
		$list =~ /([^\/]+)\.status$/;
		printcaseone($list,$1,$cmddata[0],\$count);
	}
	exit;
}

die "Unknown command...\n";


sub readcase {
	my($file) = @_;
	my(%hash);
	open(IN,$file) || die "Can't open $file\n";
	while(<IN>) {
		if(/^([^:]+):\s*(.*)\s*$/) {
			$hash{$1} = $2;
		}
	}
	close(IN);
	return %hash;
}

sub printcaseone {
	my($file,$id,$owner,$nohead) = @_;
	my(%hash) = readcase($file);
	my(%statusconv) = (
		'open' => 'O',
		'closed' => 'S',
		'solved' => 'S',
		'discuss' => 'D',
		'permanent' => 'P',
	);

	return if defined $owner && $hash{owner} !~ /$owner/;

	$hash{status} = 'permanent' if defined $hash{'cantopen'} && $hash{'cantopen'} eq 'true';

	$hash{callid} = "($id)" unless length $hash{callid};

	$hash{caller} =~ s/^(.{15}).*$/$1/;
	$hash{owner} =~ s/^(.{8}).*$/$1/;

	$hash{subject} = "<NOSUBJECT>" unless(length($hash{subject}));
	unless($$nohead) {
		$$nohead ++;
		printf "Ticket#  Status  ETA   ";
		printf "%-15s %-8s %s ","Caller","Owner" , "Re:";
		print "\n";
		print "-" x 65,"\n";
	}
	printf "%-11s %s %8s ",$hash{callid},$statusconv{$hash{status}},$hash{eta};
	printf "%-15s %-8s %s ",$hash{caller},$hash{owner},$hash{subject};
	print "\n";
}

sub printcaseinfo {
	my($file,$id) = @_;
	my(%hash) = readcase($file);

	$hash{callid} = "($id)" unless length $hash{callid};
	foreach my $k (sort keys %hash) {
		printf "%-10s = $hash{$k}\n",$k;
	}
}

sub getcallidfile {
	my($callid) = @_;
	if(-f "$basepath/list/$listcfg/$callid.status") {
		return "$basepath/list/$listcfg/$callid.status";
	}
	my($cd) = $callid;
	$cd =~ s/^(.{6}).*$/$1/;
	if(-f "$basepath/list/$listcfg/$cd/$callid.status") {
		return "$basepath/list/$listcfg/$cd/$callid.status";
	}
	return undef;
}

# EOF
