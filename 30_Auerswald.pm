##############################################################################
#
#     70_Auerswald.pm
#     An FHEM Perl module for connecting to an Auerswald PBX Telephone System and 
#     make settings there.
#     
#     Tested with an COMpact 5010 VoIP with ISDN and 2VOIP Module
#     It *should* support the following PBX's:
#
#     COMpact 4000
#     COMpact 5000
#     COMPact 5010 
#     COMPact 5020
#     COMpact 5000R
#     COMmander 6000
#     COMmander 6000R
#     COMmander 6000RX
#
#
#     Copyright by BioS
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# Version: 0.3
#
# Changelog:
#
# v0.3 2016-12-29 Added simulated calls for usage of FB_CALLLIST - Alpha release in Forum
# v0.2 2016-07-20 Added robinson lists, housekeeping
# v0.1 2015-04-18 Initial Alpha
##############################################################################
#
# Have Phun!
#
package main;

use strict;
use warnings;
use utf8;
use Time::HiRes qw(gettimeofday);
use Data::Dumper;
use POSIX;
use JSON;
use HttpUtils;
use HTML::Form;

sub Auerswald_Set($@);
sub Auerswald_Get($@);
sub Auerswald_Define($$);
sub Auerswald_UnDef($$);

#sub Auerswald_PollMessages($);
#sub Auerswald_CheckConnection($);

# If you want extended logging and debugging infomations
# in fhem.log please set the following value to 1
my $debug = 0;

my %sets = (
  "callForward" => 1,
  "activateConfig" => 1,
  "robinson" => 1,
  "clearReadings" => 1,
  
  
);

my %gets = (
  "PBXconfig"   => 1,
);

my %amtArtURLMapping = (
  1 => "ptmp",
  2 => "voip_ptmp",
);
my %amtart = (
  0 => "ISDN-PTP",
  1 => "ISDN-PTMP",
  2 => "VoIP-PTMP",
  3 => "POTS (Analog)",
  4 => "VoIP-PTP"
);

###################################
sub
Auerswald_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}      = "Auerswald_Set";
  $hash->{GetFn}      = "Auerswald_Get";
  $hash->{DefFn}      = "Auerswald_Define";
  $hash->{UndefFn}    = "Auerswald_UnDef";
  $hash->{AttrFn}     = "Auerswald_Attr";
  $hash->{AttrList}   = "loglevel:0,1,2,3,4,5 PollTimer ".$readingFnAttributes;
}

