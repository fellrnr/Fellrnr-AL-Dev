using Toybox.Lang;
using Toybox.StringUtil;
using Toybox.System;

using ActiveLookBLE;

(:typecheck(false))
module ActiveLookSDK {

    //! Private logger enabled in debug and disabled in release mode
    (:release) function _log(msg as Toybox.Lang.String, data as Toybox.Lang.Object or Null) as Void {}
    (:debug)   function _log(msg as Toybox.Lang.String, data as Toybox.Lang.Object or Null) as Void {
        if ($ has :log) { $.log(Toybox.Lang.format("[ActiveLookSDK] $1$", [msg]), data); }
    }

(:debug)   function log(msg as Toybox.Lang.String, data as Toybox.Lang.Object or Null) as Void {
    if (data instanceof Toybox.Lang.ByteArray) { data = arrayToHex(data); }
    if (data instanceof Toybox.Lang.Exception) { data.printStackTrace() ; data = data.getErrorMessage(); }
    var myTime = System.getClockTime(); // ClockTime object
    System.println(
        myTime.hour.format("%02d") + ":" +
        myTime.min.format("%02d") + ":" +
        myTime.sec.format("%02d") + "- " + 
        Toybox.Lang.format("[D]$1$ $2$", [msg, data]));
}


    //! Interface for listener
    typedef ActiveLookListener as interface {
        function onFirmwareEvent(major as Toybox.Lang.Number, minor as Toybox.Lang.Number, patch as Toybox.Lang.Number) as Void;
        function onCfgVersionEvent(cfgVersion as Toybox.Lang.Number) as Void;
        function onGestureEvent() as Void;
        function onBatteryEvent(batteryLevel as Toybox.Lang.Number) as Void;
        function onDeviceReady() as Void;
        function onDeviceDisconnected() as Void;
        function onBleError(exception as Toybox.Lang.Exception) as Void;
    };

    //! The status of the Active Look SDK is represented by a lot of flags.
    var isScanning                                   as Toybox.Lang.Boolean                      = false;
    var isPairing                                    as Toybox.Lang.Boolean                      = false;
    var isReconnecting                               as Toybox.Lang.Boolean                      = false;
    var isRegisteringProfile                         as Toybox.Lang.Boolean                      = false;

    var layoutCmdId                                  as Lang.Number                              = 0x66;

    var device                                       as Toybox.BluetoothLowEnergy.Device or Null = null;
    function isConnected()                           as Toybox.Lang.Boolean {
        return device != null;
    }

    var isActivatingGestureNotif                     as Toybox.Lang.Boolean                      = false;
    var isGestureNotifActivated                      as Toybox.Lang.Boolean                      = false;

    var isActivatingBatteryNotif                     as Toybox.Lang.Boolean                      = false;
    var isBatteryNotifActivated                      as Toybox.Lang.Boolean                      = false;

    var isActivatingALookTxNotif                     as Toybox.Lang.Boolean                      = false;
    var isALookTxNotifActivated                      as Toybox.Lang.Boolean                      = false;

    var isReadingBattery                             as Toybox.Lang.Boolean                      = false;
    var batteryLevel                                 as Toybox.Lang.Number or Null               = null;
    function isBatteryRead()                         as Toybox.Lang.Boolean {
        return batteryLevel != null;
    }

    var isReadingFirmwareVersion                     as Toybox.Lang.Boolean                      = false;
    var firmwareVersion                              as Toybox.Lang.String or Null               = null;
    function isFirmwareVersionRead()                 as Toybox.Lang.Boolean {
        return firmwareVersion != null;
    }

    var isUpdatingBleParams                          as Toybox.Lang.Boolean                      = false;
    var isBleParamsUpdated                           as Toybox.Lang.Boolean                      = false;

    var isReadingCfgVersion                          as Toybox.Lang.Boolean                      = false;
    var cfgVersion                                   as Toybox.Lang.Number or Null               = null;
    function isCfgVersionRead()                      as Toybox.Lang.Boolean {
        return cfgVersion != null;
    }

    var isUpdatingALSSensor                          as Toybox.Lang.Boolean                      = false;
    var isALSSensorUpdated                           as Toybox.Lang.Boolean                      = false;

    var isUpdatingGestureSensor                      as Toybox.Lang.Boolean                      = false;
    var isGestureSensorUpdated                       as Toybox.Lang.Boolean                      = false;


