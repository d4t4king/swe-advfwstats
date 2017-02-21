#!/usr/bin/perl

use strict;
use warnings;
use feature qw( switch );

use lib "/usr/lib/smoothwall";
use header qw( :standard );

use CGI;
use DBI;
use Date::Calc qw( Time_to_Date );
use Data::Dumper;
use Geo::IP::PurePerl;
use Net::IPv4Addr;

use Term::ANSIColor qw( colored );

my $q = CGI->new();
my $errormessage = '';
my (%filtersettings, %checked, %ethernetsettings);
my ($db, $sth, $rtv);

&readhash("${swroot}/ethernet/settings", \%ethernetsettings);

$checked{'ENABLE'}{'off'} = '';
$checked{'ENABLE'}{'on'} = '';
$checked{'cbxNoGreenSource'}{'off'} = '';
$checked{'cbxNoGreenSource'}{'on'} = '';
$checked{'cbxNoRedDest'}{'off'} = '';
$checked{'cbxNoRedDest'}{'on'} = '';

$filtersettings{'ddlPeriod'} = '';
$filtersettings{'cbxNoGreenSource'} = '';
$filtersettings{'cbxNoRedDest'} = '';
$filtersettings{'ACTION'} = '';
$filtersettings{'FILTER1'} = '';

&getcgihash(\%filtersettings);

$checked{'cbxNoGreenSource'}{$filtersettings{'cbxNoGreenSource'}} = 'CHECKED';
#
#### Data poulation for Charts.  Source graph is above.
#
my (%filters, %iface_pkts, %sources, %dests, %dports);
my $now = time();

#
#### Load the data from the database
#
# interfaces
$db = DBI->connect("dbi:SQLite:/var/smoothwall/mods/adv_fw_stats/var/db/fwstats.db", "", "");
$sth = $db->prepare("SELECT name,SUM(hitcount) FROM ifaces GROUP BY name ORDER BY SUM(hitcount) DESC") or die "can't execute statement: $DBI::errstr";
$rtv = $sth->execute() or die "Can't execute statement: $DBI::errstr";
while (my @row = $sth->fetchrow_array()) {
	$iface_pkts{$row[0]} = $row[1];
}
# filters
$sth = $db->prepare("SELECT name,SUM(hitcount) FROM filters GROUP BY name ORDER BY SUM(hitcount) DESC") or die "Can't prepare statement: $DBI::errstr";
$sth->execute() or die "Can't execute statement: $DBI::errstr";
while (my @row = $sth->fetchrow_array()) {
	$filters{$row[0]} = $row[1];
}
# sources
$sth = $db->prepare("SELECT ip_addr,SUM(hitcount) FROM sources GROUP BY ip_addr ORDER BY SUM(hitcount) DESC LIMIT 5") or die "Can't prepare statement: $DBI::errstr";
$sth->execute() or die "Can't execute statement: $DBI::errstr";
while (my @row = $sth->fetchrow_array()) {
	$sources{$row[0]} = $row[1];
}
# destinations
$sth = $db->prepare("SELECT ip_addr,SUM(hitcount) FROM destinations GROUP BY ip_addr ORDER BY SUM(hitcount) DESC LIMIT 5") or die "Can't prepare statement: $DBI::errstr";
$sth->execute() or die "Can't execute statement: $DBI::errstr";
while (my @row = $sth->fetchrow_array()) {
	$dests{$row[0]} = $row[1];
}
# dest ports
$sth = $db->prepare("SELECT port_num,SUM(hitcount) from dest_ports GROUP BY port_num ORDER BY SUM(hitcount) DESC LIMIT 5") or die "Can't prepare statement: $DBI::errstr";
$sth->execute() or die "Can't execute statement: $DBI::errstr";
while (my @row = $sth->fetchrow_array()) {
	$dports{$row[0]} = $row[1];
}

warn $DBI::errstr if $DBI::err;
$sth->finish() or die "There was a problem cleaning up the statement handle: $DBI::errstr";

$db->disconnect();

#
### Done loading the data.  Now load the page.
#

