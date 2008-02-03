#!/usr/local/bin/perl
# raid_form.cgi
# Display a form for creating a raid device

require './raid-lib.pl';
&foreign_require("mount", "mount-lib.pl");
&foreign_require("lvm", "lvm-lib.pl");
&ReadParse();
$conf = &get_raidtab();

# Display headers
$max = 0;
foreach $c (@$conf) {
	if ($c->{'value'} =~ /md(\d+)$/ && $1 >= $max) {
		$max = $1+1;
		}
	}
&ui_print_header(undef, $text{'create_title'}, "");
$raid = { 'value' => "/dev/md$max",
	  'members' => [ { 'name' => 'raid-level',
			   'value' => $in{'level'} },
			 { 'name' => 'persistent-superblock',
			   'value' => 1 }
		       ] };

# Find available partitions
@disks = &find_free_partitions(undef, 1, 1);
if (!@disks) {
	print "<p><b>$text{'create_nodisks'}</b> <p>\n";
	&ui_print_footer("", $text{'index_return'});
	exit;
	}

print &ui_form_start("create_raid.cgi");
print &ui_hidden("idx", $in{'idx'});
print &ui_table_start($text{'create_header'}, undef, 2, [ "width=30%" ]);

# Device name
print &ui_table_row($text{'create_device'}, "<tt>$raid->{'value'}</tt>");
print &ui_hidden("device", $raid->{'value'});

# RAID level
$lvl = &find_value('raid-level', $raid->{'members'});
print &ui_table_row($text{'create_level'},
	$lvl eq 'linear' ? $text{'linear'} : $text{"raid$lvl"});
print &ui_hidden("level", $lvl);

# Create superblock?
$super = &find_value('persistent-superblock', $raid->{'members'});
print &ui_table_row($text{'create_super'},
	&ui_yesno_radio("super", $super ? 1 : 0));

# Parity algorithm
if ($lvl >= 5) {
	$parity = &find_value('parity-algorithm', $raid->{'members'});
	print &ui_table_row($text{'create_parity'},
		&ui_select("parity", $parity,
			[ [ '', $text{'default'} ],
			  'left-asymmetric', 'right-asymmetric',
			  'left-symmetric', 'right-symmetric' ]));
	}

# Chunk size
$chunk = &find_value('chunk-size', $raid->{'members'});
for($i=4; $i<=4096; $i*=2) { push(@chunks, [ $i, $i." kB" ]); }
print &ui_table_row($text{'create_chunk'},
	&ui_select("chunk", $chunk, \@chunks));

# Display partitions in raid, spares and parity
print &ui_table_row($text{'create_disks'},
	&ui_select("disks", undef, \@disks, 4, 1));

if ($lvl >= 4 && $lvl != 10) {
	print &ui_table_row($text{'create_spares'},
		&ui_select("spares", undef, \@disks, 4, 1));
	}

if ($lvl == 4 && $raid_mode ne 'mdadm') {
	print &ui_table_row($text{'create_pdisk'},
		&ui_select("pdisk", '', [ [ '', $text{'create_auto'} ],
					  @disks ], 4, 1));
	}

# Force creation
print &ui_table_row($text{'create_force'},
	&ui_yesno_radio("force", 0));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'create'} ] ]);

&ui_print_footer("", $text{'index_return'});

