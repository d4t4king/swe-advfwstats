package SQL;
	# Filler to house the sub modules
1;

package SQL::Utils;

use 5.010001;
use strict;
use warnings;
use Exporter;
use DBI;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use SQL::Utils ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS	= ( 'all' => [ qw( ) ] );

our @EXPORT_OK		= ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT			= qw( );

our $VERSION		= '0.01';

# Preloaded methods go here.

my %db_types = (
	'sqlite3'	=>	'SQLite',
	'mysql'		=>	'mysql',
	'mssql'		=>	'MSSQL',
);

#END {
#	if ($sth) { $sth->finished; }
#	if ($db)  { $db->close;     }
#}

sub new {
	my $class	= shift;
	my %attrs;
	$attrs{'rdbms'}	= shift;
	my $params	= shift;
	given ($attrs{'rdbms'}) {
		when ('sqlite3') {
			$attrs{'db_filename'} = $params->{'db_filename'};
		}
		when (/^m[sy]sql$/) {
			$attrs{'db'} = $params->{'db'};
			$attrs{'user'} = $params->{'user'} or die "Must specify user with $attrs{'rdbms'} database types.";
			$attrs{'pass'} = $params->{'pass'} or die "Must specify password with $attrs{'rdbms'} database types.";
			$attrs{'host'} = $params->{'host'} or die "Must specify host with $attrs{'rdbms'} database types.";
		}
		default { die "Unrecognized database type."; }
	}
	
	my $self = \%attrs;
	
	bless $self, $class;

	return $self;
}

sub execute_non_query {
	my $self = shift;
	my $sql = shift;
	my $db;
	if ($self->{'rdbms'} eq 'sqlite3') {
		$db = DBI->connect("dbi:$db_types{$self->{'rdbms'}}:$self->{'db_filename'}", "", "") or die "Can't connect to database: $DBI::errstr";
	}
	my $sth = $db->prepare($sql) or die "Can't prepare statement: $DBI::errstr";
	my $rtv = $sth->execute or die "Can't execute statement: $DBI::errstr";
	return $rtv;
}

sub execute_single_row_query {
	my $self = shift;
	my $sql = shift;
	my ($db, $results);
	if ($self->{'rdbms'} eq 'sqlite3') {
		$db = DBI->connect("dbi:$db_types{$self->{'rdbms'}}:$self->{'db_filename'}", "", "") or die "Can't connect to database: $DBI::errstr";
	}
	my $sth = $db->prepare($sql) or die "Can't prepare statement: $DBI::errstr";
	while (my $row = $sth->fetchrow_hashref()) {
		#print Dumper($row);
		$results = $row;
	}
	return $results;
}

sub execute_multi_row_query {
	my $self = shift;
	my $sql = shift;
	my ($db, $results);
	if ($self->{'rdbms'} eq 'sqlite3') {
		$db = DBI->connect("dbi:$db_types{$self->{'rdbms'}}:$self->{'db_filename'}", "", "") or die "Can't connect to database: $DBI::errstr";
	}
	my $sth = $db->prepare($sql) or die "Can't prepare statement: $DBI::errstr";
	while (my $row = $sth->fetchrow_hashref()) {
		#print Dumper($row);
		push $results, $row;
	}
	return $results;
}

1;


__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

SQL::Utils - Perl extension for blah blah blah

=head1 SYNOPSIS

  use SQL::Utils;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for SQL::Utils, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Charlie Heselton, E<lt>charlie@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Charlie Heselton

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.20.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
