#!/usr/local/bin/perl -w
#
# Minimust is created by Magnus Jonsson <bigfoot@acc.umu.se>
# Some additional code by Markus Mårtensson <mortis@acc.umu.se>
#

use IPC::Open2;
use Mail::Util qw(read_mbox);
use MIME::Head; 
use Mail::Address;
use Encode;

my($debug) = 0;
my($version) = 'MiniMust 0.1a';
local($domain) = "acc.umu.se";
#my($sendmail) = '/usr/lib/sendmail -O DeliveryMode=b -fmust@acc.umu.se';
# -oi is "ignore single . on line, != eof"
my($sendmail) = "/usr/lib/sendmail -oi -fmust\@$domain";
my($url) = "http://www.acc.umu.se/home/must/minimust/";
local($verify_emails) = 0;  # sendmail -v -bv must be supported

my($listcfg) = shift @ARGV;
local($basepath) = '/home/projects/must/minimust/';
my($listcfgpath) = "$basepath/list/$listcfg";

die "No configfile...\n" unless defined $listcfg;
die "'$listcfgpath' does not exist...\n" unless -f $listcfgpath;

# debugging
 open(STDERR,">/tmp/stderr.$$");
 open(STDOUT,">/tmp/stdout.$$");
# debugging

local(%listmembers,$list,$listalias,$listname,$listpath,$firstmsg,$ignoreadresses,$initialresponse);

Debug("Reading Config");

#------------- Read Config ---------------#
my($ret);
unless($ret = do $listcfgpath) {
	die "couldn't parse $listcfgpath: $@" if $@;
	die "couldn't do $listcfgpath: $!"    unless defined $ret;
	die "couldn't run $listcfgpath"       unless $ret;
}
#------------- Read Config ---------------#

close(STDERR); # remove for debugging =)

#------------- Jada jada.. ---------------#
my($callid) = "$listpath/callid";

#------------- group readable... ---------------#
umask(027);

Debug("Read Mail");
my(@head,@body);
my($fromline);
my($smtpfrom);
#------------- read mail ---------------#
while(<STDIN>) {
	if(/^From (.*)/) {
		$fromline = $_;
		$smtpfrom = $1;
		next;
	}
	next if /^>/;
	last if /^$/;
	push @head, $_;
}
while(<STDIN>) {
	push @body, $_;
}

#------------- Check spam -----------------#
Debug("Checking for spam");
my $bogofilter_pid = open2(\*BOGO_READ, \*BOGO_WRITE, "bogofilter");
chomp(my $fromline2 = $fromline);
print BOGO_WRITE "$fromline2\n";
Debug("$fromline2");
foreach (@head) {
	chomp(my $line = $_);
	print BOGO_WRITE "$line\n";
	Debug("$line");
}
print BOGO_WRITE "\n";
Debug("");
foreach (@body) {
	chomp(my $line = $_);
	print BOGO_WRITE "$line\n";
	Debug("$line");
}
print BOGO_WRITE "\n";
Debug("");
close(BOGO_WRITE);
foreach (<BOGO_READ>) {
	Debug("Output from bogofilter: $_");
}
close(BOGO_READ);
waitpid($bogofilter_pid, 0);
# bogofilter indicates spam with exit status = 0
my $bogofilter_status = $? >> 8;
Debug("Result from bogofilter: $bogofilter_status");
if ($bogofilter_status == 0) {
	Debug("Spam found... exit 0");
	exit 0;
}

Debug("Parse header");
#------------- Parse header ---------------#
my($header) = new MIME::Head (\@head);

# First of all remove every possible dkim related headers.
# Must rewrites headers and breaks dkim.
$header->delete('DKIM-Signature');
$header->delete('Authentication-Results');
$header->delete('ARC-Authentication-Results');
$header->delete('ARC-Seal');
$header->delete('ARC-Message-Signature');

my $tempsubj = $header->get('Subject');
$tempsubj =~ s/\r\n +/ /gs;
$tempsubj =~ s/\r +/ /gs;
$tempsubj =~ s/\n +/ /gs;
$header->set('Subject',decode('MIME-Header',$tempsubj));
$header->unfold('Subject');

