#!/usr/bin/perl

use strict;
use warnings;
use Bio::DB::GenBank;
use Tie::Handle::CSV;
use Bio::DB::FileCache;
use Bio::DB::GenPept;
use Bio::Seq;
use Bio::DB::EUtilities;	
use Getopt::Long;

my $infile 		= 	'';
my $outfile		=	'';
my $verbose 	=	0;

my $getoptResult	= 	GetOptions(
						'verbose+'	=>	\$verbose,
						'infile=s'	=>	\$infile,
						'outfile=s'	=>	\$outfile
						);

if(!$getoptResult)
{die("bad getopt result");}

if(! -e $infile )
{die("Input file required\n");}

if (!$outfile)
{
	my @filenamesplit = split(/\./,"$infile") ;
	$outfile = $filenamesplit[0];
}


my $csvFH = Tie::Handle::CSV->new("$infile",header=>1);

my $ntdb = Bio::DB::GenBank->new(-delay=>0);
my $pepdb = Bio::DB::GenPept->new(-delay=>0);

my $cachent = new Bio::DB::FileCache(-kept => 0,
				     -file => '/tmp/nt.idx',
				     -seqdb => $ntdb);

my $cachepep = new Bio::DB::FileCache(-kept => 0,
				      -file => '/tmp/pep.idx',
				      -seqdb => $pepdb);

sub joinParts($)
{
	my ($joinString)	=	@_;
	my @parts			=	split(/,/,$joinString);
	my ($nucAccession,$seqPlainText) = '';

	foreach my $thisPart (@parts)
	{
		# chomp ($thisPart);
		# $thisPart =~ s/^\s+//;
		# $thisPart =~ s/\s+$//;
		my $strand	=	1;
		
		#handle revcom specification
		if($thisPart =~ m/[\)\)]/)
		{	
			my($command, $arguments) = split(/\(/,$thisPart,2);
			$arguments =~ s/\)$//;
			
			if(grep(/complement/,$command))
			{
				$thisPart  		= 	$arguments;
				$strand			=	2;
			}
		}
		
		
		if($thisPart =~ m/:/)
		{
			my $thisPartSeqPT;
			my ($start,$end)			=	0;
			my ($accession,$location)	=	'';
			my $efetchObj;
			
			($accession,$location)		=	split(/:/,$thisPart);
			($start,$end)				=	split(/\.\./,$location);
			
			eval
			{
				$efetchObj 				=	Bio::DB::EUtilities->new(
											-eutil		=> 'efetch',
											-db			=> 'nucleotide',
											-rettype	=> 'fasta',
											-email  	=> 'u4852380@anu.edu,au',
											-seq_start	=> "$start",
											-seq_stop	=> "$end",
											-id			=> "$accession"
											);
			} or do {warn("\tCould not EFetch nucleotide accession $accession, skipping it\n");return (undef,undef);};
			
			eval {$efetchObj->get_Response}
			or do {warn("\tEFetch of nucleotide accession $accession returned invalid result or error\n");return (undef,undef);};
			
			my $returnedObj				=	$efetchObj->get_Response->content;
			my @fastaFile				=	split(/\n/,$returnedObj);
			#print(join("\n" ,@fastaFile) . "\n\n");
			
			foreach my $fastaLine (@fastaFile)
			{
				next if($fastaLine =~ m/>/);
				chomp $fastaLine;
				$thisPartSeqPT	.=	$fastaLine;
			}
			
			if($strand !=1)
			{
				my $seqObj		=	Bio::Seq->new(-seq => $thisPartSeqPT);
				$thisPartSeqPT 	= 	$seqObj->revcom->seq;
			}
			$seqPlainText 	.= 	$thisPartSeqPT;
			$nucAccession	=	$accession;
																						#print ("was " . length ($thisPartSeqPT) . " bp long\n");
		}
		else
		{
			#use current seqobj. not implemented
		}
	}
	$| = 1;print (".");
	return($nucAccession,$seqPlainText);
}

