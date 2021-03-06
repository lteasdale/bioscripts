from Bio import Restriction
from Bio import SeqIO
import optparse
import sys

# Get all 
enzymes = Restriction.Restriction_Dictionary.rest_dict.keys()

def get_options():
    """
    This function allows commandline arguments to be passed to the script, so
    that you dont need to edit it every time you want to use a different 
    """
    parser = optparse.OptionParser('usage: %prog [options] ')
    parser.add_option(
        '-s',
        '--seqfile',
        dest='seqfile',
        help='File containing sequence to be analysed, as FASTA',
        metavar='FILE',
        default='')
    parser.add_option(
        '-e',
        '--enzyme',
        dest='enzyme',
        help='Enzyme',
        default="EcoRI")
    parser.add_option('-l',
        '--list-enzymes',
        dest='listenzymes',
        help='print list of enzymes',
        action="store_true",
        default=False)
    parser.add_option(
        '-c',
        "--count",
        dest="count",
        help="count all restriction sites, equivalent to -m 0 -x infinity",
        action="store_true",
        default=False
        )
    parser.add_option(
        '-m',
        "--min-length",
        dest="minlen",
        help="minimum length between restriction sites",
        type=int,
        default=200
        )
    parser.add_option(
        '-x',
        "--max-length",
        dest="maxlen",
        help="maximum length between restriction sites",
        type=int,
        default=600
        )
    parser.add_option(
        '-v',
        "--verbose",
        dest="verbose",
        action="count"
        )
    options, args = parser.parse_args()
    die = False
    if options.enzyme not in Restriction.Restriction_Dictionary.rest_dict.keys():
        print "ERROR: %s is an invalid enzyme name" % options.enzyme
        die = True
    if not options.seqfile and not options.listenzymes:
        print "ERROR: seqfile is required"
        die = True

    # If there's something wrong with the options
    if die:
        parser.print_help()
        sys.exit(1)
    return options


# Store Commandline args
opts = get_options()

# If we've been asked to list all enzymes, do this now and exit
if opts.listenzymes:
    print "The following enzymes are supported"
    for enzyme in enzymes:
        print enzyme
    sys.exit(0)



cut_dict = {}
for enzyme in enzymes:

    # gets enzyme class by name
    try:
        cutter = getattr(Restriction, enzyme)
        print "enzyme is %s, cuts at %s" % (cutter, cutter.site)
        cut_dict[cutter] = {}

        # Opens file, and creates fasta reader
        seq_file = open(opts.seqfile, "rb")
        seqs = SeqIO.parse(seq_file, "fasta")

        # Digest all sequences in the fasta file
        count = 0
        for record in seqs:
            record_count = 0
            # When we're counting, we only want to show how many cut sites there
            # are. Given that cutting a sequence 0 times gives one fragment, we
            # need to decrement this, or we add one to the true number of sites

            # Do virtual digest
            fragments = cutter.catalyse(record.seq)

            # Find fragment lenghts
            fragment_lengths = []
            for seq in fragments:
                fragment_lengths.append(len(seq))

            # Count how many fragments are the correct length
            for length in fragment_lengths:
                if opts.count:
                    record_count += max(0, len(fragment_lengths) - 1)
                elif length > opts.minlen and  length < opts.maxlen:
                    record_count += 1
            # Append the counts for this record to the total sum
            count += record_count

            cut_dict[cutter][record.id] = record_count

            if opts.verbose > 0:
                # Print summary
                print "%s has %i RADseq tags" % (record.id, record_count)

        print "In total, %i RADseq tags were found for this enzyme" % count
        cut_dict[cutter]["Total"] = count
    except NotImplementedError:
        continue

sort_list = []
for cutter, dct in cut_dict.iteritems():
    sort_list.append((dct["Total"], cutter))

sorted_list = sorted(sort_list)

for item in sorted_list:
    print item

