# $Id: XMLServer.pm,v 1.6 2003/11/17 22:30:12 mjb47 Exp $

use strict;
use warnings;
use XML::LibXML;
use XML::LibXSLT;

package DBIx::XMLServer;

our $VERSION = '0.01';
our $MAXPAGESIZE = 100;

my $our_ns = 'http://boojum.org.uk/NS/XMLServer';

my $sql_ns = sub {
  my $node = shift;
  my $uri = shift || $our_ns;
  my $prefix;
  $prefix = $node->lookupNamespacePrefix($uri) and return $prefix;
  for($prefix = 'a'; $node->lookupNamespaceURI($prefix); ++$prefix) {}
  $node->setNamespace($uri, $prefix, 0);
  return $prefix;
};

package DBIx::XMLServer::Field;
use Carp;

our $VERSION = sprintf '%d.%03d', (q$Revision: 1.6 $ =~ /(\d+)\.(\d+)/);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  $self->{XMLServer} = shift
    and ref $self->{XMLServer}
      and $self->{XMLServer}->isa('DBIx::XMLServer')
	or croak "No XMLServer object supplied";
  $self->{node} = shift
    and ref $self->{node}
      and $self->{node}->isa('XML::LibXML::Element')
	or croak "No XML element node supplied";
  $self->{node}->namespaceURI eq $our_ns
    and $self->{node}->localname eq 'field'
      or croak "The node is not an <sql:field> element";
  my $type = $self->{node}->getAttribute('type')
    or croak "<sql:field> element has no `type' attribute";
  $class = $self->{XMLServer}->{types}->{$type}
    or croak "Undefined field type: `$type'";
  bless($self, $class);
  $self->init if $self->can('init');
  return $self;
}

sub where { return '1'; }

sub select {
  my $self = shift;
  my $expr = $self->{node}->getAttribute('expr')
    or die "A <sql:field> element has no `expr' attribute";
  return $expr;
}

sub join {
  my $self = shift;
  return $self->{node}->getAttribute('join');
}

sub value {
  my $self = shift;
  return shift @{shift()};
}

sub result {
  my $self = shift;
  my $n = shift;

  my $value = $self->value(shift());

  do {
    $value = $n->ownerDocument->createElementNS($our_ns, 'sql:null');
    $value->setAttribute('type',
			 $self->{node}->getAttribute('null') || 'empty');
  } unless defined $value;

  do {
    my $x = $n->ownerDocument->createTextNode($value);
    $value = $x;
  } unless ref $value;

  my $attr = $self->{node}->getAttribute('attribute');

  if($attr) {
    my $x = $n->ownerDocument->createElementNS($our_ns, 'sql:attribute');
    $x->setAttribute('name', $attr);
    $x->appendChild($value);
    $value = $x;
  }

  $n->replaceNode($value);
}

1;

package DBIx::XMLServer::Request;
use DBIx::XMLServer::XPathParser;
use Carp;

our $VERSION = sprintf '%d.%03d', (q$Revision: 1.6 $ =~ /(\d+)\.(\d+)/);

our $parser = new DBIx::XMLServer::XPathParser;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  $self->{XMLServer} = shift 
    and ref $self->{XMLServer}
      and $self->{XMLServer}->isa('DBIx::XMLServer') 
	or croak "No XMLServer object supplied";

  $self->{template} = shift
    or $self->{template} = $self->{XMLServer}->{template};
  $self->{main_table} = $self->{template}->getAttribute('table')
    or croak "The <sql:template> element has no `table' attribute";
  $self->{ns} = $self->{template}->getAttribute('default-namespace');
  my $p = &$sql_ns($self->{template});
  $self->{record} = $self->{template}->findnodes(".//$p:record/*[1]")->shift
    or croak "The <sql:template> element contains no <sql:record> element";
  
  $self->{criteria} = [];
  $self->{page} = 0;
  $self->{pagesize} = 100;
  bless($self, $class);
  return $self;
}

