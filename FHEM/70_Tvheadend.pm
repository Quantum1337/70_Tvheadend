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
	"ChannelQuery:noArg" => "",
	"ConnectionQuery:noArg" => "",
);

sub Tvheadend_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'Tvheadend_Define';
    $hash->{UndefFn}    = 'Tvheadend_Undef';
    $hash->{SetFn}      = 'Tvheadend_Set';
    $hash->{GetFn}      = 'Tvheadend_Get';
    $hash->{AttrFn}     = 'Tvheadend_Attr';
    $hash->{NotifyFn}   = 'Tvheadend_Notify';

    $hash->{AttrList} =
					"HTTPTimeout " .
					"EPGVisibleItems:multiple-strict,Title,Subtitle,Summary,Description,ChannelName,ChannelNumber,StartTime,StopTime " .
					"PollingQueries:multiple-strict,ConnectionQuery " .
					"PollingIntervall " .
					"EPGChannelList:multiple-strict,all " .
          $readingFnAttributes;

}

sub Tvheadend_Define($$$) {
	my ($hash, $def) = @_;
	my @args = split("[ \t][ \t]*", $def);

	return "Error while loading $JSON. Please install $JSON" if $JSON;

	return "Usage: define <NAME> $hash->{TYPE} <IP>:[<PORT>] [<USERNAME> <PASSWORD>]" if(int(@args) < 3);

	my @address = split(":",$args[2]);

	if($address[0] =~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/){
		$hash->{helper}{http}{ip} = $address[0];
	}else{
		return "The specified ip address is not valid"
	}

	if(defined $address[1]){
		if($address[1] =~ /^[0-9]+$/){
			$hash->{helper}{http}{port} = $address[1];
		}else{
			return "The specified port is not valid"
		}
	}else{
		$hash->{helper}{http}{port} = "9981";
	}

	if(defined $args[3]){
		$hash->{helper}{http}{username} = $args[3]
	}

	if(defined $args[4]){
		$hash->{helper}{http}{password} = $args[4]
	}

	$state = 0;

	if($init_done){
		Tvheadend_ChannelQuery($hash);
		InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);

		if(AttrVal($hash->{NAME},"PollingQueries","") =~ /^.*ConnectionQuery.*$/){
			InternalTimer(gettimeofday(),"Tvheadend_ConnectionQuery",$hash);
			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - ConnectionQuery will be polled with an intervall of ".AttrVal($hash->{NAME},"PollingIntervall",60)."s");
		}
	}

	$hash->{STATE} = "Initialized";
	return;
}

sub Tvheadend_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash,"Tvheadend_EPG");

	return undef;
}

sub Tvheadend_Set($$$) {
	my ($hash, $name, $opt, @args) = @_;

	if($opt eq "EPG"){
		InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
	}elsif($opt eq "DVREntryCreate"){
		if($args[0] =~ /^[0-9]+$/){
			&Tvheadend_DVREntryCreate($hash,@args);
		}else{
			return "EventId must be numeric"
		}
	}else{
		my @cList = keys %Tvheadend_sets;
		return "Unknown command $opt, choose one of " . join(" ", @cList);
	}

}

sub Tvheadend_Get($$$) {
	my ($hash, $name, $opt, @args) = @_;

	if($opt eq "EPGQuery"){
		return &Tvheadend_EPGQuery($hash,@args);
	}elsif($opt eq "ChannelQuery"){
		return &Tvheadend_ChannelQuery($hash);
	}elsif($opt eq "ConnectionQuery"){
		return &Tvheadend_ConnectionQuery($hash);
	}else{
		my @cList = keys %Tvheadend_gets;
		return "Unknown command $opt, choose one of " . join(" ", @cList);
	}

}

