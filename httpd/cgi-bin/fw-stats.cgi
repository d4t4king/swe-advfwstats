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

use Data::Dumper;
use JSON;
use Geo::IP::PurePerl;

my (%cgiparams, %netsettings, %mainsettings, %filtersettings);

my $errormessage = '';

&readhash("$swroot/ethernet/settings", \%netsettings);
&readhash("$swroot/main/settings", \%mainsettings);
# Read the settings file and set defaults as needed (like if the file is empty)
&readhash("$swroot/mods/adv_fw_stats/settings", \%filtersettings);
if ((not defined($filtersettings{'cbxNoRedDest'})) or ($filtersettings{'cbxNoRedDest'} eq '')) {
	$filtersettings{'cbxNoRedDest'} = 'off';
}
if ((not defined($filtersettings{'cbxNoGreenSource'})) or ($filtersettings{'cbxNoGreenSource'} eq '')) {
	$filtersettings{'cbxNoGreenSource'} = 'off';
}

if ((defined($cgiparams{'btnFilter'})) and ($cgiparams{'btnFilter'} eq 'Filter')) {
	if ($cgiparams{'cbxNoRedDest'}) { $filtersettings{'cbxNoRedDest'} = $cgiparams{'cbxNoRedDest'}; }
	if ($cgiparams{'cbxNoGreenSource'}) { $filtersettings{'cbxNoGreenSource'} = $cgiparams{'cbxNoGreenSource'}; }
	unless($errormessage) {
		&writehash("$swroot/mods/adv_fw_stats/settings", \%filtersettings);
	}
}

open RED, "<$swroot/red/local-ipaddress" or $errormessage .= "Couldn't open red local-ipaddress:$!\n";
my $RED_IP = <RED>;
close RED;
chomp($RED_IP);

$cgiparams{'btnFilter'} = '';
$cgiparams{'cbxNoRedDest'} = 'off';
$cgiparams{'cbxNoGreenSource'} = 'off';

&getcgihash(\%cgiparams);

my %checked;
$checked{'cbxNoRedDest'}{'off'} = '';
$checked{'cbxNoRedDest'}{'on'} = '';
$checked{'cbxNoRedDest'}{$filtersettings{'cbxNoRedDest'}} = 'CHECKED';
$checked{'cbxNoGreenSource'}{'off'} = '';
$checked{'cbxNoGreenSource'}{'on'} = '';
$checked{'cbxNoGreenSource'}{$filtersettings{'cbxNoGreenSource'}} = 'CHECKED';

# load the json data, which is populated by another script
open JSON, "$swroot/mods/adv_fw_stats/var/db/fwstats.json" or
	$errormessage .= "There was a problem opening the json file: $!" and
	warn "ERROR: Couldn't open json file: $! \n";
my $json = <JSON>;
chomp($json);
close JSON or $errormessage .= "<br />There was a problem closing the json file: $!";
my $data = decode_json($json);

&showhttpheaders();

# Extra HTML head stuff
my $refresh = '';
&openpage($tr{'afws_advanced_stats'}, 1, $refresh, 'about');

&openbigbox('100%', 'LEFT');

&alertbox($errormessage);

print "<form method='POST' action='?'><div>\n";

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

#==================================================================================================
# Interfaces
#==================================================================================================
my $count = 0;
&openbox($tr{'afws_interfaces'});
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="interfaceStatsTable" width="100%">
	<tr style="background-color: #acacac;"><td width=\"50%\"><b>Interface Name</b></td><td><b>Drop Count</b></td></tr>
END
foreach my $if ( sort keys %{$data->{'interfaces'}} ) {
	if (($count % 2) != 0) {
		print "<tr style=\"background-color: #ccc;\"><td>$if</td><td>$data->{'interfaces'}{$if}</td></tr>\n";
	} else {
		print "<tr><td>$if</td><td>$data->{'interfaces'}{$if}</td></tr>\n";
	}
	$count++;
}
print "</table>\n";
&closebox();

#==================================================================================================
# Filters
#==================================================================================================
$count = 0;
&openbox($tr{'afws_filters'});
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="filtersStatsTable" width="100%">
	<tr style="background-color: #acacac;"><td width=\"50%\"><b>Filter Name</b></td><td><b>Drop Count</b></td></tr>
