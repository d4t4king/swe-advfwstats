#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Date::Calc qw( Time_to_Date );

use lib '/var/smoothwall/mods/advfwstats/usr/lib/perl5/site_perl/5.14.4';
use SQL::Utils;

my (@src_toptalkers, @dst_toptalkers, @dates);
my (%src_struct, %dst_struct);

my $db = SQL::Utils->new("sqlite3", {'db_filename'=>"/var/smoothwall/mods/advfwstats/var/db/fwstats.db"});
#print Dumper($db);
my $sql = "SELECT ip_addr FROM sources GROUP BY ip_addr ORDER BY SUM(hitcount) DESC LIMIT 5;";
@src_toptalkers = $db->execute_multi_row_query($sql);

foreach my $tt ( @src_toptalkers ) {
	$sql = "SELECT datetime,hitcount FROM sources WHERE ip_addr='$tt' ORDER BY datetime LIMIT 10;";
	my @rows = $db->execute_multi_row_query($sql);
	foreach my $row ( @rows ) {
		my ($dt,$hc) = split(/|/, $row);
		$src_struct{$tt}{$dt} = $hc;
	}
}

print Dumper(\@src_toptalkers);
print Dumper(\%src_struct);