sub Tvheadend_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;

	if($cmd eq "set") {

		if($attr_name eq "EPGVisibleItems"){
			if($attr_value !~ /^.*Title.*$/){
				fhem("deletereading $name channel[0-9]+TitleNow");
				fhem("deletereading $name channel[0-9]+TitleNext");
			}
			if($attr_value !~ /^.*Subtitle.*$/){
				fhem("deletereading $name channel[0-9]+SubtitleNow");
				fhem("deletereading $name channel[0-9]+SubtitleNext");
			}
			if($attr_value !~ /^.*Summary.*$/){
				fhem("deletereading $name channel[0-9]+SummaryNow");
				fhem("deletereading $name channel[0-9]+SummaryNext");
			}
			if($attr_value !~ /^.*Description.*$/){
				fhem("deletereading $name channel[0-9]+DescriptionNow");
				fhem("deletereading $name channel[0-9]+DescriptionNext");
			}
			if($attr_value !~ /^.*StartTime.*$/){
				fhem("deletereading $name channel[0-9]+StartTimeNow");
				fhem("deletereading $name channel[0-9]+StartTimeNext");
			}
			if($attr_value !~ /^.*StopTime.*$/){
				fhem("deletereading $name channel[0-9]+StopTimeNow");
				fhem("deletereading $name channel[0-9]+StopTimeNext");
			}
			if($attr_value !~ /^.*ChannelName.*$/){
				fhem("deletereading $name channel[0-9]+Name");
			}
			if($attr_value !~ /^.*ChannelNumber.*$/){
				fhem("deletereading $name channel[0-9]+Number");
			}
		}elsif($attr_name eq "PollingQueries"){
			my $hash = $defs{$name};

			if($attr_value =~ /^.*ConnectionQuery.*$/){
				if($init_done){
					InternalTimer(gettimeofday(),"Tvheadend_ConnectionQuery",$hash);
					Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - ConnectionQuery will be polled with an intervall of ".AttrVal($hash->{NAME},"PollingIntervall",60)."s");
				}
			}elsif($attr_value !~ /^.*ConnectionQuery.*$/){
				fhem("deletereading $name connections.*");
				RemoveInternalTimer($hash,"Tvheadend_ConnectionQuery");
				Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - ConnectionQuery won't be polled anymore");
			}
		}elsif($attr_name eq "HTTPTimeout"){
			if(($attr_value !~ /^[0-9]+$/) || ($attr_value < 1 || $attr_value > 60)){
				return "$attr_name must be nummeric an between 5 and 60 seconds"
			}
		}

	}elsif($cmd eq "del"){
		if($attr_name eq "EPGVisibleItems"){
			fhem("deletereading $name channel[0-9]+.*");
		}
		if($attr_name eq "PollingQueries"){
			my $hash = $defs{$name};
			fhem("deletereading $name connections.*");
			RemoveInternalTimer($hash,"Tvheadend_ConnectionQuery");
			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - ConnectionQuery won't be polled anymore");
		}
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
		Tvheadend_ChannelQuery($own_hash);
		InternalTimer(gettimeofday(),"Tvheadend_EPG",$own_hash);

		if(AttrVal($own_hash->{NAME},"PollingQueries","") =~ /^.*ConnectionQuery.*$/){
			InternalTimer(gettimeofday(),"Tvheadend_ConnectionQuery",$own_hash);
			Log3($own_hash->{NAME},3,"$own_hash->{TYPE} $own_hash->{NAME} - ConnectionQuery will be polled with an intervall of ".AttrVal($own_hash->{NAME},"PollingIntervall",60). "s");
		}
	}

	return
}

