# boxes-lib.pl
# Functions to parsing user mail files

use POSIX;
if ($userconfig{'date_tz'} || $config{'date_tz'}) {
        # Set the timezone for all date calculations, and force a conversion
        # now as in some cases the first one fails!
        $ENV{'TZ'} = $userconfig{'date_tz'} ||
                     $config{'date_tz'};
        strftime('%H:%M', localtime(time()));
        }
use Time::Local;

$dbm_index_min = 1000000;
$dbm_index_version = 3;

# list_mails(user|file, [start], [end])
# Returns a subset of mail from a mbox format file
sub list_mails
{
local (@rv, $h, $done);
my %index;
&build_dbm_index($_[0], \%index);
local ($start, $end);
local $isize = $index{'mailcount'};
if (@_ == 1 || !defined($_[1]) && !defined($_[2])) {
	$start = 0; $end = $isize-1;
	}
elsif ($_[2] < 0) {
	$start = $isize+$_[2]-1; $end = $isize+$_[1]-1;
	$start = $start<0 ? 0 : $start;
	}
else {
	$start = $_[1]; $end = $_[2];
	$end = $isize-1 if ($end >= $isize);
	}
$rv[$isize-1] = undef if ($isize);	# force array to right size
local $dash = &dash_mode($_[0]);
open(MAIL, &user_mail_file($_[0]));
$start = 0 if ($start < 0);
for($i=$start; $i<=$end; $i++) {
	# Seek to mail position
	local @idx = split(/\0/, $index{$i});
	local $pos = $idx[0];
	local $startline = $idx[1];
	seek(MAIL, $pos, 0);

	# Read the mail
	local $mail = &read_mail_fh(MAIL, $dash ? 2 : 1, 0);
	$mail->{'line'} = $startline;
	$mail->{'eline'} = $startline + $mail->{'lines'} - 1;
	$mail->{'idx'} = $i;
	# ID is position in file and message ID
	$mail->{'id'} = $pos." ".$i." ".$startline." ".
		substr($mail->{'header'}->{'message-id'}, 0, 255);
	$rv[$i] = $mail;
	}
return @rv;
}

# select_mails(user|file, &ids, headersonly)
# Returns a list of messages from an mbox with the given IDs. The ID contains
# the file offset, message number, line and message ID, and the former is used
# if valid.
sub select_mails
{
local ($file, $ids, $headersonly) = @_;
local @rv;

local (@rv);
my %index;
local $gotindex;

local $umf = &user_mail_file($file);
local $dash = &dash_mode($umf);
open(MAIL, $umf);
foreach my $i (@$ids) {
	local ($pos, $idx, $startline, $wantmid) = split(/ /, $i);

	# Go to where the mail is supposed to be, and check if any starts there
	seek(MAIL, $pos, 0);
	local $ll = <MAIL>;
	local $fromok = $ll !~ /^From\s+(\S+).*\d+\r?\n/ ||
			($1 eq '-' && !$dash) ? 0 : 1;
	print DEBUG "seeking to $pos in $umf, got $ll";
	if (!$fromok) {
		# Oh noes! Need to find it
		if (!$gotindex++) {
			&build_dbm_index($file, \%index);
			}
		$pos = undef;
		while(my ($k, $v) = each %index) {
			if (int($k) eq $k) {
				my ($p, $line, $subject, $from, $mid)=
					split(/\0/, $v);
				if ($mid eq $wantmid) {
					# Found it!
					$pos = $p;
					$idx = $k;
					$startline = $line;
					last;
					}
				}
			}
		}

	if (defined($pos)) {
		# Now we can read
		seek(MAIL, $pos, 0);
		local $mail = &read_mail_fh(MAIL, $dash ? 2 : 1, $headersonly);
		$mail->{'line'} = $startline;
		$mail->{'eline'} = $startline + $mail->{'lines'} - 1;
		$mail->{'idx'} = $idx;
		$mail->{'id'} = "$pos $idx $startline $wantmid";
		push(@rv, $mail);
		}
	else {
		push(@rv, undef);	# Mail is gone?
		}
	}
close(MAIL);
return @rv;
}

# idlist_mails(user|file)
# Returns a list of IDs in some mbox
sub idlist_mails
{
my %index;
local $idlist = &build_dbm_index($_[0], \%index);
return @$idlist;
local @rv;
while(my ($k, $v) = each %index) {
	if ($k eq int($k)) {
		local ($pos, $line, $subject, $sender, $mid) = split(/\0/, $v);
		$rv[$k] = $pos." ".$k." ".$line." ".$mid;
		}
	}
return @rv;
}

# search_mail(user, field, match)
# Returns an array of messages matching some search
sub search_mail
{
return &advanced_search_mail($_[0], [ [ $_[1], $_[2] ] ], 1);
}

# advanced_search_mail(user|file, &fields, andmode, [&limits], [headersonly])
# Returns an array of messages matching some search
sub advanced_search_mail
{
local (%index, @rv, $i);
local $dash = &dash_mode($_[0]);
local @possible;		# index positions of possible mails
local $possible_certain = 0;	# is possible list authoratative?
local ($min, $max);

# We have a DBM index .. if the search includes the from and subject
# fields, scan it first to cut down on the total time
&build_dbm_index($_[0], \%index);

# Check which fields are used in search
local @dbmfields = grep { $_->[0] eq 'from' ||
			  $_->[0] eq 'subject' } @{$_[1]};
local $alldbm = (scalar(@dbmfields) == scalar(@{$_[1]}));

$min = 0;
$max = $index{'mailcount'}-1;
if ($_[3] && $_[3]->{'latest'}) {
	$min = $max - $_[3]->{'latest'};
	}

# Only check DBM if it contains some fields, and if it contains all
# fields when in 'or' mode.
if (@dbmfields && ($alldbm || $_[2])) {
	# Scan the DBM to build up a list of 'possibles'
	for($i=$min; $i<=$max; $i++) {
		local @idx = split(/\0/, $index{$i});
		local $fake = { 'header' => { 'from', $idx[2],
					      'subject', $idx[3] } };
		local $m = &mail_matches(\@dbmfields, $_[2], $fake);
		push(@possible, $i) if ($m);
		}
	$possible_certain = $alldbm;
	}
else {
	# None of the DBM fields are in the search .. have to scan all
	@possible = ($min .. $max);
	}

# Need to scan through possible messages to find those that match
open(MAIL, &user_mail_file($_[0]));
foreach $i (@possible) {
	# Seek to mail position
	local @idx = split(/\0/, $index{$i});
	local $pos = $idx[0];
	local $startline = $idx[1];
	seek(MAIL, $pos, 0);

	# Read the mail
	local $mail = &read_mail_fh(MAIL, $dash ? 2 : 1, 0);
	$mail->{'line'} = $startline;
	$mail->{'eline'} = $startline + $mail->{'lines'} - 1;
	$mail->{'idx'} = $i;
	$mail->{'id'} = $pos." ".$i." ".$startline." ".
			substr($mail->{'header'}->{'message-id'}, 0, 255);
	push(@rv, $mail) if ($possible_certain ||
			     &mail_matches($_[1], $_[2], $mail));
	}
return @rv;
}