Debug("Get mailers");
#------------- Get mailers ---------------#
my @addrc = Mail::Address->parse($header->get('cc'));
my @addrt = Mail::Address->parse($header->get('to'));
my @addrf = Mail::Address->parse($header->get('from'));
my @addrx = Mail::Address->parse($header->get('x-distcc'));

my($from) = shift @addrf;
my($fromaddress) = translateemail($from->address());


sub translateemail {
	my($email) = @_;
	foreach my $l (keys %listmembers) {
		foreach my $u (split(/,/,$listmembers{$l})) {
			$u =~ s/^\s+//;
			$u =~ s/\s+$//;
			return $l if $u =~ /\@/ && $u eq $email;
		}
	}
	return $email;
}

Debug("Mail adresslist");
my(%addresses,%inputaddr);
foreach(@addrt) {
	my $addr = lc(translateemail($_->address()));
	$addresses{$addr} = $_->phrase;
	$inputaddr{$addr} = $_->phrase;
}
foreach(@addrf,@addrc,$from) {
	my $addr = translateemail($_->address());
	$addresses{$addr} = $_->phrase;
	$inputaddr{$addr} = $_->phrase;
}

# X-DistCC
foreach(@addrx) {
        my $addr = translateemail($_->address());
        $addresses{$addr} = $_->phrase;
}


Debug("Check for to");
my($tuser,$tdomain) = split(/\@/,$list);
my(@extrato);

