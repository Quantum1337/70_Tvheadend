package main;

use strict;
use warnings;

use HttpUtils;
use utf8;
eval "use JSON;1" or my $JSON = "JSON";

my $state = 0;

my %Tvheadend_sets = (
	"DVREntryCreate" => "",
);

my %Tvheadend_gets = (
	"EPGQuery" => "",
);

sub Tvheadend_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'Tvheadend_Define';
    $hash->{UndefFn}    = 'Tvheadend_Undef';
    $hash->{SetFn}      = 'Tvheadend_Set';
    $hash->{GetFn}      = 'Tvheadend_Get';
    $hash->{ShutdownFn} = 'Tvheadend_Shutdown';
    $hash->{AttrFn}     = 'Tvheadend_Attr';
    $hash->{NotifyFn}   = 'Tvheadend_Notify';

    $hash->{AttrList} =
					"timeout " .
          $readingFnAttributes;

}

sub Tvheadend_Define($$$) {
	my ($hash, $def) = @_;
	my @args = split("[ \t][ \t]*", $def);

	return "Error while loading $JSON. Please install $JSON" if $JSON;

	return "Usage: define <NAME> $hash->{TYPE} <IP>:[<PORT>] [<USERNAME> <PASSWORD>]" if(int(@args) < 3);

	my @address = split(":",$args[2]);

	if($address[0] =~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/){
		$hash->{helper}->{http}->{ip} = $address[0];
	}else{
		return "The specified ip address is not valid"
	}

	if(defined $address[1]){
		if($address[1] =~ /^[0-9]+$/){
			$hash->{helper}->{http}->{port} = $address[1];
		}else{
			return "The specified port is not valid"
		}
	}else{
		$hash->{helper}->{http}->{port} = "9981";
	}

	if(defined $args[3]){
		$hash->{helper}->{http}->{username} = $args[3]
	}

	if(defined $args[4]){
		$hash->{helper}->{http}->{password} = $args[4]
	}

	$state = 0;

	if($init_done){
		InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
	}

	$hash->{STATE} = "Initialized";
	return;
}

sub Tvheadend_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash,"Tvheadend_EPG");

	return undef;
}

sub Tvheadend_Shutdown($){
	my($hash) = @_;

	RemoveInternalTimer($hash,"Tvheadend_EPG");

	return;

}

sub Tvheadend_Set($$$) {
	my ($hash, $name, $opt, @args) = @_;

	if($opt eq "EPG"){
		InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
	}elsif($opt eq "DVREntryCreate"){
		&Tvheadend_DVREntryCreate($hash,@args);
	}else{
		my @cList = keys %Tvheadend_sets;
		return "Unknown command $opt, choose one of " . join(" ", @cList);
	}

}

sub Tvheadend_Get($$$) {
	my ($hash, $name, $opt, @args) = @_;

	if($opt eq "EPGQuery"){
		return &Tvheadend_EPGQuery($hash,@args);
	}else{
		my @cList = keys %Tvheadend_gets;
		return "Unknown command $opt, choose one of " . join(" ", @cList);
	}

}

sub Tvheadend_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;

	if($cmd eq "set") {

	}elsif($cmd eq "del"){


	}

	return undef
}

sub Tvheadend_Notify($$){
	my ($own_hash, $dev_hash) = @_;

	if(IsDisabled($own_hash->{NAME})){
		return ""
	}

	my $events = deviceEvents($dev_hash, 1);

	if($dev_hash->{NAME} eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})){
		InternalTimer(gettimeofday(),"Tvheadend_EPG",$own_hash);
	}

	return
}