# build_dbm_index(user|file, &index)
# Updates a reference to a DBM hash that indexes the given mail file.
# Hash contains keys 0, 1, 2 .. each of which has a value containing the
# position of the mail in the file, line number, subject, sender and message ID.
# Special key lastchange = time index was last updated
#	      mailcount = number of messages in index
#	      version = index format version
# Returns a list of all IDs
sub build_dbm_index
{
local $ifile = &user_index_file($_[0]);
local $umf = &user_mail_file($_[0]);
local @st = stat($umf);
local $index = $_[1];
dbmopen(%$index, $ifile, 0600);

# Read file of IDs
local $idsfile = $ifile.".ids";
local @ids;
local $idschanged;
if (open(IDSFILE, $idsfile)) {
	@ids = <IDSFILE>;
	chop(@ids);
	close(IDSFILE);
	}

if (scalar(@ids) != $index->{'mailcount'}) {
	# Build for first time
	print DEBUG "need meta-index rebuild for $_[0] ",scalar(@ids)," != ",$index->{'mailcount'},"\n";
	@ids = ( );
	while(my ($k, $v) = each %$index) {
		if ($k eq int($k) && $k < $index->{'mailcount'}) {
			local ($pos, $line, $subject, $sender, $mid) =
				split(/\0/, $v);
			$ids[$k] = $pos." ".$k." ".$line." ".$mid;
			}
		elsif ($k >= $index->{'mailcount'}) {
			# Old crap that is off the end
			delete($index->{$k});
			}
		}
	$index->{'mailcount'} = scalar(@ids);	# Now known for sure
	$idschanged = 1;
	}

if (!@st ||
    $index->{'lastchange'} < $st[9] ||
    $st[7] < $dbm_index_min ||
    $index->{'version'} != $dbm_index_version) {
	# The mail file is newer than the index, or we are always re-indexing
	local $fromok = 1;
	local ($ll, @idx);
	local $dash = &dash_mode($umf);
	if ($st[7] < $dbm_index_min ||
	    $index->{'version'} != $dbm_index_version) {
		$fromok = 0;	# Always re-index
		open(MAIL, $umf);
		}
	else {
		if (open(MAIL, $umf)) {
			# Check the last 100 messages (at most), to see if
			# the mail file has been truncated, had mails deleted,
			# or re-written.
			local $il = $index->{'mailcount'}-1;
			local $i;
			for($i=($il>100 ? 100 : $il); $i>=0; $i--) {
				@idx = split(/\0/, $index->{$il-$i});
				seek(MAIL, $idx[0], 0);
				$ll = <MAIL>;
				$fromok = 0 if ($ll !~ /^From\s+(\S+).*\d+\r?\n/ ||
						($1 eq '-' && !$dash));
				}
			}
		else {
			$fromok = 0;	# No mail file yet
			}
		}
	local ($pos, $lnum, $istart);
	if ($index->{'mailcount'} && $fromok && $st[7] > $idx[0]) {
		# Mail file seems to have gotten bigger, most likely
		# because new mail has arrived ... only reindex the new mails
		$pos = $idx[0] + length($ll);
		$lnum = $idx[1] + 1;
		$istart = $index->{'mailcount'};
		}
	else {
		# Mail file has changed in some other way ... do a rebuild
		# of the whole index
		$istart = 0;
		$pos = 0;
		$lnum = 0;
		seek(MAIL, 0, 0);
		@ids = ( );
		$idschanged = 1;
		}
	local ($doingheaders, @nidx);
	while(<MAIL>) {
		if (/^From\s+(\S+).*\d+\r?\n/ && ($1 ne '-' || $dash)) {
			@nidx = ( $pos, $lnum );
			$idschanged = 1;
			push(@ids, $pos." ".$istart." ".$lnum);
			$index->{$istart++} = join("\0", @nidx);
			$doingheaders = 1;
			}
		elsif ($_ eq "\n" || $_ eq "\r\n") {
			$doingheaders = 0;
			}
		elsif ($doingheaders && /^From:\s*(.{0,255})/i) {
			$nidx[2] = $1;
			$index->{$istart-1} = join("\0", @nidx);
			}
		elsif ($doingheaders && /^Subject:\s*(.{0,255})/i) {
			$nidx[3] = $1;
			$index->{$istart-1} = join("\0", @nidx);
			}
		elsif ($doingheaders && /^Message-ID:\s*(.{0,255})/i) {
			$nidx[4] = $1;
			$index->{$istart-1} = join("\0", @nidx);
			$ids[$#ids] .= " ".$1;
			}
		$pos += length($_);
		$lnum++;
		}
	close(MAIL);
	$index->{'lastchange'} = time();
	$index->{'mailcount'} = $istart;
	$index->{'version'} = $dbm_index_version;
	}

# Write out IDs file, if needed
if ($idschanged) {
	open(IDSFILE, ">$idsfile");
	foreach my $id (@ids) {
		print IDSFILE $id,"\n";
		}
	close(IDSFILE);
	}

return \@ids;
}

# has_dbm_index(user|file)
# Returns 1 if a DBM index exists for some user or file
sub has_dbm_index
{
local $ifile = &user_index_file($_[0]);
foreach my $ext (".dir", ".pag", ".db") {
	return 1 if (-r $ifile.$ext);
	}
return 0;
}

# empty_mail(user|file)
# Truncate a mail file to nothing
sub empty_mail
{
local $umf = &user_mail_file($_[0]);
local $ifile = &user_index_file($_[0]);
open(TRUNC, ">$umf");
close(TRUNC);

# Set index size to 0
local %index;
dbmopen(%index, $ifile, 0600);
$index{'mailcount'} = 0;
$index{'lastchange'} = time();
dbmclose(%index);
}

# count_mail(user|file)
# Returns the number of messages in some mail file
sub count_mail
{
my %index;
&build_dbm_index($_[0], \%index);
return $index{'mailcount'};
}

# parse_mail(&mail, [&parent], [savebody])
# Extracts the attachments from the mail body
sub parse_mail
{
return if ($_[0]->{'parsed'}++);
local $ct = $_[0]->{'header'}->{'content-type'};
local (@attach, $h, $a);
if ($ct =~ /multipart\/(\S+)/i && ($ct =~ /boundary="([^"]+)"/i ||
				   $ct =~ /boundary=([^;\s]+)/i)) {
	# Multipart MIME message
	local $bound = "--".$1;
	local @lines = split(/\r?\n/, $_[0]->{'body'});
	local $l;
	local $max = @lines;
	while($l < $max && $lines[$l++] ne $bound) {
		# skip to first boundary
		}
	while(1) {
		# read attachment headers
		local (@headers, $attach);
		while($lines[$l]) {
			$attach->{'raw'} .= $lines[$l]."\n";
			$attach->{'rawheaders'} .= $lines[$l]."\n";
			if ($lines[$l] =~ /^(\S+):\s*(.*)/) {
				push(@headers, [ $1, $2 ]);
				}
			elsif ($lines[$l] =~ /^\s+(.*)/) {
				$headers[$#headers]->[1] .= $1
					unless($#headers < 0);
				}
			$l++;
			}
		$attach->{'raw'} .= $lines[$l]."\n";
		$l++;
		$attach->{'headers'} = \@headers;
		foreach $h (@headers) {
			$attach->{'header'}->{lc($h->[0])} = $h->[1];
			}
		if ($attach->{'header'}->{'content-type'} =~ /^([^;]+)/) {
			$attach->{'type'} = lc($1);
			}
		else {
			$attach->{'type'} = 'text/plain';
			}
		if ($attach->{'header'}->{'content-disposition'} =~
		    /filename\s*=\s*"([^"]+)"/i) {
			$attach->{'filename'} = $1;
			}
		elsif ($attach->{'header'}->{'content-disposition'} =~
		       /filename\s*=\s*([^;\s]+)/i) {
			$attach->{'filename'} = $1;
			}
		elsif ($attach->{'header'}->{'content-type'} =~
		    /name\s*=\s*"([^"]+)"/i) {
			$attach->{'filename'} = $1;
			}

		# read the attachment body
		while($l < $max && $lines[$l] ne $bound && $lines[$l] ne "$bound--") {
			$attach->{'data'} .= $lines[$l]."\n";
			$attach->{'raw'} .= $lines[$l]."\n";
			$l++;
			}
		$attach->{'data'} =~ s/\n\n$/\n/;	# Lose trailing blank line
		$attach->{'raw'} =~ s/\n\n$/\n/;

		# decode if necessary
		if (lc($attach->{'header'}->{'content-transfer-encoding'}) eq
		    'base64') {
			# Standard base64 encoded attachment
			$attach->{'data'} = &b64decode($attach->{'data'});
			}
		elsif (lc($attach->{'header'}->{'content-transfer-encoding'}) eq
		       'x-uue') {
			# UUencoded attachment
			$attach->{'data'} = &uudecode($attach->{'data'});
			}
		elsif (lc($attach->{'header'}->{'content-transfer-encoding'}) eq
		       'quoted-printable') {
			# Quoted-printable text attachment
			$attach->{'data'} = &quoted_decode($attach->{'data'});
			}
		elsif (lc($attach->{'type'}) eq 'application/mac-binhex40' && &has_command("hexbin")) {
			# Macintosh binhex encoded attachment
			local $temp = &transname();
			mkdir($temp, 0700);
			open(HEXBIN, "| (cd $temp ; hexbin -n attach -d 2>/dev/null)");
			print HEXBIN $attach->{'data'};
			close(HEXBIN);
			if (!$?) {
				open(HEXBIN, "$temp/attach.data");
				local $/ = undef;
				$attach->{'data'} = <HEXBIN>;
				close(HEXBIN);
				local $ct = &guess_mime_type($attach->{'filename'});
				$attach->{'type'} = $ct;
				$attach->{'header'} = { 'content-type' => $ct };
				$attach->{'headers'} = [ [ 'Content-Type', $ct ] ];
				}
			unlink("$temp/attach.data");
			rmdir($temp);
			}

		$attach->{'idx'} = scalar(@attach);
		$attach->{'parent'} = $_[1] ? $_[1] : $_[0];
		push(@attach, $attach) if (@headers || $attach->{'data'});
		if ($attach->{'type'} =~ /multipart\/(\S+)/i) {
			# This attachment contains more attachments ..
			# expand them.
			local $amail = { 'header' => $attach->{'header'},
					 'body' => $attach->{'data'} };
			&parse_mail($amail, $attach);
			$attach->{'attach'} = [ @{$amail->{'attach'}} ];
			map { $_->{'idx'} += scalar(@attach) }
			    @{$amail->{'attach'}};
			push(@attach, @{$amail->{'attach'}});
			}
		elsif (lc($attach->{'type'}) eq 'application/ms-tnef') {
			# This attachment is a winmail.dat file, which may
			# contain multiple other attachments!
			local ($opentnef, $tnef);
			if (!($opentnef = &has_command("opentnef")) &&
			    !($tnef = &has_command("tnef"))) {
				$attach->{'error'} = "tnef command not installed";
				}
			else {
				# Can actually decode
				local $tempfile = &transname();
				open(TEMPFILE, ">$tempfile");
				print TEMPFILE $attach->{'data'};
				close(TEMPFILE);
				local $tempdir = &transname();
				mkdir($tempdir, 0700);
				if ($opentnef) {
					system("$opentnef -d $tempdir -i $tempfile >/dev/null 2>&1");
					}
				else {
					system("$tnef -C $tempdir -f $tempfile >/dev/null 2>&1");
					}
				pop(@attach);	# lose winmail.dat
				opendir(DIR, $tempdir);
				while($f = readdir(DIR)) {
					next if ($f eq '.' || $f eq '..');
					local $data;
					open(FILE, "$tempdir/$f");
					while(<FILE>) {
						$data .= $_;
						}
					close(FILE);
					local $ct = &guess_mime_type($f);
					push(@attach,
					  { 'type' => $ct,
					    'idx' => scalar(@attach),
					    'header' =>
						{ 'content-type' => $ct },
					    'headers' =>
						[ [ 'Content-Type', $ct ] ],
					    'filename' => $f,
					    'data' => $data });
					}
				closedir(DIR);
				unlink(glob("$tempdir/*"), $tempfile);
				rmdir($tempdir);
				}
			}
		last if ($l >= $max || $lines[$l] eq "$bound--");
		$l++;
		}
	$_[0]->{'attach'} = \@attach;
	}
