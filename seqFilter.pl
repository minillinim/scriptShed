#!/usr/bin/env perl
###############################################################################
#
#    filters or gets statistics for contigs/reads
#
#    Copyright (C) 2010, 2011, 2012 Connor Skennerton
#
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

#pragmas
use strict;
use warnings;

#core Perl modules
use IO::Zlib;
use IO::File;
use IO::Uncompress::Bunzip2;
#CPAN modules
use Getopt::Euclid;
use Bio::Tools::CodonTable;
#locally-written modules

BEGIN 
	{
    select(STDERR);
    $| = 1;
    select(STDOUT);
    $| = 1;
	}

# get input params and print copyright

#my $options = checkParams();



my $outfile = \*STDOUT; 
if (defined $ARGV{'-o'}) {
    $outfile = IO::File->new($ARGV{'-o'}, 'w') || die;
}


#globals
my (@gc, @seq_length, @coverage);
my %genes;
my $total_base =0; my $seq_count = 0; my $total_gc = 0;
# set these to -1,0,1 depending on what type of test we want:
# -1 = less than
# 0 = range
# 1 = greter than
my $length_input_type = undef;
my $gc_input_type = undef;

my $max;
my $count = 0;

&generate_parse_params(\$length_input_type, \$gc_input_type);

my @aux = undef;
my ($name, $seq, $qual);
my $infile;
if($ARGV{'-i'}) {    
    if($ARGV{'-z'}) {
        $infile = IO::Zlib->new($ARGV{'-i'},"rb") || die $!;
    } elsif($ARGV{'-j'}){
        $infile = IO::Uncompress::Bunzip2->new($ARGV{'-i'}) || die $!;
    } else {
       $infile = IO::File->new($ARGV{'-i'}, 'r') || die $!;
    }
} else {
    $infile = \*STDIN;
}
while (($name, $seq, $qual) = &readfq($infile, \@aux)) {
    if ((&length_test(\$seq) & &gc_test(\$seq)) ^ defined $ARGV{'-v'}) {

        unless( exists $ARGV{'-A'}) {
            if(exists $ARGV{'-r'} ) {
                if ($ARGV{'-h'}) {
                    my $h_len = human_output(length $seq);
                    my $h_gc = human_output(calcgc(\$seq));
                    $outfile->printf("%s\t%s\t%s\n", $name, $h_len, $h_gc);
                } else {
                    $outfile->printf("%s\t%d\t%.4f\n", $name, length $seq, calcgc(\$seq));
                }
            } else {
                print_seq(\$name,\$seq,\$qual, $outfile);
            }
        }
        $seq_count++;
        $total_base += length $seq;
        $total_gc += calcgc(\$seq);
    } 
}
$infile->close();
if( exists $ARGV{"-a"} | exists $ARGV{'-A'}) 
{
    if ($seq_count > 1) {
        my $n50 = $total_base / ($seq_count / 2);
        printf "%s sequences %s with an average length of %s and an n50 of %s\n", $seq_count,human_output($total_base), human_output($total_base / $seq_count), human_output($n50);
    } else {
        printf "%s\n", human_output($total_base);
    }
}

#close OUT;
unless(defined $ARGV{'--quiet'}){ printAtEnd();}
exit;

sub human_output {
    my $num = shift;
    my $result = 0;
    
    # test for a decimal and convert into a percentage
    if ($num >=0 && $num <= 1) {
        return sprintf "%.1f%%", $num * 100;
    } 

    # Peta- (P) bases
    if ( 1 <= ($result = ($num / 10**15))) {
         return sprintf "%.3f Pbp", $result;
     # Tera- (T) bases
     } elsif ( 1 <= ($result = ($num / 10**12))) {
         return sprintf "%.3f Tbp", $result;
     # Giga- (G) bases
     } elsif ( 1 <= ($result = ($num / 10**9))) {
         return sprintf "%.3f Gbp", $result;
     } elsif ( 1 <= ($result = ($num / 10**6))) {
         return sprintf "%.3f Mbp", $result;
     } elsif ( 1 <= ($result = ($num / 10**3))) {
         return sprintf "%.3f kbp", $result;
     } else {
         return sprintf "%d bp", $num;
     }

}

sub length_test {
    my $seq_ref = shift;
    # if we are not filtering on length
    # then just skip over this test
    # alternatively we might be in report mode and therefore
    # not filtering anyway
    unless (exists $ARGV{'-l'}) {
        return 1;
    }
    my $len = length ${$seq_ref};
    if ($length_input_type == 0)
    {
        if (($len <= $seq_length[1]) and ($len >= $seq_length[0]))
        {
            return 1;
        }
    }
    elsif ($length_input_type == 1) 
    {
        if ($len >= $seq_length[0])
        {
            return 1;
        }
    }
    elsif ($length_input_type == -1)
    {
        if($len <= $seq_length[0])
        {
            return 1;
        }
    }    	
    else
    {
        print "no sequences match your criteria";
    }
    return 0;
}

