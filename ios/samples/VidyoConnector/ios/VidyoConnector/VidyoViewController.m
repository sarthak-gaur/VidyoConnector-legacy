/**
{file:
	{name: VidyoViewController.m}
	{description: .}
	{copyright:
		(c) 2017-2018 Vidyo, Inc.,
		433 Hackensack Avenue, 7th Floor,
		Hackensack, NJ  07601.

		All rights reserved.

		The information contained herein is proprietary to Vidyo, Inc.
		and shall not be reproduced, copied (in whole or in part), adapted,
		modified, disseminated, transmitted, transcribed, stored in a retrieval
		system, or translated into any language in any form by any means
		without the express written consent of Vidyo, Inc.
		                  ***** CONFIDENTIAL *****
	}
}
*/
#import <Foundation/Foundation.h>
#import "VidyoConnectorAppDelegate.h"
#import "VidyoViewController.h"
#import "AppSettings.h"
#import "Logger.h"

enum VidyoConnectorState {
    VidyoConnectorStateConnecting,
    VidyoConnectorStateConnected,
    VidyoConnectorStateDisconnecting,
    VidyoConnectorStateDisconnected,
    VidyoConnectorStateDisconnectedUnexpected,
    VidyoConnectorStateFailure,
    VidyoConnectorStateFailureInvalidResource
};

@interface VidyoViewController () {
@private
    enum VidyoConnectorState vidyoConnectorState;
    VCConnector   *vc;
    VCLocalCamera *lastSelectedCamera;
    AppSettings   *appSettings;
    Logger        *logger;
    UIImage       *callStartImage;
    UIImage       *callEndImage;
    BOOL          devicesSelected;
    CGFloat       keyboardOffset;
}
@end

@implementation VidyoViewController

@synthesize toggleConnectButton, cameraPrivacyButton, microphonePrivacyButton;
@synthesize videoView, controlsView, toolbarView;
@synthesize portal, roomKey, roomPin, displayName;
@synthesize connectionSpinner, toolbarStatusText, bottomControlSeparator, clientVersion;

#pragma mark - View Lifecycle

// Called when the view is initially loaded
- (void)viewDidLoad {
    [logger Log:@"VidyoViewController::viewDidLoad"];
    [super viewDidLoad];
    
    // Initialize the logger and app settings
    logger = [[Logger alloc] init];
    appSettings = [[AppSettings alloc] init];
    
    // Initialize the member variables
    vidyoConnectorState = VidyoConnectorStateDisconnected;
    lastSelectedCamera = nil;
    devicesSelected = YES;

    // Initialize the toggle connect button to the callStartImage
    callStartImage = [UIImage imageNamed:@"callStart.png"];
    callEndImage = [UIImage imageNamed:@"callEnd.png"];
    [toggleConnectButton setImage:callStartImage forState:UIControlStateNormal];

    // add border and border radius to controlsView
    [controlsView.layer setCornerRadius:10.0f];
    [controlsView.layer setBorderColor:[UIColor lightGrayColor].CGColor];
    [controlsView.layer setBorderWidth:0.5f];

    // Initialize the Vidyo Client library; this should be done once throughout the lifetime of the application.
    [VCConnectorPkg vcInitialize];

    // Construct the VidyoConnector
    vc = [[VCConnector alloc] init:(void*)&videoView
                            ViewStyle:VCConnectorViewStyleDefault
                            RemoteParticipants:7
                            LogFileFilter:"info@VidyoClient info@VidyoConnector warning"
                            LogFileName:""
                            UserData:0];
    
    if (vc) {
        // Set the client version in the toolbar
        [clientVersion setText:[NSString stringWithFormat:@"VidyoClient-iOSSDK %@", [vc getVersion]]];

        // Register for local camera events
        if (![vc registerLocalCameraEventListener:self]) {
            [logger Log:@"registerLocalCameraEventListener failed"];
        }
        // Register for local microphone events
        if (![vc registerLocalMicrophoneEventListener:self]) {
            [logger Log:@"registerLocalMicrophoneEventListener failed"];
        }
        // Register for local speaker events
        if (![vc registerLocalSpeakerEventListener:self]) {
            [logger Log:@"registerLocalSpeakerEventListener failed"];
        }
        // Register for log events; the filter argument specifies the log level that
        // is printed to console as well as what is called back in onLog.
        if ( ![vc registerLogEventListener:self Filter:"info@VidyoClient info@VidyoConnector warning"] ) {
            [logger Log:@"LogEventListener registration failed."];
        }
        // Apply the app settings
        [self applyAppSettings];
    } else {
        // Log error and ignore interaction events (text input, button press) to prevent further VidyoConnector calls
        [logger Log:@"ERROR: VidyoConnector construction failed ..."];
        [toolbarStatusText setText:@"VidyoConnector Failed"];
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    }

    // Register for OS notifications about when this app is active/inactive (background/foreground) and will terminate.

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillTerminate:)
                                                 name:UIApplicationWillTerminateNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [logger Log:@"VidyoViewController::viewWillAppear"];
    [super viewWillAppear:animated];

    // register for keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];

    // Begin listening for URL event notifications, which is triggered by the app delegate.
    // This notification will be triggered in all but the first time that a URL event occurs.
    // It is not necessary to handle the first occurance because applyAppSettings is viewDidLoad.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyAppSettings)
                                                 name:@"handleGetURLEvent"
                                               object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [logger Log:@"VidyoViewController::viewDidAppear"];
    [super viewDidAppear:animated];

    // Refresh the user interface
    if (vc) {
        [self refreshUI];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [logger Log:@"VidyoViewController::viewWillDisappear"];
    [super viewWillDisappear:animated];

    // unregister for keyboard notifications while not visible.
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillShowNotification
                                                  object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillHideNotification
                                                  object:nil];
}

