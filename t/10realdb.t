use Test::More tests => 39;
use DBIx::XMLServer;

my $write_files = ($ARGV[0] && $ARGV[0] eq '-write');

ok(open(FILE, '<t/dbname'), "Finding out which database to use")
  or diag "Couldn't open configuration file `dbname': $!.\nThis "
	. "file should have been created by `make'.";

my ($db, $user, $pass) = split /,/, <FILE>;
chomp $pass;

SKIP: {
  skip "You haven't given me a database to use for testing", 38
	unless $db;

  use_ok('DBI');
  $dbh = DBI->connect($db, $user || undef, $pass || undef, 
	{ RaiseError => 0, PrintError => 0 });
  ok($dbh, "Opening database") or diag $DBI::errstr;

  ok($dbh->do(<<EOF), "Create table 1") or diag $dbh->errstr;
CREATE TABLE dbixtest1
(
  id INT UNSIGNED NOT NULL,
  name TEXT,
  manager INT UNSIGNED,
  dept INT UNSIGNED
)
EOF

  my $sth;
  eval {
    $sth = $dbh->prepare('INSERT INTO dbixtest1 VALUES (?,?,?,?)')
      or die $dbh->errstr;
    foreach my $record (split /\r?\n/, <<EOF) {
1,John Smith,NULL,1
2,Fred Bloggs,3,1
3,Ann Other,1,1
4,Minnie Mouse,NULL,2
5,Mickey Mouse,4,2
EOF
      $sth->execute(map($_ eq 'NULL' ? undef : $_, split(/,/, $record)))
	or die $dbh->errstr;
    }
  };
  ok(!$@, "Populate table 1") or diag $@;

  ok($dbh->do(<<EOF), "Create table 2") or diag $dbh->errstr;
CREATE TABLE dbixtest2
(
  id INT UNSIGNED NOT NULL,
  name TEXT
)
EOF

  eval {
    $sth = $dbh->prepare('INSERT INTO dbixtest2 VALUES (?,?)')
      or die $dbh->errstr;
    foreach my $record (split /\r?\n/, <<EOF) {
1,Widget Manufacturing
2,Widget Marketing
EOF
      $sth->execute(map($_ eq 'NULL' ? undef : $_, split(/,/, $record)))
	or die $dbh->errstr;
    }
  };
  ok(!$@, "Populate table 2") or diag $@;

  sub try_query {
    my $doc;
    my ($q, $f) = @_;
    eval { $doc = $xml_server->process($q) };
    ok(!$@, "Execute query '$q'") or diag $@;
    ok(ref $doc, "Check success of query '$q'") or diag $doc;
  SKIP: {
      do {
	$doc->toFile($f, 1);
	skip "Writing $f", 2;
      } if $write_files;

      ok(my $cmp = new XMLCompare($doc, $f), 
	 "Create XMLCompare object for file $f");
      my $msg = $cmp->compare;
      ok(!$msg, "Check results of query '$q'") or diag $msg;
    }
  };

  eval {

    require 'XMLCompare.pl';

    ok(eval { $xml_server = new DBIx::XMLServer($dbh, 't/t10.xml') },
       "Create DBI::XMLServer object") or diag $@;
    isa_ok($xml_server, 'DBIx::XMLServer');
    
    try_query('@id>0', 't/o10-1.xml');
    try_query('@id>0&fields=name', 't/o10-2.xml');
    try_query('department=Widget%20Marketing', 't/o10-3.xml');
    try_query('department=Widget%20Marketing&fields=name', 't/o10-4.xml');
    try_query('manager=John+Smith&fields=name', 't/o10-5.xml');
    try_query('name=Ann*', 't/o10-6.xml');
    try_query('name~M.*Mouse&fields=name', 't/o10-7.xml');
  };

  ok($dbh->do('DROP TABLE dbixtest1'), "Drop table 1")
    or diag $dbh->errstr;
  ok($dbh->do('DROP TABLE dbixtest2'), "Drop table 2")
    or diag $dbh->errstr;

  die $@ if $@;
  
}

1;