elsif ($_[0]->{'body'} =~ /begin\s+([0-7]+)\s+(.*)/i) {
	# Message contains uuencoded file(s)
	local @lines = split(/\n/, $_[0]->{'body'});
	local ($attach, $rest);
	foreach $l (@lines) {
		if ($l =~ /^begin\s+([0-7]+)\s+(.*)/i) {
			$attach = { 'type' => &guess_mime_type($2),
				    'idx' => scalar(@{$_[0]->{'attach'}}),
				    'parent' => $_[1],
				    'filename' => $2 };
			push(@{$_[0]->{'attach'}}, $attach);
			}
		elsif ($l =~ /^end/ && $attach) {
			$attach = undef;
			}
		elsif ($attach) {
			$attach->{'data'} .= unpack("u", $l);
			}
		else {
			$rest .= $l."\n";
			}
		}
	if ($rest =~ /\S/) {
		# Some leftover text
		push(@{$_[0]->{'attach'}},
			{ 'type' => "text/plain",
			  'idx' => scalar(@{$_[0]->{'attach'}}),
			  'parent' => $_[1],
			  'data' => $rest });
		}
	}
elsif (lc($_[0]->{'header'}->{'content-transfer-encoding'}) eq 'base64') {
	# Signed body section
	$ct =~ s/;.*$//;
	$_[0]->{'attach'} = [ { 'type' => lc($ct),
				'idx' => 0,
				'parent' => $_[1],
				'data' => &b64decode($_[0]->{'body'}) } ];
	}
elsif (lc($_[0]->{'header'}->{'content-type'}) eq 'x-sun-attachment') {
	# Sun attachment format, which can contain several sections
	local $sun;
	foreach $sun (split(/----------/, $_[0]->{'body'})) {
		local ($headers, $rest) = split(/\r?\n\r?\n/, $sun, 2);
		local $attach = { 'idx' => scalar(@{$_[0]->{'attach'}}),
				  'parent' => $_[1],
				  'data' => $rest };
		if ($headers =~ /X-Sun-Data-Name:\s*(\S+)/) {
			$attach->{'filename'} = $1;
			}
		if ($headers =~ /X-Sun-Data-Type:\s*(\S+)/) {
			local $st = $1;
			$attach->{'type'} = $st eq "text" ? "text/plain" :
					    $st eq "html" ? "text/html" :
					    $st =~ /\// ? $st : "application/octet-stream";
			}
		elsif ($attach->{'filename'}) {
			$attach->{'type'} =
				&guess_mime_type($attach->{'filename'});
			}
		else {
			$attach->{'type'} = "text/plain";	# fallback
			}
		push(@{$_[0]->{'attach'}}, $attach);
		}
	}
else {
	# One big attachment (probably text)
	local ($type, $body);
	($type = $ct) =~ s/;.*$//;
	$type = 'text/plain' if (!$type);
	if (lc($_[0]->{'header'}->{'content-transfer-encoding'}) eq 'base64') {
		$body = &b64decode($_[0]->{'body'});
		}
	elsif (lc($_[0]->{'header'}->{'content-transfer-encoding'}) eq 
	       'quoted-printable') {
		$body = &quoted_decode($_[0]->{'body'});
		}
	else {
		$body = $_[0]->{'body'};
		}
	$_[0]->{'attach'} = [ { 'type' => lc($type),
				'idx' => 0,
				'parent' => $_[1],
				'data' => $body } ];
	}
delete($_[0]->{'body'}) if (!$_[2]);
}

# delete_mail(user|file, &mail, ...)
# Delete mail messages from a user by copying the file and rebuilding the index
sub delete_mail
{
local @m = sort { $a->{'line'} <=> $b->{'line'} } @_[1..@_-1];
local $i = 0;
local $f = &user_mail_file($_[0]);
local $ifile = &user_index_file($_[0]);
local $lnum = 0;
local %dline;
local ($dpos = 0, $dlnum = 0);
local (@index, %index);
&build_dbm_index($_[0], \%index);

local $tmpf = $< == 0 ? "$f.del" :
	      $_[0] =~ /^\/.*\/([^\/]+)$/ ?
	   	"$user_module_config_directory/$1.del" :
	      "$user_module_config_directory/$_[0].del";
open(SOURCE, $f) || &error("Read failed : $!");
open(DEST, ">$tmpf") || &error("Open of $tmpf failed : $!");
while(<SOURCE>) {
	if ($i >= @m || $lnum < $m[$i]->{'line'}) {
		$dpos += length($_);
		$dlnum++;
		local $w = (print DEST $_);
		if (!$w) {
			local $e = "$!";
			close(DEST);
			close(SOURCE);
			unlink($tmpf);
			&error("Write to $tmpf failed : $e");
			}
		}
	elsif ($lnum == $m[$i]->{'eline'}) {
		$dline{$m[$i]->{'line'}}++;
		$i++;
		}
	$lnum++;
	}
close(SOURCE);
close(DEST) || &error("Write to $tmpf failed : $?");
local @st = stat($f);
unlink($f) if ($< == 0);

# Force a total index re-build (XXX lazy!)
$index{'mailcount'} = $in{'lastchange'} = 0;

if ($< == 0) {
	rename($tmpf, $f);
	}
else {
	system("cat ".quotemeta($tmpf)." > ".quotemeta($f).
	       " && rm -f ".quotemeta($tmpf));
	}
chown($st[4], $st[5], $f);
chmod($st[2], $f);
}

# modify_mail(user|file, old, new, textonly)
# Modify one email message in a mailbox by copying the file and rebuilding
# the index.
sub modify_mail
{
local $f = &user_mail_file($_[0]);
local $ifile = &user_index_file($_[0]);
local $lnum = 0;
local ($sizediff, $linesdiff);
local %index;
&build_dbm_index($_[0], \%index);

# Replace the email that gets modified
local $tmpf = $< == 0 ? "$f.del" :
	      $_[0] =~ /^\/.*\/([^\/]+)$/ ?
		"$user_module_config_directory/$1.del" :
	      "$user_module_config_directory/$_[0].del";
open(SOURCE, $f);
open(DEST, ">$tmpf");
while(<SOURCE>) {
	if ($lnum < $_[1]->{'line'} || $lnum > $_[1]->{'eline'}) {
		# before or after the message to change
		local $w = (print DEST $_);
		if (!$w) {
			local $e = "$?";
			close(DEST);
			close(SOURCE);
			unlink($tmpf);
			&error("Write to $tmpf failed : $e");
			}
		}
	elsif ($lnum == $_[1]->{'line'}) {
		# found start of message to change .. put in the new one
		close(DEST);
		local @ost = stat($tmpf);
		local $nlines = &send_mail($_[2], $tmpf, $_[3], 1);
		local @nst = stat($tmpf);
		local $newsize = $nst[7] - $ost[7];
		$sizediff = $newsize - $_[1]->{'size'};
		$linesdiff = $nlines - ($_[1]->{'eline'} - $_[1]->{'line'} + 1);
		open(DEST, ">>$tmpf");
		}
	$lnum++;
	}
close(SOURCE);
close(DEST) || &error("Write failed : $!");

# Now update the index and delete the temp file
for($i=0; $i<$index{'mailcount'}; $i++) {
	local @idx = split(/\0/, $index{$i});
	if ($idx[1] > $_[1]->{'line'}) {
		$idx[0] += $sizediff;
		$idx[1] += $linesdiff;
		$index{$i} = join("\0", @idx);
		}
	}
$index{'lastchange'} = time();
local @st = stat($f);
unlink($f);
if ($< == 0) {
	rename($tmpf, $f);
	}
else {
	system("cat $tmpf >$f && rm -f $tmpf");
	}
chown($st[4], $st[5], $f);
chmod($st[2], $f);

}

