#!/usr/bin/perl -w
###############################################################################
# H2 assembler
#
#   This assembler is *very* basic and is dependant on a C Pre Processor being
#   present, one should be available on most systems, I am going to be using
#   GCC's CPP.
#
#   I should probably use something more portable, see:
#   <http://www.anarres.org/projects/cpp/>
#   <http://www.perlmonks.org/?node=278562>
#
###############################################################################

#### Includes #################################################################

use warnings;
use strict;

###############################################################################

#### Globals ##################################################################
my $cppcmd = "cpp";       # The name of the *external* program to call for
	                      #   the C pre processor
my $maxmem = 8192;        # maximum memory of h2 cpu
my $entryp = 4;           # offset into memory to put program into
my $inputfile   = "cpu.asm";            # input file name
my $tmpfile     = "partial";            # partially processed file suffix
my $symfile     = "sym";                # symbol file
my $outputfile  = "mem_h2.hexadecimal"; # final assembled file
my $verbosity = 0;        # how verbose should we be?
my $outputbase = 16;      # output base of assembled file, 2 or 16
my @mem;                  # our CPUs memory
my $pc = $entryp;         # begin assembling here
my $max_irqs = $entryp;   # maximum number of interrupts
my $keeptempfiles = 0;    # !0 == true, keep temporary files
my $dumpsymbols = 0;      # !0 == true, dump all symbols

my %labels;               # labels to jump to in program
my %variables;            # variables that get calculated at comile time

my $stage00 = "$inputfile.00.$tmpfile";
my $stage01 = "$inputfile.01.$tmpfile";

my $cppcmdline = "$cppcmd $inputfile > $stage00"; # command to run

my $alu = 0;              # for enumerating all alu values.
my %cpuconstants = (      # ALU instruction field, 0-31, main field
## ALU instructions
"T"         => $alu++ << 8,
"N"         => $alu++ << 8,
"R"         => $alu++ << 8,
"[T]"       => $alu++ << 8,
"get_info"  => $alu++ << 8,
"set_interrupts"  => $alu++ << 8,
"T|N"       => $alu++ << 8,
"T&N"       => $alu++ << 8,
"T^N"       => $alu++ << 8,
"~T"        => $alu++ << 8,
"T>N"       => $alu++ << 8,
"N=T"       => $alu++ << 8,
"T+N"       => $alu++ << 8,
"N-T"       => $alu++ << 8,
"set_dptr"  => $alu++ << 8,
"get_dptr"  => $alu++ << 8,
"NrolT"     => $alu++ << 8,
"NrorT"     => $alu++ << 8,

## ALU instruction, other bits
"T->N"   => 1<<7,
"T->R"   => 1<<6,
"N->[T]" => 1<<5,
"R->PC"  => 1<<4,

## ALU stack, variable
"d+0" => 0,
"d+1" => 1,
"d-1" => 3,
"d-2" => 2,

## ALU stack, return
"r+0" => 0 << 2,
"r+1" => 1 << 2,
"r-1" => 3 << 2,
"r-2" => 2 << 2,
);

my @irqnames = ( 
  "Reset/Entry Point",
  "Clock  00        ",
  "Unused 00        ",
  "Unused 01        "
);

###############################################################################

#### Get opts #################################################################

my $intro = 
"H2 CPU Assembler.
\t06/Apr/2014
\tRichard James Howe
\thowe.r.j.89\@gmail.com\n";


my $helpmsg = 
"Usage: ./asm.pl (-(h|i|o|t|x|b|v)+( +filename)*)*
Assembler for the \"H2\" CPU architecture.

  Options:

  --, ignored
  -h, print this message and quit.
  -i, next argument the input file to be assembled.
  -o, next argument is the output file we generate.
  -t, next argument is a temporary file we use.
  -x, output file in base 16 (hexadecimal).
  -b, output file in base 2  (binary).
  -v, increase verbosity level.
  -s, keep all temporary files
  -d, dump table of jump locations

Author:
  Richard James Howe
Email (bug reports to):
  howe.r.j.89\@gmail.com
For complete documentation look at \"asm.md\" which should be
included alongside the assembler.
";