END
foreach my $if ( sort keys %{$data->{'filters'}} ) {
	if (($count % 2) != 0) {
		print "<tr style=\"background-color: #ccc\"><td>$if</td><td>$data->{'filters'}{$if}</td></tr>\n";
	} else {
		print "<tr><td>$if</td><td>$data->{'filters'}{$if}</td></tr>\n";
	}
	$count++;
}
print "</table>\n";
&closebox();

#==================================================================================================
# Source IPs
#==================================================================================================
$count = 0;
&openbox($tr{'afws_sources'});
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="sourcesStatsTable" width="100%">
	<tr style="background-color: #acacac;"><td width=\"50%\"><b>Source IPs</b></td><td><b>Drop Count</b></td></tr>
END
foreach my $if ( sort { $data->{'sources'}{$b} <=> $data->{'sources'}{$a} } keys %{$data->{'sources'}} ) {
	if ($checked{'cbxNoGreenSource'}{'on'} eq "on") {
		next if ($if == $netsettings{'GREEN_ADDRESS'});
	}
	if (($count % 2) != 0) {
		print "<tr style=\"background-color: #ccc;\"><td>$if</td><td>$data->{'sources'}{$if}</td></tr>\n";
	} else {
		print "<tr><td>$if</td><td>$data->{'sources'}{$if}</td></tr>\n";
	}
	last if ($count >= 10);
	$count++;
}
print "</table>\n";
&closebox();

#==================================================================================================
# Destination IPs
#==================================================================================================
$count = 0;
&openbox($tr{'afws_destinations'});
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="destsStatsTable" width="100%">
	<tr style="background-color: #acacac;"><td width="50%"><b>Destination IPs</b></td><td><b>Drop Count</b></td></tr>
END
foreach my $if ( sort { $data->{'destinations'}{$b} <=> $data->{'destinations'}{$a} } keys %{$data->{'destinations'}} ) {
	if ($checked{'cbxNoRedDest'}{'on'} eq "on") {
		next if ($if == $RED_IP);
	}
	if (($count % 2) != 0) {
		print "<tr style=\"background-color: #ccc;\"><td>$if</td><td>$data->{'destinations'}{$if}</td></tr>\n";
	} else {
		print "<tr><td>$if</td><td>$data->{'destinations'}{$if}</td></tr>\n";
	}
	last if ($count >= 10);
	$count++;
}
print "</table>\n";
&closebox();

#==================================================================================================
# Destination Ports
#==================================================================================================
$count = 0;
&openbox($tr{'afws_dest_ports'});
print <<END;
<table border="1" style="border-collapse: collapse; border: 1px solid black;" id="destPortStatsTable" width="100%">
	<tr style="background-color: #acacac;"><td width="50%"><b>Destination Ports</b></td><td><b>Drop Count</b></tr></tr>
END
foreach my $dp ( sort { $data->{'destination_ports'}{$b} <=> $data->{'destination_ports'}{$a} } keys %{$data->{'destination_ports'}} ) {
	if (($count % 2) != 0) {
		print "<tr style=\"background-color: #ccc;\"><td>$dp</td><td>$data->{'destination_ports'}{$dp}</td></tr>\n";
	} else {
		print "<tr><td>$dp</td><td>$data->{'destination_ports'}{$dp}</td></tr>\n";
	}
	last if ($count >= 10);
	$count++;
}
print "</table>\n";
&closebox();

&openbox('Debug Info');
#print "<div id=\"debug_container\"><h3>checked hash:</h3>\n";
print "<h3>checked hash:</h3>\n";
print "<pre>\n";
print Dumper(\%checked);
print "</pre>\n";
print "<h3>cgiparams hash:</h3>\n";
print "<pre>\n";
print Dumper(\%cgiparams);
print "</pre>\n";
print "<h3>filtersettings hash:</h3>\n";
print "<pre>\n";
print Dumper(\%filtersettings);
print "</pre>\n";
#print "</pre></div>\n";
&closebox();

print "</div></form>\n";

&alertbox('add', 'add');

&closebigbox();

&closepage();