#pragma mark - Application Lifecycle

- (void)appWillResignActive:(NSNotification*)notification {
    if (vc) {
        if (vidyoConnectorState == VidyoConnectorStateConnected ||
            vidyoConnectorState == VidyoConnectorStateConnecting) {
            // Connected or connecting to a resource.
            // Enable camera privacy so remote participants do not see a frozen frame.
            [vc setCameraPrivacy:YES];
        } else {
            // Not connected to a resource.
            // Release camera, mic, and speaker from this app while backgrounded.
            [vc selectLocalCamera:nil];
            [vc selectLocalMicrophone:nil];
            [vc selectLocalSpeaker:nil];
            devicesSelected = NO;
        }
        [vc setMode:VCConnectorModeBackground];
    }
}

- (void)appDidBecomeActive:(NSNotification*)notification {
    if (vc) {
        [vc setMode:VCConnectorModeForeground];

        if (!devicesSelected) {
            // Devices have been released when backgrounding (in appWillResignActive). Re-select them.
            devicesSelected = YES;

            // Select the previously selected local camera and default mic/speaker
            [vc selectLocalCamera:lastSelectedCamera];
            [vc selectDefaultMicrophone];
            [vc selectDefaultSpeaker];
        }

        // Reestablish camera and microphone privacy states
        [vc setCameraPrivacy:[appSettings cameraPrivacy]];
        [vc setMicrophonePrivacy:[appSettings microphonePrivacy]];
    }
}

- (void)appWillTerminate:(NSNotification*)notification {
    // Deregister from any/all notifications.
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Release the devices.
    lastSelectedCamera = nil;
    if (vc) {
        [vc selectLocalCamera:nil];
        [vc selectLocalMicrophone:nil];
        [vc selectLocalSpeaker:nil];
    }

    // Set the VidyoConnector to nil in order to decrement reference count and cleanup.
    vc = nil;

    // Uninitialize the Vidyo Client library; this should be done once throughout the lifetime of the application.
    [VCConnectorPkg uninitialize];

    // Close the log file
    [logger Close];
}

#pragma mark - Device Rotation

// The device interface orientation has changed
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];

    // Refresh the user interface
    [self refreshUI];
}

#pragma mark - Virtual Keyboard