###################################
sub Auerswald_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  
  if (!defined($sets{$cmd}))
  {
    return "Unknown argument " . $cmd . ", choose one of " . join(" ", sort keys %sets);
  }
  my $baseurl = "http://". $hash->{helper}{server} .":". $hash->{helper}{port}. "/";
  my $method = "GET";
  my $header = "Cookie: AUERSessionID=" . ReadingsVal($name,"cookieSession","") ."; AUERWEB_COOKIE=". ReadingsVal($name,"cookieUser","");
  my $sendData = "";
  my $refCommand = "";
  my $url = "";
  my $err = "";
  my $data = "";
  
  if ($cmd eq 'clearReadings')
  {
    my @cH;
    push @cH,$_ foreach(grep !/^cookie.*/,keys %{$hash->{READINGS}});
    delete $hash->{READINGS}->{$_} foreach (@cH);
  }

  if ($cmd eq 'callForward') {
    #callforward msn 1213 0|1|2 off|on|001723456789
    my ($fwdfor,$internalid,$fwdtype,$number) = @args;
    if (defined($fwdfor) && defined($internalid) && defined($number) && defined ($fwdtype) && $fwdfor ne "" && $internalid ne "" && $number ne "" && $fwdtype ne "") {
      if ($fwdfor eq "msn") {
        #use the API for on / off switching and if API ver 2, for setting the number
        #/app_msn_aws_set?msnId=6399&msnTyp=1&switchOnOff=1
        #/app_msn_aws_set?msnId=6399&msnTyp=1&switchOnOff=1&ziel=00530692000 X-AppVersion2
        
        #use the awful webinterface for setting the number (because there is a difference in API 1 and 2)
        if ($number eq "off") {
          $url = $baseurl."app_msn_aws_set?msnId=".$internalid."&msnTyp=".$fwdtype."&switchOnOff=0";
          $method = "GET";
          $sendData = "";
          ($err,$data) = HttpUtils_BlockingGet({
            url => $url,
            timeout => 10,
            method => $method,
            noshutdown => 1,
            header => $header,
            data => $sendData,
          });  
          if ($err eq "" && $data ne "" && index($data, 'Access Error') < 0) {
            my $switchJSON = Auerswald_DecodeJSON($data);
            if ($switchJSON->{successful}) {
              Auerwald_getInfoDelayed($hash,"app_msn_aws_list",5);
              return "Successful turned off forwarding";
              #return undef;
            } else {
              return "error: Cannot turn off forwarding, PBX says not successful";
            }
          } else {
            return "error: Cannot turn off forwarding: ".$err . $data;
          }
       
        } elsif ($number eq "on") {
          $url = $baseurl."app_msn_aws_set?msnId=".$internalid."&msnTyp=".$fwdtype."&switchOnOff=1";
          $method = "GET";
          $sendData = "";
          ($err,$data) = HttpUtils_BlockingGet({
            url => $url,
            timeout => 10,
            method => $method,
            noshutdown => 1,
            header => $header,
            data => $sendData,
          });  
          if ($err eq "" && $data ne "" && index($data, 'Access Error') < 0) {
            my $switchJSON = Auerswald_DecodeJSON($data);
            if ($switchJSON->{successful}) {
              Auerwald_getInfoDelayed($hash,"app_msn_aws_list",5);
              return "Successful turned on forwarding";
              #return undef;
            } else {
              return "error: Cannot turn on forwarding, PBX says not successful";
            }
          } else {
            return "error: Cannot turn on forwarding: ".$err . $data;
          }       
        } else {
          #use the webinterface for setting the number
          return "error: Cannot find the MSN Number" if (!defined($hash->{helper}{pbxconfig}{msnaws}{$internalid}));
          return "error: Cannot find the Internal ID of the amt corresponding to the MSN Number" if (!defined($hash->{helper}{pbxconfig}{msnaws}{$internalid}{amtId}));
          return "error: Amt ID ".$hash->{helper}{pbxconfig}{msnaws}{$internalid}{amtId}." is not defined" if (!defined($hash->{helper}{pbxconfig}{amt}{$hash->{helper}{pbxconfig}{msnaws}{$internalid}{amtId}}));
          return "error: Cannot find the Amt art for Amt ID ". $hash->{helper}{pbxconfig}{msnaws}{$internalid}{amtId} if (!defined($hash->{helper}{pbxconfig}{amt}{$hash->{helper}{pbxconfig}{msnaws}{$internalid}{amtId}}{art}));
          my $msnID = $internalid;
          my $amtID = $hash->{helper}{pbxconfig}{msnaws}{$internalid}{amtId};
          my $amtArt = $hash->{helper}{pbxconfig}{amt}{$hash->{helper}{pbxconfig}{msnaws}{$internalid}{amtId}}{art};
          
          #get current config
          
          $url = $baseurl."extruf_aws_rufverteilung?konfigId=-1&amtId=".$amtID."&amtArt=".$amtArt;
          $method = "GET";
          $sendData = "";
          ($err,$data) = HttpUtils_BlockingGet({
            url => $url,
            timeout => 10,
            method => $method,
            noshutdown => 1,
            header => $header,
            data => $sendData,
          });  
          return "error: Cannot set forwarding number: ".$err.$data if ($err ne "" || $data eq "" || index($data, 'Access Error') > 0); 
          my $switchJSON = Auerswald_DecodeJSON($data);
          # IN:
          #{"id":"2378","permanentaktiv":"0","permanentaktivEnabled":true,"amtrufn":"919999","bezeich":"BioS","cfu":"1","cfuNr":"01723456789","cfnr":"0","cfnrNr":"","cfb":"0","cfbNr":""}
          #{"id":"2378","permanentaktiv":"0","permanentaktivEnabled":false,"amtrufn":"919999","bezeich":"BioS","cfu":"0","cfuNr":"01723456789","cfnr":"0","cfnrNr":"","cfb":"0","cfbNr":""}
          #{"id":"2378","permanentaktiv":"1","permanentaktivEnabled":true,"amtrufn":"919999","bezeich":"BioS","cfu":"f1","cfuNr":"01723456789","cfnr":"1","cfnrNr":"123123","cfb":"1","cfbNr":"123"}
          # OUT:
          #amtrufn2378	919999
          #bezeich2378	BioS
          #cfb2378	cfb2378
          #cfbNr2378	123
          #cfnr2378	cfnr2378
          #cfnrNr2378	123123
          #cfu2378	cfu2378
          #cfuNr2378	01723456789
          #id_0	2378
          #permanentaktiv2378	permanentaktiv2378    

          
          #set AuerRaptor callForward msn 2378 0 001741234567      
          my @msnMatch = grep { $_->{id} eq $msnID } @{$switchJSON};
          if (defined($msnMatch[0])) {
            my $configVal = $msnMatch[0];
            
            my $fwdValues = {"id_0" => $configVal->{id}};
            #$fwdValues->{id_0} = $switchJSON->{id};
            
            #Map current config to needed POST data
            foreach my $cfgItem( keys %{$configVal} ) {
              if ($cfgItem ne "permanentaktivEnabled" && $cfgItem ne "id") {
                #if it is not a checkbox
                if ($cfgItem ne "permanentaktiv" && $cfgItem ne "cfu" && $cfgItem ne "cfnr" && $cfgItem ne "cfb") {
                  $fwdValues->{$cfgItem.$msnID} = $configVal->{$cfgItem};
                } else {
                  #if it is 0, we should not set it to not enable the checkbox
                  if ($configVal->{$cfgItem} eq "1") {
                    $fwdValues->{$cfgItem.$msnID} = $cfgItem.$msnID;
                  }
                }
              }
            }
            
            #Current config is now in $fwdValues. We now need to adjust it to reflect our changes
            #Remember we always set the forwarding ON with a telephone number
            if ($fwdtype eq "0") {
              #0=always forward
              $fwdValues->{"cfu".$msnID} = "cfu".$msnID;
              $fwdValues->{"cfuNr".$msnID} = $number;
            } elsif($fwdtype eq "1") {
              #1=busy forward
              $fwdValues->{"cfb".$msnID} = "cfb".$msnID;
              $fwdValues->{"cfbNr".$msnID} = $number;
            } elsif($fwdtype eq "2") {
              #2=no answer forward
              $fwdValues->{"cfnr".$msnID} = "cfnr".$msnID;
              $fwdValues->{"cfnrNr".$msnID} = $number;
            }
            
            #Build the POST request
            $sendData = "";
            foreach my $fwdvalkey ( keys %{$fwdValues} ) {
               $sendData .= "&" if $sendData ne "";
               $sendData .= $fwdvalkey."=".$fwdValues->{$fwdvalkey};
            }            

            #Find the URL to call
            return "error: Cannot set forwarding number: Cannot determine URL to call for Amt Type ".$amtArt if (!defined($amtArtURLMapping{$amtArt}));
            $url = $baseurl."extruf_aws_rufverteilung_".$amtArtURLMapping{$amtArt}."_save?konfigId=-1&amtId=".$amtID."&amtArt=".$amtArt;
            $method = "POST";
            ($err,$data) = HttpUtils_BlockingGet({
              url => $url,
              timeout => 10,
              method => $method,
              noshutdown => 1,
              header => $header,
              data => $sendData,
            });  
            return "error: Cannot set forwarding number: ".$err.$data if ($err ne "" || $data eq "" || index($data, 'Access Error') > 0);
            Auerwald_getInfoDelayed($hash,"app_msn_aws_list",5);
            return "Successfully set callforwarding to ".$number;
          }
        }
      } elsif ($fwdfor eq "user") {
        #can not be implemented as we do not know the checkboxes which are needed to be handled another way
        #if we active this, we clear the whole config on a save which is not what we want ;)
        #set the forward via user settings
        #first, find the checkboxes in html as they need to have special handling (not sending at all if unchecked, sending if checked)

        my %formfields = Auerswald_getFormFields($baseurl."statics/page_teilnehmer_profil_einzel.html?tnId=".$internalid,$header);

        #######      
        #first, we get everything needed to successful post
        $url = $baseurl."teilnehmer_profil_einzel_state?tnId=".$internalid;
        $method = "GET";
        $sendData = "";
        my($err,$data) = HttpUtils_BlockingGet({
          url => $url,
          timeout => 10,
          method => $method,
          noshutdown => 1,
          header => $header,
          data => $sendData,
        });    
        #{"rufnr":"52","name":"test","typ":2,"tnProfilId":996,"zimmertn":0,"clipinfoeigen":1,"clipdatumeigen":1,"clipsperrzeiteigen":1,"gebuehreneigen":1,"hookeigen":2,"klingelinteigen":0,"amtdiensteigen":5,"amtprivateigen":5,"sperrwgehdienstaktiv":0,"sperrwgehdiensteigen":0,"sperrwgehprivaktiv":0,"sperrwgehpriveigen":0,"freiwgehdienstaktiv":0,"freiwgehdiensteigen":0,"freiwgehprivaktiv":0,"freiwgehpriveigen":0,"kurzwdiensteigen":1,"kurzwprivateigen":1,"vamtdiensteigen":0,"vamtpriveigen":0,"rufueberdiensteigen":1,"rufueberpriveigen":1,"rufuebereigeneigen":1,"anklopfeneigen":0,"anklopfenarteigen":3,"anrufschutzeigen":0,"freiwkommaktiv":0,"freiwkommeigen":0,"sperrwkommaktiv":0,"sperrwkommeigen":0,"awscfxExternOnly":0,"awscfxKaskade":0,"awscfxBeiGrpRuf":0,"zielawssoforteigen":0,"zielawssofortrufnr":"001723456789","zielawsbusyeigen":0,"zielawsbusyrufnr":"","zielawsnichteigen":0,"zielawsnichtrufnr":"","awsbabyeigen":0,"awsbabyrufnr":"","parallelrufeigen":0,"parallelrufnr":"","gebFaktor":"1,00","zielfollowmerufnr":"","css_Style":0,"privatamteigen":1,"maxRssClients":10,"rssClients":0,"rssBoxIds0":0,"rssBoxIds1":0,"rssBoxIds2":0,"rssBoxIds3":0,"vBoxCallTyp":6,"vBoxId":0,"fBoxId":0,"mailBoxInfoRuf":0,"grpannahmeeigen":1,"mankonfigeigen":1,"audioouteigen":0,"tnrelaiseigen":1,"progberechteigen":1,"tueroeffnenzeigen":65535,"amtmsnawseigen":1,"tnawsamteigen":1,"amtanamteigen":1,"betriebsrateigen":0,"grpawseigen":0,"grprueckeigen":1,"amtapparateigen":0,"grpuebernahmeeigen":0,"intercomeigen":0,"tuerappeigen":0,"intwaehleigen":1,"besetztbeiendeeigen":1,"sonderbabyeigen":0,"sondervolleigen":0,"jitterBufSize":50,"echoCancel":1} 
        my $userJSON = Auerswald_DecodeJSON($data);
        $sendData = "";
        if ($number eq "off") {
          delete $userJSON->{zielawssoforteigen};
        } elsif ($number eq "on") {
          $userJSON->{zielawssoforteigen} = "1";
        } else {
          $userJSON->{zielawssoforteigen} = "1";
          $userJSON->{zielawssofortrufnr} = $number;
        }

        $sendData = Auerswald_buildSavePOSTString($userJSON,%formfields);

#        Log3 $name, 3, Dumper $sendData; 
        $url = $baseurl."teilnehmer_profil_einzel_save?tnId=".$internalid;
        $method = "POST";
        #$sendData = "zielawssofortrufnr=$number";
        ($err,$data) = HttpUtils_BlockingGet({
          url => $url,
          timeout => 10,
          method => $method,
          noshutdown => 1,
          header => $header,
          data => $sendData,
        });    

#        Log3 $name, 3, Dumper $data;
        #return $data;
        return "error: Cannot set forwarding number: ".$err.$data if ($err ne "" || $data eq "" || index($data, 'Access Error') > 0);
        return "Successfully set callforwarding to ".$number;
        
        #  return undef;
      }
    } else {
      return "callforward usage: set callForward [msn 1213|user 4916] [0=always|1=busy|2=no answer] on|off|001723456789";
    }
  }
  
  #Activate Config
  if ($cmd eq 'activateConfig') {
    my ($newCfgID) = @args;
    if ($newCfgID) {
      if (defined ($hash->{helper}{pbxconfig}{configs}{$newCfgID})) {
        if (!$hash->{helper}{pbxconfig}{configs}{$newCfgID}{current}) {
          $url = $baseurl."app_konfig_set?configId=".$newCfgID;
          $method = "GET";
          $sendData = "";
          ($err,$data) = HttpUtils_BlockingGet({
            url => $url,
            timeout => 10,
            method => $method,
            noshutdown => 1,
            header => $header,
            data => $sendData,
          });  
          if ($err eq "" && $data ne "" && index($data, 'Access Error') < 0) {
            my $switchJSON = Auerswald_DecodeJSON($data);
            if ($switchJSON->{successful}) { 
              Auerwald_getInfoDelayed($hash,"app_konfig_list",5); # we must wait some time before the webinterface replicate our changes, delay it by 5 seconds
              readingsSingleUpdate($hash,"ActiveConfig","Waiting for switch...",0);
              #return "Successful switched to configuration ID $newCfgID (".$hash->{helper}{pbxconfig}{configs}{$newCfgID}{bezeich}.")";
              return undef;
            } else {
              return "error: Cannot switch configuration, PBX says not successful";
            }
          } else {
            return "error: Cannot switch configuration: ".$err;
          }
        } else {
          return "error: Configuration ID ".$newCfgID." (".$hash->{helper}{pbxconfig}{configs}{$newCfgID}{bezeich}.") already active";
        }
      } else {
         return "error: Configuration ID ".$newCfgID." does not exist";
      }
    } else {
      return "usage: set activateConfig 1234";
    }
  }
  
  if ($cmd eq 'robinson') {
      my ($listID,$action,$number,@name) = @args; #catch remaining args as @name
    if (defined($listID) && defined($action) && defined($number) && $number ne "" && ($action eq "add" || $action eq "del")) {
      #check if listID exists
      my $listIDfound = 0;
      $url = $baseurl."sperrwerke_state?kommend=0";
      $method = "GET";
      $sendData = "";
      my($err,$data) = HttpUtils_BlockingGet({
        url => $url,
        timeout => 10,
        method => $method,
        noshutdown => 1,
        header => $header,
        data => $sendData,
      });    
      #[{"id":"252", "bezeich":"Nervende Nummern"}]
      my $userJSON = Auerswald_DecodeJSON($data);
      #find id for number that user wants to delete
      if (defined($userJSON->[0])) {
        if (defined($userJSON->[0]->{id})) {
          #parse all entries and try to find the number
          foreach my $item( @$userJSON ) {
            if ($item->{id} eq $listID) {
              $listIDfound = 1;
            }
          }
        }
      }      

      if ($listIDfound == 0) {
        my $retErrortxt = "ERROR: Robinson list ID ".$listID." not found.\n";
        $retErrortxt .= "I know the following ID's:\n";
        foreach my $item( @$userJSON ) {
          $retErrortxt .= "ID: ".$item->{id}." Name: ".$item->{bezeich}."\n";
        }
        return $retErrortxt;
      }
      
      if ($action eq "add") {
        if (defined @name) {
          #POST sperrwerkekonfig_save?kommend=0&werkeId=252 => rufnummer=1234567789&name=asdasdasdasd
          $sendData = "rufnummer=".$number."&name=".join(" ",@name);
          
          $url = $baseurl."sperrwerkekonfig_save?kommend=0&werkeId=".$listID;
          $method = "POST";
          ($err,$data) = HttpUtils_BlockingGet({
            url => $url,
            timeout => 10,
            method => $method,
            noshutdown => 1,
            header => $header,
            data => $sendData,
          });    

  #        Log3 $name, 3, Dumper $data;
          #return $data;
          return "error: Cannot add robinson number: ".$err.$data if ($err ne "" || $data eq "" || index($data, 'Access Error') > 0);
          return "Successfully added robinson number ".$number;
        } else {
          return "usage: set robinson <id> add 08912345678 Description";
        }
      }
      #Remove number from list
      if ($action eq "del") {
        my $numberToDeleteID = "";
        #Get ID's for the numbers that are in list
        $url = $baseurl."sperrwerkekonfig_state?kommend=0&werkeId=".$listID;
        $method = "GET";
        $sendData = "";
        my($err,$data) = HttpUtils_BlockingGet({
          url => $url,
          timeout => 10,
          method => $method,
          noshutdown => 1,
          header => $header,
          data => $sendData,
        });    
        #[{"id":"6565", "rufnummer":"040", "name": "werb"},{"id":"780", "rufnummer":"0403", "name": "Stromwerbung"}]
        my $userJSON = Auerswald_DecodeJSON($data);

        #find id for number that user wants to delete
        if (defined($userJSON->[0])) {
          if (defined($userJSON->[0]->{id})) {
            #parse all entries and try to find the number
            foreach my $item( @$userJSON ) {
              if ($item->{rufnummer} eq $number) {
                $numberToDeleteID = $item->{id};
              }
            }
          }
        }
        
        if ($numberToDeleteID ne "") {
          #POST sperrwerkekonfig_save?delete=42&kommend0&werkeId=222 => id_0=9183&tnmarker0=tnmarker0
          $sendData = "id_0=".$numberToDeleteID."&tnmarker0=tnmarker0";
          
          $url = $baseurl."sperrwerkekonfig_save?delete=42&kommend0&werkeId=".$listID;
          $method = "POST";
          ($err,$data) = HttpUtils_BlockingGet({
            url => $url,
            timeout => 10,
            method => $method,
            noshutdown => 1,
            header => $header,
            data => $sendData,
          });    

  #        Log3 $name, 3, Dumper $data;
          #return $data;
          return "error: Cannot remove robinson number: ".$err.$data if ($err ne "" || $data eq "" || index($data, 'Access Error') > 0);
          return "Successfully removed robinson number ".$number;
        } else {
          return "error: Number ".$number." not found.";
        }
      }
    } else {
      return "usage: set robinson <id> [add 08912345678 WerbeNerv]|[del 08912345678]";
    }
  }  
}