sub getopts(){
  while (my $arg = shift @ARGV){
	if($arg =~ /^-/m){
	  my @chars = split //, $arg;
	  foreach my $char (@chars){
	    if($char eq '-'){     # ignore
	    }elsif($char eq 'h'){ # print help
	      print $helpmsg;
	      exit;
	    }elsif($char eq 'i'){ # read from input file instead of default
	      $inputfile = shift @ARGV;
	      die "incorrect number of args to -i" unless defined $inputfile;
	    }elsif($char eq 'o'){ # print to output file instead of default
	      $outputfile = shift @ARGV;
	      die "incorrect number of args to -o" unless defined $outputfile;
	    }elsif($char eq 't'){ # temporary file to use
	      $tmpfile = shift @ARGV;
	      die "incorrect number of args to -t" unless defined $tmpfile;
	    }elsif($char eq 'x'){ # print hex instead
	      $outputbase = 16;
	    }elsif($char eq 'b'){ # print binary (default)
	      $outputbase = 2;
	    }elsif($char eq 'v'){ # increase the verbosity, increase it!
	      $verbosity++;
	    }elsif($char eq 's'){ # keep temporary files
	      $keeptempfiles = 1;
	    }elsif($char eq 'd'){ # dump symbols
	      $dumpsymbols = 1;
	    }else{
	      die "$char is not a valid option";
	    }
	  }
	}
  }
}
&getopts();

print $intro;
print "Memory available:\t$maxmem\n"                 if $verbosity > 1;
print "Prog entry point:\t$entryp\n"                 if $verbosity > 0;
print "Input file name :\t$inputfile\n";            #if $verbosity > 0;
print "Temporary file  :\t$inputfile.$tmpfile\n"     if $verbosity > 1;
print "Output file name:\t$outputfile\n";           #if $verbosity > 0;
print "Verbosity level :\t$verbosity\n"              if $verbosity > 2;
print "Output base     :\t$outputbase\n";           #if $verbosity > 0;

###############################################################################


#### Instruction set encoding helper functions ################################

sub printalu{ ## creates and prints an alu instruction
  my $i = 0;
  my $instr = 0;
  while (defined $_[$i]){ # for each argument
	if(exists $cpuconstants{$_[$i]}){ # if this is a valid ALU instruction
	  $instr = $instr | $cpuconstants{$_[$i]}; # or it in
	} else {
	  die "$_[$i] not a key\n";
	}
	$i++;
  }
  $mem[$pc++] = $instr | 1 << 14 | 1 << 13; # put instruction into memory
}

sub unimplemented{
  print "unimplemented word\n";
}

# instructions to put into memory
# these get called when we find a token that corresponds
# to one of these
sub s_dup       {&printalu("T","T->N","d+1")};
sub s_over      {&printalu("N","T->N","d+1")};
sub s_invert    {&printalu("~T")};
sub s_add       {&printalu("T+N","d-1")};
sub s_sub       {&printalu("N-T","d-1")};
sub s_equal     {&printalu("N=T","d-1")};
sub s_more      {&printalu("N>T","d-1")};
sub s_and       {&printalu("T&N","d-1")};
sub s_or        {&printalu("T|N","d-1")};
sub s_swap      {&printalu("N","T->N")};
sub s_nip       {&printalu("T","d-1")};
sub s_drop      {&printalu("N","d-1")};
sub s_exit      {&printalu("T","R->PC","r-1")};
sub s_tor       {&printalu("N","T->R","d-1","r+1")};
sub s_fromr     {&printalu("R","T->N","T->R","d+1","r-1")};
sub s_rload     {&printalu("R","T->N","T->R","d+1")};
sub s_load      {&printalu("[T]", "d-1", "T->N")};
sub s_store     {&printalu("N","d-2","N->[T]")};
sub s_depth     {&printalu("depth","T->N","d+1")};
sub s_set_int   {&printalu("set_interrupts", "T->N", "d-1")};
sub s_get_dptr  {&printalu("set_dptr", "d+1")};
sub s_set_dptr  {&printalu("get_dptr", "d+1")};

# associate token keywords with the functions that implement
# that instruction, aliases indented
my %keywords = (
  "dup"         => \&s_dup,
  "over"        => \&s_over,
  "invert"      => \&s_invert,
  "+"           => \&s_add,
  "-"           => \&s_sub,
  "="           => \&s_equal,
  ">"           => \&s_more,
  "and"         => \&s_and,
  "or"          => \&s_or,
  "xor"         => \&s_xor,
  "swap"        => \&s_swap,
  "nip"         => \&s_nip,
  "drop"        => \&s_drop,
  "exit"        => \&s_exit,
  "rshift"      => \&s_rshift,
  "lshift"      => \&s_lshift,
  ">r"          => \&s_tor,
  "r>"          => \&s_fromr,
  "r@"          => \&s_rload,
  "@"           => \&s_load,
  "!"           => \&s_store,
  "depth"       => \&s_depth,
  "set_interrupts"  => \&s_togglei,
  "set_dptr"        => \&s_set_dptr,
  "get_dptr"        => \&s_get_dptr
);