// The keyboard pops up for first time or switching from one text box to another.
// Only want to move the view up when keyboard is first shown.
-(void)keyboardWillShow:(NSNotification *)notification {
    // Animate the current view out of the way
    if (self.view.frame.origin.y >= 0) {
        // Determine the keyboard coordinates and dimensions
        CGRect keyboardRect = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        keyboardRect = [self.view convertRect:keyboardRect fromView:nil];
        
        // Move the view only if the keyboard popping up blocks any text field
        if ((controlsView.frame.origin.y + bottomControlSeparator.frame.origin.y) > keyboardRect.origin.y) {
            keyboardOffset = controlsView.frame.origin.y + bottomControlSeparator.frame.origin.y - keyboardRect.origin.y;
            
            [UIView beginAnimations:nil context:NULL];
            [UIView setAnimationDuration:0.3]; // to slide up the view
            
            // move the view's origin up so that the text field that will be hidden come above the keyboard
            CGRect rect = self.view.frame;
            rect.origin.y -= keyboardOffset;
            self.view.frame = rect;

            [UIView commitAnimations];
        }
    }
}

// The keyboard is about to be hidden so move the view down if it previously has been moved up.
-(void)keyboardWillHide {
    if (self.view.frame.origin.y < 0) {
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:0.3]; // to slide down the view
        
        // revert back to the normal state
        CGRect rect = self.view.frame;
        rect.origin.y += keyboardOffset;
        self.view.frame = rect;

        [UIView commitAnimations];
    }
    [self refreshUI];
}

#pragma mark - Text Fields and Editing

// User finished editing a text field; save in user defaults
- (void)textFieldDidEndEditing:(UITextField *)textField {
    // If no URL parameters (app self started), then save text updates to user defaults
    NSMutableDictionary *urlParameters = [(VidyoConnectorAppDelegate *)[[UIApplication sharedApplication] delegate] urlParameters];
    if (!urlParameters) {
        if (textField == portal) {
            [appSettings setUserDefault:@"portal" value:textField.text];
        } else if (textField == roomKey) {
            [appSettings setUserDefault:@"roomKey" value:textField.text];
        } else if (textField == displayName) {
            [appSettings setUserDefault:@"displayName" value:textField.text];
        } else if (textField == roomPin) {
            [appSettings setUserDefault:@"roomPin" value:textField.text];
        }
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == portal) {
        // when hitting return in portal field, switch to display name field
        [displayName becomeFirstResponder];
    } else if (textField == displayName) {
        // when hitting return in display name field, switch to room key field
        [roomKey becomeFirstResponder];
    } else if (textField == roomKey) {
        // when hitting return in room key field, switch to room pin field
        [roomPin becomeFirstResponder];
    } else if (textField == roomPin) {
        // when hitting return in room pin field, hide the keyboard
        [textField resignFirstResponder];
    }
    return YES;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [[self view] endEditing:YES];
}

#pragma mark - App UI Updates

// Apply supported settings/preferences.
- (void)applyAppSettings {
    // If connected to a call, then do not apply the new settings.
    if (vidyoConnectorState == VidyoConnectorStateConnected) {
        return;
    }

    // Load the configuration parameters either from the user defaults or the URL parameters
    NSMutableDictionary *urlParameters = [(VidyoConnectorAppDelegate *)[[UIApplication sharedApplication] delegate] urlParameters];
    if (urlParameters) {
        [appSettings extractURLParameters:urlParameters];
    } else {
        [appSettings extractDefaultParameters];
    }

    // Populate the form.
    portal.text         = [appSettings portal];
    roomKey.text        = [appSettings roomKey];
    displayName.text    = [appSettings displayName];
    roomPin.text        = [appSettings roomPin];

    // Hide the controls view if hideConfig is enabled
    controlsView.hidden = [appSettings hideConfig];

    // If enableDebug is configured then enable debugging
    if ([appSettings enableDebug]) {
        [vc enableDebug:7776 LogFilter:"warning info@VidyoClient info@VidyoConnector"];
        [clientVersion setHidden:NO];
    }
    // If cameraPrivacy is configured then mute the camera
    if ([appSettings cameraPrivacy]) {
        [appSettings toggleCameraPrivacy]; // toggle prior to simulating click
        [self cameraPrivacyButtonPressed:nil];
    }
    // If microphonePrivacy is configured then mute the microphone
    if ([appSettings microphonePrivacy]) {
        [appSettings toggleMicrophonePrivacy]; // toggle prior to simulating click
        [self microphonePrivacyButtonPressed:nil];
    }
    // Set experimental options if any exist
    if ([appSettings experimentalOptions]) {
        [vc setAdvancedOptions:[[appSettings experimentalOptions] UTF8String]];
    }
    // If configured to auto-join, then simulate a click of the toggle connect button
    if ([appSettings autoJoin]) {
        [self toggleConnectButtonPressed:nil];
    }
}