&showhttpheaders();

print "\<!-- MARKER################################################################MARKER -->\n";

&openpage("Advanced FW Statistics", 1, "", "Advanced FW Statistics __");

&openbigbox("100%", "LEFT");

&alertbox($errormessage);

my $gip = Geo::IP::PurePerl->open('/usr/share/GeoIP/GeoIP.dat', 'GEOIP_MEMORY_CACHE');

&openbox('DEBUG');
print <<PRE;
<pre>
	ENV{'QUERY_STRING'}	=>	$ENV{'QUERY_STRING'}
	\$now	=>	$now
	ddlPeriod	=>	$filtersettings{'ddlPeriod'}
	NoGreenSource	=>	$filtersettings{'cbxNoGreenSource'}
	NoGreenSource Checked	=>	$checked{'cbxNoGreenSource'}{'on'}
	NoGreenSource Checked	=>	$checked{'cbxNoGreenSource'}{'off'}
	NoRedDest	=>	$filtersettings{'cbxNoRedDest'}
	NoRedDest Checked	=>	$checked{'cbxNoRedDest'}{'on'}
	NoRedDest Checked	=>	$checked{'cbxNoRedDest'}{'off'}
	ACTION	=>	$filtersettings{'ACTION'}
</pre>
<h4>ethernetsettings</h4>
<pre>
PRE

print Dumper(\%ethernetsettings);

print "</pre>\n";
print <<EOHTML;
<h4>filtersettings</h4>
<pre>
EOHTML

print Dumper(\%filtersettings);

print "</pre>\n";

&closebox();

&openbox($tr{'afws_global_fw_statistics'});

print "<form method='POST' action='?' name='filterCheckBoxForm'>\n";

print <<EOS;

<table style="width: 100%">
	<tr>
		<!-- <td style="width: 20%;">
			<select name="ddlPeriod" id="ddlPeriod">
				<option value="">&nbsp;</option>
				<option value="24_hours">Last 24 Hours</option>
				<option value="7_days">Last 7 Days</option>
			</select>
		</td>
		<td style="width: 20%; align: left">
			<input type="submit" name="ACTION" id="btnSubmit" value="Update Period"></input>
		</td> -->
		<td style="width: 60%;">
			<label id="lblGreenFromSources">$tr{'afws_filter_green'}</label>
			<input type="checkbox" name="cbxNoGreenSource" id="cbxNoGreenSource" $checked{'cbxNoGreenSource'}{'on'}></input>
			<label id="lblRedFromDests">$tr{'afws_filter_red'}</label>
			<input type="checkbox" name="cbxNoRedDest" id="cbxNoRedDest" $checked{'cbxNoRedDest'}{'on'}></input>
			<input type="submit" name="ACTION" id="btnFilter1" value="FILTER"></input>
		</td>
	</tr>
	<!-- <tr>
		<td colspan="3">
			<label>Filter: </label><input type="textbox" id="txtFilter" name="txtFilter"></input>
		</td>
	</tr> -->
</table><br /><br />
EOS