sub gc_test {
    my $seq_ref = shift;
    # if we are not filtering on length
    # then just skip over this test
    # alternatively we might be in report mode and therefore
    # not filtering anyway
    unless (exists $ARGV{'-g'}) {
        return 1;
    }
    my $g_c = calcgc($seq_ref);
    if ($gc_input_type  == 0)
    {
        if (($g_c <= $gc[1]) and ($g_c >= $gc[0]))
        {
            return 1;
        }
    }
    elsif ($gc_input_type == 1) 
    {
        if ($g_c >= $gc[0])
        {
            return 1;
        }
    }
    elsif ($gc_input_type == -1)
    {
        if($g_c <= $gc[0])

        {
            return 1;
        }
    }    	
    else
    {
        print "no sequences match your criteria";
    }
    return 0;

}
sub fastaCut {
    #-----
    # Cut up a fasta sequence
    #
    my ($string, $prot, $line_wrap) = @_;
    
    # translate if need be
    if(0 != $prot)
    {
        my $codon_table = Bio::Tools::CodonTable -> new ( -id => $prot );
        $string = $codon_table->translate($string);
    }
    
    # wrap the line if need be
    if(0 != $line_wrap)
    {
        my $return_str = "";
        my $len = length $string;
        my $start = 0;
        while($start < $len)
        {
            $return_str .= substr $string, $start, $line_wrap;
            $return_str .="\n";
            $start += $line_wrap;
        }
        return $return_str;
    }
    return "$string\n";
}

sub print_seq{
    my ($name_ref, $seq_ref, $qual_ref, $fh) = @_;
    my $seq = $$seq_ref;
    if(defined $ARGV{'-w'})
    { 
        if(defined $ARGV{'-p'})
        {
            $seq = fastaCut($seq, $ARGV{'-p'}, $ARGV{'-w'});
        }
        else
        {
            $seq = fastaCut($seq, 0, $ARGV{'-w'});
        }
    }
    elsif(defined $ARGV{'-p'})
    {
        $seq = fastaCut($seq, $ARGV{'-p'}, 0);
    }
    else
    {
        $seq .= "\n";
    }

    if (defined $$qual_ref ^ defined $ARGV{'-F'})
    {
        # fastq file
        print $fh "@".$$name_ref."\n".$seq."+".$$name_ref."\n".$$qual_ref."\n";
    }
    else
    {
        print $fh ">".$$name_ref."\n".$seq;
    }
}

sub readfq {
	my ($fh, $aux) = @_;
	@$aux = [undef, 0] if (!defined(@$aux));
	return if ($aux->[1]);
	if (!defined($aux->[0])) {
		while (<$fh>) {
			chomp;
			if (substr($_, 0, 1) eq '>' || substr($_, 0, 1) eq '@') {
				$aux->[0] = $_;
				last;
			}
		}
		if (!defined($aux->[0])) {
			$aux->[1] = 1;
			return;
		}
	}
	my $name = /^.(\S+)/? $1 : '';
	my $seq = '';
	my $c;
	$aux->[0] = undef;
	while (<$fh>) {
		chomp;
		$c = substr($_, 0, 1);
		last if ($c eq '>' || $c eq '@' || $c eq '+');
		$seq .= $_;
	}
	$aux->[0] = $_;
	$aux->[1] = 1 if (!defined($aux->[0]));
	return ($name, $seq) if ($c ne '+');
	my $qual = '';
	while (<$fh>) {
		chomp;
		$qual .= $_;
		if (length($qual) >= length($seq)) {
			$aux->[0] = undef;
			return ($name, $seq, $qual);
		}
	}
	$aux->[1] = 1;
	return ($name, $seq);
}


# print an aggregate report of all the sequences
    

sub calcgc {
    my ($seq_ref) = @_;
    my $count = ${$seq_ref} =~ tr/GgCc/GgCc/;
    return $count / length ${$seq_ref};
}

