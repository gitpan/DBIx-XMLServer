#!/usr/bin/perl
# $Id: BuildParser.PL,v 1.1.1.1 2003/10/29 20:55:31 mjb47 Exp $

use warnings;
use strict;

use Parse::RecDescent;

$::RD_AUTOACTION = q{ join('', map(stringify($_), @item[1..$#item])) };

print STDERR "Compiling grammar in 'xpath-grammar' to $ARGV[0]...\n";

$/ = undef;
open GRAMMAR, 'xpath-grammar' or die "Couldn't open 'xpath-grammar': $!";
Parse::RecDescent->Precompile(<GRAMMAR>, 'DBIx::XMLServer::XPathParser');

rename 'XPathParser.pm', $ARGV[0];

1;