print "Initializing memory.\n";
for my $i ( 0 .. $maxmem - 1 ){
  $mem[$i] = 0;
}

print "Setting up interrupts.\n";
$mem[0] = $entryp;

#### Parsing helper functions #################################################

# See http://www.perlmonks.org/?node_id=520826
# by use "eyepopslikeamosquito" 
# on Jan 05, 2006 at 09:23 UTC
sub evaluate {
  my ($expr) = @_;
  my @stack;
  my @tokens = split ' ', $expr;
  for my $token (@tokens) {
	# no pops
	if ($token =~ /^\d+$/) {
	  push @stack, $token;
	  next;
	} elsif ($token =~ /^[0-9a-zA-Z_]*$/){ # implements variable assignment
	  if(exists $variables{$token}){
	    push @stack, $variables{$token};
	    next;
	  }
	  # do nothing, fall through, try other things
	}

	my $x = pop @stack;
	defined $x or die "Stack underflow: \"$token\"\n";

	## one pop
	if($token eq 'drop'){
	  next;
	} elsif($token eq '.'){
	  print "$x\n";
	  next;
	} elsif($token eq 'dup'){
	  push @stack, $x, $x;
	  next;
	} elsif($token eq 'invert'){
	  push @stack,  ~$x;
	  next;
	} elsif($token eq 'const'){
	  $token = pop @tokens;
	  $variables{$token} = $x;
	  next;
	}
	## two pops
	my $y = pop @stack;
	defined $y or die "Stack underflow\n";

	if ($token eq '+') {
	  push @stack, $y + $x;
	} elsif ($token eq '-') {
	  push @stack, $y - $x;
	} elsif ($token eq '<<') {
	  push @stack, $y << $x;
	} elsif ($token eq '>>') {
	  push @stack, $y >> $x;
	} elsif ($token eq 'and') {
	  push @stack, $y & $x;
	} elsif ($token eq 'or') {
	  push @stack, $y | $x;
	} elsif ($token eq 'xor') {
	  push @stack, $y ^ $x;
	} elsif ($token eq '*') {
	  push @stack, $y * $x;
	} elsif($token eq 'swap'){
	 push @stack, $x, $y;
	} elsif ($token eq '/') {
	  push @stack, int($y / $x);
	} else {
	  die "Invalid token:\"$token\"\n";
	}
  }

  @stack >= 1 or $stack[0] = 0;
  return $stack[0];
}


# numbers between 0 and 2**15 - 1 take one instruction
# numbers between 2**15 and 2**16 take two instructions
sub inc_by_for_number($$){
  my $number = $_[0];
  my $line = $_[1];
  my $incby = 0;
  if($number < 2**15){
	$incby=1;
  } elsif($number >= 2**15 and $number < 2**16){
	$incby=2;
  } else {
	die "number \"$number\" to large to handle on line $line\n";
  }
  return $incby;
}


###############################################################################

#### First pass ###############################################################
# Run input through C Pre Processor
###############################################################################

`$cppcmdline`;

#### Second Pass ##############################################################
# Get all labels, count instructions and evaluate expressions
###############################################################################
{
  my $linecount = 0; # current line count
  open INPUT_FIRST, "<", $stage00 or die $stage00;
  open OUTPUT_FIRST, ">", $stage01 or die $stage01;
  while(<INPUT_FIRST>){
	my $line = $_;
	next if $line =~ /^#/;
	$linecount++; # we need to set line count using the counts cpp spits out
	my @tokens = split ' ', $line;

	# foreach my $token (@tokens){
	for(my $lntok = 0; $lntok < $#tokens + 1; $lntok++){
	  my $token = $tokens[$lntok];
	  if($token =~ /(\w+):/){ # process label
	    $labels{$1} = $pc;
	    print "label:$1:$pc\n";
	  } else { # count instructions
	    if(exists $keywords{$token}){
	      print OUTPUT_FIRST "$token\n";
	      $pc++;
	    } elsif($token =~ /^\d+$/){ # print literal, special case
	      print OUTPUT_FIRST "$token\n";
	      $pc += &inc_by_for_number($token,$line);
	    } elsif($token eq "isr"){
	      print OUTPUT_FIRST "$token ";
	    } elsif($token =~ /jumpc?|call/m){
	      print OUTPUT_FIRST "$token  ";
	      $token = $tokens[++$lntok];
	      print OUTPUT_FIRST "$token\n";
	      $pc++;
	    } elsif($token =~ /define\(?/m){ ## MERGE WITH EVAL
	      my $expression = "";
	      if($token =~ /\)/m){ # eval("X")
	        $expression = $token;
	      } else { # eval("x y z")
	        for(my $t; not $tokens[$lntok] =~ /\)/m; $lntok++){
	          $t = $tokens[$lntok];
	          $expression .= " $t";
	        }
	        $expression .= " " . $tokens[$lntok];
	      }

	      $expression =~ s/define\s*\((".*")\)/$1/;
	      print "defining\t$expression\n";
	      $expression =~ s/"//g;
	      &evaluate($expression);

	    } elsif($token =~ /eval\(?/m){ ## MERGE WITH DEFINE
	      my $expression = "";
	      if($token =~ /\)/m){ # eval("X")
	        $expression = $token;
	      } else { # eval("x y z")
	        for(my $t; not $tokens[$lntok] =~ /\)/m; $lntok++){
	          $t = $tokens[$lntok];
	          $expression .= " $t";
	        }
	        $expression .= " " . $tokens[$lntok];
	      }

	      $expression =~ s/eval\s*\((".*")\)/$1/;
	      # print "evaluating:\t$expression\n";
	      $expression =~ s/"//g;
	      my $val = &evaluate($expression);
	      print OUTPUT_FIRST "$val\n";
	      $pc += &inc_by_for_number($val,$line);
	    } else {
	      die "Invalid token on line $linecount: \"$token\"";
	    }
	  } # else
	} # foreach
  } # while
  close INPUT_FIRST;
  close OUTPUT_FIRST;
} # scope