# send_mail(&mail, [file], [textonly], [nocr], [smtp-server],
#	    [smtp-user], [smtp-pass], [smtp-auth-mode],
#	    [&notify-flags], [port])
# Send out some email message or append it to a file.
# Returns the number of lines written.
sub send_mail
{
return 0 if (&is_readonly_mode());
local (%header, $h);
local $lnum = 0;
local $sm = $_[4] || $config{'send_mode'};
local $eol = $_[3] || !$sm ? "\n" : "\r\n";
local $port = $_[9] || $config{'smtp_port'} || 25;
foreach $h (@{$_[0]->{'headers'}}) {
	$header{lc($h->[0])} = $h->[1];
	}
local @tm = localtime(time());
push(@{$_[0]->{'headers'}},
     [ 'Date', strftime("%a, %d %b %Y %H:%M:%S %z (%Z)", @tm) ])
	if (!$header{'date'});
local @from = &address_parts($header{'from'});
local $esmtp = $_[8] ? 1 : 0;
if ($_[1]) {
	# Just append the email to a file using mbox format
	open(MAIL, ">>$_[1]") || &error("Write failed : $!");
	$lnum++;
	print MAIL $_[0]->{'fromline'} ? $_[0]->{'fromline'}."\n" :
		   strftime("From $from[0] %a %b %e %H:%M:%S %Y\n", @tm);
	}
elsif ($sm) {
	# Connect to SMTP server
	&open_socket($sm, $port, MAIL);
	&smtp_command(MAIL);
	if ($esmtp) {
		&smtp_command(MAIL, "ehlo ".&get_system_hostname()."\r\n");
		}
	else {
		&smtp_command(MAIL, "helo ".&get_system_hostname()."\r\n");
		}

	# Get username and password from parameters, or from module config
	local $user = $_[5] || $userconfig{'smtp_user'} || $config{'smtp_user'};
	local $pass = $_[6] || $userconfig{'smtp_pass'} || $config{'smtp_pass'};
	local $auth = $_[7] || $userconfig{'smtp_auth'} ||
		      $config{'smtp_auth'} || "Cram-MD5";
	if ($user) {
		# Send authentication commands
		eval "use Authen::SASL";
		if ($@) {
			&error("Perl module <tt>Authen::SASL</tt> is needed for SMTP authentication");
			}
		my $sasl = Authen::SASL->new('mechanism' => uc($auth),
					     'callback' => {
						'auth' => $user,
						'user' => $user,
						'pass' => $pass } );
		&error("Failed to create Authen::SASL object") if (!$sasl);
		local $conn = $sasl->client_new("smtp", &get_system_hostname());
		local $arv = &smtp_command(MAIL, "auth $auth\r\n", 1);
		if ($arv =~ /^(334)\s+(.*)/) {
			# Server says to go ahead
			$extra = $2;
			local $initial = $conn->client_start();
			local $auth_ok;
			if ($initial) {
				local $enc = &encode_base64($initial);
				$enc =~ s/\r|\n//g;
				$arv = &smtp_command(MAIL, "$enc\r\n", 1);
				if ($arv =~ /^(\d+)\s+(.*)/) {
					if ($1 == 235) {
						$auth_ok = 1;
						}
					else {
						&error("Unknown SMTP authentication response : $arv");
						}
					}
				$extra = $2;
				}
			while(!$auth_ok) {
				local $message = &decode_base64($extra);
				local $return = $conn->client_step($message);
				local $enc = &encode_base64($return);
				$enc =~ s/\r|\n//g;
				$arv = &smtp_command(MAIL, "$enc\r\n", 1);
				if ($arv =~ /^(\d+)\s+(.*)/) {
					if ($1 == 235) {
						$auth_ok = 1;
						}
					elsif ($1 == 535) {
						&error("SMTP authentication failed : $arv");
						}
					$extra = $2;
					}
				else {
					&error("Unknown SMTP authentication response : $arv");
					}
				}
			}
		}

	&smtp_command(MAIL, "mail from: <$from[0]>\r\n");
	local $notify = $_[8] ? " NOTIFY=".join(",", @{$_[8]}) : "";
	local $u;
	foreach $u (&address_parts($header{'to'}.",".$header{'cc'}.
						 ",".$header{'bcc'})) {
		&smtp_command(MAIL, "rcpt to: <$u>$notify\r\n");
		}
	&smtp_command(MAIL, "data\r\n");
	}
elsif (defined(&send_mail_program)) {
	# Use specified mail injector
	local $cmd = &send_mail_program($from[0]);
	$cmd || &error("No mail program was found on your system!");
	open(MAIL, "| $cmd >/dev/null 2>&1");
	}
elsif ($config{'qmail_dir'}) {
	# Start qmail-inject
	open(MAIL, "| $config{'qmail_dir'}/bin/qmail-inject");
	}
elsif ($config{'postfix_control_command'}) {
	# Start postfix's sendmail wrapper
	local $cmd = -x "/usr/lib/sendmail" ? "/usr/lib/sendmail" :
			&has_command("sendmail");
	$cmd || &error($text{'send_ewrapper'});
	open(MAIL, "| $cmd -t -f$from[0] >/dev/null 2>&1");
	}
else {
	# Start sendmail
	&has_command($config{'sendmail_path'}) ||
	    &error(&text('send_epath', "<tt>$config{'sendmail_path'}</tt>"));
	open(MAIL, "| $config{'sendmail_path'} -t -f$from[0] >/dev/null 2>&1");
	}
local $ctype = "multipart/mixed";
local $msg_id;
foreach $h (@{$_[0]->{'headers'}}) {
	if (defined($_[0]->{'body'}) || $_[2]) {
		print MAIL $h->[0],": ",$h->[1],$eol;
		$lnum++;
		}
	else {
		if ($h->[0] !~ /^(MIME-Version|Content-Type)$/i) {
			print MAIL $h->[0],": ",$h->[1],$eol;
			$lnum++;
			}
		elsif (lc($h->[0]) eq 'content-type') {
			$ctype = $h->[1];
			}
		}
	if (lc($h->[0]) eq 'message-id') {
		$msg_id++;
		}
	}
if (!$msg_id) {
	# Add a message-id header if missing
	print MAIL "Message-Id: <",time().".".$$."\@".
				  &get_system_hostname(),">",$eol;
	}

# Work out first attachment content type
local ($ftype, $fenc);
if (@{$_[0]->{'attach'}} >= 1) {
	local $first = $_[0]->{'attach'}->[0];
	$ftype = "text/plain";
	foreach my $h (@{$first->{'headers'}}) {
		if (lc($h->[0]) eq "content-type") {
			$ftype = $h->[1];
			}
		if (lc($h->[0]) eq "content-transfer-encoding") {
			$fenc = $h->[1];
			}
		}
	}

if (defined($_[0]->{'body'})) {
	# Use original mail body
	print MAIL $eol;
	$lnum++;
	$_[0]->{'body'} =~ s/\r//g;
	$_[0]->{'body'} =~ s/\n\.\n/\n\. \n/g;
	$_[0]->{'body'} =~ s/\n/$eol/g;
	$_[0]->{'body'} .= $eol if ($_[0]->{'body'} !~ /\n$/);
	(print MAIL $_[0]->{'body'}) || &error("Write failed : $!");
	$lnum += ($_[0]->{'body'} =~ tr/\n/\n/);
	}
elsif (!$_[2] || $ftype !~ /text\/plain/i ||
       $fenc =~ /quoted-printable|base64/) {
	# Sending MIME-encoded email
	if ($ctype !~ /multipart\/report/i) {
		$ctype =~ s/;.*$//;
		}
	print MAIL "MIME-Version: 1.0",$eol;
	local $bound = "bound".time();
	print MAIL "Content-Type: $ctype; boundary=\"$bound\"",$eol;
	print MAIL $eol;
	$lnum += 3;

	# Send attachments
	print MAIL "This is a multi-part message in MIME format.",$eol;
	$lnum++;
	foreach $a (@{$_[0]->{'attach'}}) {
		print MAIL $eol;
		print MAIL "--",$bound,$eol;
		$lnum += 2;
		local $enc;
		foreach $h (@{$a->{'headers'}}) {
			print MAIL $h->[0],": ",$h->[1],$eol;
			$enc = $h->[1]
				if (lc($h->[0]) eq 'content-transfer-encoding');
			$lnum++;
			}
		print MAIL $eol;
		$lnum++;
		if (lc($enc) eq 'base64') {
			local $enc = &encode_base64($a->{'data'});
			$enc =~ s/\r//g;
			$enc =~ s/\n/$eol/g;
			print MAIL $enc;
			$lnum += ($enc =~ tr/\n/\n/);
			}
		else {
			$a->{'data'} =~ s/\r//g;
			$a->{'data'} =~ s/\n\.\n/\n\. \n/g;
			$a->{'data'} =~ s/\n/$eol/g;
			print MAIL $a->{'data'};
			$lnum += ($a->{'data'} =~ tr/\n/\n/);
			if ($a->{'data'} !~ /\n$/) {
				print MAIL $eol;
				$lnum++;
				}
			}
		}
	print MAIL $eol;
	(print MAIL "--",$bound,"--",$eol) || &error("Write failed : $!");
	print MAIL $eol;
	$lnum += 3;
	}
else {
	# Sending text-only mail from first attachment
	local $a = $_[0]->{'attach'}->[0];
	print MAIL $eol;
	$lnum++;
	$a->{'data'} =~ s/\r//g;
	$a->{'data'} =~ s/\n/$eol/g;
	(print MAIL $a->{'data'}) || &error("Write failed : $!");
	$lnum += ($a->{'data'} =~ tr/\n/\n/);
	if ($a->{'data'} !~ /\n$/) {
		print MAIL $eol;
		$lnum++;
		}
	}
if ($sm && !$_[1]) {
	&smtp_command(MAIL, ".$eol");
	&smtp_command(MAIL, "quit$eol");
	}
if (!close(MAIL)) {
	# Only bother to report an error on close if writing to a file
	if ($_[1]) {
		&error("Write failed : $!");
		}
	}
return $lnum;
}

# mail_size(&mail, [textonly])
# Returns the size of an email message in bytes
sub mail_size
{
local ($mail, $textonly) = @_;
local $temp = &transname();
&send_mail($mail, $temp, $textonly);
local @st = stat($temp);
unlink($temp);
return $st[7];
}

# b64decode(string)
# Converts a string from base64 format to normal
sub b64decode
{
    local($str) = $_[0];
    local($res);
    $str =~ tr|A-Za-z0-9+=/||cd;
    $str =~ s/=+$//;
    $str =~ tr|A-Za-z0-9+/| -_|;
    while ($str =~ /(.{1,60})/gs) {
        my $len = chr(32 + length($1)*3/4);
        $res .= unpack("u", $len . $1 );
    }
    return $res;
}

# can_read_mail(user)
sub can_read_mail
{
return 1 if ($_[0] && $access{'sent'} eq $_[0]);
local @u = getpwnam($_[0]);
return 0 if (!@u);
return 0 if ($_[0] =~ /\.\./);
return 0 if ($access{'mmode'} == 0);
return 1 if ($access{'mmode'} == 1);
local $u;
if ($access{'mmode'} == 2) {
	foreach $u (split(/\s+/, $access{'musers'})) {
		return 1 if ($u eq $_[0]);
		}
	return 0;
	}
elsif ($access{'mmode'} == 4) {
	return 1 if ($_[0] eq $remote_user);
	}
elsif ($access{'mmode'} == 5) {
	return $u[3] eq $access{'musers'};
	}
elsif ($access{'mmode'} == 3) {
	foreach $u (split(/\s+/, $access{'musers'})) {
		return 0 if ($u eq $_[0]);
		}
	return 1;
	}
elsif ($access{'mmode'} == 6) {
	return ($_[0] =~ /^$access{'musers'}$/);
	}
elsif ($access{'mmode'} == 7) {
	return (!$access{'musers'} || $u[2] >= $access{'musers'}) &&
	       (!$access{'musers2'} || $u[2] <= $access{'musers2'});
	}
return 0;	# can't happen!
}

# from_hostname()
sub from_hostname
{
local ($d, $masq);
local $conf = &get_sendmailcf();
foreach $d (&find_type("D", $conf)) {
	if ($d->{'value'} =~ /^M\s*(\S*)/) { $masq = $1; }
	}
return $masq ? $masq : &get_system_hostname();
}

