#!/usr/bin/perl -w

use strict;
use warnings;
require 5.010;
use feature qw( switch );

use Getopt::Long qw( :config no_ignore_case bundling );
use Term::ANSIColor;
use Data::Dumper;
use IO::Uncompress::Gunzip qw( gunzip $GunzipError );
use Geo::IP::PurePerl;

use lib "/var/smoothwall/mods/advfwstats/usr/lib/perl5/site_perl/5.14.4";
use SQL::Utils;

my ($dbfile, $depth, $help, $onetime, $verbose);
our ($crontab);

my $__depth__ = 10;
my $hostname = `/usr/bin/hostname`;
chomp($hostname);

GetOptions( 
	'onetime'		=>	\$onetime,
	'd|dbfile=s'	=>	\$dbfile,
	'D|depth=s'		=>	\$depth,
	'c|crontab'		=>	\$crontab,
	'h|?|help'		=>	\$help,
	'v|verbose+'	=>	\$verbose,
);

my %colors2html = (
	'red'		=>	'#FF0000',
	'blue'		=>	'#0000FF',
	'green'		=>	'#00FF00',
	'purple'	=>	'#800080',
	'orange'	=>	'#FFA500',
);

my %known_filters = ( 
	'Denied-by-filter:FORWARD' 		=>	1,
	'Denied-by-filter:badtraffic'	=>	1,
	'Denied-by-filter:outgoing'		=>	1,
	'Denied-by-filter:tndrop'		=>	1,
);
my %unknown_filters;

if ($help) { &Usage(); }

if ($verbose) { print "Checking perl mods....\n"; }
if (&check_perl_mods()) {
	use Net::Nslookup;
	use Geo::IP::PurePerl;
	use Date::Calc qw( :all );
}

if (($depth) && ($depth ne "") && ($depth =~ /\d+/)) { $__depth__ = $depth; }

if (!defined($dbfile)) { warn yellow("Must have database file defined! \($dbfile\)"); &Usage(); }

my $is_cron = 0;
eval { open TTY, "/dev/tty"; if ($? == 0) { $is_cron = 0; close TTY; } };
if ($@) { $is_cron = 1; }

# don't run the interactive check if we are running in cron
unless (($is_cron) or ($crontab)) {
	if ($verbose) { print "Checking GeoIP database....\n"; }
	&check_geoip_db();
}

#
### Initialize Database Tables (if not exist)
#
my @create_tables_sql = (
	"CREATE TABLE IF NOT EXISTS countries (id INTEGER PRIMARY KEY AUTOINCREMENT, cc TEXT, cc3 TEXT, name text)",
	"CREATE TABLE IF NOT EXISTS ifaces (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, datetime INTEGER, hitcount INTEGER);",
	"CREATE TABLE IF NOT EXISTS filters (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, datetime INTEGER, hitcount INTEGER);",
	"CREATE TABLE IF NOT EXISTS sources (id INTEGER PRIMARY KEY AUTOINCREMENT, ip_addr TEXT, name TEXT, country_id INTEGER, latitude FLOAT, longitude FLOAT, datetime DATETIME, hitcount INTEGER);",
	"CREATE TABLE IF NOT EXISTS destinations (id INTEGER PRIMARY KEY AUTOINCREMENT, ip_addr TEXT, name TEXT, country_id INTEGER, latitude FLOAT, longitude FLOAT, datetime DATETIME, hitcount INTEGER);",
	"CREATE TABLE IF NOT EXISTS dest_ports (id INTEGER PRIMARY KEY AUTOINCREMENT, port_num INTEGER, protocol TEXT, datetime DATETIME, hitcount INTEGER)"
);

if ($verbose) { print "Setting up the tables in the database file ($dbfile)....\n"; }
my $sql_utils_obj = SQL::Utils->new('sqlite3', {'db_filename' => $dbfile});
foreach my $sql ( @create_tables_sql ) {
	#print "$sql\n";
	print join(" ", (split(" ", $sql))[0..5]).": ";
	my $rtv = $sql_utils_obj->execute_non_query($sql);
	print "RTV: $rtv\n" if ($verbose);
}

# set autoflush so we get output immediately
if ($verbose) { local $| = 1; }
#
### Grab data from tables (if exist)
#
if ($verbose) { print "Loading existing database data (filters)....\n"; }
my (%db_countries_cc, %db_countries_name, %db_filters, %db_ifaces, %db_sources, %db_dests, %db_dports);
my $sql = "SELECT id,cc,name FROM countries";
my @results = $sql_utils_obj->execute_multi_field_query($sql);
if (scalar(@results) > 0) {
	foreach my $result ( @results ) {
		my ($id,$cc,$country) = split(/\|/, $result);
		$db_countries_cc{$cc} = $id;
		$db_countries_name{$country} = $id;
	}
} else {
	if ($verbose) { print colored("Got 0 results from pre-existing countries query.\n", "yellow"); }
}