###################################
sub
Auerswald_Define($$)
{
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @args = split("[ \t]+", $def);
  
  if (int(@args) < 6)
  {
    return "Invalid number of arguments: define <name> Auerswald <server> <port> <username> <password>";
  }
  #define AuerRaptor Auerswald myip port sub-admin mypassword
  my ($tmp1,$tmp2,$server, $port, $username, $password) = @args;
  
  $hash->{STATE} = 'Initialized';
  
  #defaults:
  $attr{$name}{PollTimer}=30 if (!defined($attr{$name}{PollTimer}));
  
  if(defined($server) && defined($port) && defined($username) && defined($password))
  {    
    $hash->{helper}{server} = $server;
    $hash->{helper}{username} = $username;
    $hash->{helper}{password} = $password;
    $hash->{helper}{port} = $port;

#    Auerswald_CheckConnection($hash) if($init_done);
#    Auerwald_getInfo($hash,"all") if($init_done);
    #remove all internal timers?
    
    my $getType = "standardpoll" if $debug == 1;
    my %parm = ( hash => $hash, timerCmd => $getType );
    #on the define, we give it a second, and let it delay if fhem is not initialized yet, later we use polltimer
    Log3 $name, 3, "Before Polling" if $debug == 1;
    InternalTimer(gettimeofday()+5, "Auerswald_PollMessages", \%parm,0);

    return undef;
  }
  else
  {
    return "define not correct: define <name> Auerswald <server> <port> <username> <password>";
  }  
}