    function isIdled()                               as Toybox.Lang.Boolean {
        if (isScanning)               { return false; }
        if (isPairing)                { return false; }
        if (isActivatingGestureNotif) { return false; }
        if (isActivatingBatteryNotif) { return false; }
        if (isActivatingALookTxNotif) { return false; }
        if (isReadingBattery)         { return false; }
        if (isReadingFirmwareVersion) { return false; }
        if (isUpdatingBleParams)      { return false; }
        if (isUpdatingALSSensor)      { return false; }
        if (isUpdatingGestureSensor)  { return false; }
        if (isReadingCfgVersion)      { return false; }
        if (isRegisteringProfile)     { return true; }
        return true;
    }

    function isReady()                               as Toybox.Lang.Boolean {
        if (!isIdled())               { return false; }
        if (!isConnected())           { return false; }
        if (!isBatteryRead())         { return false; }
        if (!isFirmwareVersionRead()) { return false; }
        if (!isBleParamsUpdated)      { return false; }
        if (!isALSSensorUpdated)      { return false; }
        if (!isCfgVersionRead())      { return false; }
        if (!isGestureSensorUpdated)  { return false; }
        if (!isGestureNotifActivated) { return false; }
        if (!isBatteryNotifActivated) { return false; }
        if (!isALookTxNotifActivated) { return false; }
        return true;
    }

    var time = null;    var clearError = null;
    var timeHError = null; var timeMError = null;
    var battery = null; var batteryError = null;
    var cmdStacking = null;
    var ble = null;     var listener = null;
    var lapMessageError = "Start";
    var forceTimeLapRefresh = true;

    var _cbCharacteristicWrite   = null;

    var layouts = [];
    var buffers = [];   var values = [];
    var rotate = 0;

    class ALSDK {

        (:release) private static function _log(msg as Toybox.Lang.String, data as Toybox.Lang.Object or Null) as Void {}
        (:debug)   private static function _log(msg as Toybox.Lang.String, data as Toybox.Lang.Object or Null) as Void {
            if ($ has :log) { $.log(Toybox.Lang.format("[ActiveLookSDK::ALSDK] $1$", [msg]), data); }
        }

        function initialize(obj) {
            listener = obj != null ? obj : self;
            ble = ActiveLookBLE.ActiveLook.setUp(self);
        }

        function startGlassesScan() {
            _log("startGlassesScan", []);
            if (!isReconnecting && isIdled()) {
                if (!ActiveLookBLE.ActiveLook.fixScanState()) {
                    ActiveLookBLE.ActiveLook.requestScanning(true);
                }
            }
        }
        function stopGlassesScan() {
            _log("stopGlassesScan", []);
            if (!ActiveLookBLE.ActiveLook.fixScanState()) {
                ActiveLookBLE.ActiveLook.requestScanning(false);
            }
        }
        function connect(device) {
            _log("connect", [device]);
            if (ble.connect(device)) {
                isPairing = true;
                isReconnecting = true;
            }
        }
        function disconnect() {
            _log("disconnect", []);
            if (isReady()) {
                self.clearScreen(true); //#!JFS!# default to refreshing the top line
            }
            isReconnecting = false;
            tearDownDevice();
            ble.disconnect();
        }
        function resyncGlasses() {
            //_log("resyncGlasses", []);
            if (cmdStacking != null)  { self.sendRawCmd([]b); }
            if (clearError == true) {
                self.clearScreen(true); //#!JFS!# default to refreshing the top line
            }
            if (clearError != true) {
                if (batteryError != null && !replaceTimeWithLap) { self.setBattery(batteryError); }
                if (lapMessageError != null) { self.setLap(lapMessageError); }
                for (var i = 0; i < buffers.size(); i ++) {
                    //var pos = (i + rotate) % buffers.size();
                    if (buffers[i] != null) {
                        self.__updateLayoutValueBuffer(i);
                    }
                }
            }
        }
        
        function profileRegistrationStart() {
            isRegisteringProfile = true;
        }

        function profileRegistrationComplete() {
            isRegisteringProfile = false;
        }

        //! convert a number to a byte array
		function numberToByteArray(value) {
			var result = new [0]b;
			do {
				result.add(value & 0xFF);
				value = value >> 8;
			} while(value > 0);
			return result.reverse();
		}

		//! convert a number to a byte array of fixed size
		//! Throw an exception if trying to convert a number
		//! on a too small byte array.
		function numberToFixedSizeByteArray(value, size) {
			var optResult = self.numberToByteArray(value);
			var minSize = optResult.size();
			if (minSize > size) {
				throw new Toybox.Lang.InvalidValueException("value is too big");
			} else if (minSize == size) {
				return optResult;
			} else {
				var nbZeros = size - minSize;
				var result = new [nbZeros]b;
				result.addAll(optResult);
				return result;
			}
		}