sub Tvheadend_EPG($){
	my ($hash) = @_;

	(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Can't get EPG data, because no channels defined"),return) if($hash->{helper}{epg}{count} == 0);

	#GET NOW
	if($state == 0){
		my $count = $hash->{helper}{epg}{count};
		my @entriesNow = ();

		$hash->{helper}{http}{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $channels = $hash->{helper}{epg}{channels};
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),$state=0,return) if($err);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Server needs authentication"),$state=0,return) if($data =~ /^.*401 Unauthorized.*/s);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Requested interface not found"),$state=0,return) if($data =~ /^.*404 Not Found.*/s);

			$entries = decode_json($data)->{entries};
			if(!defined @$entries[0]){
			  Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Skipping @$channels[$param->{id}]->{number}:@$channels[$param->{id}]->{name}. No current EPG information");
				$count -=1;
			}else{
				@$entries[0]->{subtitle} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{subtitle});
				@$entries[0]->{summary} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{summary});
				@$entries[0]->{description} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{description});

				@$entries[0]->{title} = encode('UTF-8',@$entries[0]->{title});
				@$entries[0]->{subtitle} = encode('UTF-8',@$entries[0]->{subtitle});
				@$entries[0]->{summary} = encode('UTF-8',@$entries[0]->{summary});
				@$entries[0]->{description} = encode('UTF-8',@$entries[0]->{description});

				@$entries[0]->{channelId} = $param->{id};

				push (@entriesNow,@$entries[0])
			}

			if(int(@entriesNow) == $count){

				$hash->{helper}{epg}{now} = \@entriesNow;
				$hash->{helper}{epg}{count} = $count;


				$hash->{helper}{epg}{update} = $entriesNow[0]->{stop};
				for (my $i=0;$i < int(@entriesNow);$i+=1){
						$hash->{helper}{epg}{update} = $entriesNow[$i]->{stop} if($entriesNow[$i]->{stop} < $hash->{helper}{epg}{update});
				}

				InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 1");
				$state = 1;
			}

		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get EPG Now");

		my $channels = $hash->{helper}{epg}{channels};
		my $channelName = "";
		my $ip = $hash->{helper}{http}{ip};
		my $port = $hash->{helper}{http}{port};

		for (my $i=0;$i < $count;$i+=1){
			$hash->{helper}{http}{id} = @$channels[$i]->{id};
			$channelName = @$channels[$i]->{name};
			$channelName =~ s/\x20/\%20/g;
			$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/epg/events/grid?limit=1&channel=".$channelName;
			&Tvheadend_HttpGetNonblocking($hash);
		}

		return;

	## GET NEXT
	}elsif($state == 1){

		my @entriesNext = ();
		my $count = $hash->{helper}{epg}{count};

		$hash->{helper}{http}{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $channels = $hash->{helper}{epg}{channels};
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),$state=0,return) if($err);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Server needs authentication"),$state=0,return) if($data =~ /^.*401 Unauthorized.*/s);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Requested interface not found"),$state=0,return) if($data =~ /^.*404 Not Found.*/s);

			$entries = decode_json($data)->{entries};
			if(!defined @$entries[0]){
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Skipping @$channels[$param->{id}]->{number}:@$channels[$param->{id}]->{name}. No upcoming EPG information.");
				$count -=1;
			}else{
				@$entries[0]->{subtitle} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{subtitle});
				@$entries[0]->{summary} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{summary});
				@$entries[0]->{description} = "Keine Informationen verfügbar" if(!defined @$entries[0]->{description});

				@$entries[0]->{title} = encode('UTF-8',@$entries[0]->{title});
				@$entries[0]->{subtitle} = encode('UTF-8',@$entries[0]->{subtitle});
				@$entries[0]->{summary} = encode('UTF-8',@$entries[0]->{summary});
				@$entries[0]->{description} = encode('UTF-8',@$entries[0]->{description});

				@$entries[0]->{channelId} = $param->{id};

				push (@entriesNext,@$entries[0])
			}

			if(int(@entriesNext) == $count){
				$hash->{helper}{epg}{next} = \@entriesNext;
				$hash->{helper}{epg}{count} = $count;

				InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 2");
				$state = 2;
			}
		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get EPG Next");

		my $entries = $hash->{helper}{epg}{now};
		my $ip = $hash->{helper}{http}{ip};
		my $port = $hash->{helper}{http}{port};

		for (my $i=0;$i < int(@$entries);$i+=1){
			$hash->{helper}{http}{id} = @$entries[$i]->{channelId};
			$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/epg/events/load?eventId=".@$entries[$i]->{nextEventId};
			&Tvheadend_HttpGetNonblocking($hash);
		}
		return;

	## SET READINGS
	}elsif($state == 2){
		my $update = $hash->{helper}{epg}{update};
		my $entriesNow = $hash->{helper}{epg}{now};
		my $entriesNext = $hash->{helper}{epg}{next};
		my $channels = $hash->{helper}{epg}{channels};
		my $items = AttrVal($hash->{NAME},"EPGVisibleItems","");

		readingsBeginUpdate($hash);
		for (my $i=0;$i < int(@$channels);$i+=1){
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$channels[$i]->{id})."Name", @$channels[$i]->{name}) if($items =~ /^.*ChannelName.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$channels[$i]->{id})."Number", @$channels[$i]->{number}) if($items =~ /^.*ChannelNumber.*$/);
		}
		for (my $i=0;$i < int(@$entriesNow);$i+=1){
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNow[$i]->{channelId})."TitleNow", @$entriesNow[$i]->{title}) if($items =~ /^.*Title.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNow[$i]->{channelId})."StartTimeNow", strftime("%H:%M:%S",localtime(@$entriesNow[$i]->{start}))) if($items =~ /^.*StartTime.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNow[$i]->{channelId})."StopTimeNow", strftime("%H:%M:%S",localtime(@$entriesNow[$i]->{stop}))) if($items =~ /^.*StopTime.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNow[$i]->{channelId})."DescriptionNow", @$entriesNow[$i]->{description}) if($items =~ /^.*Description.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNow[$i]->{channelId})."SummaryNow", @$entriesNow[$i]->{summary}) if($items =~ /^.*Summary.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNow[$i]->{channelId})."SubtitleNow", @$entriesNow[$i]->{subtitle}) if($items =~ /^.*Subtitel.*$/);
		}
		for (my $i=0;$i < int(@$entriesNext);$i+=1){
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNext[$i]->{channelId})."DescriptionNext", @$entriesNext[$i]->{description}) if($items =~ /^.*Description.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNext[$i]->{channelId})."SummaryNext", @$entriesNext[$i]->{summary}) if($items =~ /^.*Summary.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNext[$i]->{channelId})."SubtitleNext", @$entriesNext[$i]->{subtitle}) if($items =~ /^.*Subtitel.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNext[$i]->{channelId})."TitleNext", @$entriesNext[$i]->{title}) if($items =~ /^.*Title.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNext[$i]->{channelId})."StartTimeNext", strftime("%H:%M:%S",localtime(@$entriesNext[$i]->{start}))) if($items =~ /^.*StartTime.*$/);
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", @$entriesNext[$i]->{channelId})."StopTimeNext", strftime("%H:%M:%S",localtime(@$entriesNext[$i]->{stop}))) if($items =~ /^.*StopTime.*$/);
		}
		readingsEndUpdate($hash, 1);

		Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Next update: ".  strftime("%H:%M:%S",localtime($update)));
		RemoveInternalTimer($hash,"Tvheadend_EPG");
		InternalTimer($update + 1,"Tvheadend_EPG",$hash);
		$state = 0;
	}

}