###################################
sub
Auerswald_UnDef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  #$hash->{AuerswaldDevice}->Disconnect();
  return undef;
}

###################################
sub
Auerswald_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	if ($cmd eq "set") {
#	  if ($aName eq "OnlineStatus") {
#	    if (defined($aVal) && defined($hash->{AuerswaldDevice}) && $init_done) {
              #Send Presence type only if we do not want to be available

#      }
#	  }
	}
	return undef;
}
#########################
sub
Auerswald_Get($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $opt_name = shift @a;
  my $opt = shift @a;
  if(!$gets{$opt}) {
		my @cList = keys %gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}  
	my $info = "";
	if ($opt eq "PBXconfig") {
    #PBX Configurations
    if (defined ($hash->{helper}{pbxconfig}{configs})) {
      $info .= sprintf("PBX Configurations\n");
      $info .= sprintf("-------------------------------------------\n");
      $info .= sprintf("%9s | %-15s | %s\n","Config ID","Ident Number","Name / Description");
      foreach my $pbxcfgItem( sort { $a->{identnummer} <=> $b->{identnummer} } values %{$hash->{helper}{pbxconfig}{configs}} ) {
        if (defined($pbxcfgItem->{identnummer})) {
          if ($pbxcfgItem->{current}) {
            $info .= sprintf("%9s | %-15s | %s\n",$pbxcfgItem->{id},$pbxcfgItem->{identnummer},$pbxcfgItem->{bezeich}." (Active config)");
          } else {
            $info .= sprintf("%9s | %-15s | %s\n",$pbxcfgItem->{id},$pbxcfgItem->{identnummer},$pbxcfgItem->{bezeich});
          }
        }
      }
    }
    $info .= sprintf("\n");
        
    #Amt and MSN Config
    foreach my $amtItem( reverse sort { $a->{artText} eq $b->{artText} || $a->{name} eq $b->{name} } values %{$hash->{helper}{pbxconfig}{amt}} ) {
      $info .= sprintf("\nAmt ID: %s, Art: %s, Name: %s, ptpNumber: %s\n", $amtItem->{amtId}, $amtItem->{artText}, $amtItem->{name}, $amtItem->{ptpNumber} ) if ($amtItem->{ptpNumber} ne "");
      $info .= sprintf("\nAmt ID: %s, Art: %s, Name: %s\n", $amtItem->{amtId}, $amtItem->{artText}, $amtItem->{name} ) if ($amtItem->{ptpNumber} eq "");
      $info .= sprintf("-------------------------------------------\n");
      #MSN's
      my @msnMatch = grep { $_->{amtId} eq $amtItem->{amtId} } values %{$hash->{helper}{pbxconfig}{msnaws}};
      if (defined($msnMatch[0])) {
        $info .= sprintf("%9s | %-15s | %-18s | %-16s | %-16s | %s\n","MSN ID","Calling Number","Name / Description", "Fwd Always", "Fwd on Busy", "Fwd no Answer");
        foreach my $msnItem( sort { $a->{rufNummer} <=> $b->{rufNummer}} @msnMatch ) {
          my $awssofortziel = $msnItem->{awssofortziel};
          my $awsbsziel = $msnItem->{awsbsziel};
          my $awsnrziel = $msnItem->{awsnrziel};
          $awssofortziel .= " (*)" if $msnItem->{awssoforttyp} ne "0";
          $awsbsziel .= " (*)" if $msnItem->{awsbstyp} ne "0";
          $awsnrziel .= " (*)" if $msnItem->{awsnrtyp} ne "0";
          $info .= sprintf("%9s | %-15s | %-18s | %-16s | %-16s | %s\n",$msnItem->{msnId},$msnItem->{rufNummer},$msnItem->{name},$awssofortziel,$awsbsziel,$awsnrziel);
        }
      }
    }
    $info .= sprintf("\n");

    #Hardware Modules
    if (defined ($hash->{helper}{pbxconfig}{modules})) {
      $info .= sprintf("Hardware Modules\n");
      $info .= sprintf("-------------------------------------------\n");
      $info .= sprintf("%9s | %-15s | %s\n","Module ID","Module Type","Name / Description");
      foreach my $moduleItem( sort { $a->{key} <=> $b->{key} } values %{$hash->{helper}{pbxconfig}{modules}} ) {
        if (defined($moduleItem->{modType}) && defined($moduleItem->{value})) {
          $info .= sprintf("%9s | %-15s | %s\n",$moduleItem->{key},$moduleItem->{modType},$moduleItem->{value});
        }
      }
    }
    $info .= sprintf("\n");


    #Teilnehmer / Users
    if (defined ($hash->{helper}{pbxconfig}{teilnehmer})) {
      $info .= sprintf("Configured Users / Teilnehmer\n");
      $info .= sprintf("-------------------------------------------\n");
      $info .= sprintf("%9s | %-15s | %s\n","Tn ID","Amt Number","Name / Description");
      foreach my $tnItem( sort { $a->{amtrufn} <=> $b->{amtrufn} } values %{$hash->{helper}{pbxconfig}{teilnehmer}} ) {
        if (defined($tnItem->{id}) && defined($tnItem->{amtrufn})) {
          $info .= sprintf("%9s | %-15s | %s\n",$tnItem->{id},$tnItem->{amtrufn},$tnItem->{bezeich});
        }
      }
    }
    $info .= sprintf("\n");
    
	}
	return $info;
  
}
###################################
sub
Auerswald_PollMessages($)
{
  my ($parm)=@_;
  my $hash = $parm->{hash};
  my $timerCmd = $parm->{timerCmd};
  my $name = $hash->{NAME};
  my $connectiondied = 0;
  Log3 $name, 3, "PollMessages" if $debug == 1;
  #RemoveInternalTimer($parm);
  
#  if(!$init_done) {
#    InternalTimer(gettimeofday()+$attr{$name}{PollTimer}, "Auerswald_PollMessages", $parm,0);  
#    return undef; # exit if FHEM is not ready yet.
#  }
  
  #log 3, "$hash->{NAME} Poll End" if $debug;
  
  #check if our cookie is still alive
  #Log3 $name, 3, Dumper $hash;
  if (Auerswald_CheckConnection($hash)) {
    Auerwald_getInfo($hash,"app_ext_ports_status");
		Auerwald_getInfo($hash,"app_konfig_list");
  }

  InternalTimer(gettimeofday()+$attr{$name}{PollTimer}, "Auerswald_PollMessages", $parm,0);
  return undef;
}

sub Auerswald_Request($) {
  
}
sub Auerswald_CheckConnection($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  #If we have a session cookie and username and it still matches our define
  if (ReadingsVal($name,"cookieSession","") ne "" && ReadingsVal($name,"cookieUser","") ne "" && $hash->{helper}{username} eq ReadingsVal($name,"cookieUser","")) {
    #check if we still have the correct session cookie
    my $url = "http://". $hash->{helper}{server} .":". $hash->{helper}{port}. "/languages_all";
    my $method = "GET";
    my $header = "Cookie: AUERSessionID=" . ReadingsVal($name,"cookieSession","") ."; AUERWEB_COOKIE=". ReadingsVal($name,"cookieUser","");
    my $sendData = "";
       
    my($err,$data) = HttpUtils_BlockingGet({
      url => $url,
      timeout => 4,
      method => $method,
      noshutdown => 1,
      header => $header,
      data => $sendData,
    });
    
    #If we get an access error, our cookie is dead...
    if (index($data, 'Access Error: Forbidden') != -1) {
          $hash->{STATE} = "Disconnected";
          $hash->{CONN} = "Cookie is dead";
          Auerswald_SubmitLogin($hash);
          return 0;
    } else {
          #Else we update the state and CONN to reflect our status
          #update initial info on first start of module
          if (!defined($hash->{Pbx}) || $hash->{STATE} eq "Initialized" ) {
            $hash->{STATE} = "Connected";
            $hash->{CONN} = "Successfully connected as user ". ReadingsVal($name,"cookieUser","");            
            Auerwald_getInfo($hash,"all");
          }
    }
  } else {
    #submit a login request
    Auerswald_SubmitLogin($hash);
    return 0;
  }
  return 1;
}  

