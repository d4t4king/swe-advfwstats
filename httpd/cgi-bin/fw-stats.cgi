#!/usr/bin/perl
#
# SmoothWall CGIs
#
# This code is distributed under the terms of the GPL
#
# (c) The SmoothWall Team

use lib "/usr/lib/smoothwall";
use header qw( :standard );
use smoothd qw( message );
use strict;
use warnings;

use JSON;

my (%proxysettings, %netsettings, %mainsettings, %filtersettings);

my $errormessage = '';

&readhash("$swroot/ethernet/settings", \%netsettings);
&readhash("$swroot/main/settings", \%mainsettings);
open RED, "<$swroot/red/local-ipaddress" or $errormessage .= "Couldn't open red local-ipaddress:$!\n";
my $RED_IP = <RED>;
close RED;
chomp($RED_IP);

&showhttpheaders();

$proxysettings{'btnFilter'} = '';
$proxysettings{'cbxNoRedDest'} = 'off';
$proxysettings{'cbxNoGreenSource'} = 'off';

&getcgihash(\%proxysettings);

my %checked;
$checked{'cbxNoRedDest'}{'off'} = '';
$checked{'cbxNoRedDest'}{'on'} = '';
$checked{'cbxNoRedDest'}{$proxysettings{'cbxNoRedDest'}} = 'CHECKED';
$checked{'cbxNoGreenSource'}{'off'} = '';
$checked{'cbxNoGreenSource'}{'on'} = '';
$checked{'cbxNoGreenSource'}{$proxysettings{'cbxNoGreenSource'}} = 'CHECKED';

# load the json data, which is populated by another script
open JSON, "$swroot/mods/adv_fw_stats/var/db/fwstats.json" or
	$errormessage .= "There was a problem opening the json file: $!" and
	warn "ERROR: Couldn't open json file: $! \n";
my $json = <JSON>;
chomp($json);
close JSON or $errormessage .= "<br />There was a problem closing the json file: $!";
my $data = decode_json($json);

# Extra HTML head stuff
my $refresh = '';
&openpage($tr{'afws_advanced_stats'}, 1, $refresh, 'about');

&openbigbox('100%', 'LEFT');

&alertbox($errormessage);

print "<form method='POST' action='?'><div>\n";

=begin
&openbox($tr{'afws_advanced_stats'});
print <<END
<table width='100%'>
<tr>
	<td class='base'>$tr{'afws_filter_red'}</td>
	<td><input type='checkbox' name='cbxNoRedDest' $checked{'cbxNoRedDest'}{'on'}></td>
	<td class='base'>$tr{'afws_filter_green'}</td>
	<td><input type='checkbox' name='cbxNoGreenSource' $checked{'cbxNoGreenSource'}{'on'} /></td>
</tr>
<tr>
	<td colspan='4'>&nbsp;</td>
</tr>
</table>
<BR>
END
;
&closebox();

print <<END
<table style='width: 60%; border: none; margin-left:auto; margin-right:auto'>
<tr>
        <td style='width:50%; text-align:center;'><input type='submit' name='btnFilter' value='$tr{'afws_filter_button'}'></td>
</tr>
</table>
END
;
=cut

&openbox($tr{'afws_interfaces'});
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="interfaceStatsTable" width="100%">
	<tr style="background-color: #acacac;"><td width=\"50%\"><b>Interface Name</b></td><td><b>Drop Count</b></td></tr>
END
foreach my $if ( sort keys %{$data->{'interfaces'}} ) {
	print "<tr><td>$if</td><td>$data->{'interfaces'}{$if}</td></tr>\n";
}
print "</table>\n";
&closebox();

&openbox($tr{'afws_filters'});
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="filtersStatsTable" width="100%">
	<tr><td width=\"50%\">Filter Name</td><td>Drop Count</td></tr>
END
foreach my $if ( sort keys %{$data->{'filters'}} ) {
	print "<tr><td>$if</td><td>$data->{'filters'}{$if}</td></tr>\n";
}
print "</table>\n";
&closebox();

&openbox($tr{'afws_sources'});
my $count = 0;
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="sourcesStatsTable" width="100%">
	<tr><td width=\"50%\">Source IPs</td><td>Drop Count</td></tr>
END
foreach my $if ( sort { $data->{'sources'}{$b} <=> $data->{'sources'}{$a} } keys %{$data->{'sources'}} ) {
	if ($checked{'cbxNoGreenSource'}{'on'} eq "on") {
		next if ($if = $netsettings{'GREEN_ADDRESS'});
	}
	print "<tr><td>$if</td><td>$data->{'sources'}{$if}</td></tr>\n";
	last if ($count >= 10);
	$count++;
}
print "</table>\n";
&closebox();


&openbox($tr{'afws_destinations'});
$count = 0;
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="destsStatsTable" width="100%">
	<tr><td width=\"50%\">Destination IPs</td><td>Drop Count</td></tr>
END
foreach my $if ( sort { $data->{'destinations'}{$b} <=> $data->{'destinations'}{$a} } keys %{$data->{'destinations'}} ) {
	if ($checked{'cbxNoRedDest'}{'on'} eq "on") {
		next if ($if = $RED_IP);
	}
	print "<tr><td>$if</td><td>$data->{'destinations'}{$if}</td></tr>\n";
	last if ($count >= 10);
	$count++;
}
print "</table>\n";
&closebox();
print "</div></form>\n";

&alertbox('add', 'add');

&closebigbox();

&closepage();