sub parse {
  my $self = shift;
  my $query = shift or croak "No query string supplied";
  $::XPATH_DEFAULT_NAMESPACE = $self->{ns};
  $::XPATH_DEFAULT_NAMESPACE = &$sql_ns($self->{record}, $self->{ns})
    if defined $self->{ns} && $self->{ns} ne '*';
  foreach(split /&/, $query) {
    # Un-URL-encode the string
    s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    tr/+/ /;
    # Split it into key and condition by removing an initial XPath
    # expression matching `Pattern'
    my $r = $parser->Pattern($_)
      or return "Unrecognised parameter: '$_'\n";
    my ($key, $condition) = @$r;
    for ($key) {
      /^fields$/ && do {
	$condition =~ s/^=// 
	  or return "Expected '=' after 'fields' but found '$condition'";
	$self->{fields} = $condition;
	last; 
      };
      /^page$/ && do { # The page number
        $condition =~ /^=(\d+)$/
	  or return "Unrecognised page number: $condition";
	$self->{page} = $1;
	last;
      };
      /^pagesize$/ && do { # The page size
        $condition =~ /^=(\d+)$/
	  or return "Unrecognised page size: $condition";
	$self->{pagesize} = $1;
	( $1 > 0 and $1 <= $DBIx::XMLServer::MAXPAGESIZE)
	  or return "Invalid page size: Must be between 0 " .
	    "and $DBIx::XMLServer::MAXPAGESIZE";
	last;
      };
      # Anything else we treat as a search criterion
      push @{$self->{criteria}}, [$key, $condition];
    }
  }
  return undef;
}

sub do_criteria {
  my $self = shift;

  my $p = &$sql_ns($self->{record});
  foreach(@{$self->{criteria}}) {
    my $key = $_->[0];
    my @nodelist = $self->{record}->findnodes($key);
    my $node;
    if(@nodelist eq 1 && $nodelist[0]->isa('XML::LibXML::Attr')) {
      my $name = $nodelist[0]->nodeName;
      my $owner = $nodelist[0]->getOwnerElement;
      my $q = &$sql_ns($owner);
      $node = $owner->findnodes("$q:field[@"."attribute='$name']")->shift
	or return "Attribute '$key' isn't a field";
    } else {
      my @nodes = $self->{record}->findnodes 
	($key . "//$p:field[not(@"."attribute)]")
	or return "Unknown field: '$key'";
      @nodes eq 1 or return "Expression '$key' selects more than one field";
      $node = shift @nodes;
    }
    $_->[0] = new DBIx::XMLServer::Field($self->{XMLServer}, $node);
  }
  return undef;
}

sub _prune {
  my $element = shift;
  if($element->getAttributeNS($our_ns, 'keepme')) {
    foreach my $child ($element->childNodes) {
      _prune($child) if $child->isa('XML::LibXML::Element');
    }
  } else {
    $element->unbindNode
      unless ($element->namespaceURI || '') eq $our_ns # Hack to avoid pruning 
	&& $element->localname eq 'field'      # attribute fields
	  && $element->getAttribute('attribute');
  }
}

sub build_output {
  my $self = shift;
  my $doc = shift;

  # Create the output structure
  my $new_template = $self->{template}->cloneNode(1);
  $doc->adoptNode($new_template);
  $doc->setDocumentElement($new_template);
  my $p = &$sql_ns($new_template);
  my $record;
  foreach my $node ($new_template->findnodes(".//$p:*")) {
    for($node->nodeName) {
      /record/ && do {
	$record = $node;
      };
    }
  }

  $record or croak "There is no <sql:record> element in the template";
  $self->{newrecord} = $record->findnodes('*')->shift
    or croak "The <sql:record> element has no child element";

  # Find the nodes to return
  if(defined $self->{fields}) {
    $::XPATH_DEFAULT_NAMESPACE = $self->{ns};
    $::XPATH_DEFAULT_NAMESPACE = &$sql_ns($self->{newrecord}, $self->{ns})
      if defined $self->{ns} && $self->{ns} ne '*';
    my $r = $parser->Pattern($self->{fields})
      or return "Unrecognised fields: '$self->{fields}'";
    return "Unexpected text: '" . $r->[1] . "'" if $r->[1];
    $self->{fields} = $r->[0];
  } else {
    $self->{fields} = '.';
  }
  my @nodeset = $self->{newrecord}->findnodes
    ("($self->{fields})/descendant-or-self::*");
  @nodeset > 0 or return "No elements match expression $self->{fields}";

  # Mark the subtree containing them
  $self->{newrecord}->setAttributeNS($our_ns, 'keepme', 1);
  foreach my $node (@nodeset) {
    until($node->isa('XML::LibXML::Element') && 
	  $node->getAttributeNS($our_ns, "keepme")) {
      $node->setAttributeNS($our_ns, "keepme", 1)
	if $node->isa('XML::LibXML::Element');
      $node = $node->parentNode;
    }
  }

  # Prune away what we don't want to return
  _prune($self->{newrecord});

  return undef;
}