#Executes a API Login and stores the Cookie
sub
Auerswald_SubmitLogin($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $url = "http://". $hash->{helper}{server} .":". $hash->{helper}{port}. "/login_json";
  my $method = "POST";
  my $header = "Content-Type: application/x-www-form-urlencoded";
  my $obj = "LOGIN_NOW=&LOGIN_NAME=". $hash->{helper}{username} ."&LOGIN_PASS=". $hash->{helper}{password};

  my $param = {
    url        => $url,
    timeout    => 5,
    hash       => $hash,
    method     => $method,
    data       => $obj,
    header     => $header,  
    callback   =>  \&Auerswald_CallbackLogin
  };

  HttpUtils_NonblockingGet($param);   

  return undef;
}

sub Auerswald_CallbackLogin($)
{

    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $header = $param->{httpheader};
      Log3 $name, 3, "url ".$param->{url}." returned: $data"  if $debug == 1;
#      Log3 $name, 3, Dumper $param;
      
          
    if($err ne "" || index($data, '"login":') == -1) # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
      $hash->{STATE} = "Connection error";
      
      #We try to parse the error message
      if ($data ne "") {
        my $errorJSON = Auerswald_DecodeJSON($data);
		    #Check if we're already logged in..
		    if (defined($errorJSON->[1]) && defined($errorJSON->[1]->{'finished'})) {
		      if ($errorJSON->[1]->{'finished'} eq "true") {
		        #We are already logged in but didn't have our cookie, we try to logout the other
		        ##[{"type":"error","text":"Hinweis: Das von Ihnen angegebene Passwort wird zur Zeit in der TK-Anlage verwendet. Wenden Sie sich bitte an Ihren Systemadministrator, um dieses Problem zu beheben!"},{"finished":"true"}]    
            $hash->{CONN} = $errorJSON->[0]->{text};
		      }
		    }
		    #Log3 $name, 3, Dumper $errorJSON;
        
      } else {
        Log3 $name, 3, "error while requesting ".$param->{url}." - $err";
        $hash->{CONN} = "Username or Password wrong";
      }
      #TODO: Reading interval abrechen
    } else {
      #Login seems to be successful, we save the cookie for later requests
      if( index($header, 'Set-Cookie: AUERSessionID=') > 0 ){
        my @result_headers = split(/\n/, $header);
        my $tmp_session = (grep {/Set-Cookie: AUERSessionID=/i} @result_headers)[0];
        #Save this as readings so we persist over restarts
        readingsSingleUpdate($hash, "cookieSession", substr($tmp_session, length('Set-Cookie: AUERSessionID=')) ,0 );
    	}
    	if( index($header, 'Set-Cookie: AUERWEB_COOKIE=') > 0 )
    	{
    		my @result_headers = split(/\n/, $header);
    		my $tmp_webuser = (grep {/Set-Cookie: AUERWEB_COOKIE=/i} @result_headers)[0];
    		#Save this as readings so we persist over restarts
    		readingsSingleUpdate($hash, "cookieUser", substr($tmp_webuser, length('Set-Cookie: AUERWEB_COOKIE=')),0 );
    	}
    	
    	#if we now have the cookie data, double check it, and we're save!
    	if ( ReadingsVal($name,"cookieSession","") ne "" && ReadingsVal($name,"cookieUser","") ne "" ) {
    	  $hash->{STATE} = "Connected";
    	  $hash->{CONN} = "Successfully connected as user ". ReadingsVal($name,"cookieUser","");
    	}
		  #my $res = Auerswald_DecodeJSON($data);
		  #Log3 $name, 3, Dumper $res;
      #initialize some things
      Auerwald_initAfterConnect($hash);
      
      #now -initially- get every piece of info about the phonebox
		  Auerwald_getInfo($hash,"all");
    }
}

sub Auerwald_getInfoDelayed($$$) {
      my ($hash,$getType, $delay) = @_;
      my $name = $hash->{NAME};
      my %parm = ( hash => $hash, timerCmd => $getType );
      Log3 "blah", 3, "getinfoDelayed: $getType $delay"  if $debug == 1;
      InternalTimer(gettimeofday() + $delay, "Auerwald_getInfoDelayed_do", \%parm, 0);      
    }
sub Auerwald_getInfoDelayed_do($)
{
  my ($parm)=@_;
  Log3 "blah", 3, "InfoDelayed_do";
  Auerwald_getInfo($parm->{hash}, $parm->{timerCmd});
}

#one-time initialize after connection:
sub Auerwald_initAfterConnect($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 "blah", 3, "initAfterConnect called."  if $debug == 1;

  #These commands must be done before anything other can work (it updates the IDs and baseinfo needed for this module to work)
  my $baseurl = "http://". $hash->{helper}{server} .":". $hash->{helper}{port}. "/";

  my $method = "GET";
  my $header = "Cookie: AUERSessionID=" . ReadingsVal($name,"cookieSession","") ."; AUERWEB_COOKIE=". ReadingsVal($name,"cookieUser","");
  my $sendData = "";
  my $refCommand = "";
  my $url = "";

  #Set Calllist to 10 Entries with no filter
  HttpUtils_BlockingGet({
    url => $baseurl."page_listgespr_save?linepropage=10&filterCB=0",
    timeout => 10,
    method => $method,
    noshutdown => 1,
    header => $header,
    data => $sendData,
  });   
}
    
