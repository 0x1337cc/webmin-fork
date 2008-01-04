#!/usr/local/bin/perl
# view_raid.cgi
# Display information about a raid device

require './raid-lib.pl';
&foreign_require("mount", "mount-lib.pl");
&foreign_require("lvm", "lvm-lib.pl");
&ReadParse();

print "Refresh: $config{'refresh'}\r\n"
	if ($config{'refresh'});
&ui_print_header(undef, $text{'view_title'}, "");
$conf = &get_raidtab();
$raid = $conf->[$in{'idx'}];

print &ui_form_start("save_raid.cgi");
print &ui_hidden("idx", $in{'idx'});
print &ui_table_start($text{'view_header'}, undef, 2, [ "width=30%" ]);

# Device name
print &ui_table_row($text{'view_device'}, "<tt>$raid->{'value'}</tt>");

# RAID level
$lvl = &find_value('raid-level', $raid->{'members'});
print &ui_table_row($text{'view_level'},
	$lvl eq 'linear' ? $text{'linear'} : $text{"raid$lvl"});

# Current status
@st = &device_status($raid->{'value'});
print &ui_table_row($text{'view_status'},
      $st[1] eq 'lvm' ? &text('view_lvm', "<tt>$st[0]</tt>") :
      $st[2] ? &text('view_mounted', "<tt>$st[0]</tt>") :
      @st ? &text('view_mount', "<tt>$st[0]</tt>") :
      $raid->{'active'} ? $text{'view_active'} :
			  $text{'view_inactive'});

if ($raid->{'size'}) {
	print &ui_table_row($text{'view_size'},
		&text('view_blocks', $raid->{'size'})." ".
	        "(".&nice_size($raid->{'size'}*1024).")");
	}
if ($raid->{'resync'}) {
	print &ui_table_row($text{'view_resync'}, "$raid->{'resync'} \%");
	}

# Superblock?
$super = &find_value('persistent-superblock', $raid->{'members'});
print &ui_table_row($text{'view_super'},
	$super ? $text{'yes'} : $text{'no'});

# Parity method
if ($lvl eq '5') {
	$parity = &find_value('parity-algorithm', $raid->{'members'});
	print &ui_table_row($text{'view_parity'}, $parity || $text{'default'});
	}

# Chunk size
$chunk = &find_value('chunk-size', $raid->{'members'});
print &ui_table_row($text{'view_chunk'},
	$chunk ? "$chunk kB" : $text{'default'});

# Current errors
if (ref($raid->{'errors'})) {
	for($i=0; $i<@{$raid->{'errors'}}; $i++) {
		if ($raid->{'errors'}->[$i] ne "U") {
			push(@badlist, $raid->{'devices'}->[$i]);
			}
		}
	if (@badlist) {
		print &ui_table_row($text{'view_errors'},
			"<font color=#ff0000>".
			&text('view_bad', scalar(@badlist)).
			"</font>");
		}
	}

# Current state
if ($raid->{'state'}) {
	print &ui_table_row($text{'view_state'}, $raid->{'state'});
	}

# Rebuild percent
if ($raid->{'rebuild'}) {
	print &ui_table_row($text{'view_rebuild'}, $raid->{'rebuild'}." \%");
	}


# Display partitions in RAID
$rp = undef;
foreach $d (&find('device', $raid->{'members'})) {
	if (&find('raid-disk', $d->{'members'}) ||
            &find('parity-disk', $d->{'members'})) {
		local $name = &mount::device_name($d->{'value'});
		$rp .= $name."\n";
		if (!&indevlist($d->{'value'}, $raid->{'devices'}) &&
		    $raid->{'active'}) {
			$rp .= "<font color=#ff0000>$text{'view_down'}</font>\n";
			}
		$rp .= "<br>\n";
		push(@rdisks, [ $d->{'value'}, $name ]);
		}
	}
print &ui_table_row($text{'view_disks'}, $rp);

# Display spare partitions
$sp = undef;
foreach $d (&find('device', $raid->{'members'})) {
	if (&find('spare-disk', $d->{'members'})) {
		local $name = &mount::device_name($d->{'value'});
		$sp .= "$name<br>\n";
		push(@rdisks, [ $d->{'value'}, $name ]);
		}
	}
if ($sp) {
	print &ui_table_row($text{'view_spares'}, $sp);
	}
print &ui_table_end();

print "<hr>\n";
@grid = ( );

if ($raid_mode eq "raidtools" && !$st[2]) {
	# Only classic raid tools can disable a RAID
	local $act = $raid->{'active'} ? "stop" : "start";
	push(@grid, &ui_submit($text{'view_'.$act}, $act),
		    $text{'view_'.$act.'desc'});
	}

if ($raid_mode eq "mdadm") {
	# Only MDADM can add or remove a device (so far)
	@disks = &find_free_partitions([ $raid->{'value'} ], 0, 1);
	if ($disks) {
		push(@grid, &ui_submit($text{'view_add'}, "add")." ".
			    &ui_select("disk", undef, \@disks),
			    $text{'view_adddesc'});
		}

	if ($rdisks_count > 1) {
		push(@grid, &ui_submit($text{'view_remove'}, "remove")." ".
			    &ui_select("rdisk", undef, \@rdisks),
			    $text{'view_removedesc'});
		}
	}

if ($raid->{'active'} && !$st[2]) {
	# Show buttons for creating filesystems
	$fstype = $st[1] || "ext3";
	push(@grid, &ui_submit($text{'view_mkfs2'}, "mkfs")." ".
	    &ui_select("fs", $fstype,
			[ map { [ $_, $fdisk::text{"fs_".$_} ] }
			      &fdisk::supported_filesystems() ]),
	    $text{'view_mkfsdesc'});
	}

if (!@st) {
	# Show button for mounting filesystem
	push(@grid, &ui_submit($text{'view_newmount'}, "mount")." ".
		    &ui_textbox("newdir", undef, 20),
		    $text{'view_mountmsg'});

	# Show button for mounting as swap
	push(@grid, &ui_submit($text{'view_newmount2'}, "mountswap"),
		    $text{'view_mountmsg2'});
	}

if (!$st[2]) {
	push(@grid, &ui_submit($text{'view_delete'}, "delete"),
		    $text{'view_deletedesc'});
	}

if (@grid) {
	print &ui_grid_table(\@grid, 2, 100, [ "width=20% nowrap" ]);
	}
if ($st[2]) {
	print "<b>$text{'view_cannot2'}</b><p>\n";
	}
print &ui_form_end();

&ui_print_footer("", $text{'index_return'});

# indevlist(device, &list)
sub indevlist
{
local $d;
foreach $d (@{$_[1]}) {
	return 1 if (&same_file($_[0], $d));
	}
return 0;
}

