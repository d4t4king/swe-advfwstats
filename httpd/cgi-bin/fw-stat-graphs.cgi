#!/usr/bin/perl

use strict;
use warnings;
use feature qw( switch );

use lib "/usr/lib/smoothwall";
use header qw( :standard );

use CGI;
use Date::Calc qw( Time_to_Date );
use Data::Dumper;

use lib '/var/smoothwall/mods/advfwstats/usr/lib/perl5/site_perl/5.14.4';
use SQL::Utils;

my $q = CGI->new();
my $errormessage = '';

#print $q->header("Google API Test");
# The "Smoothwall Way"...
&showhttpheaders();

my (@src_toptalkers, @dst_toptalkers, @dates);
my (%src_struct, %dst_struct);

my $db = SQL::Utils->new("sqlite3", {'db_filename'=>"/var/smoothwall/mods/advfwstats/var/db/fwstats.db"});
my $sql = "SELECT ip_addr FROM sources GROUP BY ip_addr ORDER BY SUM(hitcount) DESC LIMIT 5;";
@src_toptalkers = $db->execute_single_field_query($sql);

my (%datetimes);
foreach my $tt ( @src_toptalkers ) {
	$sql = "SELECT datetime,hitcount FROM sources WHERE ip_addr='$tt' ORDER BY datetime DESC LIMIT 10;";
	my @rows = $db->execute_multi_field_query($sql);
	foreach my $row ( @rows ) {
		my ($dt,$hc) = split(/\|/, $row);
		$datetimes{$dt}++;
		$src_struct{$dt}{$tt} = $hc;
	}
}

&openpage("Google API Test", 1, "", "Google API Test __");

&openbigbox("100%", "LEFT");

&alertbox($errormessage);

&openbox();

print <<EOS;
		<script type="text/javascript" src="https://www.google.com/jsapi"></script>
		<script type="text/javascript">
			google.charts.load('current', {'packages':['line']});
			google.charts.setOnLoadCallback(drawChart);

			function drawChart() {
				var data = new google.visualization.arrayToDataTable([
EOS
no warnings;
print "\t\t\t\t\t['Date','".join("','", @src_toptalkers)."'],\n";
foreach my $dt ( sort keys %datetimes ) {
	my ($y,$m,$d,$H,$M,$S) = Time_to_Date($dt);
	$m--;
	if (length($m) == 1) { $m = "0$m"; }
	if (length($d) == 1) { $d = "0$d"; }
	if (length($H) == 1) { $H = "0$H"; }
	if (length($M) == 1) { $M = "0$M"; }
	if (length($S) == 1) { $S = "0$S"; }
	print "\t\t\t\t\t[new Date($y,$m,$d,$H,$M,$S,000),";
	my $count = 0;
	foreach my $tt ( @src_toptalkers ) {
		if (!defined($src_struct{$dt}{$tt})) {
			$src_struct{$dt}{$tt} = 0;
		}
		if ($count == 4) {
			print "$src_struct{$dt}{$tt}";
		} else {
			print "$src_struct{$dt}{$tt},";
		}
		$count++;
	}
	print "],\n";
}
use warnings;
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
#		if (defined($dst_struct{$dst_toptalkers[0]}{$date})) { print "$dst_struct{$dst_toptalkers[0]}{$date}, "; }
#		else { print "0, "; }
#		if (defined($dst_struct{$dst_toptalkers[1]}{$date})) { print "$dst_struct{$dst_toptalkers[1]}{$date}, "; }
#		else { print "0, "; }
#		if (defined($dst_struct{$dst_toptalkers[2]}{$date})) { print "$dst_struct{$dst_toptalkers[2]}{$date}, "; }
#		else { print "0, "; }
#		if (defined($dst_struct{$dst_toptalkers[3]}{$date})) { print "$dst_struct{$dst_toptalkers[3]}{$date}, "; }
#		else { print "0, "; }
#		if (defined($dst_struct{$dst_toptalkers[4]}{$date})) { print "$dst_struct{$dst_toptalkers[4]}{$date} ],\n"; }
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
