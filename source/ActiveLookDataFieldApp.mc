using Toybox.Application;

(:typecheck(false))
class ActiveLookDataFieldApp extends Application.AppBase {

    private var _view;

    function initialize() {
        AppBase.initialize();
        _view = new ActiveLookDataFieldView();
    }

    // onStart() is called on application start up
    function onStart(state) {
        _view.onStart();
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
        _view.onStop();
    }

    //! Return the initial view of your application here
    function getInitialView() {
        return [ _view ];
    }

}