my %existing_data_sql = (
	'ifaces'		=>	'SELECT name,datetime,hitcount FROM ifaces;',
	'filters'		=>	'SELECT name,datetime,hitcount FROM filters;',
	'sources'		=>	'SELECT ip_addr,datetime,hitcount FROM sources;',
	'dests'			=>	'SELECT ip_addr,datetime,hitcount FROM destinations;',
	'dest_ports'	=>	'SELECT port_num,datetime,hitcount FROM dest_ports;',
);

foreach my $tbl_key ( sort keys %existing_data_sql ) {
	@results = $sql_utils_obj->execute_multi_field_query($existing_data_sql{$tbl_key});
	if (scalar(@results) == 0) {
		if ($verbose) { print colored("Got 0 results for pre-existing '$tbl_key' query\n", "yellow"); }
		next;
	}
	foreach my $result ( @results ) {
		given ($tbl_key) {
			when ('ifaces') {
				my ($name,$dt,$hc) = split(/\|/, $result);
				$db_ifaces{$name}{$dt} = $hc;
			}
			when ('filters') {
				my ($name,$dt,$hc) = split(/\|/, $result);
				$db_filters{$name}{$dt} = $hc;
			}
			when ('sources') {
				my ($ip,$dt,$hc) = split(/\|/, $result);
				$db_sources{$ip}{$dt} = $hc;
			}
			when ('dests') {
				my ($ip,$dt,$hc) = split(/\|/, $result);
				$db_dests{$ip}{$dt} = $hc;
			}
			when ('dest_ports') {
				my ($pn,$dt,$hc) = split(/\|/, $result);
				$db_dports{$pn}{$dt} = $hc;
			}
			default { 
				# we should never get here
			}
		}
	}
}

#
### Parse the log file(s) for the relevant data to insert
#
if ($verbose) { print "Loading data from logs into database (filters)....\n"; }
my (%filters, %iface_pkts, %sources, %dests, %dports, %protos);
my ($src, $dst, $dport, $proto);
my @lines;
if ($onetime) {
	if ($verbose) { print "_onetime_ flag set.  Loading historical data...\n"; }
	my @files = `/bin/ls -1 /var/log/messages*`;
	print colored("Got ".scalar(@files)." log files for historical data.\n", "cyan") if ($verbose);
	foreach my $file (reverse @files) {
		chomp($file);
		my $ext = (split(/\./, $file))[-1];
		if ($ext eq 'gz') {
			my $z = new IO::Uncompress::Gunzip $file
				or die "gunzip failed $GunzipError\n";
			while (my $line = $z->getline()) {
				next unless ($line =~ /$hostname\s+kernel\:/);
				chomp($line);
				push @lines, $line;
			}
			$z->close;
		} else {
			if ($file =~ /\//) {
				use File::Basename;
				$file = basename($file);
			}
			system("/bin/cp /var/log/$file /tmp/$file.$$");
			open LOG, "/tmp/$file.$$" or die "Can't open log file (/tmp/$file.$$) for reading: $! \n";
			while (my $line = <LOG>) {
				chomp($line);
				next unless ($line =~ /swe\s+kernel\:/);
				push @lines, $line;
			}
			close LOG or die "There was a problem closing the log file ($file): $! \n";
			system("/bin/rm /tmp/$file.$$");
		}
	}
} else {
	if ($verbose) { print "Just loading the last 24 hours of log data (filters)....\n"; }
	### Add the code to add the last 24 hours.
	#warn "### Previous 24-hour code still required!\n";
	# Should be set now.
	system("/bin/cp -f /var/log/messages /tmp/messages.$$");
	my $str = `head -1 /tmp/messages.$$`;
	chomp($str);
	my ($fy,$fm,$fd,$fH,$fM,$fS,$fmkt) = &extract_log_date($str);
	$str = `tail -1 /tmp/messages.$$`;
	chomp($str);
	my ($ly,$lm,$ld,$lH,$lM,$lS,$lmkt) = &extract_log_date($str);
	print "$fy,$fm,$fd,$fH,$fM,$fS,$fmkt\n";
	print "$ly,$lm,$ld,$lH,$lM,$lS,$lmkt\n";
	my $target_mktime = $lmkt - 86400;
	open LOG, "</tmp/messages.$$" or die red("Unable to open temp messages file for reading: $!");
	while (my $line = <LOG>) {
		chomp($line);
		next unless ($line =~ /swe\s+kernel\:/);
		my ($sy,$sm,$sd,$sH,$sM,$sS,$smkt) = &extract_log_date($line);
		if ($smkt < $target_mktime) {
			push @lines, $line;
		}
	}
	close LOG or die red("There was a problem closoing the temp messages file: $!");
}

	# Now process all the lines
