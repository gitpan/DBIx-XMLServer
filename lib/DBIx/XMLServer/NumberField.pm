# $Id: NumberField.pm,v 1.2 2003/11/03 21:54:08 mjb47 Exp $

package DBIx::XMLServer::NumberField;
use XML::LibXML;
our @ISA = ('DBIx::XMLServer::Field');

=head1 NAME

DBIx::XMLServer::NumberField - integer field type

=head1 DESCRIPTION

This class implements the built-in integer field type of
DBIx::XMLServer.  Only the B<where> method is overridden from the base
class.

=head2 B<where> method

  $sql_expression = $number_field->where($condition);

The condition must consist of one of the numeric comparison operators '=',
'>', '<', '>=' or '<=', followed by an integer.  The integer must match the
regular expression '-?\d+'.  The resulting SQL expression is simply

  <field> <condition> <value> .

=cut

sub where {
  my $self = shift;
  my $cond = shift;
  my $column = $self->select;
  my ($comp, $value) = ($cond =~ /([=<>]+)(.*)/);
  $comp =~ /^(=|[<>]=?)$/ or die "Unrecognised number comparison: $comp";
  $value =~ /^-?\d+$/ or die "Unrecognised number: $value";
  return "$column $comp $value";
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