sub Tvheadend_ChannelQuery($){
	my ($hash) = @_;

	Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get Channels");

	my $ip = $hash->{helper}{http}{ip};
	my $port = $hash->{helper}{http}{port};
	my $response = "";
	my $entries;
	my @channelNames = ();

	$hash->{helper}{epg}{count} = 0;
	delete $hash->{helper}{epg}{channels} if(defined $hash->{helper}{epg}{channels});

	$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/channel/grid";
	my ($err, $data) = &Tvheadend_HttpGetBlocking($hash);
	($response = $err,Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),return $err) if($err);
	($response = "Server needs authentication",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*401 Unauthorized.*/s);
	($response = "Requested interface not found",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*404 Not Found.*/s);

	$entries = decode_json($data)->{entries};

	($response = "No Channels available",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if(int(@$entries) == 0);
	@$entries = sort {$a->{number} <=> $b->{number}} @$entries;

	for (my $i=0;$i < int(@$entries);$i+=1){
		@$entries[$i]->{name} = encode('UTF-8',@$entries[$i]->{name});
		@$entries[$i]->{id} = $i;
		push(@channelNames,@$entries[$i]->{name});
	}

	my $channelNames = join(",",@channelNames);
	$channelNames =~ s/ /\_/g;
	$modules{Tvheadend}{AttrList} =~ s/EPGChannelList:multiple-strict.*/EPGChannelList:multiple-strict,all,$channelNames/;

	$hash->{helper}{epg}{count} = @$entries;
	$hash->{helper}{epg}{channels} = $entries;

	return join("\n",@channelNames);
}

