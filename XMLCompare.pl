package XMLCompare;

use XML::LibXML;

sub new {
  my $proto = shift;
  my $class = ref $proto || $proto;
  my $self = { };
  my $parser = new XML::LibXML;
  $parser->keep_blanks(0);
  my ($a, $b) = @_;
  $self->{a} = (ref $a) ? $a : $parser->parse_file($a);
  $self->{b} = (ref $b) ? $b : $parser->parse_file($b);
  bless $self, $class;
  return $self;
}

sub qname { return '{' . $_[0]->namespaceURI . '}' . $_[0]->localname; }

sub qname_cmp { qname($a) cmp qname($b) }

sub compare {
  my ($self, $a, $b) = @_;
  $a = $self->{a}->getDocumentElement unless $a;
  $b = $self->{b}->getDocumentElement unless $b;

  if($a->isa('XML::LibXML::Element')) {
    my $aname = qname($a);
    if($b->isa('XML::LibXML::Element')) {

      # Compare element names
      my $bname = qname($b);

      return "Expected element $bname but found $aname"
	unless $aname eq $bname;

      # Compare attributes
      my @aa = sort qname_cmp 
	grep { $_->isa('XML::LibXML::Attr') } $a->attributes;
      my @ba = sort qname_cmp
	grep { $_->isa('XML::LibXML::Attr') } $b->attributes;
      foreach my $x (@aa) {
	my $y = shift @ba;
	return "Unexpected attribute " . qname($x)
	  if qname($x) lt qname($y);
	return "Missing attribute " . qname($y)
	  if qname($x) gt qname($y);
	my $xv = $x->value;
	my $yv = $y->value;
	return "Attribute " . qname($x) . ": expected '$yv' but found '$xv'"
	  unless $xv eq $yv;
      };
      do {
	my $y = shift @ba;
	return "Missing attribute " . qname($y);
      } if @ba;

      # Compare children
      $a->normalize;
      $b->normalize;
      my @ac = grep { $_->isa('XML::LibXML::Element') 
			|| $_->isa('XML::LibXML::Text') } $a->childNodes;
      my @bc = grep { $_->isa('XML::LibXML::Element') 
			|| $_->isa('XML::LibXML::Text') } $b->childNodes;
      foreach my $x (@ac) {
	my $y = shift @bc;
	my $r = $self->compare($x, $y);
	return $r if $r;
      };
      return undef;
    } elsif($b->isa('XML::LibXML::Text')) {
      return "Expected text node but found $aname";
    } else {
      die "Unexpected node type: " . ref $b;
    }
  } elsif($a->isa('XML::LibXML::Text')) {
    if($b->isa('XML::LibXML::Text')) {
      my $av = $a->data;
      my $bv = $b->data;
      return "Expected: <<\n$bdata\>>  but found <<\n$adata\n>>"
	unless $av eq $bv;
      return undef;
    } elsif($b->isa('XML::LibXML::Element')) {
      return "Expected element " . qname($b) . " but found text node";
    } else {
      die "Unexpected node type: " . ref $b;
    }
  } else {
    die "Unexpected node type: " . ref $a;
  }
}

1;