// Refresh the UI
- (void)refreshUI {
    [logger Log:[NSString stringWithFormat:@"VidyoConnectorShowViewAt: x = %f, y = %f, w = %f, h = %f", videoView.frame.origin.x, videoView.frame.origin.y, videoView.frame.size.width, videoView.frame.size.height]];

    // Resize the rendered video.
    [vc showViewAt:&videoView X:0 Y:0 Width:videoView.frame.size.width Height:videoView.frame.size.height];
}

// The state of the VidyoConnector connection changed, reconfigure the UI.
// If connected, show the video in the entire window.
// If disconnected, show the video in the preview pane.
- (void)changeState:(enum VidyoConnectorState)state {
    vidyoConnectorState = state;
    
    // Execute this code on the main thread since it is updating the UI layout.
    dispatch_async(dispatch_get_main_queue(), ^{
        // Set the status text in the toolbar.
        [self updateToolbarStatus];

        switch (self->vidyoConnectorState) {
            case VidyoConnectorStateConnecting:
                // Change image of toggleConnectButton to callEndImage
                [self->toggleConnectButton setImage:self->callEndImage forState:UIControlStateNormal];

                // Start the spinner animation
                [self->connectionSpinner startAnimating];
                break;

            case VidyoConnectorStateConnected:
                if (![self->appSettings hideConfig]) {
                    // Update the view to hide the controls.
                    self->controlsView.hidden = YES;
                }
                // Stop the spinner animation
                [self->connectionSpinner stopAnimating];
                break;

            case VidyoConnectorStateDisconnecting:
                break;

            case VidyoConnectorStateDisconnected:
            case VidyoConnectorStateDisconnectedUnexpected:
            case VidyoConnectorStateFailure:
            case VidyoConnectorStateFailureInvalidResource:
                // VidyoConnector is disconnected

                // Display toolbar in case it is hidden
                self->toolbarView.hidden = NO;

                // Change image of toggleConnectButton to callStartImage
                [self->toggleConnectButton setImage:self->callStartImage forState:UIControlStateNormal];

                // If a return URL was provided as a URL parameter, then return to that application
                if ([self->appSettings returnURL]) {
                    // Provide a callstate of either 0 or 1, depending on whether the call was successful
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?callstate=%d", [self->appSettings returnURL], (int)(self->vidyoConnectorState == VidyoConnectorStateDisconnected)]]];
                }
                // If the allow-reconnect flag is set to false and a normal (non-failure) disconnect occurred,
                // then disable the toggle connect button, in order to prevent reconnection.
                if (![self->appSettings allowReconnect] && (self->vidyoConnectorState == VidyoConnectorStateDisconnected)) {
                    [self->toggleConnectButton setEnabled:NO];
                    [self->toolbarStatusText setText:@"Call ended"];
                }
                if (![self->appSettings hideConfig]) {
                    // Update the view to display the controls.
                    self->controlsView.hidden = NO;
                }

                // Stop the spinner animation
                [self->connectionSpinner stopAnimating];

                break;
        }
    });
}

// Update the text displayed in the Toolbar Status UI element
- (void)updateToolbarStatus {
    NSString* statusText = @"";

    switch (vidyoConnectorState) {
        case VidyoConnectorStateConnecting:
            statusText = @"Connecting...";
            break;
        case VidyoConnectorStateConnected:
            statusText = @"Connected";
            break;
        case VidyoConnectorStateDisconnecting:
            statusText = @"Disconnecting...";
            break;
        case VidyoConnectorStateDisconnected:
            statusText = @"Disconnected";
            break;
        case VidyoConnectorStateDisconnectedUnexpected:
            statusText = @"Unexpected disconnection";
            break;
        case VidyoConnectorStateFailure:
            statusText = @"Connection failed";
            break;
        case VidyoConnectorStateFailureInvalidResource:
            statusText = @"Invalid Resource ID";
            break;
        default:
            statusText = @"Unexpected state";
            break;
    }
    [toolbarStatusText setText:statusText];
}