foreach my $line ( @lines ) {
	my ($y, $m, $d, $h, $mm, $s, $mkt) = &extract_log_date($line);
	if ($verbose) { print STDERR "($y $m $d, $h, $mm, $s, $mkt)\n"; }
	if ($line =~ /\bIN=(eth[0-3])\b/) { 
		my $if = $1;
		print colored("IFACE: $if\n", "bold cyan") if ($verbose);
		$iface_pkts{$if}{$mkt}++; 
	}
	if ($line =~ / (\.\.FFC\.\.not\.GREEN\.subnet\.\.|Denied-by-filter:(?:FORWARD|badtraffic|outgoing|tndrop)) /) {
		my $f = $1;
		### FIX ME @@@
		#
		# Need a reliable way to check for "new" filters
		# (all categories really) 
		# We should only get to this line if the regular expression isn't 
		# matched, soooo.....never while these lines are here.
		print colored("Filter not in known filters list: |$f| \n", "yellow") 
			unless (exists($known_filters{$f}));
		$filters{$f}{$mkt}++;
	}
	if ($line =~ / SRC=((?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}?(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)) /) { 
		$src = $1; 
		#$src = trim($src);
		$src =~ s/^\s+|\s+$//g;
		next if ((!defined($src)) or ($src eq ""));
		next if (exists($db_sources{$src}{$mkt}));
		print colored("SRC IP: $src\n", "bold magenta") if ($verbose);
		$sources{$src}{$mkt}++; 
	}
	if ($line =~ / DST=((?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}?(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)) /) { 
		$dst = $1; 
		#$dst = trim($dst);
		$dst =~ s/^\s+|\s+$//g;
		next if ((!defined($dst)) or ($dst eq ""));
		next if (exists($db_dests{$dst}{$mkt}));
		print colored("DEST IP: $dst\n", "bold cyan") if ($verbose);
		$dests{$dst}{$mkt}++; 
	}
	if ($line =~ /DPT=(.*?) /) { 
		$dport = $1; 
		#$dport = trim($dport);
		$dport =~ s/^\s+|\s+$//g;
		next if ((!defined($dport)) or ($dport eq ""));
		next if (exists($db_dports{$dport}{$mkt}));
		print colored("Captured port doesn't look valid: $dport\n", "yellow")
			if ($dport !~ /\d{1,5}/);
		$dports{$dport}{$mkt}++; 
	}
}

#
### Add the "new" stuff to the database.
#
# interfaces
print "Inserting iface data....\n" if ($verbose);
foreach my $iface ( sort keys %iface_pkts ) {
	chomp($iface);
	$iface =~ s/^\s+|\s+$//g ;
	if ($iface =~ /^eth[0-3]$/) {
		foreach my $if_date ( sort keys %{$iface_pkts{$iface}} ) {
			$sql_utils_obj->execute_non_query("INSERT INTO ifaces (name,datetime,hitcount) VALUES ('$iface', '$if_date', '$iface_pkts{$iface}{$if_date}')");
		}
	} else { warn yellow("Unrecognized interface name: $iface "); }
}
# filters
print "Inserting filters data....\n" if ($verbose);
foreach my $filter ( sort keys %filters ) {
	foreach my $f_date ( sort keys %{$filters{$filter}} ) {
		$sql_utils_obj->execute_non_query("INSERT INTO filters (name,datetime,hitcount) VALUES ('$filter', '$f_date', '$filters{$filter}{$f_date}');");
	}
}
# get country data for IPs
my $gip = Geo::IP::PurePerl->new('/usr/share/GeoIP/GeoIP.dat', GEOIP_MEMORY_CACHE);