sub getCodedBySeq($)
{
	my ($codedBy) 		=	@_;
	my $commandString  	=	$codedBy;
	my ($nucAccession,$seqPlainText) = '';
	my $strand			=	1;
	if($commandString =~ m/[\(\)]/)
	{
		while($commandString =~ m/[\(\)]/)
		{
			#get the command, and the stuff inside the brackets (called arguments here) may contain other strings
			my($command, $arguments) = split(/\(/,$commandString,2);
			$arguments =~ s/\)$//;
			if(grep(/join/,$command))
			{
				$commandString  				= 	$arguments;
				($nucAccession,$seqPlainText)	=	joinParts($arguments);
				last;
			}
			elsif(grep(/complement/,$command))
			{
				$commandString  				= 	$arguments;
				$strand							=	2;#tell us to use revcom
			}
		}
	}
	else
	{
		($nucAccession,$seqPlainText)	=	joinParts($commandString);
	}
	
	if(!$nucAccession||!$seqPlainText){return(undef,undef);}
	
	#return text seq and accession
	if($strand ==1)
	{
		$| = 1;print (".");
		return ($nucAccession,$seqPlainText);
	}
	else
	{
		my $seqObj	=	Bio::Seq->new(-seq => $seqPlainText);
		$| = 1;print (".");
		return ($nucAccession,$seqObj->revcom->seq);
	}
}


my $FATT = "GGGGACAAGTTTGTACAAAAAAGCAGGCTTCGGTACC";
my $RATT = "GGGGACCACTTTGTACAAGAAAGCTGGGTGACTAGT";

open (OUTFILE,">$outfile". "_processed.csv");
print OUTFILE ($csvFH->header . "\n");
close OUTFILE;
open(PROTFASTA,">$outfile". ".aa.fasta");
close PROTFASTA;
open(NUCFASTA,">$outfile". ".nt.fasta");
close NUCFASTA;

