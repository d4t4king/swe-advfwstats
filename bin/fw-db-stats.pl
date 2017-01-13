#!/usr/bin/perl -w

use strict;
use warnings;
require 5.010;
use feature qw( switch );

use Getopt::Long qw( :config no_ignore_case bundling );
use DBI;
use Term::ANSIColor;
use Data::Dumper;
use IO::Uncompress::Gunzip qw( gunzip $GunzipError );
use Geo::IP::PurePerl;

use lib "usr/lib/perl5/site_perl/5.14.4/";
use SQL::Utils;

my ($dbfile, $depth, $help, $onetime, $verbose);
our ($crontab);

my $__depth__ = 10;

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

if ($help) { &Usage(); }

if ($verbose) { print "Checking perl mods....\n"; }
if (&check_perl_mods()) {
	use Net::Nslookup;
	use Geo::IP::PurePerl;
	use Date::Calc qw( :all );
}

if (($depth) && ($depth ne "") && ($depth =~ /\d+/)) { $__depth__ = $depth; }

if (!defined($dbfile)) { warn yellow("Must have database file defined! \($dbfile\)"); &Usage(); }

if ($verbose) { print "Checking GeoIP database....\n"; }

&check_geoip_db();

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
	my $rtv = $sql_utils_obj->execute_non_query($sql);
	print STDERR "RTV: $rtv\n" if ($verbose);
}

#
### Grab data from tables (if exist)
#
if ($verbose) { print "Loading existing database data (filters)....\n"; }
my (%db_countries_cc, %db_countries_name, %db_filters, %db_ifaces, %db_sources, %db_dests, %db_dports);
my $sql = "SELECT id,cc,name FROM countries";
my $results = $sql_utils_obj->execute_multi_row_query($sql);
foreach my $result ( @{$results} ) {
	$db_countries_cc{$result->{'cc'}} = $result->{'id'};
	$db_countries_name{$result->{'name'}} = $result->{'id'};
}

# interfaces
$sql = "SELECT name,datetime,hitcount FROM ifaces";
$results = $sql_utils_obj->execute_multi_row_query($sql);
foreach my $result ( @{$results} ) {
	$db_ifaces{$result->{'name'}}{$result->{'datetime'}} = $result->{'hitcount'};
}
# filters
$sql = "SELECT name,datetime,hitcount FROM filters";
$results = $sql_utils_obj->execute_multi_row_query($sql);
foreach my $result ( @{$results} ) {
	$db_filters{$result->{'name'}}{$result->{'datetime'}} = $result->{'hitcount'};
}
# sources
$sql = "SELECT ip_addr,datetime,hitcount FROM sources";
$results = $sql_utils_obj->execute_multi_row_query($sql);
foreach my $result ( @{$results} ) {
	$db_sources{$result->{'ip_addr'}}{$result->{'datetime'}} = $result->{'hitcount'};
}
# destinations
$sql = "SELECT ip_addr,datetime,hitcount FROM destinations";
$results = $sql_utils_obj->execute_multi_row_query($sql);
foreach my $result ( @{$results} ) {
	$db_dests{$result->{'ip_addr'}}{$result->{'datetime'}} = $result->{'hitcount'};
}
# dest_ports
$sql = "SELECT port_num, datetime, hitcount FROM dest_ports";
$results = $sql_utils_obj->execute_multi_row_query($sql);
foreach my $result ( @{$results} ) {
	$db_dports{$result->{'port_num'}}{$result->{'datetime'}} = $result->{'hitcount'};
}

#
### Parse the log file(s) for the relevant data to insert
#
if ($verbose) { print "Loading data from logs into database (filters)....\n"; }
my (%filters, %iface_pkts, %sources, %dests, %dports, %protos);
my ($src, $dst, $dport, $proto);
if ($onetime) {
	if ($verbose) { print "_onetime_ flag set.  Loading historical data...\n"; }
	my @files = `/bin/ls -1 /var/log/messages*`;
	foreach my $file (reverse @files) {
		chomp($file);
		my $ext = (split(/\./, $file))[-1];
		if ($ext eq 'gz') {
			my $z = new IO::Uncompress::Gunzip $file
				or die "gunzip failed $GunzipError\n";
			while (my $line = $z->getline()) {
				chomp($line);
				next unless ($line =~ /swe\s+kernel\:/);
				my ($y, $m, $d, $h, $mm, $s, $mkt) = &extract_log_date($line);
				if ($verbose) { print STDERR "($y $m $d, $h, $mm, $s, $mkt)\n"; }
				if ($line =~ /IN=(.*?) /) { $iface_pkts{$1}{$mkt}++; }
				if ($line =~ /(\.\.FFC\.\.not\.GREEN\.subnet\.\.|Denied-by-\w+:.*? )/) {
					my $f = $1;
					next if ((!defined($f)) || ($f eq ''));
					$filters{$f}{$mkt}++;
				}
				if ($line =~ /SRC=(.*?) /) { 
					$src = $1; 
					next if (exists($db_sources{$src}{$mkt}));
					$sources{$src}{$mkt}++; 
				}
				if ($line =~ /DST=(.*?) /) { 
					$dst = $1; 
					next if (exists($db_dests{$dst}{$mkt}));
					$dests{$dst}{$mkt}++; 
				}
				if ($line =~ /DPT=(.*?) /) { 
					$dport = $1; 
					next if (exists($db_dports{$dport}{$mkt}));
					$dports{$dport}{$mkt}++; 
				}
			}
		} else {
			open LOG, $file or die "Can't open log file ($file) for reading: $! \n";
			while (my $line = <LOG>) {
				chomp($line);
				next unless ($line =~ /swe\s+kernel\:/);
				my ($y, $m, $d, $h, $mm, $s, $mkt) = &extract_log_date($line);
				if ($verbose) { print STDERR "($y $m $d, $h, $mm, $s, $mkt)\n"; }
				if ($line =~ /IN=(.*?) /) { $iface_pkts{$1}{$mkt}++; }
				if ($line =~ /(\.\.FFC\.\.not\.GREEN\.subnet\.\.|Denied-by-\w+:.*? )/) {
					my $f = $1;
					next if ((!defined($f)) || ($f eq ''));
					$filters{$f}{$mkt}++;
				}
				if ($line =~ /SRC=(.*?) /) { 
					$src = $1; 
					next if (exists($db_sources{$src}{$mkt}));
					$sources{$src}{$mkt}++; 
				}
				if ($line =~ /DST=(.*?) /) { 
					$dst = $1; 
					next if (exists($db_dests{$dst}{$mkt}));
					$dests{$dst}{$mkt}++; 
				}
				if ($line =~ /DPT=(.*?) /) { 
					$dport = $1; 
					next if (exists($db_dports{$dport}{$mkt}));
					$dports{$dport}{$mkt}++; 
				}
			}
		}
	}
} else {
	if ($verbose) { print "Just loading the last 24 hours of log data (filters)....\n"; }
	### FIX ME:  Add the code to add the last 24 hours.
}