        function stringToPadByteArray(str, size, leftPadding) {
			var result = StringUtil.convertEncodedString(str, {
				:fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
				:toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
				:encoding => StringUtil.CHAR_ENCODING_UTF8
			});
			if(size) {
				var padSize = size - result.size();
				if(padSize > 0) {
					var padBuffer = []b;
					do {
						padBuffer.add(0x20);
						padSize -= 1;
					} while(padSize > 0);
					if(leftPadding) {
						padBuffer.addAll(result);
						result = padBuffer;
					} else {
						result.addAll(padBuffer);
					}
				}
			}
			result.add(0x00);
			return result;
		}

		function commandBuffer(id, data) {
			var buffer = new[0]b;
			buffer.addAll([0xFF, id, 0x00, 0x05 + data.size()]b);
			buffer.addAll(data);
			buffer.add(0xAA);
            _log("buffer",[buffer]);
			return buffer;
		}

        //////////////
        // Commands //
        //////////////
        function setBattery(arg) {
            batteryError = null;
            System.println("in setBattery " + arg);
            if (arg != battery) {
                try {
                    var data = [0x07]b;
                    var paddingChar = arg < 10 ? "$" :  "";
                    data.addAll(self.stringToPadByteArray(paddingChar + arg.toString(), 3, true));
                    System.println(Lang.format("setBattery $1$", [data]));
                    self.sendRawCmd(self.commandBuffer(0x62, data));
                    battery = arg;
                } catch (e) {
                    System.println("setBattery error " + e.getErrorMessage());
                    batteryError = arg;
                    onBleError(e);
                }
            }
        }

        function cfgRead() {
            try {
                var data = [0x41, 0x4C, 0x6F, 0x6F, 0x4B]b; // ALooK
                self.sendRawCmd(self.commandBuffer(0xD1, data));
            } catch (e) {
                isReadingCfgVersion = false;
                cfgVersion = null;
                onBleError(e);
            }
        }    
                

        //#!JFS!# setLap method
        function setLap(msg) {
            lapMessageError = null;
            //forceTimeLapRefresh = true; //hack - always update lap
            //if (msg != lapMessageCache || forceTimeLapRefresh) {
            if (forceTimeLapRefresh) { //don't update as soon as the lap changes, but wait for the screen to clear after the pause for the lap message
                try {
                    /*
                    //command 0x62 is layoutDisplay, with 0x0A as the layout id
                    //0x0A is "time", 
                    //https://github.com/ActiveLook/Activelook-Visual-Assets
                    //https://github.com/ActiveLook/Activelook-API-Documentation/blob/main/ActiveLook_API.md 
                    System.println("setLap " + msg);
                    var value = msg;
                    var data = [0x0A]b;
                    data.addAll(self.stringToPadByteArray(value, null, null));
                    ble.getBleCharacteristicActiveLookRx()
                        .requestWrite(self.commandBuffer(0x62, data), {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                        */

                    var data = []b;
                    //font 1=24px, 2=38, 3=64, 4=75, 5=82
                    //screen size is 304; 256

                    //Override time and battery area
                    data.addAll($.sdk.numberToFixedSizeByteArray(290, 2)); //x 
                    data.addAll($.sdk.numberToFixedSizeByteArray(230, 2)); //y (210 too low, overwrites fields, 256 less font 1 is 24 px, so set to 230? )
                    data.addAll([4, 1, 15]b); //rotation (4=norma), font size, color?
                    data.addAll($.sdk.stringToPadByteArray(msg, null, null));
                    var fullBuffer = $.sdk.commandBuffer(0x37, data); // Text lap number
                    $.sdk.sendRawCmd(fullBuffer);

                    //trying to do the refresh every time
                    //forceTimeLapRefresh = false;
                    //System.println("setLap success " + msg);
                } catch (e) {
                    forceTimeLapRefresh = true;
                    lapMessageError = msg;
                    System.println("setLap Error " + e.getErrorMessage());
                    onBleError(e);
                }
            } else {
                System.println("setLap, no change");
            }
        }


        function setTime(hour, minute) {
            if (time != minute || forceTimeLapRefresh) {
            timeHError = null;
            timeMError = null;
                try {
                    time = minute;
                    var value = hour.format("%02d") + ":" + minute.format("%02d");
                    var data = [0x0A]b;
                    data.addAll(self.stringToPadByteArray(value, null, null));
                    System.println("setTime " + data);
                    self.sendRawCmd(self.commandBuffer(0x62, data));
                    forceTimeLapRefresh = false;
                } catch (e) {
                    System.println("setTime Error " + e.getErrorMessage());
                    time = null;
                    timeHError = hour;
                    timeMError = minute;
                    onBleError(e);
                }
            } else {
                System.println("setTime, no change"); //#!JFS!#
            }
        }