sub Tvheadend_EPG($){
	my ($hash) = @_;

	(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Busy, leaving..."),return) if($hash->{helper}->{http}->{busy} eq "1");

	## GET CHANNELS
	if($state == 0){

		$hash->{helper}->{http}->{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $entries;
			my @channels = ();

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),$state=0,$hash->{helper}->{http}->{busy} = "0",return) if($err);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Server needs authentication"),$state=0,$hash->{helper}->{http}->{busy} = "0",return) if($data =~ /^.*401 Unauthorized.*/s);

			$entries = decode_json($data)->{entries};

			for (my $i=0;$i < int(@$entries);$i+=1){
				@channels[$i] = @$entries[$i]->{val};
			}

			$hash->{helper}->{epg}->{count} = @$entries;
			$hash->{helper}->{epg}->{channels} = \@channels;
			$hash->{helper}->{http}->{busy} = "0";

			InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
			Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 1");
			$state = 1;
		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get Channels");

		my $ip = $hash->{helper}->{http}->{ip};
		my $port = $hash->{helper}->{http}->{port};

		$hash->{helper}->{http}->{id} = "";
		$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/channel/list";
		$hash->{helper}->{http}->{busy} = "1";
		&Tvheadend_HttpGet($hash);

		return;

	#GET NOW
	}elsif($state == 1){

		my @entriesNow = ();

		$hash->{helper}->{http}->{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),$state=0,$hash->{helper}->{http}->{busy} = "0",return) if($err);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Server needs authentication"),$state=0,$hash->{helper}->{http}->{busy} = "0",return) if($data =~ /^.*401 Unauthorized.*/s);

			$entries = decode_json($data)->{entries};

		 	@entriesNow[$param->{id}] = @$entries[0];
			@entriesNow[$param->{id}]->{subtitle} = "Keine Informationen verfügbar" if(!defined @entriesNow[$param->{id}]->{subtitle});
			@entriesNow[$param->{id}]->{summary} = "Keine Informationen verfügbar" if(!defined @entriesNow[$param->{id}]->{summary});
			@entriesNow[$param->{id}]->{description} = "Keine Informationen verfügbar" if(!defined @entriesNow[$param->{id}]->{description});

			#Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - ".scalar(grep {defined $_} @$entriesNext)." / $hash->{helper}->{epg}->{count}");
			if(scalar(grep {defined $_} @entriesNow) == $hash->{helper}->{epg}->{count}){

				@entriesNow = sort {$a->{channelNumber} <=> $b->{channelNumber} ||
														 $a->{start} <=> $b->{start}
														}@entriesNow;
				$hash->{helper}->{epg}->{now} = \@entriesNow;

				$hash->{helper}->{epg}->{update} = @entriesNow[0]->{stop};
				for (my $i=0;$i < int(@entriesNow);$i+=1){
						$hash->{helper}->{epg}->{update} = @entriesNow[$i]->{stop} if(@entriesNow[$i]->{stop} < $hash->{helper}->{epg}->{update});
				}

				$hash->{helper}->{http}->{busy} = "0";
				InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash) if ($state == 1);
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 2");
				$state = 2;
			}

		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get EPG Now");

		my $channels = $hash->{helper}->{epg}->{channels};
		my $ip = $hash->{helper}->{http}->{ip};
		my $port = $hash->{helper}->{http}->{port};

		$hash->{helper}->{http}->{busy} = "1";
		for (my $i=0;$i < int(@$channels);$i+=1){
			$hash->{helper}->{http}->{id} = $i;
			@$channels[$i] =~ s/\x20/\%20/g;
			$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/epg/events/grid?limit=1&channel=".@$channels[$i];
			&Tvheadend_HttpGet($hash);
		}

		return;

	## GET NEXT
	}elsif($state == 2){

		my @entriesNext = ();

		$hash->{helper}->{http}->{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),$state=0,$hash->{helper}->{http}->{busy} = "0",return) if($err);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Server needs authentication"),$state=0,$hash->{helper}->{http}->{busy} = "0",return) if($data =~ /^.*401 Unauthorized.*/s);

			$entries = decode_json($data)->{entries};

			@entriesNext[$param->{id}] = @$entries[0];
			@entriesNext[$param->{id}]->{subtitle} = "Keine Informationen verfügbar" if(!defined @entriesNext[$param->{id}]->{subtitle});
			@entriesNext[$param->{id}]->{summary} = "Keine Informationen verfügbar" if(!defined @entriesNext[$param->{id}]->{summary});
			@entriesNext[$param->{id}]->{description} = "Keine Informationen verfügbar" if(!defined @entriesNext[$param->{id}]->{description});

			#Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - ".scalar(grep {defined $_} @$entriesNext)." / $hash->{helper}->{epg}->{count}");
			if(scalar(grep {defined $_} @entriesNext) == $hash->{helper}->{epg}->{count}){
				$hash->{helper}->{epg}->{next} = \@entriesNext;

				$hash->{helper}->{http}->{busy} = "0";
				InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 3");
				$state = 3;
			}
		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get EPG Next");

		my $entries = $hash->{helper}->{epg}->{now};
		my $count = $hash->{helper}->{epg}->{count};
		my $ip = $hash->{helper}->{http}->{ip};
		my $port = $hash->{helper}->{http}->{port};

		$hash->{helper}->{http}->{busy} = "1";
		for (my $i=0;$i < int($count);$i+=1){
			$hash->{helper}->{http}->{id} = $i;
			$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/epg/events/load?eventId=".@$entries[$i]->{nextEventId};
			&Tvheadend_HttpGet($hash);
		}
		return;

	## SET READINGS
	}elsif($state == 3){
		my $update = $hash->{helper}->{epg}->{update};
		my $entriesNow = $hash->{helper}->{epg}->{now};
		my $entriesNext = $hash->{helper}->{epg}->{next};
		my $channels = $hash->{helper}->{epg}->{channels};

		readingsBeginUpdate($hash);
		for (my $i=0;$i < int(@$entriesNow);$i+=1){
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."Name", encode('UTF-8',@$entriesNow[$i]->{channelName}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."Number", encode('UTF-8',@$entriesNow[$i]->{channelNumber}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."TitleNow", encode('UTF-8',@$entriesNow[$i]->{title}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."StartNow", strftime("%H:%M:%S",localtime(encode('UTF-8',@$entriesNow[$i]->{start}))));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."EndNow", strftime("%H:%M:%S",localtime(encode('UTF-8',@$entriesNow[$i]->{stop}))));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."DescriptionNow", encode('UTF-8',@$entriesNow[$i]->{description}));
		}

		for (my $i=0;$i < int(@$entriesNext);$i+=1){
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."DescriptionNext", encode('UTF-8',@$entriesNext[$i]->{description}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."TitleNext", encode('UTF-8',@$entriesNext[$i]->{title}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."StartNext", strftime("%H:%M:%S",localtime(encode('UTF-8',@$entriesNext[$i]->{start}))));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."EndNext", strftime("%H:%M:%S",localtime(encode('UTF-8',@$entriesNext[$i]->{stop}))));
		}
		readingsEndUpdate($hash, 1);

		Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Next update: ".  strftime("%H:%M:%S",localtime($update)));
		RemoveInternalTimer($hash,"Tvheadend_EPG");
		InternalTimer($update + 1,"Tvheadend_EPG",$hash);
		$state = 0;
	}

}

