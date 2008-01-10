#!/usr/local/bin/perl
# index.cgi
# Display a list of known disks and partitions

require './fdisk-lib.pl';
&error_setup($text{'index_err'});
&check_fdisk();
&ui_print_header(undef, $module_info{'desc'}, "", undef, 0, 1, 0,
	&help_search_link("fdisk", "man", "doc", "howto"));
$extwidth = 250;

# Show a table of just disks
$smart = &foreign_installed("smart-status") &&
	 &foreign_available("smart-status");
@disks = &list_disks_partitions();
@disks = grep { $access{'view'} || &can_edit_disk($_->{'device'}) } @disks;
@disks = sort { $a->{'device'} cmp $b->{'device'} } @disks;
if (@disks) {
	($hasctrl) = grep { defined($d->{'scsiid'}) ||
			    defined($d->{'controller'}) ||
			    $d->{'raid'} } @disks;
	print &ui_columns_start([ $text{'index_dname'},
				  $text{'index_dsize'},
				  $text{'index_dmodel'},
				  $text{'index_dparts'},
				  $hasctrl ? ( $text{'index_dctrl'} ) : ( ),
				  $text{'index_dacts'} ]);
	foreach $d (@disks) {
		$ed = &can_edit_disk($d->{'device'});
		@links = ( );
		@ctrl = ( );
		if (defined($d->{'scsiid'}) && defined($d->{'controller'})) {
			push(@ctrl, &text('index_dscsi', $d->{'scsiid'},
						         $d->{'controller'}));
			}
		if ($d->{'raid'}) {
			push(@ctrl, &text('index_draid', $d->{'raid'}));
			}
		if (($d->{'type'} eq 'ide' ||
		    $d->{'type'} eq 'scsi' && $d->{'model'} =~ /ATA/) && $ed) {
			# Display link to IDE params form
			push(@links, "<a href='edit_hdparm.cgi?".
			     "disk=$d->{'index'}'>$text{'index_dhdparm'}</a>");
			}
		if ($smart) {
			# Display link to smart module
			push(@links, "<a href='../smart-status/index.cgi?".
			     "drive=$d->{'device'}'>$text{'index_dsmart'}</a>");
			}
		print &ui_columns_row([
			$ed ? "<a href='edit_disk.cgi?device=$d->{'device'}'>".
			        $d->{'desc'}."</a>"
			    : $d->{'desc'},
			$d->{'cylsize'} ?
			  &nice_size($d->{'cylinders'}*$d->{'cylsize'}) : "",
			$d->{'model'},
			scalar(@{$d->{'parts'}}),
			$hasctrl ? ( join(" ", @ctrl) ) : ( ),
			&ui_links_row(\@links),
			]);
		}
	print &ui_columns_end();
	}
else {
	print "<b>$text{'index_none2'}</b><p>\n";
	}

&ui_print_footer("/", $text{'index'});