sub build_fields {
  my $self = shift;
  my @fields;
  my $p = &$sql_ns($self->{newrecord});
  foreach($self->{newrecord}->findnodes(".//$p:field")) {
    push @fields, new DBIx::XMLServer::Field($self->{XMLServer}, $_);
  }
  $self->{fields} = \@fields;
  return undef;
}

sub add_join {
  my ($self, $table) = @_;
  return unless $table;
  do {
    my $root = $self->{XMLServer}->{doc}->documentElement;
    my $p = &$sql_ns($root);
    my $tabledef = $root->find("/$p:spec/$p:table[@"."name='$table']")->shift
      or croak "Unknown table reference: $table";
    my $jointo = $tabledef->getAttribute('jointo');
    my $join = '';
    do {
      $self->add_join($jointo);
      $join = uc $tabledef->getAttribute('join') || '';
      $join .= ' JOIN ';
    } if $jointo;
    my $sqlname = $tabledef->getAttribute('sqlname')
      or croak "Table `$table' has no `sqlname' attribute";
    $join .= "$sqlname AS $table";
    do {
      if(my $using = $tabledef->getAttribute('using')) {
	$join .= " ON $jointo.$using = $table.$using";
      } elsif(my $ref = $tabledef->getAttribute('refcolumn')) {
	my $key = $tabledef->getAttribute('keycolumn')
	  or croak "Table $table has `refcolumn' without `keycolumn'";
	$join .= " ON $jointo.$ref = $table.$key";
      } elsif(my $on = $tabledef->getAttribute('on')) {
	$join .= " ON $on";
      }
    } if $jointo;
    push @{$self->{jointext}}, $join;
    $self->{joinhash}->{$table} = 1;
  } unless $self->{joinhash}->{$table};
}

sub build_joins {
  my $self = shift;
  $self->{jointext} = [];
  $self->{joinhash} = {};
  $self->add_join($self->{main_table});
  foreach my $x (@{$self->{criteria}}) {
    foreach($x->[0]->join) {
      $self->add_join($_);
    }
  }
  foreach my $f (@{$self->{fields}}) {
    foreach ($f->join) {
      $self->add_join($_);
    }
  }
  return undef;
} 

# Process a request
# $results = $xmlout->process($query_string);
sub process {
  my ($self, $arg) = @_;
  my $err;

  my $doc = new XML::LibXML::Document;

  $err = $self->parse($arg) and return $err;
  $err = $self->do_criteria and return $err;
  $err = $self->build_output($doc) and return $err;
  $err = $self->build_fields and return $err;
  $err = $self->build_joins and return $err;

  my $query;
  eval {
    my $select = join(',', map($_->select, @{$self->{fields}})) || '0';
    my $from = join(' ', @{$self->{jointext}});
    my $where = join(' AND ', map($_->[0]->where($_->[1]),
				      @{$self->{criteria}})) || '1';
    my $limit = ($self->{page} * $self->{pagesize}) . ", $self->{pagesize}";
    $query = "SELECT $select FROM $from WHERE $where LIMIT $limit";
  };
  return $@ if $@;

  # Do the query
  my $sth = $self->{XMLServer}->{dbh}->prepare($query);
  $sth->execute or croak $sth->errstr;

  # Put the data into the result tree
  my $r = $self->{newrecord}->parentNode;
  my @row;
  while(@row = $sth->fetchrow_array) {
    
    # Clone the template record and insert after the previous record
    $r = $r->parentNode->insertAfter($self->{newrecord}->cloneNode(1), $r);
    
    # Fill in the values
    my $p = &$sql_ns($self->{newrecord});
    my @n = $r->findnodes(".//$p:field");
    foreach(@{$self->{fields}}) {
      eval { $_->result(shift @n, \@row); };
      return $@ if $@;
    }

  }

  # Process through XSLT to produce the result
  return $self->{XMLServer}->{xslt}->transform($doc);
}

