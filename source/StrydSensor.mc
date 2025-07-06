// FOUND ON GARMIN'S FORUM
// https://forums.garmin.com/developer/connect-iq/f/discussion/251742/how-to-acquire-stryd-s-power-data?ReplySortBy=CreatedDate&ReplySortOrder=Ascending
using Toybox.Ant;
using Toybox.Time;
using Toybox.System;


(:release) function strydmsg(msg as Toybox.Lang.String, data as Toybox.Lang.Object or Null) as Void {} //#!JFS!#
(:debug) function strydmsg(msg as Toybox.Lang.String) as Void { 
    var myTime = System.getClockTime(); // ClockTime object
    System.println(
        myTime.hour.format("%02d") + ":" +
        myTime.min.format("%02d") + ":" +
        myTime.sec.format("%02d") + ": " + msg
        );
} //#!JFS!#


class StrydSensor extends Ant.GenericChannel {
    var searching;
    var failedInit = false;
    var searchingCount = 0;

	var currentPower = -9; //null

    const PAGE_NUMBER = 0x10;

    var deviceNumber;

    function initialize(devNumber) {
        strydmsg("Create StrydSensor, antId:" + devNumber);
    	if (devNumber < 0)
    	{
    		return;
    	}
    	deviceNumber = devNumber;
        init();
        //let our caller open us
        //open();
    }

    function init() {
        var chanAssign = new Ant.ChannelAssignment(
            Toybox.Ant.CHANNEL_TYPE_RX_NOT_TX /*Ant.CHANNEL_TYPE_RX_NOT_TX*/,
            Toybox.Ant.NETWORK_PLUS /*Ant.NETWORK_PLUS*/);
        try {
            GenericChannel.initialize(method(:onMessage), chanAssign);
        } catch(e instanceof Ant.UnableToAcquireChannelException) {
            strydmsg("Failed to aquire channel for stryd " + e.getErrorMessage());
            failedInit = true;
            return;
        }

        //https://cdn.sparkfun.com/assets/6/0/3/b/4/ANT-UserGuide.pdf
        //Deprecated_D00001086_ANT+_Device_Profile_-_Bicycle_Power_Rev_5.1.pdf
        var deviceCfg = new Ant.DeviceConfig( {
            :deviceNumber => deviceNumber,
            :deviceType => 11, //DEVICE_TYPE, BIKE_POWER(11, "Bike Power Sensors"),
            :transmissionType => 5, //TRANSMISSION_TYPE, bitmap, independent channel "An independent channel has only one master and one slave" Bike power must be independent channel
            :messagePeriod => 8182, //PERIOD, 4Hz 
            :radioFrequency => 57,              //Ant+ Frequency
            :searchTimeoutLowPriority => 10,    //Timeout. 30s is the Ant recommended default for bike power, units are 2.5 seconds, range 0-12
            :searchThreshold => 0} );

        GenericChannel.setDeviceConfig(deviceCfg);
    }
    function open() {
        currentPower = -8; //0;
        searching = true;
        var retval = GenericChannel.open();
        strydmsg("Stryd open " + retval);
        return retval;
    }

    function close() {
        currentPower = -7; //0;
        searching = true;
        var retval = GenericChannel.close();
        strydmsg("Stryd close " + retval);
        return retval;
    }

    //call this from compute in the view
    //if we don't connect, try closing the connection and reopening (it doesn't seem to help.) 
    function computeStryd() {
        if(currentPower < 0 || searching) {
            searchingCount++;
        }

        if(searchingCount > 29) {
            strydmsg("Stryd searching timeout, reset");
            reset();
        }

    }

    function reset() {
            strydmsg("Stryd close, release and reopen");
            GenericChannel.close();
            GenericChannel.release();
            init();
            GenericChannel.open();
            searchingCount = 0;
    }

