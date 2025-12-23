using Toybox.WatchUi;
using Toybox.Application;
using Toybox.Graphics;
using Toybox.System;
import Toybox.Lang;


(:release) function dmsg(msg as Toybox.Lang.String) as Void {} //#!JFS!#
(:debug) function dmsg(msg as Toybox.Lang.String) as Void {} //#!JFS!#
(:debug) function dmsgX(msg as Toybox.Lang.String) as Void {
    var myTime = System.getClockTime(); // ClockTime object
    System.println(
        myTime.hour.format("%02d") + ":" +
        myTime.min.format("%02d") + ":" +
        myTime.sec.format("%02d") + ": " + msg
        );
} //#!JFS!#

(:release) function emsg(msg as Toybox.Lang.String) as Void {} //#!JFS!#
(:debug) function emsg(msg as Toybox.Lang.String) as Void { Toybox.System.println(msg); } //#!JFS!#


class CoreField {

    var coreTemperature = -4.0;
    var skinTemperature = -4.0;
    var heatStrainIndex = -4.0;
    var heatIndicator = -4.0;

    hidden var searchingFrozenCount = 0;
    var mFitContributor = null  as CoreFitContributor or Null;;				// Fit Contributor

    var mSensor = null as CoreSensor or Null;

    var DataField; //an object that implements createField to create fit data

    function initialize(aDataField, storeCore) {
        DataField = aDataField;
        if(storeCore) {
            mFitContributor = new CoreFitContributor(DataField);
        }
    }	// end func initialize


    function computeCore() {
        //we only get in here if we're using core
        //$.dmsg("computeCore, mSensor " + mSensor);
        if ((mSensor == null) || ((mSensor.msgTimeStamp != null) && ((Time.now().value() - mSensor.msgTimeStamp.value()) > (mSensor.SENSOR_TIMEOUT + 5)))) {
            // if no sensor or it is 'stuck' after a sleep mode, no input from ant sensor after
            dataFieldReset( true );											// sensor hard reset!!
            //resort to magic values to give clues as the glasses won't easily give alpha
            coreTemperature = -1.0;
            skinTemperature = -1.0;
            return;
        }

        if ( mSensor.searching > 0 ) {
            mSensor.searching++;	// approximatly ticks / seconds searching
            $.dmsg("computeCore, searching " + mSensor.searching);

            if ((mSensor.searching > 29) ||  !mSensor.data.isValidCoreTemp( coreTemperature )) {

                searchingFrozenCount++;
                //$.dmsg("computeCore, searchingFrozenCount " + searchingFrozenCount);
                if ( searchingFrozenCount > 73 ) {		// nothing found for about 103 seconds
                    // searching looks frozen - reset the sensor
                    dataFieldReset( false );
                    //resort to magic values to give clues as the glasses won't easily give alpha characters
                    coreTemperature = -2.0;
                    skinTemperature = -2.0;
                    heatStrainIndex = -2.0;
                    return;
                } else {
                    return; //keep the last values
                }
            }
        } else {
            searchingFrozenCount = 0;
        }

        if ( !mSensor.data.isValidCoreTemp( mSensor.data.CoreTemp )) {
            // Invalid CORE temperature - calculating
            //resort to magic values to give clues as the glasses won't easily give alpha
			coreTemperature = -3.0;
            skinTemperature = -3.0;
            heatStrainIndex = -3.0;
            $.dmsg("computeCore, invalid temp " + mSensor.data.CoreTemp);
            return;
        }

        //-----------------------
        // Valid CORE temperature
        //-----------------------
        if ( isDatafieldFrozen()) {
            // if the Sensor seems to be 'stuck' - re-initialize the datafield
            dataFieldReset( false );												// force a 'reset'
        }
        coreTemperature = mSensor.data.CoreTemp;
        skinTemperature = mSensor.data.SkinTemp;
        heatStrainIndex = mSensor.data.HeatStrainIndex;

        if(heatStrainIndex < 0.1) {
            heatIndicator = coreTemperature;
        } else {
            heatIndicator = heatStrainIndex;
        }

        //$.dmsg("computeCore, got core temp " + mSensor.data.CoreTemp + ", skin temp " + mSensor.data.SkinTemp);

        //ignore battery for simplicity


        //-------------------------------
        // log CORE value in the FIT file
        //-------------------------------
        if ( mFitContributor != null ) {
            mFitContributor.compute(mSensor);
        }

    }	// end func compute

    var lastValidCoreTemp = 0.0;
    var displayCount = 0;
    var lastTempChangeDispCount = 0;
    function isDatafieldFrozen() {
        // if the values are not changing for some reason - reset the ANT connection

        displayCount++; //increment roughly 1/sec
        if ( mSensor != null && lastValidCoreTemp == mSensor.data.CoreTemp ) {
            if ((lastTempChangeDispCount + 270) < displayCount ) {		// over 4.5 minutes = 270 seconds
                return true;
            }
        } else {
            lastTempChangeDispCount = displayCount;
        }

        return false;
    }	// end func datafieldFrozen

    function dataFieldReset( hardReset ) {
        // re-initialize the datafield and sensor
        // on settings change or if field seems to be 'stuck'
        //---------------------------------------------------
        //emsg("core dataFieldReset hard:" + hardReset);
        if ( mSensor != null ) {
            //emsg("core dataFieldReset close sensor");
            mSensor.close();

            if ( hardReset == true ) {
                mSensor.release();			// release the ant channel before reopening a new one
                mSensor = null;				// close the sensor and force a re-initialize
            }
        }

        if ( mSensor == null ) {
            try {
                //Create the sensor object and open it
                //emsg("core dataFieldReset create sensor");
                mSensor = new CoreSensor();
            } catch (e) {
                System.println(e.getErrorMessage());
                System.println(e.printStackTrace());
                mSensor = null;
            }
        }

        if ( mSensor != null ) {
            //initFieldData();
            //emsg("dataFieldReset init");
            mSensor.initialize();		// force the new ANT ID
            mSensor.open();
            if(mFitContributor != null) {
                mFitContributor.initialize(DataField);
            }
        }
    }	// end func dataFieldReset




}