1; 

package DBIx::XMLServer;
use Carp;

sub add_type {
  my $self = shift;
  my $type = shift;
  my $name = $type->getAttribute('name') 
    or croak("Field type found with no name");
  
  my $p = &$sql_ns($type);
  my $package_name = $type->findnodes("$p:module");
  if($package_name->size) {
    $package_name = "$package_name";
    eval "use $package_name;";
    croak "Error loading module `$package_name' for field type"
      . " definition `$name':\n$@" if $@;
  } else {
    $package_name = "DBIx::XMLServer::Types::$name";
    my $where = $type->findnodes("$p:where");
    $where = $where->size ? "sub where { $where }" : '';
    my $select = $type->findnodes("$p:select");
    $select = $select->size ? "sub select { $select }" : '';
    my $join = $type->findnodes("$p:join");
    $join = $join->size ? "sub join { $join }" : '';
    my $value = $type->findnodes("$p:value");
    $value = $value->size ? "sub value { $value }" : '';
    my $init = $type->findnodes("$p:init");
    $init = $init->size ? "sub init { $init }" : '';
    my $isa = $type->findnodes("$p:isa");
    $isa = $isa->size ? "$isa" : 'DBIx::XMLServer::Field';
    $isa =~ s/\s+//g;
    eval <<EOF;
package $package_name;
use XML::LibXML;
our \@ISA = ('$isa');
$init
$select
$where
$join
$value
1;
EOF
    croak "Error compiling field type definition `$name':\n$@" if $@;
  }
  $self->{types}->{$name} = $package_name;
}

# Object constructor
# $xmlout = new DBIx::XMLServer($dbh, $doc[, $template]);
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless($self, $class);

  my $parser = new XML::LibXML;

  $self->{dbh} = shift or croak "No database handle supplied";
  my $doc = shift or croak "No template file supplied";
  $self->{template} = shift;

  ref $doc or $doc = $parser->parse_file($doc)
    or croak "Couldn't parse template file '$doc'";
  $self->{doc} = $doc;

  my $p = &$sql_ns($doc->documentElement);

  # Find all the field type definitions and parse them
  $self->{types} = {};
  foreach($doc->findnodes("/$p:spec/$p:type")) {
    $self->add_type($_);
  }

  # Find the template
  $self->{template}
    or $self->{template} = $doc->find("/$p:spec/$p:template")
        ->shift
      or croak "No <sql:template> element found";

  # Parse our XSLT stylesheet
  my $xslt = new XML::LibXSLT;
  my $f = $INC{'DBIx/XMLServer.pm'};
  $f =~ s/XMLServer\.pm/XMLServer\/xmlout\.xsl/;
  my $style_doc = $parser->parse_file($f)
    or croak "Couldn't open stylesheet '$f'";
  $self->{xslt} = $xslt->parse_stylesheet($style_doc)
    or croak "Error parsing stylesheet '$f'";

  return $self;
}

sub process {
  my $self = shift;
  my $query = shift;
  my $request = new DBIx::XMLServer::Request($self, @_);
  return $request->process($query);
}

1;
__END__

=head1 NAME

DBIx::XMLServer - Serve data as XML in response to HTTP requests

=head1 SYNOPSIS

  use XML::LibXML;
  use DBIx::XMLServer;

  my $xml_server = new DBIx::XMLServer($dbh, "template.xml");

  my $doc = $xml_server->process($QUERY_STRING);
  die "Error: $doc" unless ref $doc;

  print "Content-type: application/xml\r\n\r\n";
  print $doc->toString(1);

=head1 DESCRIPTION

This module implements the whole process of generating an XML document
from a database query, in response to an HTTP request.  The mapping
from the DBI database to an XML structure is defined in a template
file, also in XML; this template is used not only to turn the data
into XML, but also to parse the query string.  To the user, the format
of the query string is very natural in relation to the XML data which
they will receive.