# sources
print "Inserting source data....\n" if ($verbose);
foreach my $src ( sort keys %sources ) {
	foreach my $src_date ( sort keys %{$sources{$src}} ) {
		next if ($src eq '0.0.0.1');		# invalid IP
		#print STDERR "SRC: $src\n";
		next if (is_rfc1918($src));
		my $cc_ref = $gip->get_city_record_as_hash($src);
		#print STDERR Dumper($cc_ref) if ($verbose);
		if ($cc_ref->{'country_name'} =~ /'/) { $cc_ref->{'country_name'} =~ s/'/''/g; }
		if (!exists($db_countries_cc{$cc_ref->{'country_code'}})) {
			$cc_ref->{'country_name'} =~ s/\'/\%27/g;
			$sql_utils_obj->execute_non_query("INSERT INTO countries (cc,cc3,name) VALUES ('$cc_ref->{'country_code'}', '$cc_ref->{'country_code3'}', '$cc_ref->{'country_name'}')");
			# "refresh" the lookup hashes with the added values
			@results = $sql_utils_obj->execute_multi_field_query("SELECT id,cc,name FROM countries");
			foreach my $result ( @results ) {
				my ($id,$cc,$country) = split(/\|/, $result);
				$db_countries_cc{$cc} = $id;
				$db_countries_name{$country} = $id;
			}
		}
		$sql_utils_obj->execute_non_query("INSERT INTO sources (ip_addr,datetime,hitcount) VALUES ('$src', '$src_date', '$sources{$src}{$src_date}');");
	}
}
# destinations
print "Inserting destination data....\n" if ($verbose);
foreach my $dst ( sort keys %dests ) {
	foreach my $dst_date ( sort keys %{$dests{$dst}} ) {
		next if (is_rfc1918($dst));
		my $cc_ref = $gip->get_city_record_as_hash($dst);
		next if ((!defined($cc_ref->{'country_code'})) or ($cc_ref->{'country_code'} eq ''));
		#print STDERR Dumper($cc_ref) if ($verbose);	
		if (!exists($db_countries_cc{$cc_ref->{'country_code'}})) {
			$cc_ref->{'country_name'} =~ s/\'/\%27/g;
			$sql_utils_obj->execute_non_query("INSERT INTO countries (cc,cc3,name) VALUES ('$cc_ref->{'country_code'}', '$cc_ref->{'country_code3'}', '$cc_ref->{'country_name'}')");
			# "refresh" the lookup hashes with the added values
			@results = $sql_utils_obj->execute_multi_field_query("SELECT id,cc,name FROM countries");
			foreach my $result ( @results ) {
				my ($id,$cc,$country) = split(/\|/, $result);
				$db_countries_cc{$cc} = $id;
				$db_countries_name{$country} = $id;
			}
		}
		$sql_utils_obj->execute_non_query("INSERT INTO destinations (ip_addr,datetime,hitcount) VALUES ('$dst', '$dst_date', '$dests{$dst}{$dst_date}');");
	}
}
# dest ports
print "Inserting destination port data....\n" if ($verbose);
foreach my $dport ( sort keys %dports ) {
	foreach my $dpt_date ( sort keys %{$dports{$dport}} ) {
		$sql_utils_obj->execute_non_query("INSERT INTO dest_ports (port_num, datetime, hitcount) VALUES ('$dport', '$dpt_date', '$dports{$dport}{$dpt_date}');");
	}
}

###############################################################################
sub Usage() {
	
	print <<END

perl $0 -d|--dbfile <database file path> [-D|--depth] [depth] [--onetime] [-v|--verbose]

-d|--dbfile			Specifies the full path to the database file to be used.
-v|--verbose		Display extra output (usually to STDERR)
--onetime			Process all available log data.  Could also be called "firsttime".
-D|--depth			Only show top (depth) IPs/hits/etc.
--crontab			Customize output for routine/periodic crontab execution.
-h|-?|--help		Display this usefull message.  ;-)

END
	;

	exit 0;
}