sub Tvheadend_EPGQuery($$){
	my ($hash,@args) = @_;

	my $ip = $hash->{helper}{http}{ip};
	my $port = $hash->{helper}{http}{port};
	my $entries;
	my $response = "";

	@args = split(":",join("%20", @args));
	($args[1] = $args[0], $args[0] = 1)if(!defined $args[1]);
	($args[0] = 1)if(defined $args[1] && $args[0] !~ /^[0-9]+$/);

	$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/epg/events/grid?limit=$args[0]&title=$args[1]";

	my ($err, $data) = &Tvheadend_HttpGetBlocking($hash);
	return $err if($err);
	($response = "Server needs authentication",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*401 Unauthorized.*/s);
	($response = "Requested interface not found",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*404 Not Found.*/s);


	$entries = decode_json($data)->{entries};
	($response = "No Results",return $response) if(!defined @$entries[0]);

	for (my $i=0;$i < int(@$entries);$i+=1){
		@$entries[$i]->{subtitle} = "Keine Informationen verfügbar" if(!defined @$entries[$i]->{subtitle});
		@$entries[$i]->{description} = "Keine Informationen verfügbar" if(!defined @$entries[$i]->{description});
		@$entries[$i]->{summary} = "Keine Informationen verfügbar" if(!defined @$entries[$i]->{summary});

		$response .= "Sender: ".@$entries[$i]->{channelName} ."\n".
								"Zeit: ".strftime("%d.%m [%H:%M:%S",localtime(encode('UTF-8',@$entries[$i]->{start})))." - ".
								strftime("%H:%M:%S]",localtime(encode('UTF-8',@$entries[$i]->{stop})))."\n".
								"Titel: ".encode('UTF-8',&Tvheadend_StringFormat(@$entries[$i]->{title},80))."\n".
								"Subtitel: ".encode('UTF-8',&Tvheadend_StringFormat(@$entries[$i]->{subtitle},80))."\n".
								"Zusammenfassung: ".encode('UTF-8',&Tvheadend_StringFormat(@$entries[$i]->{summary},80)). "\n".
								"Beschreibung: ".encode('UTF-8',&Tvheadend_StringFormat(@$entries[$i]->{description},80)). "\n".
								"EventId: " . @$entries[$i]->{eventId}."\n";
	}

	return $response;

}