#
### Add the "new" stuff to the database.
#
# interfaces
print "Inserting iface data....\n" if ($verbose);
foreach my $iface ( sort keys %iface_pkts ) {
	foreach my $if_date ( sort keys %{$iface_pkts{$iface}} ) {
		$sql_utils_obj->execute_non_query("INSERT INTO ifaces (name,datetime,hitcount) VALUES ('$iface', '$if_date', '$iface_pkts{$iface}{$if_date}')");
	}
}
# filters
print "Inserting filters data....\n" if ($verbose);
foreach my $filter ( sort keys %filters ) {
	foreach my $f_date ( sort keys %{$filters{$filter}} ) {
		$sql_utils_obj->execute_non_query("INSERT INTO filters (name,datetime,hitcount) VALUES ('$filter', '$f_date', '$filters{$filter}{$f_date}');");
	}
}
# get country data for IPs
my $gip = Geo::IP::PurePerl->new('/usr/share/GeoIP/GeoLiteCity.dat', GEOIP_MEMORY_CACHE);

# sources
print "Inserting source data....\n" if ($verbose);
foreach my $src ( sort keys %sources ) {
	foreach my $src_date ( sort keys %{$sources{$src}} ) {
		next if ($src eq '0.0.0.1');		# invalid IP
		print STDERR "SRC: $src\n";
		my $cc_ref = $gip->get_city_record_as_hash($src);
		print STDERR Dumper($cc_ref) if ($verbose);
		if ($cc_ref->{'country_name'} =~ /'/) { $cc_ref->{'country_name'} =~ s/'/''/g; }
		if (!exists($db_countries_cc{$cc_ref->{'country_code'}})) {
			$sql_utils_obj->execute_non_query("INSERT INTO countries (cc,cc3,name) VALUES ('$cc_ref->{'country_code'}', '$cc_ref->{'country_code3'}', '$cc_ref->{'country_name'}')");
			# "refresh" the lookup hashes with the added values
			$results = $sql_utils_obj->execute_multi_row_query("SELECT id,cc,name FROM countries");
			foreach my $result ( @{$results} ) {
				$db_countries_cc{$results->{'cc'}} = $result->{'id'};
				$db_countries_name{$result->{'name'}} = $result->{'id'};
			}
		}
		$sql_utils_obj->execute_non_query("INSERT INTO sources (ip_addr,datetime,hitcount) VALUES ('$src', '$src_date', '$sources{$src}{$src_date}');");
	}
}
# destinations
print "Inserting destination data....\n" if ($verbose);
foreach my $dst ( sort keys %dests ) {
	foreach my $dst_date ( sort keys %{$dests{$dst}} ) {
		my $cc_ref = $gip->get_city_record_as_hash($dst);
		print STDERR Dumper($cc_ref) if ($verbose);	
		if (!exists($db_countries_cc{$cc_ref->{'country_code'}})) {
			$sql_utils_obj->execute_non_query("INSERT INTO countries (cc,cc3,name) VALUES ('$cc_ref->{'country_code'}', '$cc_ref->{'country_code3'}', '$cc_ref->{'country_name'}')");
			# "refresh" the lookup hashes with the added values
			$results = $sql_utils_obj->execute_multi_row_query("SELECT id,cc,name FROM countries");
			foreach my $result ( @{$results} ) {
				$db_countries_cc{$result->{'cc'}} = $result->{'id'};
				$db_countries_name{$result->{'name'}} = $result->{'id'};
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

sub extract_log_date() {
	my $line = shift(@_);
	if ($line =~ /(\w+)\s*(\d+)\s*([0-9:]+)\s*(\w+)\s*/) {
		my $m = $1; my $d = $2; my $time = $3;
		my ($h, $mm, $s) = split(/\:/, $time);
		my $mnum = &mon2num($m);
		my $gmt = gmtime();
		my $y = This_Year($gmt);
		my $mktime = Mktime($y, $mnum, $d, $h, $mm, $s);

		return ($y, $mnum, $d, $h, $mm, $s, $mktime);
	} else {
		warn "extract_log_date(): Received invalid or unrecognizeable log line (with date??)\n";
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
