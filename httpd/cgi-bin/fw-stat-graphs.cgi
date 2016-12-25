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

use Term::ANSIColor qw( colored );

my $q = CGI->new();
my $errormessage = '';

#print $q->header("Google API Test");
# The "Smoothwall Way"...
&showhttpheaders();

my (@src_toptalkers, @dst_toptalkers, @dates);
my (%src_data_structure, %dst_data_structure);

my $db = DBI->connect("dbi:SQLite:/httpd/html/db/fwsrc.db", "", "");
my $sth = $db->prepare("SELECT ip_addr FROM sources GROUP BY ip_addr ORDER BY SUM(hitcount) DESC LIMIT 5;") or die "Can't prepare statement: $DBI::errstr";
$sth->execute() or die "Can't execute statement: $DBI::errstr";
while (my @row = $sth->fetchrow_array()) {
	push(@src_toptalkers, $row[0]);
}
#$sth = $db->prepare("SELECT ip_addr FROM destinations GROUP BY ip_addr ORDER BY SUM(hitcount) DESC LIMIT 5;") or die "Can't prepare statement: $DBI::errstr";
#$sth->execute() or die "Can't execute statement: $DBI::errstr";
#while (my @row = $sth->fetchrow_array()) {
#	push(@dst_toptalkers, $row[0]);
#}
$sth = $db->prepare("SELECT DISTINCT datetime FROM sources ORDER BY datetime") or die "Can't prpare statement: $DBI::errstr";
$sth->execute() or die "Can't execute statement: $DBI::errstr";
while (my @row = $sth->fetchrow_array()) {
	push(@dates, $row[0]);
}
warn $DBI::errstr if $DBI::err;
$sth->finish() or die "There was a problem cleaning up the SQL statement: $DBI::err";

# loop through the data structue and poplate the top talker keys and the date keys

print STDERR "Toptalkers: ".scalar(@src_toptalkers)."\n";
print STDERR "Dates: ".scalar(@dates)."\n";
foreach my $tt ( @src_toptalkers ) {
	foreach my $d ( @dates ) {
		#$src_data_structure{$tt}{$d} = 1;
		$sth = $db->prepare("SELECT hitcount FROM sources WHERE ip_addr='$tt' AND datetime='$d'") or die "Can't prepare statement: $DBI::errstr";
		$sth->execute() or die "Can't execute statement: $DBI::errstr";
		while (my @row = $sth->fetchrow_array()) { $src_data_structure{$tt}{$d} = $row[0] ? $row[0] : 0; }
	}
}
# loop through the data structue and poplate the top talker keys and the date keys
#foreach my $tt ( @dst_toptalkers ) {
#	foreach my $d ( @dates ) {
#		#$src_data_structure{$tt}{$d} = 1;
#		$sth = $db->prepare("SELECT hitcount FROM destinations WHERE ip_addr='$tt' AND datetime='$d'") or die "Can't prepare statement: $DBI::errstr";
#		$sth->execute() or die "Can't execute statement: $DBI::errstr";
#		while (my @row = $sth->fetchrow_array()) { $dst_data_structure{$tt}{$d} = $row[0] ? $row[0] : 0; }
#	}
#}
#warn $DBI::errstr if $DBI::err;
#$sth->finish() or die "There was a problem cleaning up the statement: $DBI::errstr";
#$db->disconnect();

warn $DBI::errstr if $DBI::err;
$sth->finish() or die "There was a problem cleaning up the statement handle: $DBI::errstr";

$db->disconnect();

&openpage("Google API Test", 1, "", "Google API Test __");

&openbigbox("100%", "LEFT");

&alertbox($errormessage);

&openbox();