    function onMessage(msg) {
        // Parse the payload
        var payload = msg.getPayload();
        var payload0 = payload[0];
        var payload1 = payload[1];
        
        //optimize log storage, only log message when unexpected
        strydmsg("SoM, deviceNumber " + msg.deviceNumber);
        if (Ant.MSG_ID_BROADCAST_DATA  == msg.messageId) { //78 0x4E
            if(PAGE_NUMBER == payload0) {  //standard power only (bike power guide) 0x10
                // Were we searching?
                if (searching) {
                    searching = false;
                    var deviceCfg = GenericChannel.getDeviceConfig();                    
                    strydmsg("Found Stryd, device id " + deviceCfg.deviceNumber);
                }


                //Payload:
                //1 event count
                //2 pedal power
                //3 instantaneous cadence
                //4&5 accumlated power
                //6&7 instantaneous power
                currentPower = payload[6] | ((payload[7]) << 8);

                //strydmsg("SoM pwr " + currentPower);
            } else {
                strydmsg("SoM (bd) payload0? " + payload0.format("%2x") + ", payload " + payload);
            }
        } else if (Ant.MSG_ID_CHANNEL_RESPONSE_EVENT == msg.messageId) { //64, 0x40
            if (Ant.MSG_ID_RF_EVENT == payload0) { //0x01 (message id but checking payload?)
                if (Ant.MSG_CODE_EVENT_CHANNEL_CLOSED == payload1) {  // 0x07
                    strydmsg("SoM closed message");
                    // Channel closed, re-open
                    reset();
                } else if (Ant.MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH == payload1) { //0x08
                    strydmsg("SoM failed to search");
                    reset();
                	currentPower = -2; //0;
                    searching = true;
                } else {
                    strydmsg("SoM (channel rx, unknown payload1), payload0 " + payload0.format("%2x") + ", payload1 " + payload1.format("%2x"));
                }
            } else {
                strydmsg("SoM (crx) payload0? " + payload0.format("%2x") + ", payload " + payload);
            }


            //https://www.thisisant.com/APIassets/1.1.0_ANTnRFConnectDoc/doc/api/parameters.html
            //MESG_ACTIVE_SEARCH_SHARING_ID ((uint8_t)0x81)
            //MESG_UNASSIGN_CHANNEL_ID ((uint8_t)0x41)
            //MESG_ASSIGN_CHANNEL_ID ((uint8_t)0x42)
            //MESG_OPEN_CHANNEL_ID ((uint8_t)0x4B)
            //MESG_ACKNOWLEDGED_DATA_ID ((uint8_t)0x4F)

/*
sample log: (looks like maybe a unassign, assign, open?)
11:58:28: SoM (crx) payload0? 6e, payload [110, 0, 51, 48, 0, 0, 0, 0]
11:58:28: SoM (crx) payload0? 41, payload [65, 0, 51, 48, 0, 0, 0, 0]
11:58:28: SoM (crx) payload0? 42, payload [66, 0, 51, 48, 0, 0, 0, 0]
11:58:28: SoM (crx) payload0? 81, payload [129, 0, 51, 48, 0, 0, 0, 0]
11:58:28: SoM (crx) payload0? 4b, payload [75, 0, 0, 0, 0, 0, 0, 0]

11:58:28: SoM (crx) payload0? 4f, payload [79, 31, 0, 0, 0, 0, 0, 0]
11:58:28: SoM (bd) payload0?  1, payload [1, 0, 0, 0, 0, 0, 0, 0]
11:58:28: SoM (channel rx, unknown payload1) id 64, payload0 1, payload1 5
11:58:28: SoM (bd) payload0?  4, payload [4, 0, 0, 0, 0, 0, 37, 18]
11:58:28: SoM (bd) payload0?  3, payload [3, 0, 0, 0, 0, 0, 0, 0]
11:58:29: SoM (bd) payload0?  6, payload [6, 0, 0, 0, 1, 0, 0, 0]

*/

        }
    }
}