        function clearScreen(refresh) {
            clearError = null;
            try {
                //log(Lang.format("clearScreen $1$", [1]));
                self.sendRawCmd(self.commandBuffer(0x01, []b));
                // ble.getBleCharacteristicActiveLookRx()
                //     .requestWrite([0xFF, 0x01, 0x00, 0x05, 0xAA]b, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                if(refresh) {
                    time = null;
                    forceTimeLapRefresh = true; //#!JFS!#
                    if (batteryError == null) {
                        batteryError = battery;
                    }
                    battery = null;
                }
                self.resetLayouts([]);
                self.resyncGlasses(); 
            } catch (e) {
                clearError = true;
                onBleError(e);
            }
        }

        function Text(text, x, y, rotation, size, color) {
			var data = []b;
			data.addAll(self.numberToFixedSizeByteArray(x, 2));
			data.addAll(self.numberToFixedSizeByteArray(y, 2));
			data.addAll([rotation, size, color]b);
			data.addAll(self.stringToPadByteArray(text, null, null));
            self.sendRawCmd(self.commandBuffer(0x37, data));
		}

        function holdGraphicEngine(){
            _log("holdGraphicEngine", []);
            self.holdAndFlush(0);
        }
        
        function flushGraphicEngine(){
            _log("flushGraphicEngine", []);
            self.holdAndFlush(1);
        }

        function resetGraphicEngine(){
            _log("resetGraphicEngine", []);
            self.holdAndFlush(0xFF);
        }

        function holdAndFlush(value) {
            self.sendRawCmd(self.commandBuffer(0x39, [value]b));
		}

        function __onWrite_finishPayload(c, s) {
            _cbCharacteristicWrite = null;
            if (s == 0) {
                self.sendRawCmd([]b);
            } else {
                //this crashes the data field, which doesn't help much. //#!JFS!#
                //throw new Toybox.Lang.InvalidValueException("(E) Could write on: " + c);
                _log("Failure in __onWrite_finishPayload", []);
            }
        }

