#!/usr/bin/perl

use strict;
use warnings;

use Term::ANSIColor;
use Data::Dumper;
use Date::Calc qw( Time_to_Date );

use lib '/var/smoothwall/mods/advfwstats/usr/lib/perl5/site_perl/5.14.4';
use SQL::Utils;

my (@src_toptalkers, @dst_toptalkers, @dates);
my (%src_struct, %dst_struct);

my $db = SQL::Utils->new("sqlite3", {'db_filename'=>"/var/smoothwall/mods/advfwstats/var/db/fwstats.db"});
#print Dumper($db);
my $sql = "SELECT ip_addr FROM sources GROUP BY ip_addr ORDER BY SUM(hitcount) DESC LIMIT 5;";
@src_toptalkers = $db->execute_single_field_query($sql);

my (%datetimes,%tts);
foreach my $tt ( @src_toptalkers ) {
	$sql = "SELECT datetime,hitcount FROM sources WHERE ip_addr='$tt' ORDER BY datetime LIMIT 10;";
	my @rows = $db->execute_multi_field_query($sql);
	#print Dumper(\@rows);
	foreach my $row ( @rows ) {
		#print colored(Dumper($row), "magenta");
		my ($dt,$hc) = split(/\|/, $row);
		#print "datetime ==> $dt\thitcount ==> $hc\n";
		#my $mod = ($dt % 86400);
		#print "$mod\n";
		#my $round = ($dt - $mod);
		#print "$round\n";
		$src_struct{$dt}{$tt} = $hc;
		$datetimes{$dt}++;
		#my ($dy,$dm,$dd,$dh,$dM,$ds) = Time_to_Date($dt);
		#my ($ry,$rm,$rd,$rh,$rM,$rs) = Time_to_Date($round);
		#print colored("$dd/$dm/$dy $dh:$dM;$ds", "green");
		#print " || ";
		#print colored("$rd/$rm/$ry $rh:$rM:$rs\n", "yellow");
	}
}

#print Dumper(\@src_toptalkers);
#print Dumper(\%src_struct);

# pad the keys with no values
#foreach my $d ( keys %datetimes ) {
	
no warnings;
foreach my $d ( sort keys %datetimes ) {
	print "$d,";
	foreach my $tt ( @src_toptalkers ) {
		if (defined($src_struct{$d}{$tt})) {
			print "$src_struct{$d}{$tt},";
		} else {
			print "0,";
		}
	}
	print "\n";
}

