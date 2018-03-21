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
);

my %NoEPGEntry = (
	"start"  => 0,
	"stop" => 0,
	"title"  => "Keine Informationen verfügbar",
	"subtitle"  => "Keine Informationen verfügbar",
	"description"  => "Keine Informationen verfügbar",
	"EventId" => 0,
	"nextEventId" => 0,
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
					"timeout " .
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
	}elsif($opt eq "ChannelQuery"){
		return &Tvheadend_ChannelQuery($hash);
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

	(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Busy, leaving..."),return) if($hash->{helper}{http}{busy} eq "1");

	## GET CHANNELS
	if($state == 0){

		$hash->{helper}{http}{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $response;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($err);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Server needs authentication"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($data =~ /^.*401 Unauthorized.*/s);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Requested interface not found"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($data =~ /^.*404 Not Found.*/s);

			$response = decode_json($data);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - No Channels available"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($response->{total} == 0);
			my $test = $response->{entries};
			@$test = sort {$a->{number} <=> $b->{number}} @$test;

			$hash->{helper}{epg}{count} = $response->{total};
			$hash->{helper}{epg}{channels} = $test;
			$hash->{helper}{http}{busy} = "0";

			InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
			Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 1");
			$state = 1;
		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get Channels");

		my $ip = $hash->{helper}{http}{ip};
		my $port = $hash->{helper}{http}{port};

		$hash->{helper}{http}{id} = "";
		$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/channel/grid";
		$hash->{helper}{http}{busy} = "1";
		&Tvheadend_HttpGet($hash);

		return;

	#GET NOW
	}elsif($state == 1){

		my @entriesNow = ();

		$hash->{helper}{http}{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $channels = $hash->{helper}{epg}{channels};
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($err);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Server needs authentication"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($data =~ /^.*401 Unauthorized.*/s);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Requested interface not found"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($data =~ /^.*404 Not Found.*/s);

			$entries = decode_json($data)->{entries};
			if(!defined @$entries[0]){
			  Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - No current EPG information for Channel @$channels[$param->{id}]->{number}:@$channels[$param->{id}]->{name}");
				@entriesNow[$param->{id}] = \%NoEPGEntry;
			}else{
		 		@entriesNow[$param->{id}] = @$entries[0];
				@entriesNow[$param->{id}]->{subtitle} = "Keine Informationen verfügbar" if(!defined @entriesNow[$param->{id}]->{subtitle});
				@entriesNow[$param->{id}]->{summary} = "Keine Informationen verfügbar" if(!defined @entriesNow[$param->{id}]->{summary});
				@entriesNow[$param->{id}]->{description} = "Keine Informationen verfügbar" if(!defined @entriesNow[$param->{id}]->{description});
			}
			#Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - ".scalar(grep {defined $_} @$entriesNext)." / $hash->{helper}{epg}{count}");
			if(scalar(grep {defined $_} @entriesNow) == $hash->{helper}{epg}{count}){

				$hash->{helper}{epg}{now} = \@entriesNow;

				for (my $i=0;$i < int(@entriesNow);$i+=1){
						($hash->{helper}{epg}{update} = $entriesNow[$i]->{stop},last) if($entriesNow[$i]->{stop} != 0);
				}
				for (my $i=0;$i < int(@entriesNow);$i+=1){
						$hash->{helper}{epg}{update} = $entriesNow[$i]->{stop} if(($entriesNow[$i]->{stop} < $hash->{helper}{epg}{update}) && $entriesNow[$i]->{start} != 0);
				}

				$hash->{helper}{http}{busy} = "0";
				InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash) if ($state == 1);
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 2");
				$state = 2;
			}

		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get EPG Now");

		my $channels = $hash->{helper}{epg}{channels};
		my $count = $hash->{helper}{epg}{count};
		my $channelName = "";
		my $ip = $hash->{helper}{http}{ip};
		my $port = $hash->{helper}{http}{port};

		$hash->{helper}{http}{busy} = "1";
		for (my $i=0;$i < $count;$i+=1){
			$hash->{helper}{http}{id} = $i;
			$channelName = @$channels[$i]->{name};
			$channelName =~ s/\x20/\%20/g;
			$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/epg/events/grid?limit=1&channel=".encode('UTF-8',$channelName);
			&Tvheadend_HttpGet($hash);
		}

		return;

	## GET NEXT
	}elsif($state == 2){

		my @entriesNext = ();

		$hash->{helper}{http}{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $channels = $hash->{helper}{epg}{channels};
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($err);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Server needs authentication"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($data =~ /^.*401 Unauthorized.*/s);
			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Requested interface not found"),$state=0,$hash->{helper}{http}{busy} = "0",return) if($data =~ /^.*404 Not Found.*/s);

			$entries = decode_json($data)->{entries};
			if(!defined @$entries[0]){
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - No upcoming EPG information for Channel @$channels[$param->{id}]->{number}:@$channels[$param->{id}]->{name}");
				@entriesNext[$param->{id}] = \%NoEPGEntry;
			}else{
				@entriesNext[$param->{id}] = @$entries[0];
				@entriesNext[$param->{id}]->{subtitle} = "Keine Informationen verfügbar" if(!defined @entriesNext[$param->{id}]->{subtitle});
				@entriesNext[$param->{id}]->{summary} = "Keine Informationen verfügbar" if(!defined @entriesNext[$param->{id}]->{summary});
				@entriesNext[$param->{id}]->{description} = "Keine Informationen verfügbar" if(!defined @entriesNext[$param->{id}]->{description});
			}
			#Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - ".scalar(grep {defined $_} @$entriesNext)." / $hash->{helper}{epg}{count}");
			if(scalar(grep {defined $_} @entriesNext) == $hash->{helper}{epg}{count}){
				$hash->{helper}{epg}{next} = \@entriesNext;

				$hash->{helper}{http}{busy} = "0";
				InternalTimer(gettimeofday(),"Tvheadend_EPG",$hash);
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 3");
				$state = 3;
			}
		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get EPG Next");

		my $entries = $hash->{helper}{epg}{now};
		my $count = $hash->{helper}{epg}{count};
		my $ip = $hash->{helper}{http}{ip};
		my $port = $hash->{helper}{http}{port};

		$hash->{helper}{http}{busy} = "1";
		for (my $i=0;$i < int($count);$i+=1){
			$hash->{helper}{http}{id} = $i;
			$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/epg/events/load?eventId=".@$entries[$i]->{nextEventId};
			&Tvheadend_HttpGet($hash);
		}
		return;

	## SET READINGS
	}elsif($state == 3){
		my $update = $hash->{helper}{epg}{update};
		my $entriesNow = $hash->{helper}{epg}{now};
		my $entriesNext = $hash->{helper}{epg}{next};
		my $channels = $hash->{helper}{epg}{channels};

		readingsBeginUpdate($hash);
		for (my $i=0;$i < int(@$entriesNow);$i+=1){
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."Name", encode('UTF-8',@$channels[$i]->{name}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."Number", encode('UTF-8',@$channels[$i]->{number}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."TitleNow", encode('UTF-8',@$entriesNow[$i]->{title}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."StartNow", strftime("%H:%M:%S",localtime(encode('UTF-8',@$entriesNow[$i]->{start}))));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."EndNow", strftime("%H:%M:%S",localtime(encode('UTF-8',@$entriesNow[$i]->{stop}))));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."DescriptionNow", encode('UTF-8',@$entriesNow[$i]->{description}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."SummaryNow", encode('UTF-8',@$entriesNow[$i]->{summary}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."SubtitleNow", encode('UTF-8',@$entriesNow[$i]->{subtitle}));
		}

		for (my $i=0;$i < int(@$entriesNext);$i+=1){
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."DescriptionNext", encode('UTF-8',@$entriesNext[$i]->{description}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."SummaryNext", encode('UTF-8',@$entriesNext[$i]->{summary}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."SubtitleNext", encode('UTF-8',@$entriesNext[$i]->{subtitle}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."TitleNext", encode('UTF-8',@$entriesNext[$i]->{title}));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."StartNext", strftime("%H:%M:%S",localtime(encode('UTF-8',@$entriesNext[$i]->{start}))));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%03d", $i)."EndNext", strftime("%H:%M:%S",localtime(encode('UTF-8',@$entriesNext[$i]->{stop}))));
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
	my @channelData = ();

	$hash->{helper}{http}{id} = "";
	$hash->{helper}{http}{url} = "http://".$ip.":".$port."/api/channel/grid";
	my ($err, $data) = &Tvheadend_HttpGetBlocking($hash);
	return $err if($err);
	($response = "Server needs authentication",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*401 Unauthorized.*/s);
	($response = "Requested interface not found",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if($data =~ /^.*404 Not Found.*/s);

	$entries = decode_json($data)->{entries};

	($response = "No Channels available",Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $response"),return $response) if(int(@$entries) == 0);
	@$entries = sort {$a->{number} <=> $b->{number}} @$entries;

	for (my $i=0;$i < int(@$entries);$i+=1){
		push(@channelData,@$entries[$i]->{name});
	}

	my $channels = join(",",@channelData);
	$channels =~ s/ /\_/g;
	$modules{Tvheadend}{AttrList} =~ s/queryChannel:multiple-strict.*/queryChannel:multiple-strict,all,$channels/;

	$hash->{helper}{epg}{count} = @$entries;
	$hash->{helper}{epg}{channels} = $entries;

	return join("\n",@channelData);
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


sub Tvheadend_HttpGet($){
	my ($hash) = @_;

	HttpUtils_NonblockingGet(
		{
				method     => "GET",
				url        => $hash->{helper}{http}{url},
				timeout    => AttrVal($hash->{NAME},"timeout","5"),
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
				timeout    => AttrVal($hash->{NAME},"timeout","5"),
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
									<br><br>
							</li>
        </ul>
    </ul>
    <br>

    <a name="TVheadendattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        Attributes:
        <ul>
            <li><i>timeout</i><br>
                HTTP timeout in seconds. When not set, 5 seconds are used.
            </li>
        </ul>
    </ul>
</ul>
=end html
=cut