sub Tvheadend_ConnectionQuery($){
	my ($hash,@args) = @_;

	Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Query connections");


	my $ip = $hash->{helper}{http}{ip};
	my $port = $hash->{helper}{http}{port};
	my $entries;
	my $response = "";

	$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/status/connections";
	my ($err, $data) = &Tvheadend_HttpGetBlocking($hash);
	return $err if($err);
	($response = "Server needs authentication",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*401 Unauthorized.*/s);
	($response = "Requested interface not found",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*404 Not Found.*/s);

	$entries = decode_json($data)->{entries};

	if(!defined @$entries[0]){
		$response = "ConnectedPeers: 0";

		if(AttrVal($hash->{NAME},"PollingQueries","") =~ /^.*ConnectionQuery.*$/){
			readingsBeginUpdate($hash);
			readingsBulkUpdateIfChanged($hash, "connectionsTotal", "0");
			readingsBulkUpdateIfChanged($hash, "connectionsId", "-");
			readingsBulkUpdateIfChanged($hash, "connectionsUser", "-");
			readingsBulkUpdateIfChanged($hash, "connectionsStartTime", "-");
			readingsBulkUpdateIfChanged($hash, "connectionsPeer", "-");
			readingsBulkUpdateIfChanged($hash, "connectionsType", "-");
			readingsEndUpdate($hash, 1);

			InternalTimer(gettimeofday()+AttrVal($hash->{NAME},"PollingIntervall",60),"Tvheadend_ConnectionQuery",$hash);
		}
	}else{
		@$entries = sort {$a->{started} <=> $b->{started}} @$entries;

		$response = "ConnectedPeers: ".@$entries."\n".
								"-------------------------"."\n";
		for (my $i=0;$i < int(@$entries);$i+=1){
		$response .= "Id: ".@$entries[$i]->{id} ."\n".
								"User: ".encode('UTF-8',@$entries[$i]->{user})."\n".
								"StartTime: ".strftime("%H:%M:%S",localtime(encode('UTF-8',@$entries[$i]->{started}))) ." Uhr\n".
								"Peer: ".encode('UTF-8',@$entries[$i]->{peer})."\n".
								"Type: ".encode('UTF-8',@$entries[$i]->{type})."\n".
								"-------------------------"."\n";
		}

		if(AttrVal($hash->{NAME},"PollingQueries","") =~ /^.*ConnectionQuery.*$/){
			readingsBeginUpdate($hash);
			readingsBulkUpdateIfChanged($hash, "connectionsTotal", @$entries);
			readingsBulkUpdateIfChanged($hash, "connectionsId", join(",",(my @ids = map {$_->{id}}@$entries)));
			readingsBulkUpdateIfChanged($hash, "connectionsUser", encode('UTF-8',join(",",(my @users = map {$_->{user}}@$entries))));
			readingsBulkUpdateIfChanged($hash, "connectionsStartTime", encode('UTF-8',join(",",(my @startTimes = map {$_->{started}}@$entries))));
			readingsBulkUpdateIfChanged($hash, "connectionsPeer", encode('UTF-8',join(",",(my @peer = map {$_->{peer}}@$entries))));
			readingsBulkUpdateIfChanged($hash, "connectionsType", encode('UTF-8',join(",",(my @type = map {$_->{type}}@$entries))));
			readingsEndUpdate($hash, 1);

			InternalTimer(gettimeofday()+AttrVal($hash->{NAME},"PollingIntervall",60),"Tvheadend_ConnectionQuery",$hash);
		}
	}

	return $response;
}