One C<DBIx::XMLServer> object can process several queries.  The
following steps take place in processing a query:

=over

=item 1.

The query string is parsed.  It contains search criteria together with
other options about the format of the returned data.

=item 2.

The search criteria from the query string are converted, using the XML
template, into an SQL SELECT statement.

=item 3.

The results of the SQL query are translated into XML, again using the
template, and returned to the caller.

=back

=head1 METHODS

=head2 Constructor

  my $xml_server = new DBIx::XMLServer( $dbh, $template_doc 
                                        [, $template_node] );

The constructor for C<DBIx::XMLServer> takes two mandatory arguments
and one optional argument.

=over

=item C<$dbh>

This is a handle for the database; see L<DBI> for more information.

=item C<$template_doc>

This is the XML document containing the template.  It may be either an
C<XML::LibXML::Document> object or a string, which is taken as a file
name.

=item C<$template_node>

One template file may contain several individual templates; if so,
this argument may be used to pass an C<XML::LibXML::Element> object
indicating which template should be used.  By default the first
template in the file is used.

=back

=head2 process()

  my $result = $xml_server->process( $query [, $template_node] );

This method processes an HTTP query and returns an XML document
containing the results of the query.  There is one mandatory argument
and one optional argument.

=over

=item C<$query>

This is the HTTP GET query string to be processed.

=item C<$template_node>

As above, this may indicate which of several templates is to be used
for this query.  It is an C<XML::LibXML::Element> object.

=back

The return value of this method is either an C<XML::LibXML::Document>
object containing the result, or a string containing an error message.
An error string is only returned for errors caused by the HTTP query
string and thus the user's fault; other errors, which are the
programmer's fault, will B<croak>.

=head1 EXAMPLE

This example is taken from the tests included with the module.  The
database contains two tables.

  Table dbixtest1:

  +----+--------------+---------+------+
  | id | name         | manager | dept |
  +----+--------------+---------+------+
  |  1 | John Smith   |    NULL |    1 |
  |  2 | Fred Bloggs  |       3 |    1 |
  |  3 | Ann Other    |       1 |    1 |
  |  4 | Minnie Mouse |    NULL |    2 |
  |  5 | Mickey Mouse |       4 |    2 |
  +----+--------------+---------+------+

  Table dbixtest2:

  +----+----------------------+
  | id | name                 |
  +----+----------------------+
  |  1 | Widget Manufacturing |
  |  2 | Widget Marketing     |
  +----+----------------------+

The template file (in F<t/t10.xml>) contains the following three table
definitions:

  <sql:table name="employees" sqlname="dbixtest1"/>
  <sql:table name="managers" sqlname="dbixtest1"
    join="left" jointo="employees" refcolumn="manager" keycolumn="id"/>
  <sql:table name="departments" sqlname="dbixtest2"
    join="left" jointo="employees" refcolumn="dept" keycolumn="id"/>

The template element is as follows:

  <sql:template table="employees">
    <employees>
      <sql:record>
	<employee id="foo">
	  <sql:field type="number" attribute="id" expr="employees.id"/>
	  <name>
	    <sql:field type="text" expr="employees.name"/>
	  </name>
	  <manager>
	    <sql:field type="text" expr="managers.name" join="managers"
              null='nil'/>
	  </manager>
          <department>
	    <sql:field type="text" expr="departments.name" join="departments"/>
	  </department>
	</employee>
      </sql:record>
    </employees>
  </sql:template>

The query string B<name=Ann*> produces the following output:

  <?xml version="1.0"?>
  <employees>
    <employee id="3">
      <name>Ann Other</name>
      <manager>John Smith</manager>
      <department>Widget Manufacturing</department>
    </employee>
  </employees>

The query string B<department=Widget%20Marketing&fields=name> produces
the following output:

  <?xml version="1.0"?>
  <employees>
    <employee id="4">
      <name>Minnie Mouse</name>
    </employee>
    <employee id="5">
      <name>Mickey Mouse</name>
    </employee>
  </employees>

=head1 HOW IT WORKS: OVERVIEW