sub Auerwald_getInfo($$) {
      my ($hash,$getType) = @_;
      my $name = $hash->{NAME};
      Log3 "blah", 3, "getinfo called: $getType"  if $debug == 1;

      #These commands must be done before anything other can work (it updates the IDs and baseinfo needed for this module to work)
      my $baseurl = "http://". $hash->{helper}{server} .":". $hash->{helper}{port}. "/";

      my $method = "GET";
      my $header = "Cookie: AUERSessionID=" . ReadingsVal($name,"cookieSession","") ."; AUERWEB_COOKIE=". ReadingsVal($name,"cookieUser","");
      my $sendData = "";
      my $refCommand = "";
      my $url = "";

    #get infos and status
    if ($getType eq "all") {
      delete $hash->{helper}{pbxconfig};
    }
    if ($getType eq "all" || $getType eq "app_about") {
      #PBX Info
      $url = $baseurl. "app_about";      
      $refCommand = "app_about";
      HttpUtils_NonblockingGet({ url => $url, timeout => 5, hash => $hash, method => $method, header => $header, data => $sendData, callback   => \&Auerswald_CallbackHTTPRequest, command => $refCommand });
		
		}
		
		if ($getType eq "all" || $getType eq "app_amt_list") {  
		  #"Aemter"
		  $url = $baseurl. "app_amt_list";
		  $refCommand = "app_amt_list";
      HttpUtils_NonblockingGet({ url => $url, timeout => 5, hash => $hash, method => $method, header => $header, data => $sendData, callback   => \&Auerswald_CallbackHTTPRequest, command => $refCommand });
    
    }
    
    if ($getType eq "all" || $getType eq "app_konfig_list") { 
		  #"Configurations"
		  $url = $baseurl. "app_konfig_list";
      $refCommand = "app_konfig_list";
      HttpUtils_NonblockingGet({ url => $url, timeout => 5, hash => $hash, method => $method, header => $header, data => $sendData, callback   => \&Auerswald_CallbackHTTPRequest, command => $refCommand });
	  
	  }
	  
	  if ($getType eq "all" || $getType eq "app_msn_aws_list") {
		  #"MSN And Call forwarding table"
      $url = $baseurl. "app_msn_aws_list";
      $refCommand = "app_msn_aws_list";
      HttpUtils_NonblockingGet({ url => $url, timeout => 5, hash => $hash, method => $method, header => $header, data => $sendData, callback   => \&Auerswald_CallbackHTTPRequest, command => $refCommand });
    
    }
    
    if ($getType eq "all" || $getType eq "teilnehmereinzel_allModules") {		  
		  #"Modules"
      $url = $baseurl. "teilnehmereinzel_allModules";
      $refCommand = "teilnehmereinzel_allModules";
      HttpUtils_NonblockingGet({ url => $url, timeout => 5, hash => $hash, method => $method, header => $header, data => $sendData, callback   => \&Auerswald_CallbackHTTPRequest, command => $refCommand });

		}
		
		if ($getType eq "all" || $getType eq "tn_eigenschaften_state") {   
		  #"Teilnehmer"
      $url = $baseurl. "tn_eigenschaften_state";
      $refCommand = "tn_eigenschaften_state";
      HttpUtils_NonblockingGet({ url => $url, timeout => 5, hash => $hash, method => $method, header => $header, data => $sendData, callback   => \&Auerswald_CallbackHTTPRequest, command => $refCommand });
		}

		if ($getType eq "app_ext_ports_status") {   
      #Recurring External Port status
      $url = $baseurl. "app_ext_ports_status";
      $refCommand = "app_ext_ports_status";
      HttpUtils_NonblockingGet({ url => $url, timeout => 5, hash => $hash, method => $method, header => $header, data => $sendData, callback   => \&Auerswald_CallbackHTTPRequest, command => $refCommand });
    }

    if ($getType eq "all" || $getType eq "page_listgespr_state") {   
		  #Recurring "Anrufliste"
      $url = $baseurl. "page_listgespr_state?offset=0";
      $refCommand = "page_listgespr_state";
      HttpUtils_NonblockingGet({ url => $url, timeout => 5, hash => $hash, method => $method, header => $header, data => $sendData, callback   => \&Auerswald_CallbackHTTPRequest, command => $refCommand });
		}
    
		return undef;
}