sub Tvheadend_DVREntryCreate($$){
	my ($hash,@args) = @_;

	my $ip = $hash->{helper}{http}{ip};
	my $port = $hash->{helper}{http}{port};
	my $entries;
	my $response = "";

	$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/epg/events/load?eventId=".$args[0];
	my ($err, $data) = &Tvheadend_HttpGetBlocking($hash);
	return $err if($err);
	($response = "Server needs authentication",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*401 Unauthorized.*/s);
	($response = "Requested interface not found",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*404 Not Found.*/s);

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
	$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/dvr/entry/create?conf=".$jasonData;
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

sub Tvheadend_HttpGetNonblocking($){
	my ($hash) = @_;

	HttpUtils_NonblockingGet(
		{
				method     => "GET",
				url        => $hash->{helper}{http}{url},
				timeout    => AttrVal($hash->{NAME},"HTTPTimeout","5"),
				user			 => $hash->{helper}{http}{username},
				pwd				 => $hash->{helper}{http}{password},
				noshutdown => "1",
				hash			 => $hash,
				id				 => $hash->{helper}{http}{id},
				callback   => $hash->{helper}{http}{callback}
		});

}

sub Tvheadend_HttpGetBlocking($){
	my ($hash) = @_;

	HttpUtils_BlockingGet(
		{
				method     => "GET",
				url        => $hash->{helper}{http}{url},
				timeout    => AttrVal($hash->{NAME},"HTTPTimeout","5"),
				user			 => $hash->{helper}{http}{username},
				pwd				 => $hash->{helper}{http}{password},
				noshutdown => "1",
		});

}

1;

=pod
=begin html

<a name="Tvheadend"></a>
<h3>Tvheadend</h3>
<ul>
    <i>Tvheadend</i> is a TV streaming server for Linux supporting
		DVB-S, DVB-S2, DVB-C, DVB-T, ATSC, IPTV,SAT>IP and other formats through
		the unix pipe as input sources. For further informations, take a look at the
		<a href="https://github.com/tvheadend/tvheadend">repository</a> on GitHub.
		This module module makes use of Tvheadends JSON API.
    <br><br>
    <a name="Tvheadenddefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Tvheadend &lt;IP&gt;:[&lt;PORT&gt;] [&lt;USERNAME&gt; &lt;PASSWORD&gt;]</code>
        <br><br>
        Example: <code>define tvheadend Tvheadend 192.168.0.10</code><br>
        Example: <code>define tvheadend Tvheadend 192.168.0.10 max securephrase</code>
        <br><br>
				When &lt;PORT&gt; is not set, the module will use Tvheadends standard port 9981.
				If the definition is successfull, the module will automatically query the EPG
				for tv shows playing now and next. The query is based on Channels mapped in Configuration/Channel.
				The module will automatically query again, when a tv show ends.
    </ul>
    <br>
    <a name="Tvheadendset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;command&gt; &lt;parameter&gt;</code>
        <br><br>
				&lt;command&gt; can be one of the following:
        <br><br>
        <ul>
              <li><i>DVREntryCreate</i><br>
                  Creates a DVR entry, derived from the EventId given with &lt;parameter&gt;.
							</li>
        </ul>
    </ul>
    <br>

    <a name="Tvheadendget"></a>
    <b>Get</b><br>
    <ul>
        <code>get &lt;name&gt; &lt;command&gt; &lt;parameter&gt;</code>
        <br><br>
				&lt;command&gt; can be one of the following:
				<br><br>
        <ul>
              <li><i>EPGQuery</i><br>
                  Queries the EPG. Returns results, matched with &lt;parameter&gt; and the title of a show.
									Have not to be an exact match and is not case sensitive. The result includes i.a. the EventId.
									<br><br>
									Example: get &lt;name&gt; EPGQuery 3:tagessch<br>
									This command will query the first three results in upcoming order, including
									"tagessch" in the title of a tv show.
							</li>
							<li><i>ChannelQuery</i><br>
									Queries the channel informations. Returns channels known by tvheadend. Furthermore this command
									will update the internal channel database.
							</li>
							<li><i>ConnectionQuery</i><br>
									Queries informations about active connections. Returns the count of actual connected peers and some
									additional informations of each peer.
							</li>
        </ul>
    </ul>
    <br>

    <a name="TVheadendattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        &lt;attribute&gt; can be one of the following:
        <ul>
            <li><i>HTTPTimeout</i><br>
                HTTP timeout in seconds.<br>
								Standardvalue: 5s<br>
								Range: 1s-60s
            </li>
						<li><i>EPGVisibleItems</i><br>
                Selectable list of epg items. Items selected will generate
								readings. The readings will be generated, next time the EPG is triggered.
								When an item becomes unselected, the specific readings will be deleted.
            </li>
						<li><i>PollingQueries</i><br>
                Selectable list of queries, that can be polled. When enabled the polling of the specific
								query starts immediately with an intervall given with the attribute PollingIntervall.
								When a query is in polling mode, readings will be created. When the polling will be disabled,
								the readings will be deleted.
            </li>
						<li><i>PollingIntervalls</i><br>
								Intervall of polling a query. See PollingQueries for further details.<br>
								Standardvalue: 60s
            </li>
        </ul>
    </ul>
</ul>
=end html
=cut