The main part of the template file which controls DBIx::XMLServer is
the template element.  This element gives a skeleton for the output
XML document.  Within the template element is an element, the record
element, which gives a skeleton for that part of the document which is
to be repeated for each row in the SQL query result.  The record element
is a fragment of XML, mostly not in the B<sql:> namespace, which contains
some B<< <sql:field> >> elements.

Each B<< <sql:field> >> element corresponds to a point in the record
element where data from the database will be inserted.  Often, this
means that one B<< <sql:field> >> element corresponds to one column in
a table in the database.  The field has a I<type>; this determines the
mappings both between data in the database and data in the XML
document, and between the user's HTTP query string and the SQL WHERE
clause.

The HTTP query which the user supplies consists of search criteria,
together with other special options which control the format of the
XML output document.  Each criterion in the HTTP query selects one
field in the record and gives some way of limiting data on that field,
typically by some comparison operation.  The selection of the field is
accomplished by an XPath expression, normally very simply consisting
just of the name of the field.  After the field has been selected, the
remainder of the criterion is processed by the Perl object
corresponding to that field type.  For example, the built-in text
field type recognises simple string comparisons as well as regular
expression comparisons; and the build-in number field type recognises
numeric comparisons.

All these criteria are put together to form the WHERE clause of the
SQL query.  The user may also use the special B<fields=...> option to
select which fields appear in the resulting XML document; the value of
this option is again an XPath expression which selects a part of the
record template to be returned.

Other special options control how many records are returned on each
page and which page of the results should be returned.

=head1 THE TEMPLATE FILE

The behaviour of DBIx::XMLServer is determined entirely by the
template file, which is an XML document.  This section explains the
format and meaning of the various elements which can occur in the
template file.

=head2 Namespace

All the special elements used in the template file are in the
namespace associated to the URI B<http://boojum.org.uk/NS/XMLServer>.
In this section we will suppose that the prefix B<sql:> is bound to
that namespace, though of course any other prefix could be used
instead.

=head2 The root element

The document element of the template file must be an B<< <sql:spec> >>
element.  This element serves only to contain the other elements in
the template file.

Contained in the root element are elements of three types:

=over

=item *

Field type definition elements;

=item *

Table definition elements;

=item *

One or more template elements.

=back

We now describe each of these in more detail.

=head2 Field type definitions

A field type definition is given by a B<< <sql:type> >> element.  Each
field in the template has a type.  That type determines: how a
criterion from the query string is converted to an SQL WHERE clause
for that field; how the SQL SELECT clause to retrieve data for that
field is created; and how the resulting SQL data is turned into XML.
For example, the standard date field type can interpret simple date
comparisons in the query string, and puts the date into a specific
format in the XML.

Each field type is represented by a Perl object class, derived from
C<DBIx::XMLServer::Field>.  For information about the methods which
this class must define, see L<DBIx::XMLServer::Field>.  The class may
be defined in a separate Perl module file, as for the standard field
types; or the methods of the class may be included verbatim in the XML
file, as follows.

The B<< <sql:type> >> element has one attribute, B<name>, and four
element which may appear as children.

=over

=item attribute: B<name>

The B<name> attribute defines the name by which this type will be
referred to in the templates.

=item element: B<< <sql:module> >>

If the Perl code implementing the field type is contained in a Perl
module in a separate file, this element is used to give the name
of the module.  It should contain the Perl name of the module (for
example, C<DBIx::XMLServer::NumberField>).

=back

=head3 Example

  <sql:type name="number">
    <sql:module>DBIx::XMLOut::NumberField</sql:module>
  </sql:type>

Instead of the B<< <sql:module> >> element, the B<< <sql:type> >>
element may have separate child elements defining the various facets
of the field type.

=over

=item element: B<< <sql:isa> >>

This element contains the name of a Perl module from which the field
type is derived.  The default is C<DBIx::XMLServer::Field>.

=item element: B<< <sql:select> >>

This element contains the body of the C<select> method (probably
inside a CDATA section).

=item element: B<< <sql:where> >>

This element contains the body of the C<where> method (probably inside
a CDATA section).

=item element: B<< <sql:join> >>

This element contains the body of the C<join> method (probably inside
a CDATA section).

=item element: B<< <sql:value> >>

