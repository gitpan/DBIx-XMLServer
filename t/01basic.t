use Test::More tests => 2;
BEGIN { use_ok('DBIx::XMLServer'); };

my $dbh = 1;
# Try creating the object without a database handle
my $xml_server = new DBIx::XMLServer($dbh, 't/t01.xml');
isa_ok($xml_server, 'DBIx::XMLServer');

1;
