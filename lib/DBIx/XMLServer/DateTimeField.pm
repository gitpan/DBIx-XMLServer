# $Id: DateTimeField.pm,v 1.2 2003/11/03 21:54:08 mjb47 Exp $

package DBIx::XMLServer::DateTimeField;
use XML::LibXML;
use Date::Manip qw( Date_Init UnixDate );
our @ISA = ('DBIx::XMLServer::Field');

=head1 NAME

DBIx::XMLServer::DateTimeField - date and time field type

=head1 DESCRIPTION

This class implements the built-in date and time field type of
DBIx::XMLServer.  The B<where> and B<value> methods are overridden
from the base class.

=head2 B<where> method

  $sql_expression = $date_time_field->where($condition);

The condition must consist of one of the numeric comparison operators
'=', '>', '<', '>=' or '<=', followed by a date and time.  The date
and time may be in any format understood by the C<Date::Manip>
package, such as '2003-11-03 21:29:10' or 'yesterday at midnight'.

=cut

sub BEGIN { Date_Init("DateFormat = EU"); }

sub where {
  my $self = shift;
  my $cond = shift;
  my $column = $self->select;
  my ($comp, $date) = ($cond =~ /([=<>]+)(.*)/);
  $comp =~ /^(=|[<>]=?)$/ or die "Unrecognised date/time comparison: $comp";
  my $date1 = UnixDate($date, '%q') or die "Unrecognised date/time: $date";
  return "$column $comp " . $date1;
}

=head2 B<value> method

The date and time is returned in the format 'YYYY-mm-ddThh:mm:ss', as 
required by the B<xsi:datetime> type in XML Schema.

=cut

sub value {
  shift;
  return UnixDate(shift @{shift()}, '%Y-%m-%dT%T');
}

1;

__END__

=head1 SEE ALSO

L<DBIx::XMLServer::Field>

=head1 AUTHOR

Martin Bright E<lt>martin@boojum.org.ukE<gt>

=head1 COPYRIGHT AND LICENCE

Copyright (C) 2003 Martin Bright

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
