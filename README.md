# 70_Tvheadend.pm
Ein FHEM-Modul für die Tvheadend JSON-API

## define

`define <name> Tvheadend <IP>:[<PORT>] [<USERNAME> <PASSWORD>]`

Example: `define tvheadend Tvheadend 192.168.0.10`\
Example: `define tvheadend Tvheadend 192.168.0.10 max securephrase`

When \<PORT\> is not set, the module will use Tvheadends standard port 9981.
If the definition is successfull, the module will automatically query the EPG
for tv shows playing now and next. The query is based on Channels mapped in Configuration/Channel.
The module will automatically query again, when a tv show ends.

For further help, see commandref.