This element contains the body of the C<value> method (probably inside
a CDATA section).

=item element: B<< <sql:init> >>

This element contains the body of the C<init> method (probably inside
a CDATA section).

=back

=head2 Table definitions

Any SQL table which will be accessed by the template needs a table
definition.  As a minimum, a table definition associates a local name
for a table with the table's SQL name.  In addition, the definition
can specify how this table is to be joined to the other tables in the
database.

Note that one SQL table may often be joined several times in different
ways; this can be accomplished by several table definitions, all
referring to the same SQL table.

A table definition is represented by the B<< <sql:table> >> element,
which has no content but several attributes.

=over

=item attribute: B<name>

This mandatory attribute gives the name by which the table will be
referred to in the template, and also the alias by which it will be
known in the SQL statement.

=item attribute: B<sqlname>

This mandatory attribute gives the SQL name of the table.  In the
SELECT statement, the table will be referenced as <sqlname> AS <name>.

=item attribute: B<jointo>

This attribute specifies the name of another table to which this table
is joined.  Whenever a query involves a column from this table, this
and the following attributes will be used to add an appropriate join
to the SQL SELECT statement.

=item attribute: B<join>

This attribute specifies the type of join, such as B<LEFT>, B<RIGHT>,
B<INNER> or B<OUTER>.

=item attribute: B<on>

This attribute specifies the ON clause used to join the two tables.  In
the most common case, the following two attributes may be used instead.

=item attribute: B<keycolumn>

This attribute gives the column in this table used to join to the other 
table.

=item attribute: B<refcolumn>

This attribute gives the column in the other table used for the join.
Specifying B<keycolumn> and B<refcolumn> is equivalent to giving the
B<on> attribute value

  <this table's name>.<keycolumn> = <other table's name>.<refcolumn> .

=back

=head2 The template element

A template file must contain at least one B<< <sql:template> >>
element.  This element defines the shape of the output document.  It
may contain arbitrary XML elements, which are copied straight to the
output document.  It also contains one B<< <sql:record> >> element,
which defines that part of the output document which is repeated for
each row returned from the SQL query.

As the output document is formed from the content of the B<<
<sql:template> >> element, it follows that this element must have
exactly one child element.

The B<< <sql:template> >> may have the following attributes:

=over

=item attribute: B<table>

This mandatory attribute specifies the main table for this template, to
which any other tables will be joined.

=item attribute: B<default-namespace>

In the HTTP query string, the user must refer to parts of the template.
To avoid them having to specify namespaces for these, this attribute
gives a default namespace which will be used for unqualified names
in the query string.

=back

=head2 The record element

Each template contains precisely one B<< <sql:record> >> element among
its descendants.  This record element defines that part of the output
XML document which is to be repeated once for each row in the result
of the SQL query.  The content of the record element consists of a
fragment of XML containing some B<< <sql:field> >> elements; each of
these defines a point at which SQL data will be inserted into the
record.  The B<< <sql:record> >> must have precisely one child element.

It is also to the structure inside the B<< <sql:record> >> element
that the user's HTTP query refers.

The B<< <sql:record> >> element has no attributes.

=head2 The field element

The record element will contain several B<< <sql:field> >> elements.
Each of these field elements defines what the user will think of as a
B<field>; that is, a part of the XML record which changes from one
record to the next.  Normally this will correspond to one column in an
SQL table, though this is not obligatory.

A field has a B<type>, which refers to one of the field type
definitions in the template file.  This type determines the mappings
both between SQL data and XML output data, and between the user's
query and the SQL WHERE clause.

The B<< <sql:field> >> element may have the following attributes:

=over

=item attribute: B<type>

This mandatory attribute gives the type of the field.  It is the name
of one of the field types defined in the template file.

=item attribute: B<join>

This attribute specifies which table needs to be joined to the main
table in order for this field to be found.  (Note: this attribute is
only read by the field type class's C<join> method.  If that method is
overridden, this attribute may become irrelevant.)

=item attribute: B<attribute>

