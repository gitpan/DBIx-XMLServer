# $Id: DateField.pm,v 1.2 2003/11/03 21:54:08 mjb47 Exp $

package DBIx::XMLServer::DateField;
use XML::LibXML;
use Date::Manip qw( Date_Init UnixDate );
our @ISA = ('DBIx::XMLServer::Field');

sub BEGIN { Date_Init("DateFormat = EU"); }

=head1 NAME

DBIx::XMLServer::DateField - date field type

=head1 DESCRIPTION

This class implements the built-in date field type of
DBIx::XMLServer.  The B<where> and B<value> methods are overridden
from the base class.

To use this field type, you must have the C<Date::Manip> package installed.

=head2 B<where> method

  $sql_expression = $date_field->where($condition);

The condition consists of one of the comparison operators '=', '<', '>',
'>=' or '<=' followed by a date.  The date may be in any format understood
by the C<Date::Manip> package, such as '1976-02-28' or 'two months ago'.

=cut

sub where {
  my $self = shift;
  my $cond = shift;
  my $column = $self->select;
  my ($comp, $date) = ($cond =~ /([=<>]+)(.*)/);
  $comp =~ /^(=|[<>]=?)$/ or die "Unrecognised date comparison: $comp";
  my $date1 = UnixDate($date, '%Q') or die "Unrecognised date: $date";
  return "$column $comp " . $date1;
}

=head2 B<value> method

  $date = $date_field->value(\@results);

The date is returned as 'YYYY-mm-dd', as required by the B<xsd:date> type
of XML Schema.

=cut

sub value {
  shift;
  return UnixDate(shift @{shift()}, '%Y-%m-%d');
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