sub trim { my $s =~ shift; $s = s/^\s+|\s+$//g; return $s; }

sub extract_log_date() {
	my $line = shift(@_);
	if ($line =~ /(\w+)\s*(\d+)\s*([0-9:]+)\s*(\w+)\s*/) {
		my $m = $1; my $d = $2; my $time = $3;
		my ($h, $mm, $s) = split(/\:/, $time);
		my $mnum = &mon2num($m);
		my $gmt = gmtime();
		# if it matched the regex above, but the month
		# is greater than the current month, then it actually
		# was logged last year
		my $y = This_Year($gmt);
		my ($cY,$cM,$cD) = Today($gmt);
		#warn yellow("$cY $cM $cD");
		#warn yellow("$cM <=> $mnum");
		if ($mnum > $cM) {
			($y,$mnum,$d) = Add_Delta_YM($y,$mnum,$d,-1,0);
		}
		my $mktime = Mktime($y, $mnum, $d, $h, $mm, $s);

		return ($y, $mnum, $d, $h, $mm, $s, $mktime);
	} else {
		warn red("extract_log_date(): Received invalid or unrecognizeable log line (with date??)\n");
		warn red($line);
		return -1;
	}
}

sub mon2num() {
	my $mon = shift(@_);
	given ($mon) {
		when (/[Jj]an(?:uary)?/) 	{ return 1;		}
		when (/[Ff]eb(?:ruary)?/) 	{ return 2;		}
		when (/[Mm]ar(?:ch)?/) 		{ return 3;		}
		when (/[Aa]pr(?:il)?/) 		{ return 4;		}
		when (/[Mm]ay/) 			{ return 5; 	}
		when (/[Jj]un(?:e)?/) 		{ return 6;		}
		when (/[Jj]ul(?:y)?/) 		{ return 7;		}
		when (/[Aa]ug(?:ust)?/) 	{ return 8;		}
		when (/[Ss]ep(?:tember)?/) 	{ return 9;		}
		when (/[Oo]ct(?:tober)?/) 	{ return 10;	}
		when (/[Nn]ov(?:ember)?/) 	{ return 11;	}
		when (/[Dd]ec(?:ember)?/) 	{ return 12;	}
		default { die "Unrecognized month string: $mon\n"; }
	}
}

sub check_geoip_db() {
	if ( -f "/usr/share/GeoIP/GeoIP.dat" ) {
		my @stats = stat("/usr/share/GeoIP/GeoIP.dat");
		#print Dumper(@stats);
		my $time = time();
		if (($time - $stats[10]) >= 2592000) {
			print "GeoIP.dat file is over 30 days old.  Consider updating.\n";
			unless ($crontab) {
				print "Would you like to attempt to update the GeoIP database now?\n";
				my $ans = readline();
				chomp($ans);
				if ($ans =~ /[Yy](es)?/) {
					#update the GeoIP database
					require File::Fetch;
					my $ff = File::Fetch->new(uri => 'http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz');
					my $where = $ff->fetch( 'to' => '/tmp' );
					print "==> $where\n";
					my $input = "/tmp/GeoIP.dat.gz";
					my $output = "/usr/share/GeoIP/GeoIP.dat";
					my $status = gunzip $input => $output
						or die "gunzip failed: $GunzipError\n";
				} else {
					print "Good.  Continuing without updating.\n";
				}
			}
		} else {
			print "GeoIP.dat OK.\n";
		}
	} else {
		die boldred("Couldn't find GeoIP.dat.");
	}
}

sub check_perl_mods() {
	my $status = 0;
	#my @mods = ("Net::Nslookup", "Geo::IP::PurePerl", "Date::Calc", "Config::Simple");
	my @mods = ("Net::Nslookup", "Geo::IP::PurePerl", "Date::Calc", "MIME::Lite", "DBD::SQLite");
	foreach my $mod ( @mods ) {
		my $result = `/usr/bin/perl -m$mod -e ";" 2>&1`;
		if ($result =~ /^Can't locate /) {
			print "Couldn't find $mod. Please run the included script: install-mods.sh.\n"; 
			$status = 1
		} elsif ((! defined($result)) || $result eq "") {
			print "$mod OK.\n";
			$status = 1
		} else {
			print "$result\n";
			$status = 0
		}
		if ($status == 0) { return $status; }
	}
	#system("sed -i -e 's/#\(use .*\)/\1/g' $0");
	return $status;
}


sub parse_datetime($) {
	no warnings;
	my $dstr = shift(@_);
	my ($date, $time) = split(/ /, $dstr);
	my ($y, $m, $d) = split(/\//, $date);
	my ($h, $mm, $s) = split(/:/, $time);

	return ($y, $m, $d, $h, $mm, $s);
}

sub is_rfc1918 {
	use Net::IPv4Addr qw( ipv4_in_network );
	my $ip = shift;
	return undef unless ($ip =~ /(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/);
	given ($ip) {
		when (ipv4_in_network("10.0.0.0/8", $ip))		{ return 1; }	#true
		when (ipv4_in_network("172.16.0.0/12", $ip))	{ return 1; }	#true
		when (ipv4_in_network("192.168.0.0/16", $ip))	{ return 1; }	#true
		default 										{ return 0; }	#false
	}
}

sub red {
	my $str = shift;
	return colored("$str", "red");
}
sub boldred {
	my $str = shift;
	return colored("$str", "bold red");
}
sub yellow {
	my $str = shift;
	return colored("$str", "yellow");
}
sub boldyellow {
	my $str = shift;
	return colored("$str", "bold yellow");
}
sub green {
	my $str = shift;
	return colored("$str", "green");
}
sub boldgreen {
	my $str = shift;
	return colored("$str", "bold green");
}