        function sendRawCmd(buffer) {
            var bufferToSend = []b;
            if (cmdStacking != null) {
                bufferToSend.addAll(cmdStacking);
                cmdStacking = null;
            }
            bufferToSend.addAll(buffer);
            _log("sendRawCmd, BufferSize", [bufferToSend.size()]);
            try {
                if (bufferToSend.size() > 20) {
                    var sendNow = bufferToSend.slice(0, 20);
                    cmdStacking = bufferToSend.slice(20, null);
                    _cbCharacteristicWrite = self.method(:__onWrite_finishPayload);
                    ble.getBleCharacteristicActiveLookRx()
                        .requestWrite(sendNow, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                    _log("cmdSended, partial",[arrayToHex(sendNow)]);
                } else if (bufferToSend.size() > 0) {
                    ble.getBleCharacteristicActiveLookRx()
                        .requestWrite(bufferToSend, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                    _log("cmdSended, full",[arrayToHex(bufferToSend)]);
                }
            } catch (e) {
                cmdStacking = bufferToSend;
                onBleError(e);
            }
		}

        function indexIncompleteCmd(){
            if(cmdStacking){
                _log("indexIncompleteCmd",[arrayToHex(cmdStacking)]);
                for(var i = 0; i < cmdStacking.size(); i++) {
                    if(cmdStacking[i] == 0xAA){
                        if(cmdStacking.size() > i + 1){
                            if(cmdStacking[i+1] == 0xFF){
                                return i+1;
                            }
                        }
                    }
                }
            }
            return 0;
        }

        function flushCmdStacking(){
            _log("flushCmdStacking",[cmdStacking == null ? 0 : cmdStacking.size()]);
            var indexIncompleteCmd = indexIncompleteCmd() as Toybox.Lang.Number;
            cmdStacking = indexIncompleteCmd != 0 ? cmdStacking.slice(null, indexIncompleteCmd) : null ;
            self.resetGraphicEngine();
            _log("flushCmdStacking",[cmdStacking == null ? 0 : arrayToHex(cmdStacking)]);
        }

        function flushCmdStackingIfSup(value as Toybox.Lang.Number){
            if(cmdStacking != null){
                if(cmdStacking.size() > 200){
                    _log("flushCmdStackingIfSup",[value,cmdStacking == null ? 0 : cmdStacking.size()]);
                    flushCmdStacking();
                }
            }
        }

        function resetLayouts(args) {
            var newBuffers = [];
            var newValues = [];
            for (var i = 0; i < args.size(); i ++) {
                var pos = layouts.indexOf(args[i]);
                if (pos < 0) {
                    newBuffers.add(null);
                    newValues.add("");
                } else {
                    newBuffers.add(buffers[pos]);
                    newValues.add(values[pos]);
                }
            }
            layouts = args;
            buffers = newBuffers;
            values = newValues;
            time = null;
            battery = null;
        }

        function updateLayoutValue(layout, value) {
            if (isReady()) {
                var pos = layouts.indexOf(layout);
                if (pos < 0) {
                    pos = layouts.size();
                    layouts.add(layout);
                    buffers.add(null);
                    values.add("");
                }
                if (pos >= 0 && !values[pos].equals(value) && value != null) {
                    values[pos] = value;
                    buffers[pos] = [((layout >> 24) & 0xFF),((layout >> 16) & 0xFF),((layout >> 8) & 0xFF),(layout & 0xFF)]b;
                    buffers[pos].addAll(value);
                    self.__updateLayoutValueBuffer(pos);
                }
            }
        }

        function __updateLayoutValueBuffer(pos) {
            var data = buffers[pos];
            buffers[pos] = null;
            try {
            	//only 5Kb space in the log file
                //System.println(Lang.format("__updateLayoutValueBuffer $1$", [data]));
                self.sendRawCmd(self.commandBuffer(layoutCmdId, data));
                rotate = (rotate + 1) % buffers.size();
            } catch (e) {
                buffers[pos] = data;
                _cbCharacteristicWrite = self.method(:__onWrite_finishpUdateLayoutValueBuffer);
                onBleError(e);
            }
        }

        function __onWrite_finishpUdateLayoutValueBuffer(c, s) {
            _cbCharacteristicWrite = null;
            if (s == 0) {
                self.resyncGlasses();
            } else {
                _log("repair connection", []);
                isReconnecting = false;
                tearDownDevice();
                ble.disconnect();
                ActiveLookSDK.device = null;
                listener.onDeviceDisconnected();
            }
        }

        function setUpNewDevice(device as Toybox.BluetoothLowEnergy.Device) as Toybox.Lang.Boolean {
            _log("setUpNewDevice", [ActiveLookSDK.device, device]);
            if (ActiveLookSDK.device != null) {
                if (ActiveLookSDK.device != device) {
                    onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Device differs $1$ $2$.", [ActiveLookSDK.device, device])));
                    return false;
                }
            } else { ActiveLookSDK.device = device; }
            return setUpDevice();
        }

        function setUpDevice() as Toybox.Lang.Boolean {
            _log("setUpDevice", [ActiveLookSDK.device]);
            if (!isIdled()) { _log("setUpDevice", [ActiveLookSDK.device, "Not idle"]);
                return false;
            }
            if (!isConnected()) { _log("setUpDevice", [ActiveLookSDK.device, "Not connected"]);
                return false;
            }
            if (!isFirmwareVersionRead()) { _log("setUpDevice", [ActiveLookSDK.device, "Not isFirmwareVersionRead"]);
                if (!isReadingFirmwareVersion) { _log("setUpDevice", [ActiveLookSDK.device, "Not isReadingFirmwareVersion"]);
                    try {
                        ble.getBleCharacteristicFirmwareVersion().requestRead();
                        isReadingFirmwareVersion = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            if (!isBatteryRead()) { _log("setUpDevice", [ActiveLookSDK.device, "Not isBatteryRead"]);
                if (!isReadingBattery) { _log("setUpDevice", [ActiveLookSDK.device, "Not isReadingBattery"]);
                    try {
                        ble.getBleCharacteristicBatteryLevel().requestRead();
                        isReadingBattery = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            if (!isBatteryNotifActivated) { _log("setUpDevice", [ActiveLookSDK.device, "Not isBatteryNotifActivated"]);
                if (!isActivatingBatteryNotif) { _log("setUpDevice", [ActiveLookSDK.device, "Not isActivatingBatteryNotif"]);
                    try {
                        ble.getBleCharacteristicBatteryLevel().getDescriptor(BluetoothLowEnergy.cccdUuid()).requestWrite([0x01, 0x00]b);
                        isActivatingBatteryNotif = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            if (!isALookTxNotifActivated) { _log("setUpDevice", [ActiveLookSDK.device, "Not isALookTxNotifActivated"]);
                if (!isActivatingALookTxNotif) { _log("setUpDevice", [ActiveLookSDK.device, "Not isActivatingALookTxNotif"]);
                    try {
                        ble.getBleCharacteristicActiveLookTx().getDescriptor(BluetoothLowEnergy.cccdUuid()).requestWrite([0x01, 0x00]b);
                        isActivatingALookTxNotif = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            if (!isBleParamsUpdated) { _log("setUpDevice", [ActiveLookSDK.device, "Not isBleParamsUpdated"]);
                if (!isUpdatingBleParams) { _log("setUpDevice", [ActiveLookSDK.device, "Not isUpdatingBleParams"]);
                    try {
                        // Command id : 0xA4
                        // u16 intervalMin: 30ms => 24 (interval are in 1.25 ms)
                        // u16 intervalMax: 30ms  => 24 (interval are in 1.25 ms)
                        // u16 slaveLatency: 0
                        // u16 supTimeout: 4s => 400 (supervision is 10 ms)
                        var data = [0x00, 0x18, 0x00, 0x18, 0x00, 0x00, 0x01, 0x90]b;
                        ble.getBleCharacteristicActiveLookRx()
                            .requestWrite(self.commandBuffer(0xA4, data), {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                        isUpdatingBleParams = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            if (!isALSSensorUpdated) { _log("setUpDevice", [ActiveLookSDK.device, "Not isALSSensorUpdated"]);
                if (!isUpdatingALSSensor) { _log("setUpDevice", [ActiveLookSDK.device, "Not isUpdatingALSSensor"]);
                    try {    
                        var is_als_enable = Toybox.Application.Properties.getValue("is_als_enable") as Toybox.Lang.Boolean;
                        _log("is_als_enable",[is_als_enable]);
                        var data = []b;
                        if(is_als_enable){data = [0x01]b;}else{data = [0x00]b;}
                        ble.getBleCharacteristicActiveLookRx()
                            .requestWrite(self.commandBuffer(0x22, data), {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                        isUpdatingALSSensor = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            if (!isCfgVersionRead()) { _log("setUpDevice", [ActiveLookSDK.device, "Not isCfgVersionRead"]);
                if (!isReadingCfgVersion) { _log("setUpDevice", [ActiveLookSDK.device, "Not isReadingCfgVersion"]);
                    try {
                        self.cfgRead();
                        isReadingCfgVersion = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            if (!isGestureSensorUpdated) { _log("setUpDevice", [ActiveLookSDK.device, "Not isGestureSensorUpdated"]);
                if (!isUpdatingGestureSensor) { _log("setUpDevice", [ActiveLookSDK.device, "Not isUpdatingGestureSensor"]);
                    try {        
                        var is_gesture_enable = Toybox.Application.Properties.getValue("is_gesture_enable") as Toybox.Lang.Boolean;
                        _log("is_gesture_enable",[is_gesture_enable]);
                        var data = []b;
                        if(is_gesture_enable){data = [0x01]b;}else{data = [0x00]b;}
                        ble.getBleCharacteristicActiveLookRx()
                            .requestWrite(self.commandBuffer(0x21, data), {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                        isUpdatingGestureSensor = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            if (!isGestureNotifActivated) { _log("setUpDevice", [ActiveLookSDK.device, "Not isGestureNotifActivated"]);
                if (!isActivatingGestureNotif) { _log("setUpDevice", [ActiveLookSDK.device, "Not isActivatingGestureNotif"]);
                    try {
                        ble.getBleCharacteristicActiveLookGesture().getDescriptor(BluetoothLowEnergy.cccdUuid()).requestWrite([0x01, 0x00]b);
                        isActivatingGestureNotif = true;
                    } catch (e) { onBleError(e); }
                }
                return false;
            }
            listener.onDeviceReady();
            return true;
        }

        function tearDownDevice() as Void {
            _log("tearDownDevice", [ActiveLookSDK.device]);
            time = null;
            cmdStacking = null;
            var newBuffers = [];
            var newValues = [];
            for (var i = 0; i < layouts.size(); i ++) {
                newBuffers.add(null);
                newValues.add("");
            }
            buffers = newBuffers;
            values = newValues;
            ActiveLookSDK.isScanning               = false;
            ActiveLookSDK.isPairing                = false;
            ActiveLookSDK.isActivatingGestureNotif = false;
            ActiveLookSDK.isGestureNotifActivated  = false;
            ActiveLookSDK.isActivatingBatteryNotif = false;
            ActiveLookSDK.isBatteryNotifActivated  = false;
            ActiveLookSDK.isActivatingALookTxNotif = false;
            ActiveLookSDK.isALookTxNotifActivated  = false;
            ActiveLookSDK.isReadingBattery         = false;
            ActiveLookSDK.batteryLevel             = null;
            ActiveLookSDK.isReadingFirmwareVersion = false;
            ActiveLookSDK.firmwareVersion          = null;
            ActiveLookSDK.isUpdatingBleParams      = false;
            ActiveLookSDK.isBleParamsUpdated       = false;
            ActiveLookSDK.isReadingCfgVersion      = false;
            ActiveLookSDK.cfgVersion               = null;
            ActiveLookSDK.isUpdatingALSSensor      = false;
            ActiveLookSDK.isUpdatingGestureSensor  = false;
        }

        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onCharacteristicChanged
        function onCharacteristicChanged(characteristic as Toybox.BluetoothLowEnergy.Characteristic, value as Toybox.Lang.ByteArray) as Void {
            _log("onCharacteristicChanged", [characteristic, value]);
            if (value == null) {
                onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Characteristic change error $1$ $2$.", [characteristic, value])));
                return;
            }
            switch (characteristic.getUuid()) {
                case ble.getBleCharacteristicBatteryLevel().getUuid(): {
                    batteryLevel = value[0];
                    listener.onBatteryEvent(batteryLevel);
                    break;
                }
                case ble.getBleCharacteristicActiveLookGesture().getUuid(): {
                    if (value[0] != 0x01) {
                        _log("onCharacteristicChanged", ["Expecting gesture value 0x01", value]);
                    }
                    self.flushCmdStacking();
                    listener.onGestureEvent();
                    break;
                }
                case ble.getBleCharacteristicActiveLookTx().getUuid(): {
                    if (value.size() >= 2 && value[0] == 0xFF) {
                        switch (value[1]) {
                            case 0xD1 :{ // cfgRead
                            	cfgVersion = value[7];
                                isReadingCfgVersion = false;
                                _log("onCharacteristicChanged", ["cfgVersion", cfgVersion]);
                                listener.onCfgVersionEvent(cfgVersion);
                                setUpDevice();
                                break;
                            }
                            // case 0x0A: { // Settings
                            //     luma = value[6];
                            //     als = value[7];
                            //     gesture = value[8];
                            //     break;
                            // }
                            default: {
                                System.println("__characteristicUpdate("+ characteristic.getUuid().toString() + ", " + value.toString()+")");
                            }
                        }
                        break;
                    }
                }
                default: {
                    onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Unknown characteristic $1$.", [characteristic])));
                    return;
                }
            }
        }
        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onCharacteristicRead
        function onCharacteristicRead(characteristic as Toybox.BluetoothLowEnergy.Characteristic, status as Toybox.BluetoothLowEnergy.Status, value as Toybox.Lang.ByteArray) as Void {
            _log("onCharacteristicRead", [characteristic, status, value]);
            switch (characteristic.getUuid()) {
                case ble.getBleCharacteristicBatteryLevel().getUuid(): {
                    isReadingBattery = false;
                    if (value != null) {
                        batteryLevel = value[0];
                        listener.onBatteryEvent(batteryLevel);
                        setUpDevice();
                        return;
                    }
                    break;
                }
                case ble.getBleCharacteristicFirmwareVersion().getUuid(): {
                    isReadingFirmwareVersion = false;
                    if (value != null) {
                        firmwareVersion = StringUtil.convertEncodedString(value, {
                                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                                :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
                                :encoding => StringUtil.CHAR_ENCODING_UTF8
                            });
                        var major = 0;
                        var minor = 0;
                        var patch = 0;
                        var offset = firmwareVersion.find("v");
                        if (offset == null) { offset = -1; }
                        var subStr = firmwareVersion.substring(offset + 1, firmwareVersion.length());
                        major = subStr.toNumber();
                        offset = subStr.find(".");
                        if (offset != null) {
                            subStr = subStr.substring(offset + 1, subStr.length());
                            minor = subStr.toNumber();
                            offset = subStr.find(".");
                            if (offset != null) {
                                subStr = subStr.substring(offset + 1, subStr.length());
                                patch = subStr.toNumber();
                            }
                        }
                        
                        if(major > 4 || (major == 4  && minor >= 5)){
                            layoutCmdId = 0x6A;
                        }else{
                            layoutCmdId = 0x66;
                        }

                        listener.onFirmwareEvent(major, minor, patch);
                        setUpDevice();
                        return;
                    }
                    break;
                }
                default: {
                    isReadingBattery = false;
                    isReadingFirmwareVersion = false;
                    onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Unknown characteristic $1$.", [characteristic])));
                    return;
                }
            }
            onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Characteristic read error $1$ $2$ $3$.", [characteristic, status, value])));
        }
        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onCharacteristicWrite
        function onCharacteristicWrite(characteristic as Toybox.BluetoothLowEnergy.Characteristic, status as Toybox.BluetoothLowEnergy.Status) as Void {
            //_log("onCharacteristicWrite", [characteristic.getUuid(), status]);
            if (isUpdatingBleParams && !isBleParamsUpdated) {
                isUpdatingBleParams = false;
                if (status == Toybox.BluetoothLowEnergy.STATUS_SUCCESS) {
                    isBleParamsUpdated = true;
                }
            }else if (isUpdatingALSSensor && !isALSSensorUpdated) {
                isUpdatingALSSensor = false;
                if (status == Toybox.BluetoothLowEnergy.STATUS_SUCCESS) {
                    isALSSensorUpdated = true;
                }
            } else if (isUpdatingGestureSensor && !isGestureSensorUpdated) {
                isUpdatingGestureSensor = false;
                if (status == Toybox.BluetoothLowEnergy.STATUS_SUCCESS) {
                    isGestureSensorUpdated = true;
                }
            }else {
                // TODO: Refactor to avoid callback like this
                var _cb = _cbCharacteristicWrite;
                if (_cb != null) {
                    _cb.invoke(characteristic, status);
                }
            }
        }
        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onConnectedStateChanged
        function onConnectedStateChanged(device as Toybox.BluetoothLowEnergy.Device, state as Toybox.BluetoothLowEnergy.ConnectionState) as Void {
            _log("onConnectedStateChanged", [device, state]);
            if (state == Toybox.BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
                isPairing = false;
                setUpNewDevice(device);
            } else if (ActiveLookSDK.device == null) {
                onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Device was alread disconnected $1$ $2$.", [ActiveLookSDK.device, device])));
            } else if (ActiveLookSDK.device != device) {
                onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Device differs $1$ $2$.", [ActiveLookSDK.device, device])));
            } else {
                ActiveLookSDK.device = null;
                tearDownDevice();
                listener.onDeviceDisconnected();
            }
        }
        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onDescriptorRead
        function onDescriptorRead(descriptor as Toybox.BluetoothLowEnergy.Descriptor, status as Toybox.BluetoothLowEnergy.Status, value as Toybox.Lang.ByteArray) as Void {
            _log("onDescriptorRead", [descriptor, status, value]);
        }
        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onDescriptorWrite
        function onDescriptorWrite(descriptor as Toybox.BluetoothLowEnergy.Descriptor, status as Toybox.BluetoothLowEnergy.Status) as Void {
            _log("onDescriptorWrite", [descriptor, status]);
            var isActivated = status == Toybox.BluetoothLowEnergy.STATUS_SUCCESS;
            switch (descriptor.getCharacteristic().getUuid()) {
                case ble.getBleCharacteristicBatteryLevel().getUuid(): {
                    isActivatingBatteryNotif = false;
                    if (isActivated) { isBatteryNotifActivated = true; }
                    break;
                }
                case ble.getBleCharacteristicActiveLookTx().getUuid(): {
                    isActivatingALookTxNotif = false;
                    if (isActivated) { isALookTxNotifActivated = true; }
                    break;
                }
                case ble.getBleCharacteristicActiveLookGesture().getUuid(): {
                    isActivatingGestureNotif = false;
                    if (isActivated) { isGestureNotifActivated = true; }
                    break;
                }
                default: {
                    isActivatingALookTxNotif = false;
                    isActivatingBatteryNotif = false;
                    isActivatingGestureNotif = false;
                    onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Unknown descriptor $1$ $2$.", [descriptor.getCharacteristic(), descriptor, status])));
                    return;
                }
            }
            if (!isActivated) {
                onBleError(new Toybox.Lang.InvalidValueException(Toybox.Lang.format("(E) Descriptor write error $1$ $2$.", [descriptor.getCharacteristic(), descriptor, status])));
                return;
            }
            setUpDevice();
        }
        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onScanResult
        function onScanResult(scanResult as Toybox.BluetoothLowEnergy.ScanResult) as Void {
            _log("onScanResult", [scanResult]);
            listener.onScanResult(scanResult);
        }
        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onScanStateChange
        function onScanStateChange(scanState as Toybox.BluetoothLowEnergy.ScanState, status as Toybox.BluetoothLowEnergy.Status) as Void {
            _log("onScanStateChange", [scanState, status]);
            if (scanState == Toybox.BluetoothLowEnergy.SCAN_STATE_SCANNING) {
                if (status <= Toybox.BluetoothLowEnergy.STATUS_SUCCESS) {
                    isScanning = true;
                }
            } else {
                isScanning = false;
            }
        }

        // Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onPassiveConnection
        function onPassiveConnection(device as Toybox.BluetoothLowEnergy.Device) as Void {
            ActiveLookSDK.device = device;
        }


        //! Override ActiveLookBLE.ActiveLook.ActiveLookDelegate.onBleError
        function onBleError(exception as Toybox.Lang.Exception) as Void {
            _log("onBleError", [exception.getErrorMessage()]);
            listener.onBleError(exception);
        }

    }

}