#
# support+user{a}domain.com#otheruser{a}otherdomian.com@acc.umu.se
#
if(length($tuser) && length($tdomain)) {
	foreach my $a (keys %addresses) {

		if($a =~ /^$tuser\+(.+)\@$tdomain$/) {
			my($t) = $1;
			$t =~ s/\s+//g;
			foreach my $i (split(/#/,$t)) {
				if($i =~ /^.+\{a\}.+\..+$/) {
					$i =~ s/\{a\}/\@/;
					push @extrato,$i;
				}
			}
			$addresses{$list} = $addresses{$a};
			delete $addresses{$a};
		}
	}
}
Debug("Got Extra: ".join(",",@extrato)) if scalar @extrato;

Debug("Remove alias and check for deliver.");
my($nottothelist) = 1;
foreach(split(/,/,$listalias),$list,split(/,/,$ignoreadresses)) {
	Debug("Alias: $_");
	if(defined $addresses{$_}) {
		$nottothelist = 0;
		delete $addresses{$_};
	}
}

foreach my $em (keys %addresses) {
	my($dest) = verifymail($em);
	if(!defined $dest) {
		Debug("Removing $em (undef)");
		delete $addresses{$em};
		next;
	}
	if($dest =~ /\bmust\b/) { ## FIX ##
		Debug("Removing $em");
		delete $addresses{$em};
		Debug("It's to the list... *sucka*");
		$nottothelist = 0;
		next;
	}
}

if($nottothelist) {
	my @resentto = Mail::Address->parse($header->get('Resent-To'));
	foreach my $l (split(/,/,$listalias),$list) {
		foreach my $r (@resentto) {
			if($r->address() =~ /^$l/) {
				$nottothelist = 0;
				last;
			}
		}
	}
}

if($nottothelist) {
	send_mail(join(',',keys %listmembers), join("",@head,"X-MustNotToTheList: Stupid user", "\n", @body),1);
	Debug("Not To The List");
	exit 0;
}

Debug("Stupid adresses");
foreach(qw/$list MAILER-DAEMON/) {
	exit 1 if $fromaddress =~ /^$_/;
}

# Move #
sub getalladmins {
	my(@result);
	foreach my $l (keys %listmembers) {
		push @result,$l;
	}
	return @result;
}
# Move #

#------------- Find out if from admin ---------------#
#------------- Write better one ---------------#
Debug("Find admin");
my($admin) = 0;
foreach(getalladmins()) {
	Debug("$_ eq ".$fromaddress);
	$admin = 1 if $_ eq $fromaddress;
}
Debug("Admin found") if $admin;
#------------- Write better one ---------------#

if($admin) {
	foreach(@extrato) {
		Debug("Add Extra: $_");
		$addresses{$_} = "";
	}
}

Debug("Checking for loops");
if(!$admin && $header->get('X-Mailer') =~ /$version/) {
	Debug("Loop found... exit 2");
	exit 2;
}


# ------------ Handle Subject --------- #

my($subject) = $header->get('Subject');
$subject =~ s/^\s*\*REJECTED\*//;

Debug("Handle subject");
my($id,$cmd,$adminsubject,%status,$cmdsubject);
if($subject =~ /\[$listname#(\d+.\d+):?([^\]]*)\]/) {
	$id = $1;
	$cmd = $2;

	Debug("ID $id found ($cmd)");

	my($abegin) = $`;
	my($aend) = $';

	$aend=~s/^\s+//;
	if($abegin && $abegin=~s/\s*(Re|Sv|Fw):\s*//gi) {
        if( $aend=~/^(Re|Sv|Fw):/i ) {
            $aend=" $aend";
        }else {
            $aend=($1?" $1: ":' ')."$aend";
        }
	}
	$abegin=~s/^\s*(\S*)\s*$/ $1/ if $abegin;

	$header->set('Subject',"[$listname#$id]$abegin$aend");

	my($adminreject) = "*REJECTED* [$listname#${id}:F:$cmd]$abegin$aend";
	$cmdsubject = "CMD: [$listname#${id}:N]$abegin$aend";
	$header->delete('Delivered-To');

	lockid($id) || die "Can't lock $id\n";
	my($s) = readstatus($id);
	if(defined $s && ${$s}{'cantopen'} && ${$s}{'cantopen'} eq 'true') {
		writestatus($id,%{$s});
		unlockid($id);
		undef $s;
	}
	if(defined $s) {
		%status = %{$s};

		foreach(split(/,/,$status{'distlist'})) {
			$addresses{$_} = "";
		}

		if($admin) {
			Debug("Ticket exists and you are admin");
			my($force) = 0;
			foreach my $c (split(/:/,$cmd)) {
				$force = 1 if($c =~ /^F/);
				$force = 1 if($c =~ /^N/);
				$force = 1 if($c =~ /\!/);
			}
			if($status{owner} eq $fromaddress || $status{owner} eq 'unassign' ||
				$status{status} eq 'discuss' || $force) {
				Debug("Status: $status{status}, cmd: $cmd");
				$status{'laststatus'} = $status{'status'};
				$status{'status'} = 'open';
				$status{'distlist'} = join(",",keys %addresses);
				$status{'owner'} = $fromaddress if $status{'owner'} eq "unassign";
				docmd($id,$cmd);
			} else {
				Debug("Adminbounce... Status: $status{status}, cmd: $cmd");
				$header->set('Subject', $adminreject);
				$status{'adminbounce'} = 1;
			}
		} else {
			Debug("!admin");
			if(length $cmd) {
				$header->set('Subject',"*ALERT* ".$header->get('Subject'));
				$status{'adminbounce'} = 2;
			}
			$status{'status'} = 'open';
			$status{'distlist'} = join(",",keys %addresses);
		}
		$adminsubject = "[$listname#${id}". &GetMode ."]$abegin$aend";
	} else {
		undef $id;
		$header->set('Subject',"$`$'");
	}
} 

#------------- New ticket ---------------#
if(!defined $id) {
	Debug("New ID");
	$id = getid();
	Debug("ID = $id");
	die "Can't get new ID ($id)" if $id < 0;
	$subject = $header->get('Subject');
	$header->set('Subject',"[$listname#$id] $subject");
	$adminsubject = "[$listname#${id}] $subject";
	%status = (
		'subject' => $subject,
		'caller' => $fromaddress,
		'owner' => 'unassign',
		'time'  => time,
		'status' => 'open',
		'mailcount' => 0,
		'usermailcount' => 0,
		'callid' => $id,
		'distlist' => join(",",keys %addresses),
		'messageid' => {},
	);
	sendfirstreply($id,$fromaddress,$subject);
	if($header->get('To') !~ /$list/) {
		$header->set('X-RealTo',$header->get('To'));
		$header->set('To',"$listname <$list>");
	}
}
my($mid) = $header->get('Message-ID');
chomp($mid);
${$status{'messageid'}}{$mid} = 1;
Debug("Adding message id: $mid");
foreach(split(/\s+/,$header->get('References'))) {
	chomp;
	Debug("adding message id: $_");
	${status{'messageid'}}{$_}=1 if length;
}

#------------- Fix List ----------#
Debug("Fix List");
my(%adminlist);
foreach(getalladmins()) {
        # Passive admins should not get mail unless explicitely assigned
	if ($listmembers{$_} =~ /\bpassive\b/) {
		delete $listmembers{$_};
		delete $addresses{$_};
		next;
	}
	delete $addresses{$_} if defined $addresses{$_};
	$adminlist{$_} = 1 if (!defined $inputaddr{$_} || $listmembers{$_} =~ /\bcopy\b/);
}
delete $addresses{$fromaddress};
delete $adminlist{$fromaddress} 
	unless defined $listmembers{$fromaddress} 
	    && $listmembers{$fromaddress} =~ /\bcopy\b/;
my($adminto) = join(",",keys %adminlist);

#------------- Fix headers ---------------#
$header->set('X-From',$fromaddress);
$header->set('X-SMTPFrom',$smtpfrom);
$header->set('From',$from->phrase()." <$list>");
$header->delete('cc');
$header->delete('Resent-Date');
$header->delete('Resent-From');
$header->delete('Resent-To');
$header->set('X-DistList',$status{'distlist'});
$header->set('X-RealMailer',$header->get('X-Mailer'));
$header->set('X-Mailer',$version);

$header->set('References',join(" ",keys %{$status{'messageid'}}));

if(defined $header->get('Reply-To')) {
	$header->set('X-Reply-To',$header->get('Reply-To'));
}
$header->set('Reply-To',"$listname <$list>");

#---------- Save mail -------------#
if(!lockfile("$listpath/$id.mail")) {
	Debug("Can't lock $id.mail");
	die "Can't lock $id.mail";
}
open(SAVE,">>$listpath/$id.mail") || die "Can't save $id.mail";
print SAVE $fromline,@head,"\n",@body,"\n";
close(SAVE);
unlockfile("$listpath/$id.mail");

#------------- write status ---------------#
$status{'mailcount'}++;
if($status{'adminbounce'} != 1 && $status{'dontsenduser'} == 0) {
	$status{'usermailcount'}++;
}

if(defined $status{'dontsenduser'} && $status{'dontsenduser'} > 1) {
	writestatus($id,%status) || die "Can't write status";
	unlockid($id);
	exit 0;
}

foreach(keys %inputaddr) {
	delete $addresses{$_} if defined $addresses{$_};
}

if($status{'adminbounce'} == 2) {
	my(@dist);
	my $from = $from->phrase()." <". $fromaddress .">";
	chomp($from);
	my($ref) = join(" ",keys %{$status{'messageid'}});
	push @dist,keys %listmembers;
	my $subj = encode('MIME-Header',$header->get('Subject'));
	chomp($subj);
	my($msg) = <<EOM;
To: $listname <$list>
From: $from
MIME-Version: 1.0
Subject: $subj
Content-Type: TEXT/PLAIN; charset=iso-8859-1
Content-Transfer-Encoding: 8BIT
X-Mailer: $version
References: $ref

$from sent a command but is not an admin!

/$listname

EOM

	send_mail(join(',',@dist), $msg);
} elsif($status{'adminbounce'} == 1) {
	$adminto = $fromaddress;
	$header->set('From',encode('MIME-Header',$from->phrase())." <". $fromaddress .">");
	$header->set('Subject',encode('MIME-Header',$header->get('Subject')));
	send_mail($adminto, $header->as_string."\n".join("",@body));
	$header->set('Subject',decode('MIME-Header',$header->get('Subject')));
} elsif($status{'dontsenduser'} == 1) {
	my($fromstr) = encode('MIME-Header',$from->phrase()). " <$list>";
	chomp($cmdsubject);
	$cmdsubject = encode('MIME-Header',$cmdsubject);
	my($ref) = join(" ",keys %{$status{'messageid'}});

	my($msg) = <<EOM;
To: $listname <$list>
From: $fromstr
Subject: $cmdsubject
MIME-Version: 1.0
Content-Type: TEXT/PLAIN; charset=iso-8859-1
Content-Transfer-Encoding: 8BIT
X-Mailer: $version
References: $ref

Status:

$status{statusmsg}
EOM

	send_mail($adminto,$msg);
} else {
	#------------- Send mail ---------------#
	my($sendto) = join(",",keys %addresses);
	my($body) = join('',@body);

	if($status{'status'} ne 'discuss' && 
			!defined $status{dontsendlist} &&
			length $sendto) {
		$header->set('Subject',encode('MIME-Header',$header->get('Subject')));
		send_mail($sendto,$header->as_string."\n$body",1);
		$header->set('Subject',decode('MIME-Header',$header->get('Subject')));
	}

	#------------- Send mail (admin) ---------------#
	#$header->set('Subject',encode('MIME-Header',$adminsubject));
	$header->set('Subject',$adminsubject);
	$header->set('X-CMD',$cmd) if length $cmd;
	$header->set('X-Help',":cmd = D-discuss, S-solve, O-reopen, N-note, A-assign, T-take, U-untake, F-force, P-Permanent. $url");

	$header->set('Subject',encode('MIME-Header',$header->get('Subject')));
	send_mail($adminto,$header->as_string."\n$body");
	$header->set('Subject',decode('MIME-Header',$header->get('Subject')));
}
writestatus($id,%status) || die "Can't write status";
unlockid($id);


####################
# --- mustfunc --- #
####################

sub GetMode {
	if($status{'status'} eq 'open') {
		return "";
	}
	if($status{'status'} eq 'closed') {
		return ":S";
	}
	if($status{'status'} eq 'discuss') {
		return ":D";
	}
	return "";
}

#------------- Handle must commands ---------------#
sub max {
	my($a,$b) = @_;
	return ($a > $b?$a:$b);
}
sub docmd {
	my($id,$cmd) = @_;
	my(%tstatus) = %status;
	$tstatus{'DEBUG'} = "$subject";
	$tstatus{'lastcmd'} = "$cmd";
	$tstatus{'lasttime'} = time;
	my($c) = 0;
	foreach(split(/:/,$cmd)) {
		$c++;
		$tstatus{"cmd$c"} = $_;
		if(/^CC(.*)$/) {
			# $addresses{$_};
			next;
		}
		if(/^E(TA|T|)(.*?)(\!+|)$/i) {
			my($data) = $2;
			my($tre) = $3;
			$tstatus{'DEBUG'} = "($data)";
			if($data =~ /^\d{8}$/) {
				$tstatus{eta} = $&;
			}
			if($data =~ /^(\d+)d$/i) {
				my($y,$m,$d) = (localtime(time+60*60*24*$1))[5,4,3];
				$y += 1900;
				$m ++;
				$tstatus{eta} = sprintf("%4d%02d%02d",$y,$m,$d);
			}
			if($data =~ /^(\d+)w$/i) {
				my($y,$m,$d) = (localtime(time+60*60*24*7*$1))[5,4,3];
				$y += 1900;
				$m ++;
				$tstatus{eta} = sprintf("%4d%02d%02d",$y,$m,$d);
			}
			$tstatus{statusmsg} .= $fromaddress . 
				" has set eta for [$listname#$tstatus{callid}] to $tstatus{eta}\n".
				"Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($tre));
			next;
		}
		if(/^(S|C)(\!+|)$/i) {
			$tstatus{status} = "closed";
			$tstatus{owner} = $fromaddress;
			$tstatus{solvedby} = $fromaddress;
			$tstatus{solvedtime} = time;
			$tstatus{statusmsg} .= $fromaddress . 
				" has closed [$listname#$tstatus{callid}]\n".
				"Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = 1 if uc($1) eq 'C';
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($2));
			next;
		}
		if(/^O(\!+|)$/i) {
			$tstatus{status} = "open";
			$tstatus{'openby'} = $fromaddress;
			$tstatus{'opentime'} = time;
			$tstatus{statusmsg} .= $fromaddress . 
				" has opened [$listname#$tstatus{callid}]\n".
				"Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($1));
			next;
		}
		if(/^P(\!+|)$/i) {
			$tstatus{status} = "closed";
			$tstatus{cantopen} = 'true';
			$tstatus{owner} = $fromaddress;
			$tstatus{solvedby} = $fromaddress;
			$tstatus{solvedtime} = time;
			$tstatus{statusmsg} .= $fromaddress .
				" has permanently closed [$listname#$tstatus{callid}]\n".
				"Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($1));
			next;
		}
		if(/^A(.*?)(\!+|.)$/i) {
			$tstatus{status} = "open" if $status{status} eq "closed";
			my($one,$user) = ($1,$1);
			my($two) = $2;

			if($two =~ /\!/) {
				$user = $one;
			} else {
				$user = $one.$two;
				$two = "";
			}
			my($do) = 0;
			foreach my $un (keys %listmembers) {
				# might send mail to user... ???
				if($un =~ /$user/i && length $user) {
					$tstatus{owner} = $un;
					$do = 1;
				}
			}
			$tstatus{owner} = 'unassign' unless $do;
			$tstatus{statusmsg} .= $fromaddress . 
				" has assigned [$listname#$tstatus{callid}] to $tstatus{owner}\n"
				."Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($two));
			next;
		}
		if(/^I(.*?)(\!+|.)$/i) {
			my($one,$user) = ($1,$1);
			my($two) = $2;

			if($two =~ /\!/) {
				$user = $one;
			} else {
				$user = $one.$two;
				$two = "";
			}
			my($do) = 0;
			
			# Can invite non-members by email address
			unless ($user =~ /\@/) {
				Debug("Who to invite?");
				# And members by regexp
				foreach my $un (keys %listmembers) {
					if($un =~ /$user/i && length $user) {
						Debug("$un matches /$user/i");
						$user = $un;
						last;
					}
				}
			}
			# Some local user
                        unless ($user =~ /\@/) {
				$user.="\@$domain";
				Debug("Assuming local user $user");
			}

			send_invitation($fromaddress, $user, 
				$tstatus{callid}, $tstatus{subject});
			# Add user to distribution list
			$addresses{$user} = "";
			$tstatus{'distlist'} .= ",$user";

			$tstatus{statusmsg} .= $fromaddress . 
				" has invited $user to [$listname#$tstatus{callid}]\n"
				."Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($two));
			next;
		}
		if(/^T(\!+|)/i) {
			$tstatus{status} = "open" if $status{status} eq "closed";
			$tstatus{owner} = $fromaddress;
			$tstatus{statusmsg} .= $fromaddress . 
				" has taken [$listname#$tstatus{callid}]\n".
				"Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($1));
			next;
		}
		if(/^U(\!+|)/i) {
			$tstatus{status} = "open" if $status{status} eq "closed";
			$tstatus{owner} = "unassign";
				$tstatus{statusmsg} .= $fromaddress . 
								" has unassigned [$listname#$tstatus{callid}]\n".
								"Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($1));
			next;
		}
		if(/^D(\!+|)/i) {
			$tstatus{status} = "discuss";
			$tstatus{statusmsg} .= $fromaddress . 
				" has put [$listname#$tstatus{callid}] in discussmode.\n".
				"Subject: $tstatus{subject}\n\n";
			$tstatus{dontsenduser} = max($tstatus{dontsenduser},length($1));
			next;
		}
		if(/^N/i) {
			$tstatus{dontsendlist} = 1;
			$tstatus{status} = $tstatus{laststatus};
			next;
		}
	}
	%status = %tstatus;
}