# mail_from_queue(qfile, [dfile|"auto"])
# Reads a message from the Sendmail mail queue
sub mail_from_queue
{
local $mail = { 'file' => $_[0] };
$mail->{'quar'} = $_[0] =~ /\/hf/;
$mail->{'lost'} = $_[0] =~ /\/Qf/;
if ($_[1] eq "auto") {
	$mail->{'dfile'} = $_[0];
	$mail->{'dfile'} =~ s/\/(qf|hf|Qf)/\/df/;
	}
elsif ($_[1]) {
	$mail->{'dfile'} = $_[1];
	}
$mail->{'lfile'} = $_[0];
$mail->{'lfile'} =~ s/\/(qf|hf|Qf)/\/xf/;
local $_;
local @headers;
open(QF, $_[0]) || return undef;
while(<QF>) {
	s/\r|\n//g;
	if (/^M(.*)/) {
		$mail->{'status'} = $1;
		}
	elsif (/^H\?[^\?]*\?(\S+):\s+(.*)/ || /^H(\S+):\s+(.*)/) {
		push(@headers, [ $1, $2 ]);
		$mail->{'rawheaders'} .= "$1: $2\n";
		}
	elsif (/^\s+(.*)/) {
		$headers[$#headers]->[1] .= $1 unless($#headers < 0);
		$mail->{'rawheaders'} .= $_."\n";
		}
	}
close(QF);
$mail->{'headers'} = \@headers;
foreach $h (@headers) {
	$mail->{'header'}->{lc($h->[0])} = $h->[1];
	}

if ($mail->{'dfile'}) {
	# Read the mail body
	open(DF, $mail->{'dfile'});
	while(<DF>) {
		$mail->{'body'} .= $_;
		}
	close(DF);
	}
local $datafile = $mail->{'dfile'};
if (!$datafile) {
	($datafile = $mail->{'file'}) =~ s/\/(qf|hf|Qf)/\/df/;
	}
local @st0 = stat($mail->{'file'});
local @st1 = stat($datafile);
$mail->{'size'} = $st0[7] + $st1[7];
return $mail;
}

# wrap_lines(text, width)
# Given a multi-line string, return an array of lines wrapped to
# the given width
sub wrap_lines
{
local @rv;
local $w = $_[1];
foreach $rest (split(/\n/, $_[0])) {
	if ($rest =~ /\S/) {
		while($rest =~ /^(.{1,$w}\S*)\s*([\0-\377]*)$/) {
			push(@rv, $1);
			$rest = $2;
			}
		}
	else {
		# Empty line .. keep as it is
		push(@rv, $rest);
		}
	}
return @rv;
}

# smtp_command(handle, command, no-error)
sub smtp_command
{
local ($m, $c) = @_;
print $m $c;
local $r = <$m>;
if ($r !~ /^[23]\d+/ && !$_[2]) {
	&error(&text('send_esmtp', "<tt>".&html_escape($c)."</tt>",
				   "<tt>".&html_escape($r)."</tt>"));
	}
$r =~ s/\r|\n//g;
if ($r =~ /^(\d+)\-/) {
	# multi-line ESMTP response!
	while(1) {
		local $nr = <$m>;
		$nr =~ s/\r|\n//g;
		if ($nr =~ /^(\d+)\-(.*)/) {
			$r .= "\n".$2;
			}
		elsif ($nr =~ /^(\d+)\s+(.*)/) {
			$r .= "\n".$2;
			last;
			}
		}
	}
return $r;
}

# address_parts(string)
# Returns the email addresses in a string
sub address_parts
{
local @rv;
local $rest = $_[0];
while($rest =~ /([^<>\s,'"\@]+\@[A-z0-9\-\.\!]+)(.*)/) {
	push(@rv, $1);
	$rest = $2;
	}
return wantarray ? @rv : $rv[0];
}

# link_urls(text, separate)
sub link_urls
{
local $r = $_[0];
local $tar = $_[1] ? "target=link".int(rand()*100000) : "";
$r =~ s/((http|ftp|https|mailto):[^><"'\s]+[^><"'\s\.\)])/<a href="$1" $tar>$1<\/a>/g;
return $r;
}

# link_urls_and_escape(text, separate)
# HTML escapes some text, as well as properly linking URLs in it
sub link_urls_and_escape
{
local $l = $_[0];
local $rv;
local $tar = $_[1] ? " target=link".int(rand()*100000) : "";
while($l =~ /^(.*?)((http|ftp|https|mailto):[^><"'\s]+[^><"'\s\.\)])(.*)/) {
	local ($before, $url, $after) = ($1, $2, $4);
	$rv .= &eucconv_and_escape($before)."<a href='$url' $tar>".
	       &html_escape($url)."</a>";
	$l = $after;
	}
$rv .= &eucconv_and_escape($l);
return $rv;
}

# uudecode(text)
sub uudecode
{
local @lines = split(/\n/, $_[0]);
local ($l, $data);
for($l=0; $lines[$l] !~ /begin\s+([0-7]+)\s/i; $l++) { }
while($lines[++$l]) {
	$data .= unpack("u", $lines[$l]);
	}
return $data;
}

sub simplify_date
{
local $u = &parse_mail_date($_[0]);
if ($u) {
	local $fmt = $userconfig{'date_fmt'} || $config{'date_fmt'} || "dmy";
	local $strf = $fmt eq "dmy" ? "%d/%m/%Y" :
		      $fmt eq "mdy" ? "%m/%d/%Y" :
				      "%Y/%m/%d";
	return strftime("$strf %H:%M", localtime($u));
        }
elsif ($_[0] =~ /^(\S+),\s+0*(\d+)\s+(\S+)\s+(\d+)\s+(\d+):(\d+)/) {
	return "$2/$3/$4 $5:$6";
	}
elsif ($_[0] =~ /^0*(\d+)\s+(\S+)\s+(\d+)\s+(\d+):(\d+)/) {
	return "$1/$2/$3 $4:$5";
	}
return $_[0];
}

# simplify_from(from)
# Simplifies a From: address for display in the mail list. Only the first
# address is returned.
sub simplify_from
{
local $rv = &eucconv(&decode_mimewords($_[0]));
local @sp = &split_addresses($rv);
if (!@sp) {
	return $text{'mail_nonefrom'};
	}
else {
	local $first = &html_escape($sp[0]->[1] ? $sp[0]->[1] : $sp[0]->[2]);
	if (length($first) > 80) {
		return substr($first, 0, 80)." ..";
		}
	else {
		return $first.(@sp > 1 ? " , ..." : "");
		}
	}
}

# simplify_subject(subject)
sub simplify_subject
{
local $rv = &eucconv(&decode_mimewords($_[0]));
$rv = substr($rv, 0, 80)." .." if (length($rv) > 80);
return $rv =~ /\S/ ? &html_escape($rv) : "<br>";
}

# quoted_decode(text)
sub quoted_decode
{
local $t = $_[0];
$t =~ s/=\n//g;
$t =~ s/=([a-zA-Z0-9]{2})/pack("c",hex($1))/ge;
return $t;
}

# quoted_encode(text)
sub quoted_encode
{
local $t = $_[0];
$t =~ s/([=\177-\377])/sprintf("=%2.2X",ord($1))/ge;
return $t;
}

sub decode_mimewords {
    my $encstr = shift;
    my %params = @_;
    my @tokens;
    $@ = '';           ### error-return

    ### Collapse boundaries between adjacent encoded words:
    $encstr =~ s{(\?\=)\r?\n[ \t](\=\?)}{$1$2}gs;
    pos($encstr) = 0;
    ### print STDOUT "ENC = [", $encstr, "]\n";

    ### Decode:
    my ($charset, $encoding, $enc, $dec);
    while (1) {
	last if (pos($encstr) >= length($encstr));
	my $pos = pos($encstr);               ### save it

	### Case 1: are we looking at "=?..?..?="?
	if ($encstr =~    m{\G             # from where we left off..
			    =\?([^?]*)     # "=?" + charset +
			     \?([bq])      #  "?" + encoding +
			     \?([^?]+)     #  "?" + data maybe with spcs +
			     \?=           #  "?="
			    }xgi) {
	    ($charset, $encoding, $enc) = ($1, lc($2), $3);
	    $dec = (($encoding eq 'q') ? _decode_Q($enc) : _decode_B($enc));
	    push @tokens, [$dec, $charset];
	    next;
	}

	### Case 2: are we looking at a bad "=?..." prefix? 
	### We need this to detect problems for case 3, which stops at "=?":
	pos($encstr) = $pos;               # reset the pointer.
	if ($encstr =~ m{\G=\?}xg) {
	    $@ .= qq|unterminated "=?..?..?=" in "$encstr" (pos $pos)\n|;
	    push @tokens, ['=?'];
	    next;
	}

	### Case 3: are we looking at ordinary text?
	pos($encstr) = $pos;               # reset the pointer.
	if ($encstr =~ m{\G                # from where we left off...
			 ([\x00-\xFF]*?    #   shortest possible string,
			  \n*)             #   followed by 0 or more NLs,
		         (?=(\Z|=\?))      # terminated by "=?" or EOS
			}xg) {
	    length($1) or die "MIME::Words: internal logic err: empty token\n";
	    push @tokens, [$1];
	    next;
	}

	### Case 4: bug!
	die "MIME::Words: unexpected case:\n($encstr) pos $pos\n\t".
	    "Please alert developer.\n";
    }
    return join('',map {$_->[0]} @tokens);
}

# _decode_Q STRING
#     Private: used by _decode_header() to decode "Q" encoding, which is
#     almost, but not exactly, quoted-printable.  :-P
sub _decode_Q {
    my $str = shift;
    $str =~ s/_/\x20/g;                                # RFC-1522, Q rule 2
    $str =~ s/=([\da-fA-F]{2})/pack("C", hex($1))/ge;  # RFC-1522, Q rule 1
    $str;
}

# _decode_B STRING
#     Private: used by _decode_header() to decode "B" encoding.
sub _decode_B {
    my $str = shift;
    &decode_base64($str);
}

# user_mail_file(user|file, [other details])
sub user_mail_file
{
if ($_[0] =~ /^\//) {
	return $_[0];
	}
elsif ($config{'mail_dir'}) {
	return &mail_file_style($_[0], $config{'mail_dir'},
				$config{'mail_style'});
	}
elsif (@_ > 1) {
	return "$_[7]/$config{'mail_file'}";
	}
else {
	local @u = getpwnam($_[0]);
	return "$u[7]/$config{'mail_file'}";
	}
}

# mail_file_style(user, basedir, style)
sub mail_file_style
{
if ($_[2] == 0) {
	return "$_[1]/$_[0]";
	}
elsif ($_[2] == 1) {
	return $_[1]."/".substr($_[0], 0, 1)."/".$_[0];
	}
elsif ($_[2] == 2) {
	return $_[1]."/".substr($_[0], 0, 1)."/".
		substr($_[0], 0, 2)."/".$_[0];
	}
else {
	return $_[1]."/".substr($_[0], 0, 1)."/".
		substr($_[0], 1, 1)."/".$_[0];
	}
}

# user_index_file(user|file)
sub user_index_file
{
local $us = $_[0];
$us =~ s/\//_/g;
local $f;
local $hn = &get_system_hostname();
if ($_[0] =~ /^\/.*\/([^\/]+)$/) {
	# A file .. the index file is in ~/.usermin/mailbox or
	# /etc/webmin/mailboxes
	if ($user_module_config_directory && $config{'shortindex'}) {
		# Use short name for index file
		$f = "$user_module_config_directory/$1.findex";
		}
	else {
		$f = $user_module_config_directory ?
			"$user_module_config_directory/$us.findex" :
			"$module_config_directory/$us.findex";
		}
	}
else {
	# A username .. the index file is in /etc/webmin/mailboxes
        $f = $user_module_config_directory ?
		"$user_module_config_directory/$_[0].index" :
		"$module_config_directory/$_[0].index";
	}
return -r $f && !-r "$f.$hn" ? $f : "$f.$hn";
}

# extract_mail(data)
# Converts the text of a message into mail object.
sub extract_mail
{
local $text = $_[0];
$text =~ s/^\s+//;
local ($amail, @aheaders, $i);
local @alines = split(/\n/, $text);
while($i < @alines && $alines[$i]) {
	if ($alines[$i] =~ /^(\S+):\s*(.*)/) {
		push(@aheaders, [ $1, $2 ]);
		$amail->{'rawheaders'} .= $alines[$i]."\n";
		}
	elsif ($alines[$i] =~ /^\s+(.*)/) {
		$aheaders[$#aheaders]->[1] .= $1 unless($#aheaders < 0);
		$amail->{'rawheaders'} .= $alines[$i]."\n";
		}
	$i++;
	}
$amail->{'headers'} = \@aheaders;
foreach $h (@aheaders) {
	$amail->{'header'}->{lc($h->[0])} = $h->[1];
	}
splice(@alines, 0, $i);
$amail->{'body'} = join("\n", @alines)."\n";
return $amail;
}

# split_addresses(string)
# Splits a comma-separated list of addresses into [ email, real-name, original ]
# triplets
sub split_addresses
{
local (@rv, $str = $_[0]);
while(1) {
	if ($str =~ /^[\s,]*(([^<>\(\)\s]+)\s+\(([^\(\)]+)\))(.*)$/) {
		# An address like  foo@bar.com (Fooey Bar)
		push(@rv, [ $2, $3, $1 ]);
		$str = $4;
		}
	elsif ($str =~ /^[\s,]*("([^"]+)"\s*<([^\s<>,]+)>)(.*)$/ ||
	       $str =~ /^[\s,]*(([^<>\@]+)\s+<([^\s<>,]+)>)(.*)$/ ||
	       $str =~ /^[\s,]*(([^<>\@]+)<([^\s<>,]+)>)(.*)$/ ||
	       $str =~ /^[\s,]*(([^<>\[\]]+)\s+\[mailto:([^\s\[\]]+)\])(.*)$/||
	       $str =~ /^[\s,]*(()<([^<>,]+)>)(.*)/ ||
	       $str =~ /^[\s,]*(()([^\s<>,]+))(.*)/) {
		# Addresses like  "Fooey Bar" <foo@bar.com>
		#                 Fooey Bar <foo@bar.com>
		#                 Fooey Bar<foo@bar.com>
		#		  Fooey Bar [mailto:foo@bar.com]
		#		  <foo@bar.com>
		#		  <group name>
		#		  foo@bar.com
		push(@rv, [ $3, $2 eq "," ? "" : $2, $1 ]);
		$str = $4;
		}
	else {
		last;
		}
	}
return @rv;
}

$match_ascii = '\x1b\([BHJ]([\t\x20-\x7e]*)';
$match_jis = '\x1b\$[@B](([\x21-\x7e]{2})*)';

sub eucconv {
	local($_) = @_;
	if ($current_lang eq 'ja_JP.euc') {
		s/$match_jis/&j2e($1)/geo;
		s/$match_ascii/$1/go;
		}
	$_;
}

sub j2e {
	local($_) = @_;
	tr/\x21-\x7e/\xa1-\xfe/;
	$_;
}

# eucconv_and_escape(string)
sub eucconv_and_escape {
	return &html_escape(&eucconv($_[0]));
}

# list_maildir(file, [start], [end], [headersonly])
# Returns a subset of mail from a maildir format directory
sub list_maildir
{
local (@rv, $i, $f);
&mark_read_maildir($_[0]);
local @files = &get_maildir_files($_[0]);

local ($start, $end);
if (!defined($_[1])) {
	$start = 0;
	$end = @files - 1;
	}
elsif ($_[2] < 0) {
	$start = @files + $_[2] - 1;
	$end = @files + $_[1] - 1;
	$start = 0 if ($start < 0);
	}
else {
	$start = $_[1];
	$end = $_[2];
	$end = @files-1 if ($end >= @files);
	}
foreach $f (@files) {
	if ($i < $start || $i > $end) {
		# Skip files outside requested index range
		push(@rv, undef);
		$i++;
		next;
		}
	local $mail = &read_mail_file($f, $_[3]);
	$mail->{'idx'} = $i++;
	$mail->{'id'} = $f;	# ID is relative path, like cur/4535534
	$mail->{'id'} = substr($mail->{'id'}, length($_[0])+1);
	push(@rv, $mail);
	}
return @rv;
}

# idlist_maildir(file)
# Returns a list of files in a maildir, which form the IDs
sub idlist_maildir
{
local ($file) = @_;
&mark_read_maildir($file);
return map { substr($_, length($file)+1) } &get_maildir_files($file);
}

# select_maildir(file, &ids, headersonly)
# Returns a list of messages with the given IDs, from a maildir directory
sub select_maildir
{
local ($file, $ids, $headersonly) = @_;
&mark_read_maildir($file);
local @files = &get_maildir_files($file);
local @rv;
foreach my $i (@$ids) {
	local $path = "$file/$i";
	local $mail = &read_mail_file($path, $headersonly);
	if (!$mail && $path =~ /\/cur\//) {
		# May have moved - update path
		$path =~ s/\/cur\//\/new\//g;
		$mail = &read_mail_file($path, $headersonly);
		}
	if ($mail) {
		# Set ID from corrected path
		$mail->{'id'} = $path;
		$mail->{'id'} = substr($mail->{'id'}, length($file)+1);
		# Get index in directory
		$mail->{'idx'} = &indexof($path, @files);
		}
	push(@rv, $mail);
	}
return @rv;
}

# Get ordered list of message files (with in-memory and on-disk caching, as
# this can be slow)
# get_maildir_files(directory)
sub get_maildir_files
{
# Work out last modified time
local $newest;
foreach my $d ("$_[0]/cur", "$_[0]/new") {
	local @dst = stat($d);
	$newest = $dst[9] if ($dst[9] > $newest);
	}

local @files;
if (defined($main::list_maildir_cache{$_[0]}) &&
    $main::list_maildir_cache_time{$_[0]} == $newest) {
	# Use the in-memory cache cache
	@files = @{$main::list_maildir_cache{$_[0]}};
	}
else {
	# Check the on-disk cache file
	local $cachefile = &get_maildir_cachefile($_[0]);
	local @cst = $cachefile ? stat($cachefile) : ( );
	if ($cst[9] >= $newest) {
		# Can read the cache
		open(CACHE, $cachefile);
		while(<CACHE>) {
			chop;
			push(@files, $_[0]."/".$_);
			}
		close(CACHE);
		}
	else {
		# Really read
		local @shorts;
		foreach my $d ("cur", "new") {
			opendir(DIR, "$_[0]/$d");
			while(my $f = readdir(DIR)) {
				push(@shorts, "$d/$f")
					if ($f ne "." && $f ne "..");
				}
			closedir(DIR);
			}
		@shorts = sort { substr($a, 4) cmp substr($b, 4) } @shorts;
		@files = map { "$_[0]/$_" } @shorts;

		# Write out the on-disk cache
		if ($cachefile) {
			&open_tempfile(CACHE, ">$cachefile", 1);
			my $err;
			foreach my $f (@shorts) {
				my $ok = (print CACHE $f,"\n");
				$err++ if (!$ok);
				}
			&close_tempfile(CACHE) if (!$err);
			local @st = stat($_[0]);
			if ($< == 0) {
				# Cache should have some ownership as directory
				&set_ownership_permissions($st[4], $st[5],
							   undef, $cachefile);
				}
			}
		}
	$main::list_maildir_cache{$_[0]} = \@files;
	$main::list_maildir_cache_time{$_[0]} = $st[7];
	}
return @files;
}

# search_maildir(file, field, what)
# Search for messages in a maildir directory, and return the results
sub search_maildir
{
return &advanced_search_maildir($_[0], [ [ $_[1], $_[2] ] ], 1);
}

# advanced_search_maildir(user|file, &fields, andmode, [&limit], [headersonly])
# Search for messages in a maildir directory, and return the results
sub advanced_search_maildir
{
&mark_read_maildir($_[0]);
local @rv;
local ($min, $max);
if ($_[3] && $_[3]->{'latest'}) {
	$min = -1;
	$max = -$_[3]->{'latest'};
	}
foreach $mail (&list_maildir($_[0], $min, $max, $_[4])) {
	push(@rv, $mail) if ($mail &&
			     &mail_matches($_[1], $_[2], $mail));
	}
return @rv;
}

# mark_read_maildir(dir)
# Move any messages in the 'new' directory of this maildir to 'cur'
sub mark_read_maildir
{
local ($dir) = @_;
local @files = &get_maildir_files($dir);
local $i = 0;
foreach my $nf (@files) {
	if (substr($nf, length($dir)+1, 3) eq "new") {
		local $cf = $nf;
		$cf =~ s/\/new\//\/cur\//g;
		if (rename($nf, $cf)) {
			$files[$i] = $cf;
			$changed = 1;
			}
		}
	$i++;
	}
if ($changed) {
	# Update the cache
	$main::list_maildir_cache{$dir} = \@files;
	local $cachefile = &get_maildir_cachefile($dir);
	if ($cachefile) {
		&open_tempfile(CACHE, ">$cachefile", 1);
		foreach my $f (@files) {
			local $short = substr($f, length($dir)+1);
			&print_tempfile(CACHE, $short,"\n");
			}
		&close_tempfile(CACHE);
		local @st = stat($_[0]);
		if ($< == 0) {
			&set_ownership_permissions($st[4], $st[5],
						   undef, $cachefile);
			}
		}
	}
}

# delete_maildir(&mail, ...)
# Delete messages from a maildir directory
sub delete_maildir
{
local $m;

# Find all maildirs being deleted from
local %dirs;
foreach $m (@_) {
	if ($m->{'file'} =~ /^(.*)\/(cur|new)\/([^\/]+)$/) {
		$dirs{$1}->{"$2/$3"} = 1;
		}
	}

# Delete from caches
foreach my $dir (keys %dirs) {
	local $cachefile = &get_maildir_cachefile($dir);
	next if (!$cachefile);
	local @cst = stat($cachefile);
	next if (!@cst);

	# Work out last modified time, and don't update cache if too new
	local $newest;
	foreach my $d ("$dir/cur", "$dir/new") {
		local @dst = stat($d);
		$newest = $dst[9] if ($dst[9] > $newest);
		}
	next if ($newest > $cst[9]);

	local $lref = &read_file_lines($cachefile);
	for(my $i=0; $i<@$lref; $i++) {
		if ($dirs{$dir}->{$lref->[$i]}) {
			# Found an entry to remove
			splice(@$lref, $i--, 1);
			}
		}
	&flush_file_lines($cachefile);
	}

# Actually delete the files
foreach $m (@_) {
	unlink($m->{'file'});
	}

}

# modify_maildir(&oldmail, &newmail, textonly)
# Replaces a message in a maildir directory
sub modify_maildir
{
unlink($_[0]->{'file'});
&send_mail($_[1], $_[0]->{'file'}, $_[2], 1);
}

# write_maildir(&mail, directory, textonly)
# Adds some message in maildir format to a directory
sub write_maildir
{
# Work out last modified time, and don't update cache if too new
local $cachefile = &get_maildir_cachefile($_[1]);
local $up2date = 0;
if ($cachefile) {
	local @cst = stat($cachefile);
	if (@cst) {
		local $newest;
		foreach my $d ("$dir/cur", "$dir/new") {
			local @dst = stat($d);
			$newest = $dst[9] if ($dst[9] > $newest);
			}
		$up2date = 1 if ($newest <= $cst[9]);
		}
	}

# Select a unique filename and write to it
local $now = time();
local $hn = &get_system_hostname();
local $mf;
mkdir($_[1], 0755);
mkdir("$_[1]/cur", 0755);
do {
	$mf = "$_[1]/cur/$now.$$.$hn";
	$_[0]->{'id'} = "cur/$now.$$.$hn";
	$now++;
	} while(-r $mf);
&send_mail($_[0], $mf, $_[2], 1);

# Create tmp and new sub-dirs, if missing
foreach my $sd ("tmp", "new") {
	mkdir("$_[1]/$sd", 0755);
	}

if ($up2date && $cachefile) {
	# Bring cache up to date
	$now--;
	local $lref = &read_file_lines($cachefile);
	push(@$lref, "cur/$now.$$.$hn");
	&flush_file_lines($cachefile);
	}
}

# empty_maildir(file)
# Delete all messages in an maildir directory
sub empty_maildir
{
local $d;
foreach $d ("$_[0]/cur", "$_[0]/new") {
	local $f;
	opendir(DIR, $d);
	while($f = readdir(DIR)) {
		unlink("$d/$f") if ($f ne '.' && $f ne '..');
		}
	closedir(DIR);
	}
local $cachefile = &get_maildir_cachefile($_[0]);
unlink($cachefile) if ($cachefile);
}

# get_maildir_cachefile(dir)
# Returns the cache file for a maildir directory
sub get_maildir_cachefile
{
local ($dir) = @_;
local $oldcache = -r "$dir/maildircache" ? "$dir/maildircache"
			      		 : "$dir/.usermin-maildircache";
unlink($oldcache); 
local $cd = $user_module_config_directory || $module_config_directory;
local $sd = "$cd/maildircache";
if (!-d $sd) {
	&make_dir($sd, 0755) || return undef;
	}
$dir =~ s/\//_/g;
return "$sd/$dir";
}

# count_maildir(dir)
# Returns the number of messages in a maildir directory
sub count_maildir
{
local $d;
local $count = 0;
foreach $d ("$_[0]/cur", "$_[0]/new") {
	opendir(DIR, $d);
	local @files = grep { $_ !~ /^\./ } readdir(DIR);
	$count += scalar(@files);
	closedir(DIR);
	}
return $count;
}

# list_mhdir(file, [start], [end], [headersonly])
# Returns a subset of mail from an MH format directory
sub list_mhdir
{
local ($start, $end, $f, $i, @rv);
opendir(DIR, $_[0]);
local @files = map { "$_[0]/$_" }
		sort { $a <=> $b }
		 grep { /^\d+$/ } readdir(DIR);
closedir(DIR);
if (!defined($_[1])) {
	$start = 0;
	$end = @files - 1;
	}
elsif ($_[2] < 0) {
	$start = @files + $_[2] - 1;
	$end = @files + $_[1] - 1;
	$start = 0 if ($start < 0);
	}
else {
	$start = $_[1];
	$end = $_[2];
	$end = @files-1 if ($end >= @files);
	}
foreach $f (@files) {
	if ($i < $start || $i > $end) {
		# Skip files outside requested index range
		push(@rv, undef);
		$i++;
		next;
		}
	local $mail = &read_mail_file($f, $_[3]);
	$mail->{'idx'} = $i++;
	$mail->{'id'} = $f;	# ID is message number
	$mail->{'id'} = substr($mail->{'id'}, length($_[0])+1);
	push(@rv, $mail);
	}
return @rv;
}

# idlist_mhdir(file)
# Returns a list of files in an MH directory, which are the IDs
sub idlist_mhdir
{
opendir(DIR, $file);
local @files = grep { /^\d+$/ } readdir(DIR);
closedir(DIR);
return @files;
}

# select_mhdir(file, &ids, headersonly)
# Returns a list of messages with the given indexes, from an mhdir directory
sub select_mhdir
{
local ($file, $ids, $headersonly) = @_;
local @rv;
opendir(DIR, $file);
local @files = map { "$file/$_" }
		sort { $a <=> $b }
		 grep { /^\d+$/ } readdir(DIR);
closedir(DIR);
foreach my $i (@$ids) {
	local $mail = &read_mail_file("$file/$i", $headersonly);
	if ($mail) {
		$mail->{'idx'} = &indexof("$file/$i", @files);
		$mail->{'id'} = $i;
		}
	push(@rv, $mail);
	}
return @rv;
}

# search_mhdir(file|user, field, what)
# Search for messages in an MH directory, and return the results
sub search_mhdir
{
return &advanced_search_mhdir($_[0], [ [ $_[1], $_[2] ] ], 1);
}

# advanced_search_mhdir(file|user, &fields, andmode, &limit, [headersonly])
# Search for messages in an MH directory, and return the results
sub advanced_search_mhdir
{
local @rv;
local ($min, $max);
if ($_[3] && $_[3]->{'latest'}) {
	$min = -1;
	$max = -$_[3]->{'latest'};
	}
foreach $mail (&list_mhdir($_[0], $min, $max, $_[4])) {
	push(@rv, $mail) if ($mail && &mail_matches($_[1], $_[2], $mail));
	}
return @rv;
}

# delete_mhdir(&mail, ...)
# Delete messages from an MH directory
sub delete_mhdir
{
local $m;
foreach $m (@_) {
	unlink($m->{'file'});
	}
}

# modify_mhdir(&oldmail, &newmail, textonly)
# Replaces a message in a maildir directory
sub modify_mhdir
{
unlink($_[0]->{'file'});
&send_mail($_[1], $_[0]->{'file'}, $_[2], 1);
}

# max_mhdir(dir)
# Returns the maximum message ID in the directory
sub max_mhdir
{
local $max = 1;
opendir(DIR, $_[0]);
foreach $f (readdir(DIR)) {
	$max = $f if ($f =~ /^\d+$/ && $f > $max);
	}
closedir(DIR);
return $max;
}

# empty_mhdir(file)
# Delete all messages in an MH format directory
sub empty_mhdir
{
local $f;
opendir(DIR, $_[0]);
foreach $f (readdir(DIR)) {
	unlink("$_[0]/$f") if ($f =~ /^\d+$/);
	}
closedir(DIR);
}

# count_mhdir(file)
# Returns the number of messages in an MH directory
sub count_mhdir
{
opendir(DIR, $_[0]);
local @files = grep { /^\d+$/ } readdir(DIR);
closedir(DIR);
return scalar(@files);
}

# read_mail_file(file, [headersonly])
# Read a single message from a file
sub read_mail_file
{
local (@headers, $mail);

# Open and read the mail file
open(MAIL, $_[0]) || return undef;
$mail = &read_mail_fh(MAIL, 0, $_[1]);
$mail->{'file'} = $_[0];
close(MAIL);

local @st = stat($_[0]);
$mail->{'size'} = $st[7];
return $mail;
}

# read_mail_fh(handle, [end-mode], [headersonly])
# Reads an email message from the given file handle, either up to end of
# the file, or a From line. End mode 0 = EOF, 1 = From without -,
#				     2 = From possibly with -
sub read_mail_fh
{
local ($fh, $endmode, $headeronly) = @_;
local (@headers, $mail);

# Read the headers
local $lnum = 0;
while(1) {
	$lnum++;
	local $line = <$fh>;
	$mail->{'size'} += length($line);
	$line =~ s/\r|\n//g;
	last if ($line eq '');
	if ($line =~ /^(\S+):\s*(.*)/) {
		push(@headers, [ $1, $2 ]);
		$mail->{'rawheaders'} .= $line."\n";
		}
	elsif ($line =~ /^\s+(.*)/) {
		$headers[$#headers]->[1] .= $1 unless($#headers < 0);
		$mail->{'rawheaders'} .= $line."\n";
		}
	elsif ($line =~ /^From\s+(\S+).*\d+/ &&
	       ($1 ne '-' || $endmode == 2)) {
		$mail->{'fromline'} = $line;
		}
	}
$mail->{'headers'} = \@headers;
foreach $h (@headers) {
	$mail->{'header'}->{lc($h->[0])} = $h->[1];
	}

if (!$headersonly) {
	# Read the mail body
	if ($endmode == 0) {
		# Till EOF
		while(read($fh, $buf, 1024) > 0) {
			$mail->{'size'} += length($buf);
			$mail->{'body'} .= $buf;
			$lc = ($buf =~ tr/\n/\n/);
			$lnum += $lc;
			}
		close(MAIL);
		}
	else {
		# Tell next From line
		while(1) {
			$line = <$fh>;
			last if (!$line || $line =~ /^From\s+(\S+).*\d+\r?\n/ &&
				 ($1 ne '-' || $endmode == 2));
			$lnum++;
			$mail->{'size'} += length($line);
			$mail->{'body'} .= $line;
			}
		}
	$mail->{'lines'} = $lnum;
	}
elsif ($endmode) {
	# Not reading the body, but we still need to search till the next
	# From: line in order to get the size 
	while(1) {
		$line = <$fh>;
		last if (!$line || $line =~ /^From\s+(\S+).*\d+\r?\n/ &&
			 ($1 ne '-' || $endmode == 2));
		$lnum++;
		$mail->{'size'} += length($line);
		}
	$mail->{'lines'} = $lnum;
	}
return $mail;
}

# dash_mode(user|file)
# Returns 1 if the messages in this folder are separated by lines like
# From - instead of the usual From foo@bar.com
sub dash_mode
{
open(DASH, &user_mail_file($_[0])) || return 0;	# assume no
local $line = <DASH>;
close(DASH);
return $line =~ /^From\s+(\S+).*\d/ && $1 eq '-';
}

# mail_matches(&fields, andmode, &mail)
# Returns 1 if some message matches a search
sub mail_matches
{
local $count = 0;
local $f;
foreach $f (@{$_[0]}) {
	local $field = $f->[0];
	local $what = $f->[1];
	local $neg = ($field =~ s/^\!//);
	if ($field eq 'body') {
		$count++
		    if (!$neg && $_[2]->{'body'} =~ /\Q$what\E/i ||
		         $neg && $_[2]->{'body'} !~ /\Q$what\E/i);
		}
	elsif ($field eq 'size') {
		$count++
		    if (!$neg && $_[2]->{'size'} > $what ||
		         $neg && $_[2]->{'size'} < $what);
		}
	elsif ($field eq 'headers') {
		local $headers = $_[2]->{'rawheaders'} ||
			join("", map { $_->[0].": ".$_->[1]."\n" }
				     @{$_[2]->{'headers'}});
		$count++
		    if (!$neg && $headers =~ /\Q$what\E/i ||
			 $neg && $headers !~ /\Q$what\E/i);
		}
	elsif ($field eq 'all') {
		local $headers = $_[2]->{'rawheaders'} ||
			join("", map { $_->[0].": ".$_->[1]."\n" }
				     @{$_[2]->{'headers'}});
		$count++
		    if (!$neg && ($_[2]->{'body'} =~ /\Q$what\E/i ||
				  $headers =~ /\Q$what\E/i) ||
		         $neg && ($_[2]->{'body'} !~ /\Q$what\E/i &&
				  $headers !~ /\Q$what\E/i));
		}
	elsif ($field eq 'status') {
		$count++
		    if (!$neg && $_[2]->{$field} =~ /\Q$what\E/i||
		         $neg && $_[2]->{$field} !~ /\Q$what\E/i);
		}
	else {
		$count++
		    if (!$neg && $_[2]->{'header'}->{$field} =~ /\Q$what\E/i||
		         $neg && $_[2]->{'header'}->{$field} !~ /\Q$what\E/i);
		}
	return 1 if ($count && !$_[1]);
	}
return $count == @{$_[0]};
}

# search_fields(&fields)
# Returns an array of headers/fields from a search
sub search_fields
{
local @rv;
foreach $f (@{$_[0]}) {
	$f->[0] =~ /^\!?(.*)$/;
	push(@rv, $1);
	}
return &unique(@rv);
}

# parse_delivery_status(text)
# Returns the fields from a message/delivery-status attachment
sub parse_delivery_status
{
local @lines = split(/[\r\n]+/, $_[0]);
local (%rv, $l);
foreach $l (@lines) {
	if ($l =~ /^(\S+):\s*(.*)/) {
		$rv{lc($1)} = $2;
		}
	}
return \%rv;
}

# parse_mail_date(string)
# Converts a mail Date: header into a unix time
sub parse_mail_date
{
open(OLDSTDERR, ">&STDERR");	# suppress STDERR from Time::Local
close(STDERR);
my $rv = eval {
	if ($_[0] =~ /^\s*(\S+),\s+(\d+)\s+(\S+)\s+(\d+)\s+(\d+):\s?(\d+):\s?(\d+)\s+(\S+)/) {
		# Format like Mon, 13 Dec 2004 14:40:41 +0100
		# or          Mon, 13 Dec 2004 14:18:16 GMT
		# or	      Tue, 14 Sep 04 02:45:09 GMT
		local $tm = timegm($7, $6, $5, $2, &month_to_number($3),
				   $4 < 50 ? $4+100 : $4 < 1000 ? $4 : $4-1900);
		local $tz = $8;
		if ($tz =~ /^(\-|\+)?\d+$/) {
			local $tz = int($tz);
			$tz = $tz/100 if ($tz >= 50 || $tz <= -50);
			$tm -= $tz*60*60;
			}
		return $tm;
		}
	elsif ($_[0] =~ /^\s*(\S+),\s+(\d+),?\s+(\S+)\s+(\d+)\s+(\d+):\s?(\d+):\s?(\d+)/) {
		# Format like Mon, 13 Dec 2004 14:40:41 or
		#	      Mon, 13, Dec 2004 14:40:41
		# No timezone, so assume local
		local $tm = timelocal($7, $6, $5, $2, &month_to_number($3),
				   $4 < 50 ? $4+100 : $4 < 1000 ? $4 : $4-1900);
		return $tm;
		}
	elsif ($_[0] =~ /^\s*(\S+)\s+(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)/) {
		# Format like Tue Dec  7 12:58:52 2004
		local $tm = timelocal($6, $5, $4, $3, &month_to_number($2),
				      $7 < 50 ? $7+100 : $7 < 1000 ? $7 : $7-1900);
		return $tm;
		}
	elsif ($_[0] =~ /^(\d{4})\-(\d+)\-(\d+)\s+(\d+):(\d+)/) {
		# Format like 2004-12-07 12:53
		local $tm = timelocal(0, $4, $4, $3, $2-1,
				      $1 < 50 ? $1+100 : $1 < 1000 ? $1 : $1-1900);
		}
	elsif ($_[0] =~ /^(\d+)\s+(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)/) {
		# Format like 30 Jun 2005 21:01:01 -0000
		local $tm = timegm($6, $5, $4, $1, &month_to_number($2),
				   $3 < 50 ? $3+100 : $3 < 1000 ? $3 : $3-1900);
		local $tz = $7;
		if ($tz =~ /^(\-|\+)?\d+$/) {
			$tz = int($tz);
			$tz = $tz/100 if ($tz >= 50 || $tz <= -50);
			$tm -= $tz*60*60;
			}
		return $tm;
		}
	else {
		return undef;
		}
	};
open(STDERR, ">&OLDSTDERR");
close(OLDSTDERR);
if ($@) {
	return undef;
	}
return $rv;
}

# send_text_mail(from, to, cc, subject, body, [smtp-server])
# A convenience function for sending a email with just a text body
sub send_text_mail
{
local ($from, $to, $cc, $subject, $body, $smtp) = @_;
local $cs = &get_charset();
local $attach = $body =~ /[\177-\377]/ ?
	{ 'headers' => [ [ 'Content-Type', 'text/plain; charset='.$cs ],
		         [ 'Content-Transfer-Encoding', 'quoted-printable' ] ],
          'data' => &quoted_encode($body) } :
	{ 'headers' => [ [ 'Content-type', 'text/plain' ] ],
	  'data' => &entities_to_ascii($body) };
local $mail = { 'headers' =>
		[ [ 'From', $from ],
		  [ 'To', $to ],
		  [ 'Cc', $cc ],
		  [ 'Subject', $subject ] ],
		'attach' => [ $attach ] };
return &send_mail($mail, undef, 1, 0, $smtp);
}


1;
