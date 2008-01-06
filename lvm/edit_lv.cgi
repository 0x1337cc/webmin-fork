#!/usr/local/bin/perl
# Display a form for editing an existing logical volume

require './lvm-lib.pl';
&foreign_require("fdisk", "fdisk-lib.pl");
&ReadParse();
($vg) = grep { $_->{'name'} eq $in{'vg'} } &list_volume_groups();
@lvs = &list_logical_volumes($in{'vg'});

$vgdesc = &text('lv_vg', $vg->{'name'});
if ($in{'lv'}) {
	($lv) = grep { $_->{'name'} eq $in{'lv'} } @lvs;
	&ui_print_header($vgdesc, $lv->{'is_snap'} ? $text{'lv_edit_snap'}
				 : $text{'lv_edit'}, "");
	@stat = &device_status($lv->{'device'});
	}
else {
	&ui_print_header($vgdesc, $in{'snap'} ? $text{'lv_create_snap'} : $text{'lv_create'},"");
	$lv = { 'perm' => 'rw',
		'alloc' => 'n',
		'is_snap' => $in{'snap'},
	 	'size' => ($vg->{'pe_total'} - $vg->{'pe_alloc'})*
			  $vg->{'pe_size'} };
	}

print &ui_form_start("save_lv.cgi");
print &ui_hidden("vg", $in{'vg'});
print &ui_hidden("lv", $in{'lv'});
print &ui_hidden("snap", $in{'snap'});
print &ui_table_start($text{'lv_header'}, "width=100%", 4);

if ($stat[2]) {
	# Current status
	print &ui_table_row($text{'lv_name'}, $lv->{'name'});

	print &ui_table_row($text{'lv_size'}, &nice_size($lv->{'size'}*1024));
	}
else {
	# Details for new LV
	print &ui_table_row($text{'lv_name'}, 
		&ui_textbox("name", $lv->{'name'}, 20));

	print &ui_table_row($text{'lv_size'},
		&ui_textbox("size", $lv->{'size'}, 8)." kB");
	}

# Number of physical extents
print &ui_table_row($text{'lv_petotal'},
	&text('lv_petotals', $vg->{'pe_alloc'}, $vg->{'pe_total'}));

# Extent size
print &ui_table_row($text{'lv_pesize'},
	&nice_size($vg->{'pe_size'}*1024));

if ($in{'lv'}) {
	# Device file and current status
	print &ui_table_row($text{'lv_device'}, "<tt>$lv->{'device'}</tt>");

	print &ui_table_row($text{'lv_status'},
		@stat ? &device_message(@stat) : $text{'lv_notused'});
	}

if ($lv->{'is_snap'}) {
	if ($in{'lv'}) {
		# Show which LV this is a snapshot of
		local @snapof = grep { $_->{'size'} == $lv->{'size'} &&
				       $_->{'has_snap'} } @lvs;
		if (@snapof == 1) {
			$snapsel = "<tt>$snapof[0]->{'name'}</tt>";
			}
		else {
			$snapsel = "<i>$text{'lv_nosnap'}</i>";
			}
		}
	else {
		# Allow selection of snapshot source
		$snapsel = &ui_select("snapof", undef,
		    [ map { $_->{'name'} } grep { !$_->{'is_snap'} } @lvs ]);
		}
	print &ui_table_row($text{'lv_snapof'}, $snapsel);
	}
elsif ($stat[2]) {
	# Display current permissons and allocation method
	print &ui_table_row($text{'lv_perm'},
		$text{"lv_perm".$lv->{'perm'}});

	print &ui_table_row($text{'lv_alloc'},
		$text{"lv_alloc".$lv->{'alloc'}});
	}
else {
	# Allow editing of permissons and allocation method
	print &ui_table_row($text{'lv_perm'},
		&ui_radio("perm", $lv->{'perm'},
			  [ [ 'rw', $text{'lv_permrw'} ],
			    [ 'r', $text{'lv_permr'} ] ]));

	print &ui_table_row($text{'lv_alloc'},
		&ui_radio("alloc", $lv->{'alloc'},
			  [ [ 'y', $text{'lv_allocy'} ],
			    [ 'n', $text{'lv_allocn'} ] ]));
	}

if (!$in{'lv'} && !$lv->{'is_snap'}) {
	# Allow selection of striping
	print &ui_table_row($text{'lv_stripe'},
		&ui_opt_textbox("stripe", undef, 4, $text{'lv_nostripe'},
				$text{'lv_stripes2'}), 3);
	}
elsif (!$lv->{'is_snap'}) {
	# Show current striping
	print &ui_table_row($text{'lv_stripe'},
		$lv->{'stripes'} > 1 ? &text('lv_stripes', $lv->{'stripes'})
				     : $text{'lv_nostripe'}, 3);
	}

# Show free disk space
if (@stat && $stat[2]) {
	($total, $free) = &mount::disk_space($stat[1], $stat[0]);

	print &ui_table_row($text{'lv_freedisk'},
		&nice_size($free*1024));

	print &ui_table_row($text{'lv_free'},
		($total ? 100 * $free / $total : 0)." %");
	}

# Show extents on PVs
if ($in{'lv'}) {
	@pvinfo = &get_logical_volume_usage($lv);
	if (@pvinfo) {
		@pvs = &list_physical_volumes($in{'vg'});
		foreach $p (@pvinfo) {
			($pv) = grep { $_->{'name'} eq $p->[0] } @pvs;
			push(@pvlist, "<a href='edit_pv.cgi?vg=$in{'vg'}&pv=$pv->{'name'}'>$pv->{'name'}</a> ".&nice_size($p->[1]*$pv->{'pe_size'}*1024));
			}
		print &ui_table_row($text{'lv_pvs'}, join(" , ", @pvlist), 3);
		}
	}

print &ui_table_end();
if ($stat[2]) {
	# In use - cannot be edited
	print &ui_form_end();
	print "<b>$text{'lv_cannot'}</b><p>\n";
	}
elsif ($in{'lv'}) {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     [ 'delete', $text{'delete'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}

if ($in{'lv'} && !$stat[2] && !$lv->{'is_snap'}) {
	# Show button for creating filesystems
	print "<hr>\n";
	print &ui_buttons_start();

	$fstype = $stat[1] || "ext3";
	print &ui_buttons_row("mkfs_form.cgi", $text{'lv_mkfs'},
			      $text{'lv_mkfsdesc'},
			      &ui_hidden("dev", $lv->{'device'}),
			      &ui_select("fs", $fstype,
				[ map { [ $_, $fdisk::text{"fs_".$_}." ($_)" ] }
				      &fdisk::supported_filesystems() ]));

	if (!@stat) {
		# Show button for mounting
		$type = $config{'lasttype_'.$lv->{'device'}} || "ext2";
		print &ui_buttons_row("../mount/edit_mount.cgi",
				      $text{'lv_newmount'},
				      $text{'lv_mountmsg'},
				      &ui_hidden("type", $type).
				      &ui_hidden("newdev", $lv->{'device'}),
				      &ui_textbox("newdir", "", 20));
		}

	print &ui_buttons_end();
	}

&ui_print_footer("index.cgi?mode=lvs", $text{'index_return'});