print "Counted $pc instructions\n";

#### Third Pass ###############################################################
# Now we have the labels we can assemble the source
###############################################################################
{
	my $linecount++;
	$pc = $entryp;
	open INPUT_SECOND, "<", $stage01 or die $stage01;

	while(<INPUT_SECOND>){
		my $line = $_;
		my @tokens = split ' ', $line;
		$linecount++;
		for(my $lntok = 0; $lntok < $#tokens + 1; $lntok++){
			my $token = $tokens[$lntok];
	  		if($token =~ /(\w+):/){ # process label
				die "$linecount: lable made it passed label processing stage";
			} else { # count instructions
				if(exists $keywords{$token}){
	      print "\t\t$token\n";
	      my $func = $keywords{$token};
	      &$func();
	    } elsif($token =~ /^\d+$/){ # print literal, special case
	      print "\t\t$token\n";
	      if($token < 2**15){
	        $mem[$pc++] = $token | 1 << 15;
	      } elsif(($token >= 2**15) and ($token < 2**16)){
	        $mem[$pc++] = (~$token & 0xFFFF) | 1<<15;
	        &s_invert();
	      } else {
	        die "number to large to handle\n";
	      }
	    } elsif($token eq "isr"){
	      $token = $tokens[++$lntok];
	      die "isr $token too big" if $token > $max_irqs or $token < 0 ;
	      $mem[$token] = $pc;
	    } elsif($token =~ /jumpc?|call/m){
	      my $type = $token;
	      $token = $tokens[++$lntok];
	      print "\t$type $token\n";
	      if(exists $labels{$token}){
	        if($type eq "jump"){
	          $mem[$pc++] = $labels{$token};
	        } elsif($type eq "jumpc"){
	          $mem[$pc++] = ($labels{$token} | 1 << 13);
	        } elsif($type eq "call"){
	          $mem[$pc++] = ($labels{$token} | 1 << 14);
	        } else{
	          die "$token should not have matched regex!\n";
	        }
	      } else {
	        die "label \"$token\" does not exist\n";
	      }
	    } else {
	      die "Error with \"$token\"";
	    }
	  } # if/else
	} # for
  } # while
  close INPUT_SECOND;
} # scope

#### Some options #############################################################
# Command line options that must be implemented after processing go here      # 
###############################################################################

if(0 == $keeptempfiles){ # remove temporary files or not
  unlink $stage00 or warn "unlink failed:$!";
  unlink $stage01 or warn "unlink failed:$!";
}

if(0 != $dumpsymbols){
  open SYMFILE, ">", "$inputfile.$symfile" or die "open $!\n";
  print SYMFILE "pc $pc\n";
  print SYMFILE "$_ $labels{$_}\n" for (keys %labels);
  close SYMFILE;
}

#### Write output file ########################################################
# Write the output to a file                                                  #
###############################################################################

open OUTPUT, ">", $outputfile or die "unabled to open output $outputfile: $!\n";
for (my $i = 0; $i < $maxmem ; $i++){
  if($outputbase eq 2){
	printf OUTPUT "%016b\n", $mem[$i];
  }elsif($outputbase eq 16){
	printf OUTPUT "%04X\n", $mem[$i];
  }else{
	die "invalid output base of $outputbase\n";
  }
}
close OUTPUT;

print "Done!\n";