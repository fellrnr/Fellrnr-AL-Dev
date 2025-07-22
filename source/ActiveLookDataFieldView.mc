using Toybox.Application;
using Toybox.Activity;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.AntPlus;

using ActiveLookSDK;
using ActiveLook.AugmentedActivityInfo;
using ActiveLook.PageSettings;
using ActiveLook.Layouts;
using ActiveLook.Laps;

//! Private logger enabled in debug and disabled in release mode
(:release) function log(msg as Toybox.Lang.String) as Void {}
(:release) function arrayToHex(array as Toybox.Lang.ByteArray or Toybox.Lang.Array<Toybox.Lang.Integer>) as Toybox.Lang.String { return ""; }
(:debug)   function arrayToHex(array as Toybox.Lang.ByteArray or Toybox.Lang.Array<Toybox.Lang.Integer>) as Toybox.Lang.String {
    var msg = "[";
    var prefix = "";
    for(var i = 0; i < array.size(); i++) {
        msg = Toybox.Lang.format("$1$$2$0x$3$", [msg, prefix, array[i].format("%02X")]);
        prefix = ", ";
    }
    return Toybox.Lang.format("$1$]", [msg]);
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

var sdk as ActiveLookSDK.ALSDK = null as ActiveLookSDK.ALSDK;

//page spec is array of array of symbols
var pagesSpec as Lang.Array<PageSettings.PageSpec> = [] as Lang.Array<PageSettings.PageSpec>;
var pageIdx as Lang.Number = 0;
var swipe as Lang.Boolean = false;
var battery as Lang.Number or Null = null;
var tempo_off as Lang.Number = -1; //#!JFS!# turn the screen blank, for "(0)"
var tempo_pause as Lang.Number = 0; //#!JFS!# the watch has been paused (was -1, but we want to show the data before we start)
var tempo_started as Lang.Number = -1; //#!JFS!# replacement for tempo_pause = -1
var tempo_lap_freeze as Lang.Number = -1; //#!JFS!# freeze the screen after lap button
var tempo_congrats as Lang.Number = 1; //#!JFS!# session end
var isRun = false; //#!JFS!#
var antplusBikePower as AntPlus.BikePower;

//#!JFS!# variable to hold the current screen being displayed
//GeneratorArguments has an id, symbol, a converter and a method
//method is class Layouts, method such as toFullStr which takes a value
var currentLayouts as Lang.Array<Layouts.GeneratorArguments> = [] as Lang.Array<Layouts.GeneratorArguments>;
var runningDynamics as Toybox.AntPlus.RunningDynamics or Null = null;



// ToDo : différence pause stop
// 1) Event onTimerStop  devrait être considéré comme un onTimerPause
// 2) Pour afficher le Congrats : Compute vérifier durée de la session,
//      Si on a onTimerStopEvent et que dans le compute nouvelle Session Timer = 0
//      Alors afficher le Congrats --> onTimerStop mécanique
//      Sinon c'est une pause
// Trois cas : onTimerStop qui est un onTimerPause, onTimerPause et onTimerStop

// ToDo : Laps Warning Mémoir compatibility devices
// 1) Quand lap bouton activer
// 2) Stocker toute la session d'Activity
// 3) Afficher les valeurs avec un différentiel des données sauvegardées et les données de l'Activity

(:typecheck(false))
function resetGlobals() as Void {
    try {
        var _ai = "screens";
        if (Toybox.Activity has :getProfileInfo) {
            var profileInfo = Toybox.Activity.getProfileInfo();
            if (profileInfo has :sport) {
                switch (profileInfo.sport) {
                    case Toybox.Activity.SPORT_RUNNING: { _ai = "run";     break; }
                    case Toybox.Activity.SPORT_CYCLING: { _ai = "bike";    break; }
                    default:                            { _ai = "screens"; break; }
                }
            }
        }
        $.pagesSpec = PageSettings.strToPages(Application.Properties.getValue(_ai), "(1,12,2)(15,4,2)(10,18,22)(0)");
    } catch (e) {
        $.pagesSpec = PageSettings.strToPages("(1,12,2)(15,4,2)(10,18,22)(0)", null);
    }
    // $.pagesSpec = PageSettings.strToPages(
    //     "0, 1,2,3,4,5,6,7,8,9,10,11,(1),(2,3),(4,5,6),(7,8,9,10),(11,12,13,14,15,16),(17,18,19,20,21,22),(23,24,25,27,28,29)",
    // "1,2,3,0");
    // $.pagesSpec = PageSettings.strToPages("1,2,3,0", "1,2,3,0");
    $.pageIdx = 0;
    $.swipe = false;
    $.tempo_off = -1;
    $.tempo_pause = 0; //#!JFS!# was -1
    $.tempo_started = -1; //replace tempo_pause = -1
    $.tempo_lap_freeze = -1;
    $.tempo_congrats = 0;

    if(Toybox.Activity has :ProfileInfo &&
                Activity.getProfileInfo() != null &&
                Activity.getProfileInfo() has :sport &&
                Activity.getProfileInfo().sport != null && Activity.getProfileInfo().sport == Activity.SPORT_RUNNING) {
        isRun = true;
    }

    $.updateCurrentLayouts(0);
}

function updateCurrentLayouts(incr as Lang.Number) as Void {
    if (incr != 0) {
        var nextPageIdx = ($.pageIdx + incr) % pagesSpec.size();
        if ($.pageIdx != nextPageIdx) {
            $.pageIdx = nextPageIdx;
            incr = 0;
        }
    }
    if (incr == 0) {
        $.currentLayouts = Layouts.pageToGenerator($.pagesSpec[$.pageIdx]);
    }
}

(:typecheck(false))
function updateFields() as Void {
    var after = $.currentLayouts.size();
    if ($.swipe == true) {
        $.log("updateFields, swipe", []);

        //Todo reset tempo
         if($.tempo_off > 0){
            $.tempo_off = 0;
         }
         if ($.tempo_pause > 0) {
            $.tempo_pause = 0;
         }
         if ($.tempo_congrats > 0) {
            $.tempo_congrats = 1;
         }
    }
    if ($.tempo_off > 0) {
        //$.amsg("updateFields, $.tempo_off is >0: " + $.tempo_off);
        $.tempo_off -= 1;
        if ($.tempo_off == 0) {
            var fullBuffer = $.sdk.commandBuffer(0x01, []b) as Lang.ByteArray; // Clear Screen after being set to "(0)" screen, don't refresh time/battery
            fullBuffer.addAll($.sdk.commandBuffer(0x00, [0x00]b)); // turn off screen
            $.sdk.sendRawCmd("clear-off", fullBuffer);
            $.sdk.resetLayouts([]);
        }
        return;
    }
    if ($.tempo_pause > 0) {
        //$.amsg("updateFields, $.tempo_pause is >0: " + $.tempo_pause);
        $.tempo_pause -= 1;
        if ($.tempo_pause == 0) {
            var fullBuffer = $.sdk.commandBuffer(0x01, []b) as Lang.ByteArray; // Clear Screen after watch paused, don't refresh time/battery
            fullBuffer.addAll($.sdk.commandBuffer(0x62, [0x49, 0x00]b)); // layout petit pause
            $.sdk.sendRawCmd("clear-pause", fullBuffer);
            $.sdk.resetLayouts([]);
        }
        return;
    }
    if ($.tempo_congrats > 0) {
        //$.amsg("updateFields, $.tempo_congrats is >0: " + $.tempo_congrats);
        $.tempo_congrats -= 1;
        if ($.tempo_congrats == 0) {
            var fullBuffer = $.sdk.commandBuffer(0x01, []b) as Lang.ByteArray; // Clear Screen after session end, don't refresh time/battery
            fullBuffer.addAll($.sdk.commandBuffer(0x62, [0x4B, 0x00]b)); // layout ready
            $.sdk.sendRawCmd("clear-done", fullBuffer);
            $.sdk.resetLayouts([]);
        }
        return;
    }
    if ($.tempo_congrats == 0) {
        //$.amsg("updateFields, $.tempo_congrats ==0: " + $.tempo_congrats);
        return;
    }
    //#!JFS!# change the pause then clear logic to use a variable freeze time
    //in compute below we check if $.tempo_lap_freeze == -1 before updating the screen
    if ($.tempo_lap_freeze >= 0) {
        $.log("update fields, $.tempo_lap_freeze is >=0: ", [$.tempo_lap_freeze]);
        //$.tempo_lap_freeze -= 1; //decrement earlier so we don't add another second to the freeze time

        if ($.lapFreezeSeconds == 1 && $.tempo_lap_freeze == 0) { //#!JFS!# really short freeze time means we have to clear the screen earlier than normal
            $.log("clear screen, as $.lapFreezeSeconds == 1 and $.tempo_lap_freeze is  ", [$.tempo_lap_freeze]);
            $.sdk.clearScreen(true); //#!JFS!# this is the right time to refresh the top line, after clearing the lap message
        }

        if ($.tempo_lap_freeze >= ($.lapFreezeSeconds-1)) {
            $.log("update fields abort, freeze as $.tempo_lap_freeze is  ", [$.tempo_lap_freeze]);
            return;
        }
        //#!JFS!# This clearing of the screen gets rid of the "Lap #xx" message, otherwise we end up with noise on the screen
        if ($.tempo_lap_freeze >= ($.lapFreezeSeconds-2)) {
            $.log("clear screen carry on, as $.tempo_lap_freeze is  ", [$.tempo_lap_freeze]);
            $.sdk.clearScreen(true); //#!JFS!# this is the right time to refresh the top line, after clearing the lap message
        }
    }
    if ($.swipe == true) {
        var before = after;
        $.log("set swipe false", []);
        $.swipe = false;
        $.updateCurrentLayouts(1);
        var fullBuffer = $.sdk.commandBuffer(0x01, []b) as Lang.ByteArray; // Clear Screen after a swipe (why not call clearScreen?)
        $.lastLapMessage = ""; //refresh top line after the clear
        if ($.tempo_pause == 0) {
            fullBuffer.addAll($.sdk.commandBuffer(0x62, [0x49, 0x00]b)); // layout petit pause
        }
        after = $.currentLayouts.size();
        if (before == 0 && after > 0) {
            $.tempo_off = -1;
            fullBuffer.addAll($.sdk.commandBuffer(0x00, [0x01]b)); // turn on screen
        } else if (after == 0) {
            $.tempo_off = 2;
            fullBuffer.addAll($.sdk.commandBuffer(0x62, [0x64, 0x00]b)); // layout screen off
            $.sdk.sendRawCmd("swipe-layout id", fullBuffer);
            $.sdk.resetLayouts([]);
            return;
        }
        $.sdk.sendRawCmd("swipe-clear-on", fullBuffer);
        $.sdk.resetLayouts([]);
    }
    if ($.tempo_off == 0) {
        return;
    }
    //$.sdk.flushCmdStackingIfSup(200);
    //at 20 bytes per write, this would take a long time
    $.sdk.flushCmdStackingIfSup(200);
    $.sdk.holdGraphicEngine();
    for (var i = 0; i < after; i++) {
        var asStr = Layouts.get($.currentLayouts[i]);
        //log("updateFields", [i, asStr, $.currentLayouts]); //#!JFS!#
        $.sdk.updateLayoutValue($.currentLayouts[i][:id], asStr);
    }
    $.sdk.flushGraphicEngine();
}

(:typecheck(false))
class DataFieldDrawable extends WatchUi.Drawable {

    public var bg as Graphics.ColorType = Graphics.COLOR_DK_GRAY;
    public var updateMsg as Lang.String? = null;
    public var updateMsgSecondRow as Lang.String? = null;
    public var updateMsgThirdRow as Lang.String? = null;

    function initialize() {
        Drawable.initialize({ :id => "canvas" });

        //#!JFS!# get data we need for HrPwr
        var profile = UserProfile.getProfile();
        weight = profile.weight / 1000.0; //grams to Kg
        //hrZones = profile.getHeartRateZones(profile.getCurrentSport());
        //MaxHR = hrZones[5];
        //weight = weight.toLong();
        rhr = profile.restingHeartRate;

    }

    function toFullChronoStrJFS(value as Lang.Array<Lang.Number> or Null) as Lang.String {
        if (value == null) {
            return "--:--:--";
        }
        return Lang.format("$1$:$2$:$3$", [ value[0].format("%02d"), value[1].format("%02d"), value[2].format("%02d") ]);
    }


    function draw(dc as Graphics.Dc) as Void {
        var fg = self.bg == Graphics.COLOR_BLACK ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(fg, self.bg);
        dc.clear();
        var midX = dc.getWidth() / 2d;                // x 50%
        var midY = dc.getHeight() * 3d / 5d;          // y 60%
        if(self.updateMsg != null && self.updateMsgSecondRow != null && self.updateMsgThirdRow != null){
            dc.drawText(midX, midY - 40d, Graphics.FONT_XTINY, self.updateMsg, justify); // (50%, 20%)
            dc.drawText(midX, midY - 20d, Graphics.FONT_XTINY, self.updateMsgSecondRow, justify); // (50%, 40%)
            dc.drawText(midX, midY, Graphics.FONT_XTINY, self.updateMsgThirdRow, justify); // (50%, 60%)
        }else if (self.updateMsg != null) {
            dc.drawText(midX, midY / 4, Graphics.FONT_XTINY, "ActiveLook (Fellrnr)", justify); // (50%, 15%)
            dc.drawText(midX, midY, Graphics.FONT_XTINY, self.updateMsg, justify); // (50%, 60%)
        }else {
            var p = "X";
            if(AugmentedActivityInfo.__ai != null && AugmentedActivityInfo.chrono != null) {
                p = toFullChronoStrJFS(AugmentedActivityInfo.chrono);
            }

            dc.drawText(midX, midY / 4, Graphics.FONT_XTINY, "D0715a: " + p, justify); // (50%, 15%)

            //note, the icon's are done using a custom font, with each number mapped to a png image in the assets/fonts/alfont folder
            var font = WatchUi.loadResource(Rez.Fonts.alfont) as Graphics.FontType;
            if (!ActiveLookSDK.isReady()) {
                dc.drawText(midX, midY, font, "5", justify); // (50%, 60%)
            } else {
                // status: 4 = connected
                dc.drawText(midX / 2, midY, font, "4", justify); // (25%, 60%)
                // battery;
                if ($.battery != null) {
                    var batteryStr =
                          $.battery < 10 ? "0"
                        : $.battery < 50 ? "1"
                        : $.battery < 90 ? "2"
                        : "3";
                    dc.drawText(midX * 3 / 2, midY, font, batteryStr, justify); // (75%, 60%)
                    //show the actual battery percent, as the icon is only a rough range (0-10-50-90-100)
                    dc.drawText(midX, midY, Graphics.FONT_MEDIUM, ($.battery).format("%d") + "%", justify); // (50%, 60%)
                } else {
                    // page number = pageIdx + 1
                    //not much use, so only show page if no battery
                    dc.drawText(midX, midY, Graphics.FONT_MEDIUM, ($.pageIdx + 1).format("%d"), justify); // (50%, 60%)

                }
            }
        }
    }
}

(:typecheck(false))
class ActiveLookDataFieldView extends WatchUi.DataField {

    hidden var __heart_count = -3;
    hidden var __lastError = null;

    var __is_auto_loop = Toybox.Application.Properties.getValue("is_auto_loop") as Toybox.Lang.Boolean or Null;
    var __loop_timer = Toybox.Application.Properties.getValue("loop_timer") as Toybox.Lang.Integer or Null;

    var _currentGestureStatus = Toybox.Application.Properties.getValue("is_gesture_enable") as Toybox.Lang.Boolean;
    var _nextGestureStatus = Toybox.Application.Properties.getValue("is_gesture_enable") as Toybox.Lang.Boolean;
    var _currentAlsStatus = Toybox.Application.Properties.getValue("is_als_enable") as Toybox.Lang.Boolean;
    var _nextAlsStatus = Toybox.Application.Properties.getValue("is_als_enable") as Toybox.Lang.Boolean;

    private var canvas as DataFieldDrawable = new DataFieldDrawable();


    function initialize() {
        DataField.initialize();

        antplusBikePower = new AntPlus.BikePower(null);

        $.resetGlobalsNext();
        $.sdk = new ActiveLookSDK.ALSDK(self);
        View.setLayout([self.canvas]);
        if(Toybox.AntPlus has :RunningDynamics) {
    		runningDynamics = new Toybox.AntPlus.RunningDynamics(null);
		}

        if(UseCore) {
			coreField = new CoreField(self, StoreCore);
        }
    }

    // Called from App.onStart()
    function onStart() {

	}

    // Called from App.onStop()
    function onStop() {

	}


    function onLayout(dc) {
        self.canvas.bg = self.getBackgroundColor();
        return View.onLayout(dc);
    }

    var __starttimer as Lang.Number;
    var __endtimer as Lang.Number = 0;
    function compute(info) {
        log("Enter Compute", []);

        __starttimer = System.getTimer();

        //core sensor
        if(UseCore) {
            coreField.computeCore();
            AugmentedActivityInfo.getCore(coreField);
        }

        _nextGestureStatus = Toybox.Application.Properties.getValue("is_gesture_enable");
        _nextAlsStatus = Toybox.Application.Properties.getValue("is_als_enable");
        AugmentedActivityInfo.accumulate(info);
        AugmentedActivityInfo.compute(info);
        var rdd = null;
        if (runningDynamics != null) {
            rdd = runningDynamics.getRunningDynamics();
            ActiveLook.Laps.accumulateRunningDynamics(rdd);
            AugmentedActivityInfo.accumulateRunningDynamics(rdd);
            AugmentedActivityInfo.computeRunningDynamics(rdd);
        }

        //decrement $.tempo_lap_freeze here rather than below in updateFields
        if ($.tempo_lap_freeze >= 0) {
            $.tempo_lap_freeze -= 1;
        }

        if ($.tempo_lap_freeze == -1) {
            ActiveLook.Laps.compute(info);
            if (rdd != null) {
                ActiveLook.Laps.computeRunningDynamics(rdd);
            }
        } else {
            //$.amsg("don't call laps.compute (freeze),  as $.tempo_lap_freeze is  " + $.tempo_lap_freeze);
        }
        self.__heart_count += 1;
        if (self.__heart_count < 0) {
            log("compute", [info, self.__heart_count]);
            timeIt();
            return null;
        }

		if (ActiveLookSDK.isIdled() && !ActiveLookSDK.isReconnecting && !ActiveLookSDK.isConnected()) {
			$.sdk.startGlassesScan();
		} else if (!ActiveLookSDK.isReady()) {
			if (self.__lastError != null && (self.__heart_count - self.__lastError) > 50) {
				self.__lastError = null;
				$.sdk.disconnect();
			} else if (ActiveLookSDK.isConnected()) {
				var retval = $.sdk.setUpDevice();
                timeIt();
                return retval;
			}
		} else {
			self.__lastError = null;
		}
        var ct = System.getClockTime();
        var hour = ct.hour;
        if (System.getDeviceSettings().is24Hour == false && hour > 12) {
            hour = hour - 12;
        }
        if (ActiveLookSDK.isReady()) {
//            log("compute::updateFields  ", [self.__heart_count]);//#!JFS!#
            if(self.__is_auto_loop){
                if(self.__loop_timer.equals(0)){
                    log("onLoopEvent", []);
                    $.swipe = true;
                    self.__loop_timer = Toybox.Application.Properties.getValue("loop_timer");
                }else{
                    self.__loop_timer -= 1;
                }
            }            $.updateFields();
            if($.replaceTimeWithLap) {
                log("compute-check lap", [self.__heart_count]);
                //need to update lap message (takes up a lot of bluetooth bandwidth)
                if($.lastLapMessage.compareTo($.lapMessage) != 0) {
                    $.lastLapMessage = $.lapMessage;
                    $.sdk.setLap($.lapMessage);
                }
            } else {
                //log("compute-{time}  ", [self.__heart_count]);
                $.sdk.setTime(hour, ct.min);
                $.sdk.setBattery($.battery);
            }
            $.sdk.resyncGlasses();
            if(_nextGestureStatus != _currentGestureStatus){
                _currentGestureStatus = _nextGestureStatus;
                self.onSettingClickGestureEvent();
            }
            if(_nextAlsStatus != _currentAlsStatus){
                _currentAlsStatus = _nextAlsStatus;
                self.onSettingClickAlsEvent();
            }
        }

        timeIt();
        return null;
    }

    function timeIt()
    {
        var endtimer;
        endtimer = System.getTimer();
        var total = endtimer - __starttimer;
        var delay = -1;
        if(__endtimer != 0) {
            delay = __starttimer - __endtimer;
        }
        if(delay > 1000 || total > 100) {
            log("Time taken " + total.format("%d") + ", delay " + + delay.format("%d"), []);
        }
        __endtimer = endtimer;
    }

    //! The activity timer has started.
    //! This method is called when the activity timer goes from a stopped state to a started state.
    //! If the activity timer is running when the app is loaded, this event will run immediately after startup.
    function onTimerStart() {
        //if ($.tempo_pause == -1) { // If not in pause mode, it is a new session

        if ($.tempo_started == -1) { // If not in pause mode, it is a new session
            $.tempo_started = 0;
            AugmentedActivityInfo.onSessionStart();

            var workoutMsg = getWorkoutDetails();

            if(workoutMsg != null) {
                log("onTimerStart: " + workoutMsg, [self.__heart_count]);
                $.lapMessage = workoutMsg;
            }else {
                log("onTimerStart, no workout", [self.__heart_count]);
                $.lapMessage = "Warm Up"; //a default friendly message
            }

        }
        self.onTimerResume();
    }

    //! The activity timer is paused.
    //! This method is called when the activity timer goes from a running state to a paused state.
    //! The paused state occurs when the auto-pause feature pauses the timer.
    //! If the activity timer is paused when the app is loaded, this event will run immediately after startup.
    function onTimerPause() {
        $.tempo_congrats = -1;
        if ($.tempo_off == -1) {
            $.tempo_pause = 6;
            if (ActiveLookSDK.isReady()) {
                var fullBuffer = $.sdk.commandBuffer(0x01, []b) as Lang.ByteArray; // Clear Screen when timer paused
                fullBuffer.addAll($.sdk.commandBuffer(0x62, [0x62, 0x00]b)); // layout pause
                $.sdk.sendRawCmd("layout pause", fullBuffer);
                $.sdk.resetLayouts([]);
            }
        } else {
            $.tempo_pause = 1;
        }
    }

    //! The activity time has resumed.
    //! This method is called when the activity timer goes from a paused state to a running state.
    function onTimerResume() {
        $.tempo_pause = -1;
        $.tempo_congrats = -1;
        if ($.tempo_off == -1) {
            if (ActiveLookSDK.isReady()) {
                $.sdk.clearScreen(true); //#!JFS!# assume top line is out of date
            }
        }
    }

    //! The activity timer has stopped.
    //! This method is called when the activity timer goes from a running state to a stopped state.
    function onTimerStop() {
        self.onTimerPause(); // In fact, it is a pause. The reset event is the real stop.
    }

    //! The current activity has ended.
    //! This method is called when the time has stopped and current activity is ended.
    function onTimerReset() as Void {
        //$.tempo_pause = -1;
        $.tempo_pause = 0;
        $.tempo_started = -1;
        if ($.tempo_off == -1) {
            $.tempo_congrats = 6;
            if (ActiveLookSDK.isReady()) {
                var fullBuffer = $.sdk.commandBuffer(0x01, []b) as Lang.ByteArray; // Clear Screen in timer reset
                fullBuffer.addAll($.sdk.commandBuffer(0x62, [0xB4, 0x00]b)); // layout Session Complete
                $.sdk.sendRawCmd("layout reset", fullBuffer);
                $.sdk.resetLayouts([]);
                resetGlobals();
            }
        } else {
            $.tempo_congrats = 1;
        }
        $.lapMessage = "Done";

    }

    function onTimerLap() as Void {

        //log("onTimerLap {enter} ", [self.__heart_count]);

        AugmentedActivityInfo.addLap();


        //#!JFS!# Don't freeze the display for 10 seconds, and add the option to count intervals rather than laps
        $.tempo_lap_freeze = $.lapFreezeSeconds;
        //log("timer lap, set $.tempo_lap_freeze to: " + $.tempo_lap_freeze, [self.__heart_count]);
        $.tempo_pause = -1;
        $.tempo_congrats = -1;
        if ($.tempo_off == -1) {
            if (ActiveLookSDK.isReady()) {
                var data = []b;
                //data for 0x37 command, display text
                //data.addAll($.sdk.numberToFixedSizeByteArray(250, 2)); //x
                //data.addAll($.sdk.numberToFixedSizeByteArray(170, 2)); //y
                //data.addAll([4, 3, 15]b); //rotation (4=norma), font size, color?
                //font 1=24px, 2=38, 3=64, 4=75, 5=82
                //screen size is 304; 256

                //smaller font for more data
                data.addAll($.sdk.numberToFixedSizeByteArray(280, 2)); //x
                data.addAll($.sdk.numberToFixedSizeByteArray(170, 2)); //y
                data.addAll([4, 2, 15]b); //rotation (4=norma), font size, color?


                ////#!JFS!# Get workout data if it's there
                var workoutMsg = getWorkoutDetails();

                if(workoutMsg != null) {
                    $.lapMessage = workoutMsg;
                } else if($.lapsPerInterval > 1) {
                    var intNo = ActiveLook.Laps.intervalNumber % 100;
                    if(ActiveLook.Laps.lapNumber % $.lapsPerInterval == 0) { //note, modulo the lap number not the interval number!
                        $.lapMessage = "R" + intNo.format("%02d");
                    } else {
                        $.lapMessage = "I" + intNo.format("%02d");
                    }
                } else {
                    $.lapMessage = Toybox.Lang.format("Lap $1$", [ActiveLook.Laps.lapNumber % 100]);
                }

                var banner;
                if(ActiveLook.Laps.lapAveragePowerPrevious != null && ActiveLook.Laps.lapAveragePowerPrevious != 0) {
                    banner = $.lapMessage + " (" + ActiveLook.Laps.lapAveragePowerPrevious.format("%.0f") + "w)";
                } else {
                    banner = $.lapMessage;
                }

                //data.addAll($.sdk.stringToPadByteArray($.lapMessage, null, null));
                data.addAll($.sdk.stringToPadByteArray(banner, null, null));
                var fullBuffer = $.sdk.commandBuffer(0x01, []b) as Lang.ByteArray; // Clear Screen in onTimerLap, but after two seconds we should clear screen again with battery/time resets
                fullBuffer.addAll($.sdk.commandBuffer(0x37, data)); // Text lap number
                $.sdk.sendRawCmd("text lap big", fullBuffer);
                $.sdk.resetLayouts([]);

                //$.lapMessage = "123456789 123456789 123456789 123456789 ";
                //we have about 25 characters width
            }
        }
        //log("onTimerLap {exit} ", [self.__heart_count]);
    }

    function getWorkoutDetails() {
        var workoutMsg = null;
        if (Activity has :getCurrentWorkoutStep) {
            var workoutStepInfo = Activity.getCurrentWorkoutStep();
            if (workoutStepInfo != null) {
                if (workoutStepInfo has :step && workoutStepInfo.step != null) {
                    if (workoutStepInfo.step instanceof Activity.WorkoutStep) {
                        //workoutMsg += "S";
                        workoutMsg = getWorkoutStepDetails(workoutStepInfo, workoutStepInfo.step);
                    }
                    else if (workoutStepInfo.step instanceof Activity.WorkoutIntervalStep) { //we never go down this path, so consider removing to save space

                        if($.workoutIntervalIsActive) {
                            workoutMsg = "A";
                            if (workoutStepInfo.step has :activeStep && workoutStepInfo.step.activeStep != null) {
                                workoutMsg += getWorkoutStepDetails(workoutStepInfo, workoutStepInfo.step.activeStep);
                            }
                            $.workoutIntervalIsActive = false;
                        } else {
                            workoutMsg = "R";
                            if (workoutStepInfo.step has :restStep && workoutStepInfo.step.restStep != null) {
                                workoutMsg += getWorkoutStepDetails(workoutStepInfo, workoutStepInfo.step.restStep);
                            }
                            $.workoutIntervalIsActive = true;
                        }

                    }
                }
            }
        }
        return workoutMsg;

    }

    function getWorkoutStepDetails(workoutStepInfo, workoutStep) {
        var workoutMsg = "";
        var intensityType = "";

        if (workoutStepInfo has :intensity && workoutStepInfo.intensity != null) {
            if(workoutStepInfo.intensity == Activity.WORKOUT_INTENSITY_ACTIVE) {
                $.workoutCounter++;
                intensityType = "go";
            } else if(workoutStepInfo.intensity == Activity.WORKOUT_INTENSITY_REST) {
                intensityType = "rest";
            } else if(workoutStepInfo.intensity == Activity.WORKOUT_INTENSITY_WARMUP) {
                intensityType = "wu";
            } else if(workoutStepInfo.intensity == Activity.WORKOUT_INTENSITY_COOLDOWN) {
                intensityType = "cd";
            } else if(workoutStepInfo.intensity == Activity.WORKOUT_INTENSITY_RECOVERY) {
                intensityType = "rec";
            } else if(workoutStepInfo.intensity == Activity.WORKOUT_INTENSITY_INTERVAL) {
                $.workoutCounter++;
                intensityType = "int";
            } else {
                intensityType = "?";
            }
        } else {
            intensityType = "!";
        }

        workoutMsg += $.workoutCounter.format("%02d") + intensityType;

        var duration = 0;

        if (workoutStep has :durationValue && workoutStep.durationValue != null && workoutStep.durationValue != 0) {
            duration = workoutStep.durationValue;
        }

        if (workoutStep has :durationType && workoutStep.durationType != null) {
            if(workoutStep.durationType == Activity.WORKOUT_STEP_DURATION_DISTANCE) {
                if(duration > 1000) {
                    var durationKm = duration / 1000.0;
                    duration = duration.toNumber();
                    if(duration % 100 == 0) {
                        workoutMsg += durationKm.format("%.1f") + "km";
                    } else if(duration % 10 == 0) {
                        workoutMsg += durationKm.format("%.2f") + "km";
                    } else {
                        workoutMsg += durationKm.format("%.3f") + "km";
                    }
                } else {
                    workoutMsg += duration.format("%d") + "m";
                }

            } else if(workoutStep.durationType == Activity.WORKOUT_STEP_DURATION_TIME) {
                if(duration > 60) {
                    var value = Math.round(duration).toLong();
                    workoutMsg += Lang.format("$1$:$2$", [ (value / 60).format("%02d"), (value % 60).format("%02d") ]);
                } else {
                    workoutMsg += duration.format("%d") + "s";
                }

            } else if(workoutStep.durationType == Activity.WORKOUT_STEP_DURATION_OPEN) {
                workoutMsg += "p";
            } else {
                workoutMsg += workoutStep.durationType;
            }
        }

        if (workoutStepInfo has :notes && workoutStepInfo.notes != null) {
            workoutMsg += ":" + workoutStepInfo.notes.substring(null, 10); //only have about 25 total
        }

        return workoutMsg;
    }


    function onNextMultisportLeg() as Void {
        self.onTimerLap();
    }
    function onWorkoutStepComplete() as Void {
        self.onTimerLap();
    }

    //////////////////
    // SDK Listener //
    //////////////////
    function onFirmwareEvent(major as Toybox.Lang.Number, minor as Toybox.Lang.Number, patch as Toybox.Lang.Number) as Void {
        $.log("onFirmwareEvent", [major, minor, patch]);
        major -= 4;
        minor -= 6;
        if (major > 0) {
            self.canvas.updateMsg = Application.loadResource(Rez.Strings.update_datafield);
        } else if (major < 0 || minor < 0) {
            self.canvas.updateMsg = Application.loadResource(Rez.Strings.update_glasses);
            self.canvas.updateMsgSecondRow = Application.loadResource(Rez.Strings.update_glasses_second_row);
            self.canvas.updateMsgThirdRow = Application.loadResource(Rez.Strings.update_glasses_third_row);
        } else {
            self.canvas.updateMsg = null;
            self.canvas.updateMsgSecondRow = null;
            self.canvas.updateMsgThirdRow = null;
            var data = $.sdk.stringToPadByteArray("ALooK", null, null);
            var cfgSet = $.sdk.commandBuffer(0xD2, data);
            $.sdk.sendRawCmd("firmware", cfgSet);
        }
    }
    function onCfgVersionEvent(cfgVersion as Toybox.Lang.Number) as Void {
        $.log("onCfgVersionEvent", [cfgVersion]);
        cfgVersion -= 12;
        if (cfgVersion < 0 && self.canvas.updateMsg == null) {
            self.canvas.updateMsg = Application.loadResource(Rez.Strings.update_glasses);
            self.canvas.updateMsgSecondRow = Application.loadResource(Rez.Strings.update_glasses_second_row);
            self.canvas.updateMsgThirdRow = Application.loadResource(Rez.Strings.update_glasses_third_row);
        }
    }
    function onGestureEvent() as Void {
        $.log("onGestureEvent", []);
        $.swipe = true;
        if(self.__is_auto_loop){self.__loop_timer = Toybox.Application.Properties.getValue("loop_timer");}
    }
    function onBatteryEvent(batteryLevel as Toybox.Lang.Number) as Void {
        //$.log("onBatteryEvent", [batteryLevel]);
        $.battery = batteryLevel;
    }
    function onDeviceReady() as Void {
        $.log("onDeviceReady", []);
        if ($.tempo_off >= 0) {
            $.tempo_off = 2;
            $.tempo_pause = -1;
            $.tempo_congrats = -1;
            return;
        }
        $.tempo_off = -1;
        if ($.tempo_pause >= 0) {
            $.tempo_pause = 1;
            $.tempo_congrats = -1;
            return;
        }
        $.tempo_pause = -1;
        if ($.tempo_congrats >= 0) {
            $.tempo_congrats = 1;
            return;
        }
        $.sdk.clearScreen(false);
        $.tempo_congrats = -1;
    }
    function onDeviceDisconnected() as Void {
        $.log("onDeviceDisconnected", []);
        $.swipe = false;
        $.battery = null;
    }
    function onBleError(msg, exception as Toybox.Lang.Exception) as Void {
        // $.log("onBleError", exception);
        if (self.__lastError == null) {
            self.__lastError = self.__heart_count;
        }
    }
    function onSettingClickGestureEvent(){
        if (ActiveLookSDK.isReady()) {
            $.log("onSettingClickGestureEvent", []);
            var data = []b;
            if(_currentGestureStatus){data = [0x01]b;}else{data = [0x00]b;}
            var gestureSet = $.sdk.commandBuffer(0x21, data);
            $.sdk.sendRawCmd("onSettingClickGestureEvent", gestureSet);
        }
    }
    function onSettingClickAlsEvent(){
        if (ActiveLookSDK.isReady()) {
            $.log("onSettingClickAlsEvent", []);
            var data = []b;
            if(_currentAlsStatus){data = [0x01]b;}else{data = [0x00]b;}
            var alsSet = $.sdk.commandBuffer(0x22, data);
            $.sdk.sendRawCmd("onSettingClickAlsEvent", alsSet);
        }
    }
}

//! Global variables.
var glassesName as Toybox.Lang.String = "";
var lapsPerInterval as Toybox.Lang.Number = 0; //#!JFS!#
var lapFreezeSeconds as Toybox.Lang.Number = 10; //#!JFS!#
var replaceTimeWithLap = true; //#!JFS!# (make this configurable if it works)
var lapMessage = "Paused";
var lastLapMessage = "";
var workoutIntervalIsActive = true;
var workoutCounter = 0;
var UseCore = false;
var StoreCore = false;
var ZeroPowerHR = 0;
var HrPwrSmoothing = 0;
var coreField = null;
var weight;
var rhr;


//! Reset global variables.
//! They represent the actual state of the DataField.
function resetGlobalsNext() as Void {
    $.resetGlobals();
    var __glassesName = Toybox.Application.Properties.getValue("glasses_name") as Toybox.Lang.String or Null;
    if (__glassesName == null) { __glassesName = ""; }
    // TODO: >>> Remove deprecated backward compatibility
    if (__glassesName.equals("")) {
        __glassesName = Application.Storage.getValue("glasses");
        if (__glassesName == null) { __glassesName = ""; }
        Toybox.Application.Properties.setValue("glasses_name", __glassesName);
        Toybox.Application.Storage.setValue("glasses", __glassesName);
    }
    // TODO: <<< Remove deprecated backward compatibility
    $.glassesName = __glassesName as Toybox.Lang.String;

    //#!JFS!# add laps per interval
    var __laps_per_interval = Toybox.Application.Properties.getValue("laps_per_interval") as Toybox.Lang.Number or Null;
    if (__laps_per_interval == null) { __laps_per_interval = 0; }
    $.lapsPerInterval = __laps_per_interval;

    //#!JFS!# add lap freeze seconds
    var __lap_freeze_seconds = Toybox.Application.Properties.getValue("lap_freeze_seconds") as Toybox.Lang.Number or Null;
    if (__lap_freeze_seconds == null) { __lap_freeze_seconds = 9; }
    $.lapFreezeSeconds = __lap_freeze_seconds -1; //counter goes to reach -1,

    UseCore = Toybox.Application.Properties.getValue("UseCore");
    StoreCore = Toybox.Application.Properties.getValue("StoreCore");
    ZeroPowerHR = Toybox.Application.Properties.getValue("ZeroPowerHR");
    HrPwrSmoothing = Toybox.Application.Properties.getValue("HrPwrSmoothing");

    lapMessage = "Not started";
}

//! Global ScanRescult handler.
//! Defining it in this scope make it available from anywhere.
function onScanResult(scanResult as Toybox.BluetoothLowEnergy.ScanResult) as Void {
    $.log("onScanResult", [scanResult]);
    var deviceName = scanResult.getDeviceName();
    if (scanResult.getDeviceName() == null) { deviceName = ""; }
    if ($.glassesName.equals("")) {
        Toybox.Application.Properties.setValue("glasses_name", deviceName);
        $.glassesName = deviceName as Toybox.Lang.String;
    } else if (!$.glassesName.equals(deviceName)) { return; }
    $.sdk.connect(scanResult);
}