sub Auerswald_CallbackHTTPRequest($)
{

    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $header = $param->{httpheader};
    my $refCommand = $param->{command}; #find what we have called
    my $infoJSON = "";
    my @incrementalGotVals = (); #used for incrementally deleting things we didn't got to not mess up everything
    
#    Log3 $name, 3, Dumper $refCommand;
#    Log3 $name, 3, Dumper $err;
#    Log3 $name, 3, Dumper $data;
    if ($err eq "" && $data ne "" && index($data, 'Access Error') < 0 ) {
      if ($refCommand eq "app_about") {
      my $infoJSON = Auerswald_DecodeJSON($data);
		  #if we have some json info..
		  if (defined($infoJSON->{pbx})) {
          $hash->{Pbx} = $infoJSON->{pbx};
          $hash->{Pbx_Ver} = $infoJSON->{version};
          $hash->{Pbx_Serial} = $infoJSON->{serial};
          $hash->{Pbx_MAC} = $infoJSON->{macaddr};
          $hash->{Pbx_DongleSN} = $infoJSON->{donglesn};
        }
		  } elsif ($refCommand eq "app_konfig_list") {
        $infoJSON = Auerswald_DecodeJSON($data);
        #[{"id":34,"bezeich":"Konfig-1","identnummer":"201","current":true}]
        if (defined($infoJSON->[0])) {
          if (defined($infoJSON->[0]->{id})) {
            #store all external ports
            foreach my $item( @$infoJSON ) {
              push @incrementalGotVals,$item->{id};
              
              $hash->{helper}{pbxconfig}{configs}{$item->{id}} = $item;
              #$hash->{helper}{pbxconfig}{idtype}{$item->{id}} = "configs";
              if ($item->{current}) {
                readingsSingleUpdate($hash,"ActiveConfig", $item->{id}." (".$item->{identnummer}."/".$item->{bezeich}.")",1) if (ReadingsVal($name, "ActiveConfig", undef) ne $item->{id}." (".$item->{identnummer}."/".$item->{bezeich}.")");
              }
            }       
            Auerswald_IncrementalRemove($hash,"configs",\@incrementalGotVals);   
          }
        }	      
      } elsif ($refCommand eq "app_msn_aws_list") {
        
        $infoJSON = Auerswald_DecodeJSON($data);
        #[{"msnId":9600,"amtId":9890,"name":"","rufNummer":"919191","awssoforttyp":0,"awssofortziel":"","awsnrtyp":0,"awsnrziel":"","awsbstyp":0,"awsbsziel":""},...]
        if (defined($infoJSON->[0])) {
          if (defined($infoJSON->[0]->{msnId})) {
            #MSN and AWS
            foreach my $item( @$infoJSON ) {
              push @incrementalGotVals,$item->{msnId};
              #store the data in msnaws
              $hash->{helper}{pbxconfig}{msnaws}{$item->{msnId}} = $item;
              #$hash->{helper}{pbxconfig}{idtype}{$item->{msnId}} = "msnaws";
            }          
            Auerswald_IncrementalRemove($hash,"msnaws",\@incrementalGotVals);
          }
        }		  
      } elsif ($refCommand eq "app_amt_list") {
        $infoJSON = Auerswald_DecodeJSON($data);
        #[{"amtId":9890, "name":"","ptpNumber":"","art":1},{"amtId":8604, "name":"5505.01","ptpNumber":"","art":2}]
        if (defined($infoJSON->[0])) {
          if (defined($infoJSON->[0]->{amtId})) {
            #store all external ports
            foreach my $item( @$infoJSON ) {
              push @incrementalGotVals,$item->{amtId};
              $hash->{helper}{pbxconfig}{amt}{$item->{amtId}} = $item;
              $hash->{helper}{pbxconfig}{amt}{$item->{amtId}}{artText} = $amtart{$item->{art}};
              #$hash->{helper}{pbxconfig}{idtype}{$item->{amtId}} = "amt";
            }
            Auerswald_IncrementalRemove($hash,"amt",\@incrementalGotVals); 
          }
        }
  		} elsif ($refCommand eq "app_ext_ports_status") {
        my $infoJSON = Auerswald_DecodeJSON($data);
  		  #{"amtId":"9890","anschlArt":"1","bKanalGesperrt":"0","bKanalStatus":"0","moduleId":"5","portId":"3709","portNr":"0"},
  		  #{"amtId":"9890","anschlArt":"1","bKanalGesperrt":"0","bKanalStatus":"2","moduleId":"5","portId":"3709","portNr":"0"},
  		  #{"amtId":"0","anschlArt":"2","bKanalGesperrt":"0","bKanalStatus":"0","moduleId":"1","portId":"9621","portNr":"1"},
  		  #{"amtId":"0","anschlArt":"2","bKanalGesperrt":"0","bKanalStatus":"0","moduleId":"1","portId":"9621","portNr":"1"}]
        if (defined($infoJSON->[0])) {
          if (defined($infoJSON->[0]->{amtId})) {
            #store readings for external ports
            my $inc = 1;
            my $setvalue = "";
            
            foreach my $item( @$infoJSON ) {
              #Amtid for VoiP is 0? error?
              if ($item->{bKanalGesperrt} ne "0") {
                $setvalue = "blocked";
              } elsif ($item->{bKanalStatus} ne "0") {
                $setvalue = "inuse";
              } else {
                $setvalue = "free";
              }
              
              #update only if things changed
              if (ReadingsVal($name, "Ext-".$inc."-".$amtart{$item->{anschlArt}}, undef) ne $setvalue) {
                readingsSingleUpdate($hash,"Ext-".$inc."-".$amtart{$item->{anschlArt}},$setvalue,1);
                
                if ($setvalue eq "free") {
                  #update Call-list if channel goes to "free" and has changed, we must give the PBX 10 seconds to save the call
                  Auerwald_getInfoDelayed($hash,"page_listgespr_state",10);
                }

              }               
              
              
              $inc++;
            }
          }
        }
  		} elsif ($refCommand eq "tn_eigenschaften_state") {
        $infoJSON = Auerswald_DecodeJSON($data);
        #[{"id":"3180","amtrufn":"20","bezeich":"Mein Analog","btnconfig":"Konfigurieren"},...]
        if (defined($infoJSON->[0])) {
          if (defined($infoJSON->[0]->{id})) {
            #store all external ports
            foreach my $item( @$infoJSON ) {
              push @incrementalGotVals,$item->{id};
              $hash->{helper}{pbxconfig}{teilnehmer}{$item->{id}} = $item;
            }
            Auerswald_IncrementalRemove($hash,"teilnehmer",\@incrementalGotVals); 
          }
        }
      } elsif ($refCommand eq "teilnehmereinzel_allModules") {
        $infoJSON = Auerswald_DecodeJSON($data);
        #[{"key":"0","value":"- kein Modul -","class":""},{"key":"1", "value":"VoIP-Modul", "modType":"voip"},...]
        if (defined($infoJSON->[0])) {
          if (defined($infoJSON->[0]->{key})) {
            #store all external ports
            foreach my $item( @$infoJSON ) {
              push @incrementalGotVals,$item->{key};
              $hash->{helper}{pbxconfig}{modules}{$item->{key}} = $item;
              #$hash->{helper}{pbxconfig}{idtype}{$item->{key}} = "modules";
            }
            Auerswald_IncrementalRemove($hash,"modules",\@incrementalGotVals);             
          }
        }
      } elsif ($refCommand eq "page_listgespr_state") {
        #Anrufliste
        $infoJSON = Auerswald_DecodeJSON($data);
        #[   0       1         2           3      4       5                 6          7        8           9            10       11      12      13        14         15              16     17 18    19
        #  ["1","29.12.16","15:48:03","00:00:07","","015123456789",""               ,"8701","911111",      "20","xxxx Analog","911111","0,0000","1,00","kommend"," erfolgr.",       "normal","","0","9138"],
        #  ["2","29.12.16","15:03:57","00:02:30","","071234567890","xxxxxxx, xxxxxxx","8701","912222",      "20","xxxx Analog","912222","0,0000","1,00","kommend"," erfolgr.",       "normal","","0","9137"],
        #  ["16","28.12.16","13:07:04","00:06:37","","1234",       "xxxx, xxxxxxx",  "22",  "xxxxx Analog","22","xxxxx Analog","912222","0,0000","1,00","gehend","dienstl. erfolgr.","normal","","0","9123"],...
        #]
        if (defined($infoJSON->[0])) {
          my $callrow = $infoJSON->[0];
          
          if (ReadingsVal($name, "call_id", "") ne $callrow->[19]) {

            #Simulate callmonitor reading for FB_Calllist
            #only update reading if the call_id is new
            readingsBeginUpdate($hash);
            
            # <li><b>event</b> (call|ring|connect|disconnect) - Welches Event wurde genau ausgel&ouml;st. ("call" =&gt; ausgehender Rufversuch, "ring" =&gt; eingehender Rufversuch, "connect" =&gt; Gespr&auml;ch ist zustande gekommen, "disconnect" =&gt; es wurde aufgelegt)</li>
            # <li><b>direction</b> (incoming|outgoing) - Die Anruf-Richtung ("incoming" =&gt; eingehender Anruf, "outgoing" =&gt; ausgehender Anruf)</li>
            # <li><b>external_number</b> - Die Rufnummer des Gegen&uuml;bers, welcher anruft (event: ring) oder angerufen wird (event: call)</li>
            # <li><b>external_name</b> - Das Ergebniss der R&uuml;ckw&auml;rtssuche (sofern aktiviert). Im Fehlerfall kann diese Reading auch den Inhalt "unknown" (keinen Eintrag gefunden) enthalten. Im Falle einer Zeit&uuml;berschreitung bei der R&uuml;ckw&auml;rtssuche und aktiviertem Caching, wird die Rufnummer beim n&auml;chsten Mal erneut gesucht.</li>
            # <li><b>internal_number</b> - Die interne Rufnummer (Festnetz, VoIP-Nummer, ...) auf welcher man angerufen wird (event: ring) oder die man gerade nutzt um jemanden anzurufen (event: call)</li>
            # <li><b>internal_connection</b> - Der interne Anschluss an der Fritz!Box welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren (FON1, FON2, ISDN, DECT, ...)</li>
            # <li><b>external_connection</b> - Der externe Anschluss welcher genutzt wird um das Gespr&auml;ch durchzuf&uuml;hren  ("POTS" =&gt; analoges Festnetz, "SIPx" =&gt; VoIP Nummer, "ISDN", "GSM" =&gt; Mobilfunk via GSM/UMTS-Stick)</li>
            # <li><b>call_duration</b> - Die Gespr&auml;chsdauer in Sekunden. Dieser Wert wird nur bei einem disconnect-Event erzeugt. Ist der Wert 0, so wurde das Gespr&auml;ch von niemandem angenommen.</li>
            # <li><b>call_id</b> - Die Identifizierungsnummer eines einzelnen Gespr&auml;chs. Dient der Zuordnung bei zwei oder mehr parallelen Gespr&auml;chen, damit alle Events eindeutig einem Gespr&auml;ch zugeordnet werden k&ouml;nnen</li>
            # <li><b>missed_call</b> - Dieses Event wird nur generiert, wenn ein eingehender Anruf nicht beantwortet wird. Sofern der Name dazu bekannt ist, wird dieser ebenfalls mit angezeigt.</li>
            # </ul>
            
            $callrow->[3] =~ m/((?<hour>\d+):)((?<min>\d+):)((?<sec>\d+))/x;
            my $call_duration_secs = (($+{'hour'} * 60) * 60 ) + ($+{'min'} * 60) + $+{'sec'};    

            my $callid = $callrow->[19];
            my $direction = ($callrow->[14] eq "kommend" ? "incoming" : "outgoing");
            my $external_number = $callrow->[5];
            my $external_name = ($callrow->[6] ne "" ? $callrow->[6] : "unknown");
            my $internal_number = $callrow->[11];
            my $internal_connection = $callrow->[10];
            my $external_connection = "";
            my $call_duration = ($callrow->[15] eq " vergebl." ? 0 : $call_duration_secs);
            my $missed_call = $external_number.($external_name ne "unknown" ? " (".$external_name.")" : "");
            
            readingsBulkUpdate($hash, "event", ($callrow->[14] eq "kommend" ? "ring" : "call"));
            readingsBulkUpdate($hash, "call_id", $callid);
            readingsBulkUpdate($hash, "direction", $direction);
            readingsBulkUpdate($hash, "external_number", $external_number);
            readingsBulkUpdate($hash, "external_name", $external_name);
            readingsBulkUpdate($hash, "internal_number", $internal_number);
            readingsBulkUpdate($hash, "internal_connection", $internal_connection);
            #readingsBulkUpdate($hash, "external_connection", $external_connection);
            readingsEndUpdate($hash, 1);

            if ($call_duration > 0) {
              readingsBeginUpdate($hash);
              readingsBulkUpdate($hash, "event", "connect");
              readingsEndUpdate($hash, 1);
            }
            
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "event", "disconnect");
            readingsBulkUpdate($hash, "call_duration", $call_duration);
            if ($call_duration <= 0) {
              readingsBulkUpdate($hash, "missed_call", $missed_call);
            }
       
            readingsEndUpdate($hash, 1);
        
          }
        }
      }
    }
}