sub Tvheadend_EPGQuery($$){
	my ($hash,@args) = @_;

	my $ip = $hash->{helper}->{http}->{ip};
	my $port = $hash->{helper}->{http}->{port};
	my $arg = join("%20", @args);
	my $entries;
	my $response = "";

	$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/epg/events/grid?limit=1&title=$arg";

	my ($err, $data) = &Tvheadend_HttpGetBlocking($hash);
	return $err if($err);
	($response = "Server needs authentication",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*401 Unauthorized.*/s);


	$entries = decode_json($data)->{entries};
	($response = "No Results",return $response) if(!defined @$entries[0]);

	@$entries[0]->{subtitle} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{subtitle});
	@$entries[0]->{description} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{description});
	@$entries[0]->{summary} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{summary});

	$response = @$entries[0]->{channelName} ."\n".
							strftime("%d.%m [%H:%M:%S",localtime(encode('UTF-8',@$entries[0]->{start})))." - ".
							strftime("%H:%M:%S]",localtime(encode('UTF-8',@$entries[0]->{stop})))."\n".
							encode('UTF-8',&Tvheadend_StringFormat(@$entries[0]->{title},80))."\n".
							encode('UTF-8',&Tvheadend_StringFormat(@$entries[0]->{summary},80)). "\n".
							"ID: " . @$entries[0]->{eventId};

	return $response;

}

sub Tvheadend_DVREntryCreate($$){
	my ($hash,@args) = @_;

	my $ip = $hash->{helper}->{http}->{ip};
	my $port = $hash->{helper}->{http}->{port};
	my $entries;
	my $response = "";

	$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/epg/events/load?eventId=".@args[0];
	my ($err, $data) = &Tvheadend_HttpGetBlocking($hash);
	return $err if($err);
	($response = "Server needs authentication",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*401 Unauthorized.*/s);

	$entries = decode_json($data)->{entries};
	($response = "EventId is not valid",return $response) if(!defined @$entries[0]);

	my %record = (
    "start"  => @$entries[0]->{start},
    "stop" => @$entries[0]->{stop},
		"title"  => {
			"ger" => @$entries[0]->{title},
		},
    "subtitle"  => {
			"ger" => @$entries[0]->{subtitle},
		},
		"description"  => {
			"ger" => @$entries[0]->{description},
		},
		"channelname"  => @$entries[0]->{channelName},
	);

	my $jasonData = encode_json(\%record);

	$jasonData =~ s/\x20/\%20/g;
	$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/dvr/entry/create?conf=".$jasonData;
	($err, $data) = &Tvheadend_HttpGetBlocking($hash);
}

sub Tvheadend_StringFormat($$){

	my ($string, $maxLength) = @_;

  my @words = split(/ /, $string);
  my $rowLength = 0;
  my $result = "";
  while (int(@words) > 0) {
  	my $tempString = shift @words;
    if ($rowLength > 0){
    	if (($rowLength + length($tempString)) > $maxLength){
      	$rowLength = 0;
        $result .= "\n";
      }
    }
    $result .= $tempString;
    $rowLength += length($tempString);
    if (int(@words) > 0){
	    $result .= ' ';
  	  $rowLength += 1;
    }
  }

	return $result;
}


sub Tvheadend_HttpGet($){
	my ($hash) = @_;

	HttpUtils_NonblockingGet(
		{
				method     => "GET",
				url        => $hash->{helper}->{http}->{url},
				timeout    => AttrVal($hash->{NAME},"timeout","20"),
				user			 => $hash->{helper}->{http}->{username},
				pwd				 => $hash->{helper}->{http}->{password},
				noshutdown => "1",
				hash			 => $hash,
				id				 => $hash->{helper}->{http}->{id},
				callback   => $hash->{helper}->{http}->{callback}
		});

}

sub Tvheadend_HttpGetBlocking($){
	my ($hash) = @_;

	HttpUtils_BlockingGet(
		{
				method     => "GET",
				url        => $hash->{helper}->{http}->{url},
				timeout    => AttrVal($hash->{NAME},"timeout","20"),
				user			 => $hash->{helper}->{http}->{username},
				pwd				 => $hash->{helper}->{http}->{password},
				noshutdown => "1",
		});

}