#pragma mark - Button Event Handlers

// The Connect button was pressed.
// If not in a call, attempt to connect to the backend service.
// If in a call, disconnect.
- (IBAction)toggleConnectButtonPressed:(id)sender {

    // If the toggleConnectButton is the callEndImage, then either user is connected to a resource or is in the process
    // of connecting to a resource; call VidyoConnectorDisconnect to disconnect or abort the connection attempt
    if ([toggleConnectButton imageForState:UIControlStateNormal] == callEndImage) {
        [self changeState:VidyoConnectorStateDisconnecting];
        [vc disconnect];
    } else {
        
            // Connect to a VidyoCloud system
            [self changeState:VidyoConnectorStateConnecting];
            if (![vc connectToRoomAsGuest:[[[portal text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] UTF8String]
                                  DisplayName:[[[displayName text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] UTF8String]
                                      RoomKey:[[[roomKey text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] UTF8String]
                                      RoomPin:[[[roomPin text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] UTF8String]
                            ConnectorIConnect:self]) {
                // Connect failed.
                [self changeState:VidyoConnectorStateFailure];
            }
        }
        [logger Log:[NSString stringWithFormat:@"VidyoConnectorConnect status = %d", vidyoConnectorState == VidyoConnectorStateConnecting]];
    
}

// Toggle the microphone privacy
- (IBAction)microphonePrivacyButtonPressed:(id)sender {
    BOOL microphonePrivacy = [appSettings toggleMicrophonePrivacy];
    if (microphonePrivacy == NO) {
        [microphonePrivacyButton setImage:[UIImage imageNamed:@"microphoneOnWhite.png"] forState:UIControlStateNormal];
    } else {
        [microphonePrivacyButton setImage:[UIImage imageNamed:@"microphoneOff.png"] forState:UIControlStateNormal];
    }
    [vc setMicrophonePrivacy:microphonePrivacy];
}

// Toggle the camera privacy
- (IBAction)cameraPrivacyButtonPressed:(id)sender {
    BOOL cameraPrivacy = [appSettings toggleCameraPrivacy];
    if (cameraPrivacy == NO) {
        [cameraPrivacyButton setImage:[UIImage imageNamed:@"cameraOnWhite.png"] forState:UIControlStateNormal];
    } else {
        [cameraPrivacyButton setImage:[UIImage imageNamed:@"cameraOff.png"] forState:UIControlStateNormal];
    }
    [vc setCameraPrivacy:cameraPrivacy];
}

// Handle the camera swap button being pressed. Cycle the camera.
- (IBAction)cameraSwapButtonPressed:(id)sender {
    [vc cycleCamera];
}

// Handle the toggle debug button being pressed.
- (IBAction)toggleDebugButtonPressed:(id)sender {
    if ([appSettings toggleDebug]) {
        [vc enableDebug:7776 LogFilter:"warning info@VidyoClient info@VidyoConnector"];
        [clientVersion setHidden:NO];
    } else {
        [vc disableDebug];
        [clientVersion setHidden:YES];
    }
}

- (IBAction)toggleToolbar:(UITapGestureRecognizer *)sender {
    if (vidyoConnectorState == VidyoConnectorStateConnected) {
        toolbarView.hidden = !toolbarView.hidden;
    }
}

#pragma mark - VCConnectorIConnect

//  Handle successful connection.
-(void) onSuccess {
    [logger Log:@"onSuccess: Successfully connected."];
    [self changeState:VidyoConnectorStateConnected];
}

// Handle attempted connection failure.
-(void) onFailure:(VCConnectorFailReason)reason {
    [logger Log:@"onFailure: Connection attempt failed."];
    [self changeState:VidyoConnectorStateFailure];
}

//  Handle an existing session being disconnected.
-(void) onDisconnected:(VCConnectorDisconnectReason)reason {
    if (reason == VCConnectorDisconnectReasonDisconnected) {
        [logger Log:@"onDisconnected: Succesfully disconnected."];
        [self changeState:VidyoConnectorStateDisconnected];
    } else {
        [logger Log:@"onDisconnected: Unexpected disconnection."];
        [self changeState:VidyoConnectorStateDisconnectedUnexpected];
    }
}

#pragma mark - VCConnectorIRegisterLocalCameraEventListener

-(void) onLocalCameraAdded:(VCLocalCamera*)localCamera {
    [logger Log:[NSString stringWithFormat:@"onLocalCameraAdded: %@", [localCamera getName]]];
}
-(void) onLocalCameraRemoved:(VCLocalCamera*)localCamera {
    [logger Log:[NSString stringWithFormat:@"onLocalCameraRemoved: %@", [localCamera getName]]];
}
-(void) onLocalCameraSelected:(VCLocalCamera*)localCamera {
    [logger Log:[NSString stringWithFormat:@"onLocalCameraSelected: %@", localCamera ? [localCamera getName] : @"none"]];

    // If a camera is selected, then update lastSelectedCamera.
    // localCamera will be nil only when backgrounding app while disconnected.
    if (localCamera) {
        lastSelectedCamera = localCamera;
    }
}
-(void) onLocalCameraStateUpdated:(VCLocalCamera*)localCamera State:(VCDeviceState)state {
    [logger Log:[NSString stringWithFormat:@"onLocalCameraStateUpdated: name=%@ state=%ld", [localCamera getName], (long)state]];
}

#pragma mark - VCConnectorIRegisterLocalMicrophoneEventListener

-(void) onLocalMicrophoneAdded:(VCLocalMicrophone*)localMicrophone {
    [logger Log:[NSString stringWithFormat:@"onLocalMicrophoneAdded: %@", [localMicrophone getName]]];
}
-(void) onLocalMicrophoneRemoved:(VCLocalMicrophone*)localMicrophone {
    [logger Log:[NSString stringWithFormat:@"onLocalMicrophoneRemoved: %@", [localMicrophone getName]]];
}
-(void) onLocalMicrophoneSelected:(VCLocalMicrophone*)localMicrophone {
    [logger Log:[NSString stringWithFormat:@"onLocalMicrophoneSelected: %@", localMicrophone ? [localMicrophone getName] : @"none"]];
}
-(void) onLocalMicrophoneStateUpdated:(VCLocalMicrophone*)localMicrophone State:(VCDeviceState)state {
    [logger Log:[NSString stringWithFormat:@"onLocalMicrophoneStateUpdated: name=%@ state=%ld", [localMicrophone getName], (long)state]];
}

#pragma mark - VCConnectorIRegisterLocalSpeakerEventListener

-(void) onLocalSpeakerAdded:(VCLocalSpeaker*)localSpeaker {
    [logger Log:[NSString stringWithFormat:@"onLocalSpeakerAdded: %@", [localSpeaker getName]]];
}
-(void) onLocalSpeakerRemoved:(VCLocalSpeaker*)localSpeaker {
    [logger Log:[NSString stringWithFormat:@"onLocalSpeakerRemoved: %@", [localSpeaker getName]]];
}
-(void) onLocalSpeakerSelected:(VCLocalSpeaker*)localSpeaker {
    [logger Log:[NSString stringWithFormat:@"onLocalSpeakerSelected: %@", localSpeaker ? [localSpeaker getName] : @"none"]];
}
-(void) onLocalSpeakerStateUpdated:(VCLocalSpeaker*)localSpeaker State:(VCDeviceState)state {
    [logger Log:[NSString stringWithFormat:@"onLocalSpeakerStateUpdated: name=%@ state=%ld", [localSpeaker getName], (long)state]];
}

#pragma mark - VCConnectorIRegisterLogEventListener

- (void)onLog:(VCLogRecord*)logRecord {
    [logger LogClientLib:logRecord.message];
}

@end
