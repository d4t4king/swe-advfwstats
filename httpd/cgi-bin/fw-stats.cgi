#!/usr/bin/perl
#
# SmoothWall CGIs
#
# This code is distributed under the terms of the GPL
#
# (c) The SmoothWall Team

use lib "/usr/lib/smoothwall";
use lib "/var/smoothwall/mods/adv_fw_stats/usr/lib/perl5/site_perl";	# Add the mod perl modules
use header qw( :standard );
use smoothd qw( message );
use strict;
use warnings;

use Data::Dumper;
use JSON;			# JSON perl module is missing from mod package
use Geo::IP::PurePerl;

my (%netsettings, %mainsettings, %filtersettings, %checked);

&readhash("$swroot/ethernet/settings", \%netsettings);
&readhash("$swroot/main/settings", \%mainsettings);

my $errormessage = '';

open RED, "<$swroot/red/local-ipaddress" or $errormessage .= "Couldn't open red local-ipaddress:$!\n";
my $RED_IP = <RED>;
close RED;
chomp($RED_IP);

# establish some default settings
$filtersettings{'ACTION'} = '';	# Changed key from 'btnFilter' as 'ACTION' is excluded by &writehash
$filtersettings{'cbxNoRedDest'} = 'off';
$filtersettings{'cbxNoGreenSource'} = 'off';
$filtersettings{'cbxIp2Country'} = 'off';

# get the CGI parameters
&getcgihash(\%filtersettings);	# Over-write %filtersettings with any received from cgi. Use %filtersettings from now on.

# If the filter button was pressed, save the new settings from cgi to %filtersettings
##### Use filtersettings instead of cgiparams #####
if ($filtersettings{'ACTION'} eq $tr{'afws_filter_button'}) { 				# This is always defined now, as a default was set earlier
	#$filtersettings{'cbxNoRedDest'} = $cgiparams{'cbxNoRedDest'};			# Not needed as the settings have been over-written above
	#$filtersettings{'cbxNoGreenSource'} = $cgiparams{'cbxNoGreenSource'};	# Not needed as the settings have been over-written above
	unless($errormessage) {
		&writehash("$swroot/mods/adv_fw_stats/settings", \%filtersettings);
	}
}

##### Read the settings file after it has been over-written by any cgi values #####
&readhash("$swroot/mods/adv_fw_stats/settings", \%filtersettings);

$checked{'cbxNoRedDest'}{'off'} = '';
$checked{'cbxNoRedDest'}{'on'} = '';
$checked{'cbxNoRedDest'}{$filtersettings{'cbxNoRedDest'}} = 'CHECKED';		# Use settings read from %filtersettings instead
$checked{'cbxNoGreenSource'}{'off'} = '';
$checked{'cbxNoGreenSource'}{'on'} = '';
$checked{'cbxNoGreenSource'}{$filtersettings{'cbxNoGreenSource'}} = 'CHECKED';	# Use settings read from %filtersettings instead
$checked{'cbxIp2Country'}{'off'} = '';
$checked{'cbxIp2Country'}{'on'} = '';
$checked{'cbxIp2Country'}{$filtersettings{'cbxIp2Country'}} = 'CHECKED'


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
	<td class="base">$tr{'afws_ip2country'}</td>
	<td><input type="checkbox" name="cbxIp2Country" $checked{'cbxIp2Country'}{'on'} /></td>
	<td class="base">&nbsp;</td>
	<td>&nbsp;</td>
<tr>
END
;
if ( -e "/var/smoothwall/mods/adv_fw_stats/updating" ) {
	print <<END;
	<!-- <td colspan='4'>&nbsp;</td> -->
	<td colspan="4" style="width: 100%; margin: 0 auto; font-weight: bold; text-align: center;">Stats update is currently running.</td>
END
}
print <<END
</tr>
</table>
<BR>
END
;
&closebox();

print <<END
<table style='width: 60%; border: none; margin-left:auto; margin-right:auto'>
<tr>
        <td style='width:50%; text-align:center;'><input type='submit' name='ACTION' value='$tr{'afws_filter_button'}'></td>
</tr>
</table>
END
;

my $gip = Geo::IP::PurePerl->new(GEOIP_STANDARD);
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
		print "<tr style=\"background-color: #ddd;\"><td>$if</td><td>$data->{'interfaces'}{$if}</td></tr>\n";
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
		print "<tr style=\"background-color: #ddd\"><td>$if</td><td>$data->{'filters'}{$if}</td></tr>\n";
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
	if ($checked{'cbxNoGreenSource'}{'on'} eq "CHECKED") {
		next if ($if eq $netsettings{'GREEN_ADDRESS'});	# Changed '==' to 'eq' as comparison is not numeric
	}
	if (($count % 2) != 0) {
		print "<tr style=\"background-color: #ddd;\"><td>$if</td><td>$data->{'sources'}{$if}</td></tr>\n";
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
	if ($checked{'cbxNoRedDest'}{'on'} eq "CHECKED") {
		next if ($if eq $RED_IP);		# Changed '==' to 'eq' as comparison is not numeric (evaluates as a string)
	}
	if (($count % 2) != 0) {
		print "<tr style=\"background-color: #ddd;\"><td>$if</td><td>$data->{'destinations'}{$if}</td></tr>\n";
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
		print "<tr style=\"background-color: #ddd;\"><td>$dp</td><td>$data->{'destination_ports'}{$dp}</td></tr>\n";
	} else {
		print "<tr><td>$dp</td><td>$data->{'destination_ports'}{$dp}</td></tr>\n";
	}
	last if ($count >= 10);
	$count++;
}
print "</table>\n";
&closebox();

=begin
&openbox('Debug Info');
#print "<div id=\"debug_container\"><h3>checked hash:</h3>\n";
print "<h3>checked hash:</h3>\n";
print "<pre>\n";
print Dumper(\%checked);
print "</pre>\n";
print "<h3cgiparams hash:</h3>\n";
print "<pre>\n";
print Dumper(\%cgiparams);
print "</pre>\n";
print "<h3>filtersettings hash:</h3>\n";
print "<pre>\n";
print Dumper(\%filtersettings);
print "</pre>\n";
#print "</pre></div>\n";
&closebox();
=cut

print "</div></form>\n";

&alertbox('add', 'add');

&closebigbox();

&closepage();