while(my $csvline = <$csvFH>) 
{
    if ($csvline->{'ProtAccession'})
    {	
    	my $protAccession = $csvline->{'ProtAccession'};
		print ($protAccession. "\t");
		my $protSeqObj;
		
		$| = 1;print (".");
		
		eval
		{
			$protSeqObj = $cachepep->get_Seq_by_acc($protAccession);
		} or do 
		{			
			warn("Exception caught while trying to reterive genpept entry for accession $protAccession. Error was: @_\n");
			next;
		};
		
		if (!$protSeqObj) {warn("\t\tNo sequence found for protein accession $protAccession, skipping it\n");next;}
		
		$| = 1;print (".");
		
		my $nucSeq;
		my $nucAccession;
		my $nucSeqobj;
		my $nucGI;
		my $protGI;
		
		foreach my $cdsSeqFeatureObj (  grep { $_->primary_tag eq 'CDS' } $protSeqObj->get_SeqFeatures())
		{
			next unless( $cdsSeqFeatureObj->has_tag('coded_by') ); # skip CDSes with no coded_by
			$| = 1;print (".");
			my ($codedby)				=	$cdsSeqFeatureObj->each_tag_value('coded_by');
			($nucAccession,$nucSeq)		=	getCodedBySeq($codedby);
		}
		
		if(!$nucAccession||!$nucSeq){warn("\tNo nucelotide sequence found for protein accession $protAccession, skipping it\n");next;}
		
		$csvline->{'NucSequence'}	= $nucSeq;
		$csvline->{'ProtSequence'}	= $protSeqObj->seq;
		$csvline->{'NucAccession'}	= $nucAccession;#$nucSeqobj->accession;
		$csvline->{'ProtAccession'}	= $protAccession;
		$csvline->{'NucGI'}			= $nucGI;
		$csvline->{'ProtGI'}		= $protGI;

		#print ($csvline. "\n");
		
		open (OUTFILE,">>$outfile". "_processed.csv");
		print OUTFILE ($csvline. "\n");
		close OUTFILE;
		
		open (PROTFASTA,">>$outfile". ".aa.fasta");
		print PROTFASTA (">gp|$protAccession\n" . $csvline->{'ProtSequence'} . "\n\n");
		close PROTFASTA;
		
		open (NUCFASTA,">>$outfile". ".nt.fasta");
		print NUCFASTA (">gb|$nucAccession\n" . $csvline->{'NucSequence'} . "\n\n");
		close NUCFASTA;
		print ("\tdone\tnuc length:\t". length($nucSeq). "\tprot length:\t". length($protSeqObj->seq). "\n");
    }
	elsif ($csvline->{'ProtGI'})
    {	
    	my $protGI = $csvline->{'ProtGI'};
		my $protAccession = $csvline->{'ProtAccession'};
		#print ($protGI);
		my $protSeqObj = $cachepep->get_Seq_by_id($protGI);
		
		my $nucSeq;
		my $nucAccession;
		my $nucSeqobj;
		my $nucGI;
		
		
		if (!$protSeqObj) {warn("No sequence found for protein accession $protAccession, skipping it\n");next;}
		
		foreach my $cdsSeqFeatureObj (  grep { $_->primary_tag eq 'CDS' } $protSeqObj->get_SeqFeatures())
		{
			next unless( $cdsSeqFeatureObj->has_tag('coded_by') ); # skip CDSes with no coded_by
			my ($codedby)			=	$cdsSeqFeatureObj->each_tag_value('coded_by');
			$nucSeq					=	getCodedBySeq($codedby);
		}
		$csvline->{'NucSequence'}	= $nucSeq;
		$csvline->{'ProtSequence'}	= $protSeqObj->seq;
		$csvline->{'NucAccession'}	= $nucAccession;#$nucSeqobj->accession;
		$csvline->{'ProtAccession'}	= $protAccession;
		$csvline->{'NucGI'}			= $nucGI;
		$csvline->{'ProtGI'}		= $protGI;

		#print ($csvline. "\n");
		
		open (OUTFILE,">>$outfile". "_processed.csv");
		print OUTFILE ($csvline. "\n");
		close OUTFILE;
		
		open (PROTFASTA,">>$outfile". ".aa.fasta");
		print PROTFASTA (">gp|$protAccession\n" . $csvline->{'ProtSequence'} . "\n\n");
		close PROTFASTA;
		
		open (NUCFASTA,">>$outfile". ".nt.fasta");
		print NUCFASTA (">gb|$nucAccession\n". $csvline->{'NucSequence'} . "\n\n");
		close NUCFASTA;
		print ("\tdone\tnuc length:\t". length($nucSeq). "\tprot length:\t". length($protSeqObj->seq). "\n");
    }
    elsif ($csvline->{'NucAccession'})
    {	
	my $nucAccession = $csvline->{'NucAccession'};
	print ($nucAccession);
	my $nucSeq;
	my $protSeq;
	my $protSeqObj;
	my $protAccession;
	my $nucGI;
	my $protGI;

	my $nucEUtil = Bio::DB::EUtilities->new( -eutil   => 'efetch',
									-db      => 'nucleotide',
									-id      => "$nucAccession",
									-email   => 'u4852380@anu.edu.au',
									-rettype => 'fasta');

	my @nucFasta = split(m{\n},$nucEUtil->get_Response->content);
	my (undef,$gi,$accDB,$acc,$name) = split(/\|/,$nucFasta[0]);
	if ($acc ne $nucAccession){print STDERR "$acc != $nucAccession\n";}
	$nucGI = $gi;
	$nucSeq .= join("",@nucFasta[1..$#nucFasta]);

	my $nucSeqobj = $cachepep->get_Seq_by_id($nucGI);

	if( ! $nucSeqobj ) { print STDERR "could not find a seq for accession: " .$nucAccession. "\n";close OUTFILE;next;}
	foreach my $cds (  grep { $_->primary_tag eq 'CDS' } $nucSeqobj->get_SeqFeatures())
	{
		next unless( $cds->has_tag('protein_id') ); # skip CDSes with no coded_by
		
		$protAccession			=	$cds->each_tag_value('protein_id');
		my $protEUtil		=	Bio::DB::EUtilities->new(
									-eutil   => 'efetch',
									-db      => 'protein',
									-id      => "$protAccession",
									-email   => 'u4852380@anu.edu.au',
									-rettype => 'fasta');

		my @protFasta = split(m{\n},$protEUtil->get_Response->content);
		my (undef,$gi,$accDB,$acc,$name) = split(/\|/,$protFasta[0]);
		if ($gi ne $protGI){print STDERR "$acc != $protAccession\n";next;}
		$protAccession = $acc;
		print "\tacc:" . $protAccession;
		#print  "\n" . $protFasta[0] . "\n";
		$protSeq .= join('',@protFasta[1..$#protFasta]);
	}
	$csvline->{'NucSequence'}	= $nucSeqobj->seq;
	$csvline->{'ProtSequence'}	= $protSeqObj->seq;
	$csvline->{'NucAccession'}	= $nucSeqobj->id;
	$csvline->{'ProtAccession'}	= $protSeqObj->id;
	$csvline->{'NucGI'}			= $nucGI;
	$csvline->{'ProtGI'}		= $protGI;

	$csvline->{'NucSequence'}	= $nucSeq;
	$csvline->{'ProtSequence'}	= $protSeq;
	$csvline->{'NucAccession'}	= $nucAccession;#$nucSeqobj->accession;
	$csvline->{'ProtAccession'}	= $protSeqObj->accession;
	$csvline->{'NucGI'}			= $nucGI;
	$csvline->{'ProtGI'}		= $protGI;

	#print ($csvline. "\n");


	open (OUTFILE,">>$outfile". "_processed.csv");
	print OUTFILE ($csvline. "\n");
	close OUTFILE;

	open (PROTFASTA,">>$outfile". ".aa.fasta");
	print PROTFASTA (">" . $protSeqObj->id ."\n" . $protSeqObj->seq . "\n\n");
	close PROTFASTA;

	open (NUCFASTA,">>$outfile". ".nt.fasta");
	print NUCFASTA (">" . $nucSeqobj->id . " from " .$protSeqObj->id . "\n" . $nucSeqobj->seq . "\n\n");
	close NUCFASTA;
	print (" done\n");
    }
elsif ($csvline->{'NucGI'})
    {	
	my $nucGI = $csvline->{'NucAccession'};
	print ($nucGI);
	my $nucSeqobj = $cachent->get_Seq_by_id($nucGI);
	my $protSeqobj;
	my $nucAccession;
	my $protGI;

	if( ! $nucSeqobj ) { print STDERR "could not find a seq for accession: " .$nucAccession. "\n";close OUTFILE;next;}
	foreach my $cds (  grep { $_->primary_tag eq 'CDS' } $nucSeqobj->get_SeqFeatures())
	{
		next unless( $cds->has_tag('protein_id') ); # skip CDSes with no coded_by
		
		my ($protAcc)			=	$cds->each_tag_value('protein_id');
		$protSeqobj				=	$cachepep->get_Seq_by_acc($protAcc);
	}
	$csvline->{'NucSequence'}	= $nucSeqobj->seq;
	$csvline->{'ProtSequence'}	= $protSeqobj->seq;
	$csvline->{'NucAccession'}	= $nucSeqobj->id;
	$csvline->{'ProtAccession'}	= $protSeqobj->id;
	$csvline->{'NucGI'}			= $nucGI;
	$csvline->{'ProtGI'}		= $protGI;

	#print ($csvline. "\n");
	
	
	open (OUTFILE,">>$outfile". "_processed.csv");
	print OUTFILE ($csvline. "\n");
	close OUTFILE;
	
	open (PROTFASTA,">>$outfile". ".aa.fasta");
	print PROTFASTA (">" . $protSeqobj->id ."\n" . $protSeqobj->seq . "\n\n");
	close PROTFASTA;
	
	open (NUCFASTA,">>$outfile". ".nt.fasta");
	print NUCFASTA (">" . $nucSeqobj->id . " from " .$protSeqobj->id . "\n" . $nucSeqobj->seq . "\n\n");
	close NUCFASTA;
	print (" done\n");
    }
    else {next;}
}
close $csvFH;