sub generate_parse_params
{
    my($len_ref, $gc_ref) = @_;
    if (exists ($ARGV{"-g"}))
    {
        if ($ARGV{"-g"} =~ /:/) 
        {
            ${$gc_ref} = 0;
            @gc = split (/:/, $ARGV{"-g"});
        }
        # if the user wants anything less than a specified gc percent
        #//CTS// check that regex is correct
        elsif ($ARGV{"-g"} =~ /\,(0.\d{1,})/)
        {
            ${$gc_ref} = -1;
            push(@gc, $1);
        }
        # if the user wants anything greater than a specified gc percent
        #//CTS// check that regex is correct    
        elsif ($ARGV{"-g"} =~ /(0.\d{1,})\,/) {
            ${$gc_ref} = 1;
            push(@gc, $1);
        } else {
            warn "\nERROR: input parameter error for -g\n";
            print Getopt::Euclid->usage();
        }
    }
if (exists ($ARGV{"-l"}))
	{
    if ($ARGV{"-l"} =~ /:/) 
    	{
        ${$len_ref} = 0;
        @seq_length = split (/:/, $ARGV{"-l"});
        }
    # if the user wants anything less than a specified length
    elsif ($ARGV{"-l"} =~ /\,(\d+)/)
    	{
		${$len_ref} = -1;
        push(@seq_length, $1);
        }
    # if the user wants anything greater than a specified length
    elsif ($ARGV{"-l"} =~ /(\d+)\,/)
    	{
        ${$len_ref}  = 1;
        push(@seq_length, $1);
        } 
    else
    	{
        warn "\nERROR: input parameter error for -l\n";
        print Getopt::Euclid->usage();
        }
	}
}


sub printAtEnd 
{
warn<<"EOF";
---------------------------------------------------------------- 
 $0
 Copyright (C) 2010, 2011, 2012 Connor Skennerton
    
 This program comes with ABSOLUTELY NO WARRANTY;
 This is free software, and you are welcome to redistribute it
 under certain conditions: See the source for more details.
---------------------------------------------------------------- 
EOF
}

__DATA__

=head1 NAME
 
 seqfilter.pl
 
=head1 COPYRIGHT
 
 copyright (C) 2010, 2011 Connor Skennerton
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 
=head1 DESCRIPTION
 
 parses a fasta file based on length, gc, n-statistic, coverage or number  
 of sequences to keep. Can also produce a report of sequences containing
 just the name, length, gc content and coverage for all sequences. The 
 report can be sorted based on  gc content, length or coverage if no option
 is provided then the sequences will be printed in a random order.
 the aggregate option is provied for an at-a-glance look that the 
 overall sequence statistics of the file.
 
=head1 OPTIONS
 
=over

=item -i <input_file> | --input <input_file> | -d <input_file> | --db <input_file>

        the name of the fasta file to be parsed
 
=for Euclid:
    input_file.type: readable

=item -o <output> | --output <output>

        the name of the out put file for printing

=for Euclid:
    output.type: writable

 
=item -l <length> | --length <length>
                      
parse sequences based on the length value, specified as an integer.
                      there are two forms of this option. first is range where two values
                      are separated by a colon.  this will be interperated as the lower and
                      upper limits for the sequences; any sequences that fall between these 
                      two values (inclusive) will be printed
                      
                      in the second form a single comma is placed before or after the specified
                      value.  if the comma is before then it is interperated that the user would
                      like all values less than the specified length (inclusive); or greater than
                      if the comma is placed after the value.
 
=item -g <gc> | --gc <gc>        
                     
 parse sequences based on the GC value, specified as a decimal.
                      there are two forms of this option. first is range where two values
                      are separated by a colon.  this will be interperated as the lower and
                      upper limits for the sequences; any sequences that fall between these 
                      two values (inclusive) will be printed
                      
                      in the second form a single comma is placed before or after the specified
                      value.  if the comma is before then it is interperated that the user would
                      like all values less than the specified GC (inclusive); or greater than
                      if the comma is placed after the value.

=item -m <maximum> | --maximum <maximum>
          
 modifier of  -g -l  prints only the specified maximum number of sequences
 
=item -r | --report 
                     
 modifies the print function so that the name, length, GC and coverage are 
                      printed in tab delimated format. default is to print the name and the 
                      sequence of the contig

=item -a | --aggregate 
                     
 prints a summary of the entire assembly including the average GC content, 
                      average length, total number of bases, and n-statistic.  if -n is specified
                      the n-statistic will be calculated using that variable else the default is
                      n50.

=item -w [<wrap>] | --wrap [<wrap>]

wrap the output lines in the fasta to wrap.default

=for Euclid
    wrap.type: +i
    wrap.type.error: "you must specify a positive integer for -w"


=item -p <trans_code> | --protein <trans_code>

=for Euclid
    trans_code.type: int
    trans_code.type.error: "please specify a single integer corresponding to the protein translation"
    trans_code.default: 0

translate the nucleotides into their protein sequences

=item -F | --Fasta

force fasta output

=item -v | --inverse

reverse the sequences outputed

=item -z

The input file is gziped

=item -j

The input file is bziped

=item -h

Human readable output

=item -A

Print only the summary statistics (implies -a)

=item --quiet

suppress all un-needed information

=back                      

=cut