print <<EOS;
		<script type="text/javascript" src="https://www.google.com/jsapi"></script>
		<script type="text/javascript">
			google.load('visualization', '1.1', {packages: ['line']});
			google.setOnLoadCallback(drawChart);

			function drawChart() {
				var data = new google.visualization.DataTable();
				data.addColumn('date', 'Date');
EOS
	
	foreach my $tt ( @src_toptalkers ) {
		print "\t\t\t\tdata.addColumn('number', '$tt');\n";
	}
#data.addColumn('number', 'Hits');
	
print <<EOS;
				data.addRows([
EOS

	foreach my $date ( sort @dates ) {
		my ($y,$m,$d,$h,$M,$s) = Time_to_Date($date);
		print "\t\t\t\t\t[new Date($y,".($m-1).",$d,$h,$M,$s,'000'), ";
		if (defined($src_data_structure{$src_toptalkers[0]}{$date})) { print "$src_data_structure{$src_toptalkers[0]}{$date}, "; }
		else { print "0, "; }
		if (defined($src_data_structure{$src_toptalkers[1]}{$date})) { print "$src_data_structure{$src_toptalkers[1]}{$date}, "; }
		else { print "0, "; }
		if (defined($src_data_structure{$src_toptalkers[2]}{$date})) { print "$src_data_structure{$src_toptalkers[2]}{$date}, "; }
		else { print "0, "; }
		if (defined($src_data_structure{$src_toptalkers[3]}{$date})) { print "$src_data_structure{$src_toptalkers[3]}{$date}, "; }
		else { print "0, "; }
		if (defined($src_data_structure{$src_toptalkers[4]}{$date})) { print "$src_data_structure{$src_toptalkers[4]}{$date} ],\n"; }
		else { print "0 ],\n"; }
	}

print <<EOS;
				]);

				var options = {
					chart: {
						title: 'Top Talking Sources',
						legend: { position: 'bottom' }
					},
					width: 750,
					hight: 415
				};

				var chart = new google.charts.Line(document.getElementById('curve_chart'));

				chart.draw(data, options);
			}
		</script>

		<div id="curve_chart" style="width: 750px; height: 415px"></div>
EOS

#print <<EOS;
#		<script type="text/javascript" src="https://www.google.com/jsapi"></script>
#		<script type="text/javascript">
#			google.load('visualization', '1.1', {packages: ['line']});
#			google.setOnLoadCallback(drawChart2);
#
#			function drawChart2() {
#				var data = new google.visualization.DataTable();
#				data.addColumn('date', 'Date');
#EOS
#	
#	foreach my $tt ( @dst_toptalkers ) {
#		print "\t\t\t\tdata.addColumn('number', '$tt');\n";
#	}
##data.addColumn('number', 'Hits');
#	
#print <<EOS;
#				data.addRows([
#EOS
#
#	foreach my $date ( sort @dates ) {
#		my ($y,$m,$d,$h,$M,$s) = Time_to_Date($date);
#		print "\t\t\t\t\t[new Date($y,".($m-1).",$d,$h,$M,$s,'000'), ";
#		if (defined($dst_data_structure{$dst_toptalkers[0]}{$date})) { print "$dst_data_structure{$dst_toptalkers[0]}{$date}, "; }
#		else { print "0, "; }
#		if (defined($dst_data_structure{$dst_toptalkers[1]}{$date})) { print "$dst_data_structure{$dst_toptalkers[1]}{$date}, "; }
#		else { print "0, "; }
#		if (defined($dst_data_structure{$dst_toptalkers[2]}{$date})) { print "$dst_data_structure{$dst_toptalkers[2]}{$date}, "; }
#		else { print "0, "; }
#		if (defined($dst_data_structure{$dst_toptalkers[3]}{$date})) { print "$dst_data_structure{$dst_toptalkers[3]}{$date}, "; }
#		else { print "0, "; }
#		if (defined($dst_data_structure{$dst_toptalkers[4]}{$date})) { print "$dst_data_structure{$dst_toptalkers[4]}{$date} ],\n"; }
#		else { print "0 ],\n"; }
#	}
#
#print <<EOS;
#				]);
#
#				var options = {
#					chart: {
#						title: 'Top Talking Destinations',
#						legend: { position: 'bottom' }
#					},
#					width: 750,
#					hight: 415
#				};
#
#				var chart = new google.charts.Line(document.getElementById('curve_chart2'));
#
#				chart.draw(data, options);
#			}
#		</script>
#
#		<div id="curve_chart2" style="width: 750px; height: 415px"></div>
#EOS

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