If this attribute is set, the contents of the field will not be
returned as a text node, but rather as an attribute on the B<<
<sql:field> >> node's parent node.  The value of the B<attribute>
attribute gives the name of the attribute on the parent node which
should be filled in with the value of this field.  When this attribute
is set, the parent node should always have an attribute of that name
defined; the contents are irrelevant.

=item attribute: B<expr>

This attribute gives the SQL SELECT expression which should be
evaluated to find the value of the field.  (Note: this attribute is
only ever looked at in the field type class's C<select> method.  If
this method is overridden, this attribute need not necessarily still
be present.)

=item attribute: B<null>

This attribute determines the action when the field value is null.  There
are three possible values:

=over

=item B<empty> (default)

The field is omitted from the result, but the parent element remains.

=item B<omit>

The parent element is omitted from the record

=item B<nil>

The parent element has the B<xsi:nil> attribute set.

=back

=back

=head1 SPECIAL OPTIONS IN THE QUERY STRING

The HTTP query string may contain certain special options which are
not interpreted as criteria on the records to be returned, but instead
have some other effect.

=over

=item fields = <expression>

This option selects which part of each record is to be returned.  In
the absence of this option, an entire record is returned for each row
in the result of the SQL query.  If this option is set, its value
should be an XPath expression.  The expression will be evaluated in
the context of the single child of the B<< <sql:record> >> element and
should evaluate to a set of nodes; the part of the record returned is
the smallest subtree containing all the nodes selected by the
expression.

=item pagesize = <number>, page = <number>

These options give control over how many records are returned in one
query, and which of several pages is returned.

=back

=head1 HOW IT REALLY WORKS

When a C<DBIx::XMLServer> object is created, the template file is
parsed.  A new Perl module is compiled for each field type defined.

The C<process()> method performs the following steps.

=over

=item 1.

The HTTP query string is parsed.  It is split at each `&' character,
and each resulting fragment is un-URL-escaped.  Each fragment is then
examined, and a leading part removed which matches a grammar very
similar to the B<Pattern> production in XSLT (see
L<http://www.w3.org/TR/xslt>).  This leading part is assumed to be an
expression referring to a field in the B<< <sql:record> >> element of
the template, unless it is one of the special options B<fields>,
B<pagesize> or B<page>.  If the B<< <sql:template> >> has a
B<default-namespace> attribute, then any unqualified name in this
expression has that default namespace added to it.

=item 2.

Each criterion in the query string is turned into part of the WHERE
clause.  The leading part of each fragment of the query string is
evaluated as an XPath expression in the context of the single child of
the B<< <sql:record> >> element.  The result must be either a nodeset
having a unique B<< <sql:field> >> descendant; or an attribute on an
element having a child B<< <sql:field> >> element whose B<attribute>
attribute matches.  In either case, a single B<< <sql:field> >>
element is found.  That field's type is looked up and the resulting
field type class's C<where> method called, being passed the remainder
of the fragment of the HTTP query string.  The result of the C<where>
method is added to the WHERE clause; all criteria are combined by AND.

=item 3.

A new result document is created whose document element is a clone of
the B<< <sql:template> >> element.  The B<< <sql:record> >> in this
new document is located.  The value of the special B<fields> option is
evaluated, as an XPath expression, within the unique child of that
element, and the smallest subtree containing the resulting fields is
formed.  The rest of the record is pruned away.  The SQL SELECT clause
is now created by calling the C<select> method of each of the B<<
<sql:field> >> elements left after this pruning.

=item 4.

The `tables' part of the SELECT statement is formed by calling the
C<join> methods of all the tables which are referred to either in the
search criteria, or by any of the field to be returned.

=item 5.

The SELECT statement is executed.  For each result row, a copy of the
pruned result record is created.  Each field in this record is filled in
by calling the C<value> method of the corresponding field type.

=item 6.

The resulting document is passed through an XSL transform for tidying
up before being returned to the caller.

=back

=head1 BUGS

There are quite a lot of stray namespace declarations in the output.
They make no difference to the semantic meaning of the markup, but
they are ugly.

=head1 SEE ALSO

L<DBIx::XMLServer::Field>

=head1 AUTHOR

Martin Bright E<lt>martin@boojum.org.ukE<gt>

=head1 COPYRIGHT AND LICENCE

Copyright (C) 2003 Martin Bright

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