my $line_cnt = 0;
print $q->h3($tr{'afws_interfaces'});
print "\n\t\t<table class=\"centered\" style=\"width: 75%\">\n";
foreach my $if ( sort { $iface_pkts{$b} <=> $iface_pkts{$a} } keys %iface_pkts ) {
	if ($line_cnt % 2 == 0 ) {
		print "\t\t\t<tr class=\"light\"><td style=\"width: 80%\">$if</td><td style=\"width: 20%\">$iface_pkts{$if}</td></tr>\n";
	} else {
		print "\t\t\t<tr class=\"dark\"><td style=\"width: 80%\">$if</td><td style=\"width: 20%\">$iface_pkts{$if}</td></tr>\n";
	}
	$line_cnt++;
}
print "\t\t</table>\n";
print "<br /><br />\n";
$line_cnt = 0;
print $q->h3($tr{'afws_filters'});
print "\n<table class=\"centered\" style=\"width: 75%\">\n";
foreach my $f ( sort { $filters{$b} <=> $filters{$a} } keys %filters ) {
	if ($line_cnt % 2 == 0) {
		print "\t\t<tr class=\"light\"><td style=\"width: 80%\">$f</td><td style=\"width: 20%\">$filters{$f}</td></tr>\n";
	} else {
		print "\t\t<tr class=\"dark\"><td style=\"width: 80%\">$f</td><td style=\"width: 20%\">$filters{$f}</td></tr>\n";
	}
	$line_cnt++;
}
print "</table>\n";
print "<br /><br />\n";
$line_cnt = 0;
print $q->h3($tr{'afws_sources'});
print "\n<table class=\"centered\" style=\"width: 75%\">\n";
foreach my $s ( sort { $sources{$b} <=> $sources{$a} } keys %sources ) {
	if ($line_cnt % 2 == 0) {
		print "<tr class=\"light\"><td style=\"width: 40%\">$s</td><td style=\"width: 40%\">";
	} else {
		print "<tr class=\"dark\"><td style=\"width: 40%\">$s</td><td style=\"width: 40%\">"
	}
	### FIX ME:  Use NetIPv4::Addr to match CIDRs,
	# and utilitze the GREEN/RED settings where
	#  appropriate.
	my $country = $gip->country_name_by_addr($s);
	if ($s !~ /192\.168\.1\.\d+/) { print $country; }
	else { print "&nbsp;"; }
	print "</td><td style=\"width: 20%\">$sources{$s}</td></tr>\n";
	$line_cnt++;
}
print "</table>\n";
print "<br /><br />\n";
$line_cnt = 0;
print $q->h3($tr{'afws_destinations'});
print "\n<table class=\"centered\" style=\"width: 75%\">\n";
foreach my $d ( sort { $dests{$b} <=> $dests{$a} } keys %dests ) {
	if ($line_cnt % 2 == 0 ) {
		print "<tr class=\"light\"><td style=\"width: 40%\">$d</td><td style=\"width: 40%\">";
	} else {
		print "<tr class=\"dark\"><td style=\"width: 40%\">$d</td><td style=\"width: 40%\">";
	}
	### FIX ME:  Use NetIPv4::Addr to match CIDRs,
	# and utilitze the GREEN/RED settings where
	#  appropriate.
	my $country = $gip->country_name_by_addr($d);
	if ($d !~ /192\.168\.1\.\d+/) { print $country; }
	else { print "&nbsp;"; }
	print "</td><td style=\"width: 20%\">$dests{$d}</td></tr>\n";
	$line_cnt++;
}
print "</table\n";
print "<br /><br />\n";
$line_cnt = 0;
print $q->h3("$tr{'afws_dest_ports'}");
print "<table class=\"centered\" style=\"width: 75%\">\n";
foreach my $dp ( sort { $dports{$b} <=> $dports{$a} } keys %dports ) {
	if ($line_cnt % 2 == 0 ) {
		print "<tr class=\"light\"><td style=\"width: 80%\">$dp</td><td style=\"with: 20%\">$dports{$dp}</td></td>\n";
	} else {
		print "<tr class=\"dark\"><td style=\"width: 80%\">$dp</td><td style=\"with: 20%\">$dports{$dp}</td></td>\n";
	}
	$line_cnt++;
}
print "</table>\n";
print "<br /><br />\n";

print "</form>\n";

&closebox();

&alertbox('add', 'add');

&closebigbox();

&closepage();

sub mon2num() {
	no warnings;
	my $m = shift(@_);
	given ($m) {
		when ('Jan') { return '1'; }
		when ('Feb') { return '2'; }
		when ('Mar') { return '3'; }
		when ('Apr') { return '4'; }
		when ('May') { return '5'; }
		when ('Jun') { return '6'; }
		when ('Jul') { return '7'; }
		when ('Aug') { return '8'; }
		when ('Sep') { return '9'; }
		when ('Oct') { return '10'; }
		when ('Nov') { return '11'; }
		when ('Dec') { return '12'; }
		default { die "Unexpected month input: $m\n"; }
	}
}