#Incrementally delete things we did not got to clean up the hashes and readings on every update call
#Auerswald_IncrementalRemove($hash,"msnaws",@incrementalGotVals);
sub Auerswald_IncrementalRemove($$$)
{
    my ($hash, $hashtype, $incrementalGotVals) = @_;
    my $name = $hash->{NAME};
    my @idsNotFound;
    #map array to a hash
    my %incrementalGot = map { $_ => 1 } @{$incrementalGotVals};

    #configs msnaws amt teilnehmer modules
    #Find items that dont exists
    foreach my $item( keys %{$hash->{helper}{pbxconfig}{$hashtype}}) {
      if(!exists($incrementalGot{$item})) {
        push @idsNotFound,$item;
      }
    }
    
    #delete readings for specific types
    if ($hashtype eq "msnaws") {
     #remove the readings 
    }
    #delete the data in our hash
    delete $hash->{helper}{pbxconfig}{$hashtype}{$_} foreach (@idsNotFound);
}              
sub Auerswald_DecodeJSON($) 
{
  my ($ret) = @_;
  #return HUEBridge_ProcessResponse($hash,decode_json($ret)) if( HUEBridge_isFritzBox() );

  return from_json($ret);  
}

sub Auerswald_getFormFields($$) {
  my ($url,$header) = @_;
  my $method = "GET";
  my $sendData = "";
  my %formfields;
  
  my($err,$data) = HttpUtils_BlockingGet({
    url => $url,
    timeout => 10,
    method => $method,
    noshutdown => 1,
    header => $header,
    data => $sendData,
  });
  
  #Log3 $name, 3, Dumper $data;
  #we need to simulate the form tags as the original html page don't have one (sic!)
  my @forms = HTML::Form->parse("<form>".$data."</form>",$url);
  #now find all checkboxes and put to array
  foreach my $form (@forms) {
    my @fields = $form->inputs;
    foreach my $input (@fields) {
      $formfields{$input->type()}{$input->name()} = 1;
    }
  }
  return %formfields;
}
sub Auerswald_buildSavePOSTString($$) {
  my ($userJSON,%formfields) = @_;
  my $sendData = "";
  
  #modify checkboxes
  foreach my $usercfgItem( keys %{$userJSON} ) {
    #if the item is a checkbox
    if ( exists $formfields{"checkbox"}{$usercfgItem} ) {
      #if it is turned off, delete the item
      if ($userJSON->{$usercfgItem} eq "0") {
        delete $userJSON->{$usercfgItem};
      } else {
        #if it is turned on, set the name as value
        $userJSON->{$usercfgItem} = $usercfgItem;             
      }
    }
  }
  #build the POST string
  $sendData = "undefined=0";
  foreach my $usercfgItem( keys %{$userJSON} ) {
     $sendData .= "&".$usercfgItem."=".$userJSON->{$usercfgItem};
  }
  return $sendData;
}
1;


=pod
=item device
=item summary configure and monitor the Auerswald PBX 5010/5020
=item summary_DE konfiguriert und Ueberwacht die Auerswald 5010/5020 Telefonanlage
=begin html

<a name="Auerswald"></a>
<h3>Auerswald</h3>
<ul>
  See german description for now...<br>
  <br> 
  <a name="AuerswaldDefine"></a>
  <b>Define</b>
  <ul>
  </ul>
  <br>
  <a name="AuerswaldSet"></a>
  <b>Set</b>
  <ul>
  </ul>  
  <br>
  <a name="AuerswaldGet"></a>
  <b>Get</b> 
  <ul>
    <li>N/A</li>
  </ul>
  <br>
  <a name="AuerswaldAttr"></a>
  <b>Attributes</b>
  <ul>
  </ul>
  <br>
  <a name="AuerswaldEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
  <br>
  <a name="AuerswaldNotes"></a>
  <b>Author's Notes:</b>
    <ul>
    </ul>    
</ul>
=end html
=begin html_DE

<a name="Auerswald"></a>
<h3>Auerswald</h3>
<ul>
  <br>
  Es muss in der Auserwaldanlage ein sub-admin angelegt werden und dieses Modul mitt mit dem Passwort ausgestattet werden:<br>
  In der Anlage unter "Administration" -> "Benutzer-PINs/Passwoerter" einen user anlegen und ein haekchen bei "sub-admin" machen.<br>
  Das Passwort dahinter ist das Passwort, dass man hier angeben muss.
  <br>
  <a name="AuerswaldDefine"></a>
  <b>Define</b>
  <ul> 	
   <code>define &lt;name&gt; Auerswald &lt;ip&gt; &lt;port&gt; &lt;username&gt; &lt;password&gt;</code><br>
   <br>
   <code>define &lt;name&gt; Auerswald &lt;ip&gt; 80 sub-admin thepassword</code><br>
  </ul>
  <br>
  <a name="AuerswaldSet"></a>
  <b>Set</b>
  <ul>
    <li>
      <code>set &lt;name&gt; activateConfig &lt;configID&gt; &lt;msg&gt;</code>
      <br>
      Aktiviert eine Anlagenkonfiguration. Die entsprechende ID kann über den Get-Befehl PBXconfig herausgefunden werden.
      <br>
      Beispiel:
      <ul>
        <code>set AuersPBX activateConfig 1234 </code><br>
      </ul>
    </li>
    <br>
    <li>
      <code>set &lt;name&gt; callForward &lt;msnID/userID&gt; &lt;0=always/1=busy/2=no answer&gt; &lt;on/off/nummer&gt;</code>
      <br>
      Aktiviert oder Loescht ein callforward fuer eine MSN oder einen bestimmten Teilnehmer.<br>
      Die entsprechenden IDs koennen ueber den Get-Befehl PBXconfig herausgefunden werden.<br>
      <b>Achtung - Null (0) an die Nummer voranstellen!</b>
      <br>
      Beispiel:
      <ul>
        MSN ID 1213 immer (0) an 0172123456789 weiterleiten: <br>
        <code>set AuersPBX msn 1213 0 00172123456789</code><br>
        Vorhandene Weiterleitung fuer MSN ID 1213 immer (0) aktivieren: <br>
        <code>set AuersPBX msn 1213 0 on</code><br>
        MSN ID 1213 bei besetzt (1) an 0172123456789 weiterleiten: <br>
        <code>set AuersPBX msn 1213 1 00172123456789</code><br>
        Teilnehmer ID 4916 immer (0) an 0172123456789 weiterleiten: <br>
        <code>set AuersPBX user 1213 0 00172123456789</code><br>        
      </ul>
    </li>  
    <br>
    <li>
      <code>set &lt;name&gt; robinson &lt;listID&gt; add/del &lt;nummer&gt; &lt;beschreibung&gt;</code>
      <br>
      Fuegt eine Nummer dem Sperrwerk(kommend) mit entsprechender ID hinzu oder Loescht diese davon..<br>
      Die entsprechenden IDs der Sperrwerke kann man ueber Get PBXconfig einsehen (noch nicht implementiert, sorry).<br>
      <br>
      Beispiel:
      <ul>
        <code>set AuersPBX robinson 1 add 08912345678 NervWerbung</code><br>
        <code>set AuersPBX robinson 1 del 08912345678</code><br>
      </ul>
    </li>  
    <li>
      <code>set &lt;name&gt; clearReadings</code>
      <br>
      Loescht alle Readings.<br>
      <br>
      Beispiel:
      <ul>
        <code>set AuersPBX clearReadings</code><br>
      </ul>
    </li>     
  </ul>
  <br>
  <b>Get</b> 
  <ul>
    <code>get &lt;name&gt; PBXconfig</code><br>
    Zeigt alle geladenen Konfigurationdaten an, z.B. aktivierte externe Kanäle und eingestellte Teilnehmer<br>
    diese Informationen werden fuer verschiedene Set Kommandos benoetigt
  </ul>
  <br>
  <a name="AuerswaldAttr"></a>
  <b>Attribute</b>
  <ul>
  </ul>
  <br>
  <a name="AuerswaldEvents"></a>
  <b>Generierte events:</b>
  <ul>
     N/A
  </ul>
  <br>
  <a name="AuerswaldNotes"></a>
  <b>Notizen des Entwicklers:</b>
    <ul>
    </ul>    
</ul>
=end html_DE
=cut