sub send_mail {
	my($to,$msg,$dontsave) = @_;
	open(MAIL,"|$sendmail $to") || die "Can't send mail $to";
	print MAIL $msg;
	close(MAIL);
	return if defined $dontsave;
	open(MAIL,">>$listpath/$id.outmail") || return undef;
	print MAIL "From must\@$domain ".scalar localtime(time)."\n";
	print MAIL "$msg\n\n";
	close(MAIL);
}

sub sendfirstreply {
	my($callid,$from,$subject) = @_;
	chomp($subject);
	chomp($from);

	return unless $initialresponse;
	return unless $from =~ /\.se$/;

	my $bodysubj = encode('UTF-8',$subject); # to get byte-wise utf8

	$firstmsg =~ s/%subject%/$bodysubj/gm;
	$firstmsg =~ s/%callid%/\[$listname#$callid\]/gm;
	$subject = encode('MIME-Header',$subject);

	my($msg) =<<EOM;
To: $from
From: $listname <$list>
Subject: [$listname#$callid] Re: $subject
MIME-Version: 1.0
Content-Type: TEXT/PLAIN; charset=UTF-8
Content-Transfer-Encoding: 8BIT
X-Mailer: $version

$firstmsg
EOM

	send_mail("$from", $msg);
}

sub send_invitation {
	my ($from,$to,$callid,$subject) = @_;

	$subject = encode('MIME-Header',$subject);
	Debug("Inviting $to to case $callid");
	my $file = "$listpath/$callid.outmail";

	Debug("Processing $file");
        @mbox = read_mbox $file or die "Could not read $file:$!";

        my($ref) = join(" ",keys %{$status{'messageid'}});

	my($msg) =<<EOM;
To: $to
From: $listname <$list>
Subject: [$listname#$callid] $subject
MIME-Version: 1.0
Content-Type: TEXT/PLAIN; charset=iso-8859-1
Content-Transfer-Encoding: 8BIT
X-Mailer: $version
References: $ref

You have been invited by $from to participate in the case
[$listname#$callid]. The relevant mail thread has been sent to you.
Do not reply directly to this email. If, after reading the thread,
you are not sure why you were invited then contact $from for
an explaination.
EOM

	send_mail("$to", $msg, "Don't save");

	Debug("Trying to locate mails bound for $list ($#mbox candidates)");
	foreach (@mbox) {
		Debug("Checking");
		my @msg = @{$_};
		my($header) = new MIME::Head (\@msg);
		if ( $header->get('to') =~ /$list/ ) {
			my $subject = $header->get('subject');
			next if ($subject =~ /\*REJECTED\*/);
			next if ($subject =~ /^CMD:/);

			Debug("Sending mail");
			open(MAIL,"|$sendmail $to") || die "Can't send mail to $to";
			foreach (@msg) {
				next if (/^From \S+@\S+/);
				print MAIL "$_";
			}
			close(MAIL);
		}
	}
	Debug("Done sending invitation mails");
}

sub lockid {
	my($id) = @_;
	if(!lockfile("$listpath/$id.status")) {
		return undef;
	}
	return 1;
}
sub unlockid {
	my($id) = @_;
	unlockfile("$listpath/$id.status");
}

sub readstatus {
	my($id) = @_;
	my(%ns) = ();
	if(!open(RSTATUS,"$listpath/$id.status")) {
		my($date);
		if($id =~ /^\d{6}/) {
			$date = $&;
			return undef unless(-f "$listpath/$date/$id.status");
			rename("$listpath/$date/$id.status","$listpath/$id.status") || return undef;
			if(!rename("$listpath/$date/$id.mail","$listpath/$id.mail")) {
				rename("$listpath/$id.status","$listpath/$date/$id.status") || return undef;
				return undef;
			}
			if(-f "$listpath/$date/$id.outmail") {
				if(!rename("$listpath/$date/$id.outmail","$listpath/$id.outmail")) {
					rename("$listpath/$id.status","$listpath/$date/$id.status") || return undef;
					rename("$listpath/$id.mail","$listpath/$date/$id.mail") || return undef;
					return undef;
				}
			}
			open(RSTATUS,"$listpath/$id.status") || return undef;
		} else {
			return undef;
		}
	}

	$ns{'messageid'} = {};
	while(<RSTATUS>) {
		chomp;
		if(/^([^:]+):\s*/) {
			if($1 eq "messageid") {
				foreach(split(/\s+/,$')) {
					${$ns{messageid}}{$_} = 1 if length;
				}
			} else {
				$ns{$1} = $';
			}
		}
	}
	close(RSTATUS);
	return \%ns;
}

sub writestatus {
	my($id,%ns) = @_;
	open(RSTATUS,">$listpath/$id.status") || return undef;
	foreach(sort keys %ns) {
		next if /dontsendlist/;
		next if /dontsenduser/;
		next if /adminbounce/;
		next if /statusmsg/;
		if(/messageid/) {
			print RSTATUS "messageid:";
			foreach(keys %{$ns{messageid}}) {
				s/(\r|\n)+//g;
				Debug("writeing message id: $_");
				print RSTATUS " $_";
			}
			print RSTATUS "\n";
			next;
		}
		$ns{$_} =~ s/(\r|\n)+//g;
		print RSTATUS "$_: $ns{$_}\n";
		Debug("Writing status: $_ -> $ns{$_}");
	}
	close(RSTATUS);
	if($ns{'status'} eq 'closed') {
		my($date);
		if($id =~ /^\d{6}/) {
			$date = $&;
			mkdir "$listpath/$date",0750 unless(-d "$listpath/$date");
			rename("$listpath/$id.status","$listpath/$date/$id.status") || return undef;
			rename("$listpath/$id.mail","$listpath/$date/$id.mail") || return undef;
			if(-f "$listpath/$id.outmail") {
				rename("$listpath/$id.outmail","$listpath/$date/$id.outmail") || return undef;
			}
		}
	}
	unlockfile("$listpath/$id.status");
	return $id;
}

sub getid {
	my($id,$date) = 0;
	my($d,$m,$y) = (localtime(time))[3..5];
	$date = sprintf("%04d%02d%02d",$y+1900,$m+1,$d);
	if(!lockfile($callid)) {
		return -1;
	}
	if(open(CID,$callid)) {
		my($in) = <CID>;
		chomp($in);
		if($in =~ /^(\d+)\.(\d+)$/) {
			$id = $2;
			if($date eq $1) {
				$id++;
			} else {
				$id = 0;
			}
		}
		close(CID);
	}
	if(!open(CID,">$callid.n")) {
		return -2;
	}
	print CID "$date.$id";
	close(CID);
	rename("$callid.n","$callid") || return -3;
	unlockfile($callid);
	return "$date.$id";
}

# --- Funcs --- #

sub verifymail {
	my($email,$match) = @_;

	return $email unless ($verify_emails);

	open(SMVF,"/usr/lib/sendmail -v -bv $email|") || return undef;
	my($retmsg) = undef;
	foreach my $ret (<SMVF>) {
		chomp ($ret);
		#print "($ret)\n";
		if($ret =~ /\.\.\. User unknown/) {
			return undef;
		}
		if($ret =~ /\.\.\. deliverable: mailer local, user (\S+)/) {
			$retmsg .= ",$1";
		}
		if($ret =~ /\.\.\. deliverable: mailer esmtp, host \S+, user (\S+)/) {
			$retmsg .= ",$1";
		}
		if($ret =~ /\.\.\. deliverable: mailer esmtp, host \S+, user (\S+)/) {
			$retmsg .= ",$1";
		}
		if($ret =~ /\.\.\. aliased to (\S+)/) {
			$retmsg .= ",$1";
		}
	}
	close(SMVF);
	$retmsg =~ s/(^,|\s+)//g if defined $retmsg;
	return $retmsg;
}

sub unlockfile {
	my($file) = @_;
	rmdir("$file.lock");
}

sub lockfile {
	my($file) = @_;
	my($count) = 60;
	# print STDERR "mkdir(\"$file.lock\",0)\n";
	while(!mkdir("$file.lock",0) && $count) {
		if(int($!) == 17) {
			sleep(2);
			$count--;
		} else {
			return 0;
		}        
	}
	return 1;
}

sub Debug {
	my($msg) = @_;
	chomp($msg);
	return unless $debug;
	open(DE,">>/tmp/minimust.debug.$$") || die "Can't open debug";
	print DE scalar(localtime(time)),": $msg\n";
	close(DE);
}

