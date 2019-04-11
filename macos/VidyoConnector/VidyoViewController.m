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
#import "VidyoViewController.h"

// Indicates whether app is quitting; Helps coordinate disconnect and clean-up.
static volatile bool appIsQuitting = false;

// Baseline menu offsets for no camera, no mic, no speaker, no monitor share, no window share
const unsigned long NO_CAMERA_MENU_OFFSET              = 1;  // "Camera" text
const unsigned long NO_MICROPHONE_MENU_OFFSET          = 4;  // plus "None" camera, divider, "Microphone" text
const unsigned long NO_SPEAKER_MENU_OFFSET             = 7;  // plus "None" microphone, divider, "Speaker" text
const unsigned long NO_MONITOR_SHARE_MENU_OFFSET       = 3;  // "Monitor" text
const unsigned long NO_WINDOW_SHARE_MENU_OFFSET        = 6;  // "Monitor" text, "None monitor, divider, "Window" text
const unsigned long NO_VIDEO_CONTENT_SHARE_MENU_OFFSET = 1;  // "Video Content Share" text
const unsigned long NO_AUDIO_CONTENT_SHARE_MENU_OFFSET = 4;  // plus "None" video content share, divider, "Audio Content Share" text

@implementation VidyoViewController

@synthesize portal, roomKey, displayName, roomPin, chatMessage;
@synthesize controlsStatusText, toolbarStatusText, participantStatusText;
@synthesize mainView, controlsView, previewView, chatView, chatTableView;
@synthesize toggleConnectButton, cameraPrivacyButton, microphonePrivacyButton, speakerPrivacyButton;
@synthesize connectionSpinner;

#pragma mark - View Lifecycle

// Called when the view is initially loaded; this method is only called once in the lifecycle of this app
- (void)viewDidLoad {
    [super viewDidLoad];

    // Initialize the logger and appSettings
    logger = [[Logger alloc] init];
    appSettings = [[AppSettings alloc] init];

    // Initialize member variables
    vc                  = nil;
    vidyoConnectorState = VidyoConnectorStateDisconnected;
    selectedLocalCamera = nil;
    isSharingMonitor    = NO;
    isSharingWindow     = NO;
    showSharePreview    = NO;

    // Initialize the toggle connect button to display the callStartImage
    callStartImage = [NSImage imageNamed:@"callStart.png"];
    callEndImage   = [NSImage imageNamed:@"callEnd.png"];
    [toggleConnectButton setImage:callStartImage];

    // Initialize tables for cameras, microphones, speakers and shares
    cameraMap            = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:1];
    videoContentShareMap = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:1];
    microphoneMap        = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:1];
    audioContentShareMap = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:1];
    speakerMap           = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:1];
    monitorShareMap      = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:1];
    windowShareMap       = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:1];

    // Initialize data used for text chat
    chatTableUsers    = [[NSMutableArray alloc] initWithCapacity:1];
    chatTableMessages = [[NSMutableArray alloc] initWithCapacity:1];
    chatTableView.delegate = self;
    chatTableView.dataSource = self;
    chatView.hidden = YES;

    // Lock to protect against multi-threaded access to the device maps
    deviceLock = [[NSRecursiveLock alloc] init];

    ///////////////// Handle the menu item selection callbacks /////////////////

    // Add a selector function to the "VidyoConnector" -> "About VidyoConnector" menu item
    NSMenu *vidyoConnectorMenu = [[[NSApp mainMenu] itemWithTitle:@"VidyoConnector"] submenu];
    NSMenuItem *menuItem = [vidyoConnectorMenu itemWithTitle:@"About VidyoConnector"];
    [menuItem setAction:@selector( About: )];
    [menuItem setTarget:self];

    // Add selector functions to the following menu items:
    //   "Conference" -> "Connect"
    //   "Conference" -> "Disconnect"
    //   "Conference" -> "Advanced"
    NSMenu *conferenceMenu = [[[NSApp mainMenu] itemWithTitle:@"Conference"] submenu];
    connectMenuItem = [conferenceMenu itemWithTitle:@"Connect"];
    [connectMenuItem setAction:@selector( connect: )];
    [connectMenuItem setTarget:self];
    disconnectMenuItem = [conferenceMenu itemWithTitle:@"Disconnect"];
    [disconnectMenuItem setAction:@selector( disconnect: )];
    [disconnectMenuItem setTarget:self];

    NSMenu *advancedMenu = [[conferenceMenu itemWithTitle:@"Advanced"] submenu];
    debugMenuItem = [advancedMenu itemWithTitle:@"Debug"];
    [debugMenuItem setAction:@selector( toggleDebug: )];
    [debugMenuItem setTarget:self];

    NSMenu *maxResolutionMenu = [[advancedMenu itemWithTitle:@"Max Resolution"] submenu];
    for (uint i = 0; i < [maxResolutionMenu numberOfItems]; ++i) {
        [[maxResolutionMenu itemAtIndex:i] setAction:@selector( setMaxResolution: )];
    }
    selectedMaxResolutionMenuItem = [maxResolutionMenu itemWithTitle:@"720p"]; // default value

    NSMenu *experimentalMenu = [[advancedMenu itemWithTitle:@"Experimental"] submenu];
    NSMenuItem *digitalPTZMenuItem = [experimentalMenu itemWithTitle:@"PTZ"];
    [digitalPTZMenuItem setAction:@selector( setExperimentalOptions: )];
    [digitalPTZMenuItem setTarget:self];
    NSMenuItem *forceDigitalPTZMenuItem = [experimentalMenu itemWithTitle:@"Force Digital PTZ"];
    [forceDigitalPTZMenuItem setAction:@selector( setExperimentalOptions: )];
    [forceDigitalPTZMenuItem setTarget:self];
    NSMenuItem *vp9Menuitem = [experimentalMenu itemWithTitle:@"VP9"];
    [vp9Menuitem setAction:@selector( setExperimentalOptions: )];
    [vp9Menuitem setTarget:self];
    NSMenuItem *blcMenuitem = [experimentalMenu itemWithTitle:@"Backlight Compensation"];
    [blcMenuitem setAction:@selector( setBacklightCompensationOptions: )];
    [blcMenuitem setTarget:self];

    [conferenceMenu setAutoenablesItems:NO];
    [advancedMenu setAutoenablesItems:NO];
    [maxResolutionMenu setAutoenablesItems:NO];
    [experimentalMenu setAutoenablesItems:NO];

    // Hook up the Devices sub menu and add "None" menu items for camera, mic, and speaker
    devicesMenu = [[[NSApp mainMenu] itemWithTitle:@"Devices"] submenu];
    [devicesMenu setAutoenablesItems:NO];

    noCameraMenuItem = [devicesMenu insertItemWithTitle:@"None"
                                                 action:@selector( cameraSelected: )
                                          keyEquivalent:@""
                                                atIndex:NO_CAMERA_MENU_OFFSET];
    [noCameraMenuItem setTarget:self];

    noMicrophoneMenuItem = [devicesMenu insertItemWithTitle:@"None"
                                                     action:@selector( microphoneSelected: )
                                              keyEquivalent:@""
                                                    atIndex:NO_MICROPHONE_MENU_OFFSET];
    [noMicrophoneMenuItem setTarget:self];

    noSpeakerMenuItem = [devicesMenu insertItemWithTitle:@"None"
                                                  action:@selector( speakerSelected: )
                                           keyEquivalent:@""
                                                 atIndex:NO_SPEAKER_MENU_OFFSET];
    [noSpeakerMenuItem setTarget:self];

    // Hook up the Shares sub menu and add "None" menu items for Monitor and Window
    sharesMenu = [[[NSApp mainMenu] itemWithTitle:@"Shares"] submenu];
    showSharePreviewMenuItem = [sharesMenu itemWithTitle:@"Show Local Window Share"];
    [showSharePreviewMenuItem setAction:@selector( toggleShowSharePreview: )];
    [showSharePreviewMenuItem setTarget:self];
    noMonitorShareMenuItem = [sharesMenu insertItemWithTitle:@"None"
                                                 action:@selector( monitorShareSelected: )
                                          keyEquivalent:@""
                                                atIndex:NO_MONITOR_SHARE_MENU_OFFSET];
    [noMonitorShareMenuItem setTarget:self];
    [noMonitorShareMenuItem setState:NSOnState];
    noWindowShareMenuItem = [sharesMenu insertItemWithTitle:@"None"
                                                       action:@selector( windowShareSelected: )
                                                keyEquivalent:@""
                                                      atIndex:NO_WINDOW_SHARE_MENU_OFFSET];
    [noWindowShareMenuItem setTarget:self];
    [noWindowShareMenuItem setState:NSOnState];

    // Hook up the Content sub menu and add "None" menu items for video content share and audio content share
    contentMenu = [[[NSApp mainMenu] itemWithTitle:@"Content"] submenu];
    [contentMenu setAutoenablesItems:NO];

    noVideoContentShareMenuItem = [contentMenu insertItemWithTitle:@"None"
                                                            action:@selector( videoContentShareSelected: )
                                                     keyEquivalent:@""
                                                           atIndex:NO_VIDEO_CONTENT_SHARE_MENU_OFFSET];
    [noVideoContentShareMenuItem setTarget:self];
    [noVideoContentShareMenuItem setState:NSOnState];

    noAudioContentShareMenuItem = [contentMenu insertItemWithTitle:@"None"
                                                            action:@selector( audioContentShareSelected: )
                                                     keyEquivalent:@""
                                                           atIndex:NO_AUDIO_CONTENT_SHARE_MENU_OFFSET];
    [noAudioContentShareMenuItem setTarget:self];
    [noAudioContentShareMenuItem setState:NSOnState];

    ///////////////////////////////////////////////////////////////////////
    // Register for OS notifications about this app.
    // - Expect any "Get URL" event that potentially affects app settings/preferences
    //   to be processed by the time this app has finished launching.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidFinishLaunch:)
                                                 name:NSApplicationDidFinishLaunchingNotification
                                               object:nil];
}

// called when the view has appeared on the screen,
// both when app is constructed and when it returns from being minimized
- (void)viewDidAppear {
    [super viewDidAppear];

    [logger Log:@"VidyoViewController::viewDidAppear is called"];

    // Set this view controller to be the delegate to the NSWindow
    self.view.window.delegate = self;

    // Note: viewDidAppear is called upon initial appearance of the view and when unminimizing the app

    // If the vidyo connector was not previously successfully constructed then construct it
    if ( vc == nil ) {

        // Initialize the Vidyo Client library; this should be done once throughout the lifetime of the application.
        [VCConnectorPkg vcInitialize];

        vc = [[VCConnector alloc] init:&mainView
                           ViewStyle:VCConnectorViewStyleDefault
                  RemoteParticipants:15
                       LogFileFilter:"info@VidyoClient info@VidyoConnector warning"
                         LogFileName:""
                            UserData:0];

        if ( vc ) {
            // Register for local camera events
            if ( ![vc registerLocalCameraEventListener:self] ) {
                [logger Log:@"LocalCameraEventListener registration failed."];
            }

            // Register for local microphone events
            if ( ![vc registerLocalMicrophoneEventListener:self] ) {
                [logger Log:@"LocalMicrophoneEventListener registration failed."];
            }

            // Register for local speaker (audio output) events
            if ( ![vc registerLocalSpeakerEventListener:self] ) {
                [logger Log:@"LocalSpeakerEventListener registration failed."];
            }

            // Register for local monitor share events
            if ( ![vc registerLocalMonitorEventListener:self] ) {
                [logger Log:@"LocalMonitorEventListener registration failed."];
            }

            // Register for local window share events
            if ( ![vc registerLocalWindowShareEventListener:self] ) {
                [logger Log:@"LocalWindowShareEventListener registration failed."];
            }

            // Register for participant events
            if ( ![vc registerParticipantEventListener:self] ) {
                [logger Log:@"ParticipantEventListener registration failed."];
            }

            // Register for remote camera events
            if ( ![vc registerRemoteCameraEventListener:self] ) {
                [logger Log:@"RemoteCameraEventListener registration failed."];
            }

            // Register for network interface events
            if ( ![vc registerNetworkInterfaceEventListener:self] ) {
                [logger Log:@"NetworkInterfaceListener registration failed."];
            }

            // Register for message (chat) events
            if ( ![vc registerMessageEventListener:self] ) {
                [logger Log:@"MessageEventListener registration failed."];
            }

            // Register for log events; the filter argument specifies the log level that
            // is printed to console as well as what is called back in onLog.
            if ( ![vc registerLogEventListener:self Filter:"info@VidyoClient info@VidyoConnector warning"] ) {
                [logger Log:@"LogEventListener registration failed."];
            }
        } else {
            // Log error and disable toolbar buttons and menu items to prevent further VidyoConnector calls
            [logger Log:@"ERROR: VidyoConnector construction failed ..."];
            [toolbarStatusText  setStringValue:@"VidyoConnector Failed"];
            [controlsStatusText setStringValue:@"VidyoConnector Failed"];
            [controlsStatusText setTextColor:[NSColor redColor]];
            [cameraPrivacyButton      setEnabled:NO];
            [microphonePrivacyButton  setEnabled:NO];
            [speakerPrivacyButton     setEnabled:NO];
            [toggleConnectButton      setEnabled:NO];
            [connectMenuItem          setEnabled:NO];
            [disconnectMenuItem       setEnabled:NO];
            [debugMenuItem            setEnabled:NO];
            [showSharePreviewMenuItem setEnabled:NO];
        }
        [logger Log:[NSString stringWithFormat:@"VidyoViewController::viewDidAppear: VidyoConnector Constructed => %s",
                     (vc != nil) ? "success" : "failed"]];
    }
}

#pragma mark - Application Lifecycle

// OS event notification registered elsewhere in this view-controller class.
- (void)appDidFinishLaunch:(NSNotification*)aNotification {
    // Apply the app settings now, whether the app was launched tradionally,
    // via command line, or via URL.
    // By this point, other parts of this app should have processed any
    //  "Get URL" event that potentially affects app settings/preferences.
    [self applyAppSettings];

    // Begin listening for URL event notifications, which is triggered by the app delegate.
    // This notification will be triggered in all but the first time that a URL event occurs.
    // It is not necessary to handle the first occurance because applyAppSettings is called here
    // in the appDidFinishLaunch method.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyAppSettings)
                                                 name:@"handleGetURLEvent"
                                               object:nil];
}

#pragma mark - Private Utility Functions

// Apply supported settings/preferences.
- (void)applyAppSettings {
    // If connected to a call, then do not apply the new settings.
    if (vidyoConnectorState == VidyoConnectorStateConnected) {
        return;
    }

    // Extract the app settings from either command line or URL
    [appSettings extract];

    // Set the fields in the form
    [portal setStringValue:[appSettings portal]];
    [roomKey setStringValue:[appSettings roomKey]];
    [displayName setStringValue:[appSettings displayName]];
    [roomPin setStringValue:[appSettings roomPin]];

    // Display or hide the controlsView
    controlsView.hidden = [appSettings hideConfig];

    // If enableDebug is configured then enable debugging
    [self debug:[appSettings enableDebug]];

    // If cameraPrivacy is configured then mute the camera
    BOOL privacy = [appSettings cameraPrivacy];
    [vc setCameraPrivacy:privacy];
    [cameraPrivacyButton setState:(privacy ? NSOffState : NSOnState)];

    // If microphonePrivacy is configured then mute the microphone
    privacy = [appSettings microphonePrivacy];
    [vc setMicrophonePrivacy:privacy];
    [microphonePrivacyButton setState:(privacy ? NSOffState : NSOnState)];

    // If speakerPrivacy is configured then mute the speaker
    privacy = [appSettings speakerPrivacy];
    [vc setSpeakerPrivacy:privacy];
    [speakerPrivacyButton setState:(privacy ? NSOffState : NSOnState)];

    // Set experimental options if any exist
    if ([appSettings experimentalOptions]) {
        [VCConnectorPkg setExperimentalOptions:[[appSettings experimentalOptions] UTF8String]];
    }

    // If configured to auto-join, then simulate a click of the toggle connect button
    if ([appSettings autoJoin]) {
        [self toggleConnectButtonPressed:nil];
    }

    [self refreshUI];
}

// Called when the "VidyoConnector" -> "About VidyoConnector" menu item is selected
- (void)About:( id )sender {
    NSDictionary<NSString*, id> *options = @{ @"Version" : [NSString stringWithFormat:@"VidyoClient-OSXSDK Version %@", [vc getVersion]],
                                              @"ApplicationVersion" : @"macOS" };

    [[NSApplication sharedApplication] orderFrontStandardAboutPanelWithOptions:options];
}

// Called when the "Conference" -> "Toggle Debug" menu item is selected
- (void)toggleDebug:( id )sender {
    [self debug:[appSettings toggleDebug]];
}

- (void)debug:(BOOL)enableDebug {
    if (enableDebug) {
        [vc enableDebug:7776 LogFilter:"warning info@VidyoClient info@VidyoConnector"];

        // Add check in the menu
        [debugMenuItem setState:NSOnState];
    } else {
        [vc disableDebug];

        // Remove check in the menu
        [debugMenuItem setState:NSOffState];
    }
}

// Called when the "Shares" -> "Show Local Window Share" menu item is selected
- (void)toggleShowSharePreview:( id )sender {
    showSharePreview = !showSharePreview;
    [vc showWindowSharePreview:showSharePreview];
    [showSharePreviewMenuItem setState:(showSharePreview ? NSOnState : NSOffState)];
}

// Sets the maximum resolution constraint on the local camera.
- (void)setMaxResolution:( id )sender {
    unsigned int height = 0, width = 0;
    long frameInterval = 1000000000/30; // 30 frames per second (interval in nanoseconds between consecutive frames)
    NSMenuItem *menuItem = (NSMenuItem*)sender;

    // Update checkmark in menu if selected resolution has changed
    if ( ![[selectedMaxResolutionMenuItem title] isEqualToString:[menuItem title]] ) {
        [selectedMaxResolutionMenuItem setState:NSOffState];
        selectedMaxResolutionMenuItem = menuItem;
        [selectedMaxResolutionMenuItem setState:NSOnState];
    }

    if ( [[menuItem title] isEqualToString:@"180p"] ) {
        width  = 320;
        height = 180;
    } else if ( [[menuItem title] isEqualToString:@"270p"] ) {
        width  = 480;
        height = 270;
    } else if ( [[menuItem title] isEqualToString:@"360p"] ) {
        width  = 640;
        height = 360;
    } else if ( [[menuItem title] isEqualToString:@"540p"] ) {
        width  = 960;
        height = 540;
    } else if ( [[menuItem title] isEqualToString:@"720p"] ) {
        width  = 1280;
        height = 720;
    } else if ( [[menuItem title] isEqualToString:@"1080p"] ) {
        width  = 1920;
        height = 1080;
    } else if ( [[menuItem title] isEqualToString:@"2160p"] ) {
        width  = 3840;
        height = 2160;
    } else {
        [logger Log:@"Warning: unexpected max resolution selected"];
    }

    // Set the max constraint as long as a local camera is selected
    if ( selectedLocalCamera && width > 0 ) {
        [selectedLocalCamera setMaxConstraint:width Height:height FrameInterval:frameInterval];
    }
}

// Sets the Backlight Compensation Options on the local camera.
- (void)setBacklightCompensationOptions:( id )sender {
    NSMenuItem *currentMenuItem = (NSMenuItem*)sender;
    Boolean enable = false;

    // Toggle the state of the menu item (add or remove checkmark)
    if ( [currentMenuItem state] == NSOffState ) {
        [currentMenuItem setState:NSOnState];
        enable = true;
    } else {
        [currentMenuItem setState:NSOffState];
        enable = false;
    }

    // Set the Backlight Compensation as a local camera is selected
    if ( selectedLocalCamera) {
        [selectedLocalCamera setBacklightCompensation:enable];
    }
}

// Set experimental options such as PTZ or VP9
- (void)setExperimentalOptions:( id )sender {
    NSMenuItem *currentMenuItem = (NSMenuItem*)sender;
    NSMenuItem *menuItem;
    NSMenu * menu = [(NSMenuItem*)sender menu];
    NSString *value = nil;
    NSMutableString *experimentalOptions = [NSMutableString stringWithString:@"{"];

    // Toggle the state of the menu item (add or remove checkmark)
    if ( [currentMenuItem state] == NSOffState ) {
        [currentMenuItem setState:NSOnState];
    } else {
        [currentMenuItem setState:NSOffState];
    }

    // Iterate through all the menu options to find their cumulative states
    for (int i=0; i < [menu numberOfItems]; i++) {
        menuItem = [menu itemAtIndex:i];

        // Check the state of the menu item
        if ( [menuItem state] == NSOffState ) {
            value = @"false";
        } else {
            value = @"true";
        }

        if ( [[menuItem title] isEqualToString:@"PTZ"] ) {
            [experimentalOptions appendFormat:@"\"PTZ\":%@,", value];
        } else if ( [[menuItem title] isEqualToString:@"Force Digital PTZ"] ) {
            [experimentalOptions appendFormat:@"\"ForceDigitalPTZ\":%@,", value];
        } else if ( [[menuItem title] isEqualToString:@"VP9"] ) {
            [experimentalOptions appendFormat:@"\"VP9\":%@,", value];
        } else {
            [logger Log:@"Warning: unexpected experimental option selected"];
        }
    }

    [experimentalOptions appendString:@"}"];
    [vc setAdvancedOptions:[experimentalOptions UTF8String]];
}

// Update the UI in either preview or full-screen mode.
- (void)refreshUI {
    // Note: x, y coordinates in NSView has (0,0) in bottom left corner of the view (relative to parent view),
    // whereas in VidyoConnector API (0,0) is top left of the view.

    // Depending on whether the configuration should be hidden, render the video in either
    // the previewView or the mainView, which is the full screen other than bottom toolbar.
    if ( ( vidyoConnectorState == VidyoConnectorStateConnected ) || [appSettings hideConfig] ) {
        unsigned int chatWidth = self.chatView.hidden ? 0 : chatView.frame.size.width;
        [vc showViewAt:&mainView X:0 Y:0 Width:(mainView.frame.size.width - chatWidth) Height:mainView.frame.size.height];
    } else {
        [vc showViewAt:&mainView X:previewView.frame.origin.x Y:previewView.frame.origin.y Width:previewView.frame.size.width Height:previewView.frame.size.height];
    }
}

// The state of the VidyoConnector connection changed, reconfigure the UI.
// If connected, show the video in the entire window.
// If disconnected, show the video in the preview pane.
- (void)connectorStateUpdated:( enum VidyoConnectorState )state refreshUI:( bool )refreshUI {
    vidyoConnectorState = state;

    // Execute this code on the main thread since it is updating the UI layout
    dispatch_async( dispatch_get_main_queue(), ^{

        // Set the status text in the toolbar
        [self updateToolbarStatus];
        [self->controlsStatusText setStringValue:@""];

        if ( self->vidyoConnectorState == VidyoConnectorStateConnected ) {
            if ( ![self->appSettings hideConfig] && refreshUI ) {
                // Update the view to hide the controls
                self->controlsView.hidden = YES;

                // Update the video to be full-screen
                [self refreshUI];
            }
        } else {
            // VidyoConnector is disconnected

            // Change image of toggleConnectButton to callStartImage
            [self->toggleConnectButton setImage:self->callStartImage];
            [self->participantStatusText setStringValue:@""];

            // Clear chat data
            [self->chatTableUsers removeAllObjects];
            [self->chatTableMessages removeAllObjects];
            [self.chatMessage setStringValue:@""];
            [self.chatTableView reloadData];
            [self.chatTableView scrollRowToVisible:[self.chatTableView numberOfRows]-1];
            self->chatView.hidden = YES;

            // If the allow-reconnect flag is set to false and a normal (non-failure) disconnect occurred,
            // then disable the toggle connect button, in order to prevent reconnection.
            if ( ![self->appSettings allowReconnect] && ( self->vidyoConnectorState == VidyoConnectorStateDisconnected ) ) {
                [self->toggleConnectButton setEnabled:NO];
                [self->toolbarStatusText   setStringValue:@"Call ended"];
                [self->controlsStatusText  setStringValue:@"Call ended"];

                // Disable the Connect, Disconnect, and Toggle Debug menu items
                [self->connectMenuItem     setEnabled:NO];
                [self->disconnectMenuItem  setEnabled:NO];
                [self->debugMenuItem       setEnabled:NO];
            }

            if ( ![self->appSettings hideConfig] && refreshUI ) {
                // Update the view to display the controls
                self->controlsView.hidden = NO;

                // Update the video to be in preview mode
                [self refreshUI];
            }
        }

        // Stop the spinner animation
        [self->connectionSpinner stopAnimation:self];
    } );
}

#pragma mark - Button Event Handlers

// The Connect button was pressed.
// If not in a call, attempt to connect to the backend service.
// If in a call, disconnect.
- (IBAction)toggleConnectButtonPressed:( id )sender {
    // If the toggleConnectButton is the callEndImage, then either user is connected to a resource or is in the process
    // of connecting to a resource; call VidyoConnectorDisconnect to disconnect or abort the connection attempt
    if ( [toggleConnectButton image] == callEndImage ) {
        [self disconnect:sender];
    } else {
        [self connect:sender];
    }
}

// Toggle the camera privacy
- (IBAction)cameraPrivacyButtonPressed:( id )sender {
    BOOL cameraPrivacy = [appSettings toggleCameraPrivacy];
    [vc setCameraPrivacy:cameraPrivacy];
}

// Toggle the microphone privacy
- (IBAction)microphonePrivacyButtonPressed:( id )sender {
    BOOL microphonePrivacy = [appSettings toggleMicrophonePrivacy];
    [vc setMicrophonePrivacy:microphonePrivacy];
}

// Toggle the speaker privacy
- (IBAction)speakerPrivacyButtonPressed:(id)sender {
    BOOL speakerPrivacy = [appSettings toggleSpeakerPrivacy];
    [vc setSpeakerPrivacy:speakerPrivacy];
}

// Toggle whether to show text chat
- (IBAction)toggleChatButtonPressed:(id)sender {
    // Only show/hide chat while connected
    if (vidyoConnectorState == VidyoConnectorStateConnected) {
        self.chatView.hidden = !self.chatView.hidden;
        [self refreshUI];
    }
}

// Send a chat message to all participants in the conference
- (IBAction)sendChatButtonPressed:(id)sender {
    if ([[self.chatMessage stringValue] length] > 0) {
        // Send chat message.
        [vc sendChatMessage:[[self.chatMessage stringValue] UTF8String]];

        // Populate the chatTableUsers and chatTableMessages arrays with the display name
        // and chat message. This data is used to populate the chatTableView.
        [chatTableUsers addObject:[displayName stringValue]];
        [chatTableMessages addObject:[self.chatMessage stringValue]];
        [self.chatMessage setStringValue:@""];

        // Reload the data in the chatTableView and scroll to bottom of table if needed.
        [chatTableView reloadData];
        [chatTableView scrollRowToVisible:[chatTableView numberOfRows] - 1];
    }
}

// Either the Connect button was pressed or the Connect option was selected from the menu.
// Signal the VidyoConnector object to connect to the backend.
- (void)connect:( id )sender {
    // If the Connect option was selected from the menu, check that user is not already connected
    // or in the process of trying to connect.
    if ( sender == ( id )connectMenuItem && [toggleConnectButton image] == callEndImage ) {
        if ( vidyoConnectorState == VidyoConnectorStateConnected ) {
            [controlsStatusText setStringValue:@""];
        }
    } else {
        // Attempt to connect

        [toolbarStatusText  setStringValue:@"Connecting..."];
        [controlsStatusText setStringValue:@"Connecting..."];
        [controlsStatusText setTextColor:[NSColor blackColor]];

        // Connect to a VidyoCloud system, not Vidyo.io.
        BOOL status = [vc connectToRoomAsGuest:[[portal stringValue] UTF8String]
                                   DisplayName:[[displayName stringValue] UTF8String]
                                       RoomKey:[[roomKey stringValue] UTF8String]
                                       RoomPin:[[roomPin stringValue] UTF8String]
                             ConnectorIConnect:self];
        if ( status == NO ) {
            [self connectorStateUpdated:VidyoConnectorStateFailure refreshUI:false];
        } else {      
            // Change image of toggleConnectButton to callEndImage
            [toggleConnectButton setImage:callEndImage];

            // Start the spinner animation
            [connectionSpinner startAnimation:self];
        }

        [logger Log:[NSString stringWithFormat:@"VidyoConnectorConnect status = %d", status]];
    }
}

// Either the Disconnect button was pressed or the Disconnect option was selected from the menu.
// Signal the VidyoConnector object to disconnect from the backend.
- (void)disconnect:( id )sender {

    // If the Disconnect option was selected from the menu, check that user is not already disconnected
    // or in the process of trying to disconnect.
    if ( sender == ( id )disconnectMenuItem && [toggleConnectButton image] == callStartImage ) {
        if ( vidyoConnectorState != VidyoConnectorStateConnected ) {
            [controlsStatusText setStringValue:@""];
        }
    } else {
        // Attempt to disconnect
        [toolbarStatusText setStringValue:@"Disconnecting..."];
        [vc disconnect];
    }
}

#pragma mark - Menu Events

// A camera was selected from the menu.
- (void)cameraSelected:( id )sender {

    [deviceLock lock];

    // Check if "None" was selected
    if ([[(NSMenuItem*)sender title] isEqualToString:@"None"]) {
        [vc selectLocalCamera:nil];
    } else {
        VCLocalCamera *camera = [cameraMap objectForKey:( NSMenuItem * )sender];

        if ( camera != nil ) {
            [vc selectLocalCamera:camera];
        } else {
            [logger Log:@"WARNING: cameraSelected called but the selected camera is not in the cameraMap."];
        }
    }

    [deviceLock unlock];
}

// A microphone was selected from the menu.
- (void)microphoneSelected:( id )sender {

    [deviceLock lock];

    // Check if "None" was selected
    if ([[(NSMenuItem*)sender title] isEqualToString:@"None"]) {
        [vc selectLocalMicrophone:nil];
    } else {
        VCLocalMicrophone *microphone = [microphoneMap objectForKey:( NSMenuItem * )sender];

        if ( microphone != nil ) {
            [vc selectLocalMicrophone:microphone];
        } else {
            [logger Log:@"WARNING: microphoneSelected called but the selected microphone is not in the microphoneMap."];
        }
    }

    [deviceLock unlock];
}

// A speaker was selected from the menu.
- (void)speakerSelected:( id )sender {

    [deviceLock lock];

    // Check if "None" was selected
    if ([[(NSMenuItem*)sender title] isEqualToString:@"None"]) {
        [vc selectLocalSpeaker:nil];
    } else {
        VCLocalSpeaker *speaker = [speakerMap objectForKey:( NSMenuItem * )sender];

        if ( speaker != nil ) {
            [vc selectLocalSpeaker:speaker];
        } else {
            [logger Log:@"WARNING: speakerSelected called but the selected speaker is not in the speakerMap."];
        }
    }

    [deviceLock unlock];
}

// A video content share was selected from the menu.
- (void)videoContentShareSelected:( id )sender {

    [deviceLock lock];

    for ( NSMenuItem * aMenuItem in videoContentShareMap ) {
        // Uncheck all video content share first
        [aMenuItem setState:NSOffState];
    }

    // Check if "None" was selected
    if ([[(NSMenuItem*)sender title] isEqualToString:@"None"]) {
        [vc selectVideoContentShare:nil];
        [noVideoContentShareMenuItem setState:NSOnState];
        for ( NSMenuItem * aMenuItem in cameraMap )
            [aMenuItem setEnabled:true];

    } else {
        VCLocalCamera *camera = [videoContentShareMap objectForKey:( NSMenuItem * )sender];

        if ( camera != nil ) {
            [vc selectVideoContentShare:camera];
            [noVideoContentShareMenuItem setState:NSOffState];
            [sender setState:NSOnState];
            [self disableCameraInMap:cameraMap ID:[camera getId]];
        } else {
            [logger Log:@"WARNING: videoContentShareSelected called but the selected camera is not in the videoContentShareMap."];
        }
    }

    [deviceLock unlock];
}

// A video content share was removed due to camera removal.
- (void)videoContentShareRemoved {

    BOOL found = NO;

    for ( NSMenuItem * aMenuItem in videoContentShareMap ) {
        if ([aMenuItem state] == NSOnState)
            found = YES;
    }
    if (!found) {
        [noVideoContentShareMenuItem setState:NSOnState];
    }
}

// An audio content share was selected from the menu.
- (void)audioContentShareSelected:( id )sender {

    [deviceLock lock];

    for ( NSMenuItem * aMenuItem in audioContentShareMap ) {
        // Uncheck all audio content share first
        [aMenuItem setState:NSOffState];
    }

    // Check if "None" was selected
    if ([[(NSMenuItem*)sender title] isEqualToString:@"None"]) {
        [vc selectAudioContentShare:nil];
        [noAudioContentShareMenuItem setState:NSOnState];
        for ( NSMenuItem * aMenuItem in microphoneMap )
            [aMenuItem setEnabled:true];

    } else {
        VCLocalMicrophone *microphone = [audioContentShareMap objectForKey:( NSMenuItem * )sender];

        if ( microphone != nil ) {
            [vc selectAudioContentShare:microphone];
            [noAudioContentShareMenuItem setState:NSOffState];
            [sender setState:NSOnState];
            [self disableMicrophoneInMap:microphoneMap ID:[microphone getId]];
        } else {
            [logger Log:@"WARNING: audioContentShareSelected called but the selected microphone is not in the audioContentShareMap."];
        }
    }

    [deviceLock unlock];
}

// A audio content share was removed due to microphone removal.
- (void)audioContentShareRemoved {

    BOOL found = NO;

    for ( NSMenuItem * aMenuItem in audioContentShareMap ) {
        if ([aMenuItem state] == NSOnState)
            found = YES;
    }
    if (!found) {
        [noAudioContentShareMenuItem setState:NSOnState];
    }
}

// A monitor share was selected from the menu.
- (void)monitorShareSelected:( id )sender {

    [deviceLock lock];

    // Check if "None" was selected
    if ([[(NSMenuItem*)sender title] isEqualToString:@"None"]) {
        [vc selectLocalMonitor:nil];
    } else {
        VCLocalMonitor *monitor = [monitorShareMap objectForKey:( NSMenuItem * )sender];

        if ( monitor != nil ) {
            [vc selectLocalMonitor:monitor];
        } else {
            [logger Log:@"WARNING: monitorShareSelected called but the selected monitor share is not in the monitorShareMap."];
        }
    }

    [deviceLock unlock];
}

// A window share was selected from the menu.
- (void)windowShareSelected:( id )sender {

    [deviceLock lock];

    // Check if "None" was selected
    if ([[(NSMenuItem*)sender title] isEqualToString:@"None"]) {
        [vc selectLocalWindowShare:nil];
    } else {
        VCLocalWindowShare *windowShare = [windowShareMap objectForKey:( NSMenuItem * )sender];

        if ( windowShare != nil ) {
            [vc selectLocalWindowShare:windowShare];
        } else {
            [logger Log:@"WARNING: windowShareSelected called but the selected window share is not in the windowShareMap."];
        }
    }

    [deviceLock unlock];
}

- (void)disableCameraInMap:(NSMapTable *)map ID:(NSString*)cameraId {

    VCLocalCamera *camPtr = nil;

    for ( NSMenuItem * aMenuItem in map ) {
        camPtr = [map objectForKey:aMenuItem];

        // Check for camera to disable
        if ( [[camPtr getId] isEqualToString:cameraId] )
            [aMenuItem setEnabled:false];
        else
            [aMenuItem setEnabled:true];
    }
}

- (void)removeCameraFromMap:(NSMapTable *)map ID:(NSString*)id MENU:(NSMenu *)menu {

    VCLocalCamera *camPtr = nil;

    for ( NSMenuItem * aMenuItem in map ) {
        camPtr = [map objectForKey:aMenuItem];

        // Check for camera to remove
        if ( [[camPtr getId] isEqualToString:id] ) {
            // Free the memory, remove from menu, and remove from map
            camPtr = nil; // memory will be freed due to ARC

            [menu removeItem:aMenuItem];

            [map removeObjectForKey:aMenuItem];

            // Break out of loop
            break;
        }
    }
}

- (void)disableMicrophoneInMap:(NSMapTable *)map ID:(NSString*)microphoneId {

    VCLocalMicrophone *micPtr = nil;

    for ( NSMenuItem * aMenuItem in map ) {
        micPtr = [map objectForKey:aMenuItem];

        // Check for microphone to disable
        if ( [[micPtr getId] isEqualToString:microphoneId] )
            [aMenuItem setEnabled:false];
        else
            [aMenuItem setEnabled:true];
    }
}

- (void)removeMicrophoneFromMap:(NSMapTable *)map ID:(NSString*)id MENU:(NSMenu*)menu {

    VCLocalMicrophone *micPtr = nil;

    for ( NSMenuItem * aMenuItem in map ) {
        micPtr = [map objectForKey:aMenuItem];

        // Check for microphone to remove
        if ( [[micPtr getId] isEqualToString:id] ) {
            // Free the memory, remove from menu, and remove from map
            micPtr = nil; // memory will be freed due to ARC

            [menu removeItem:aMenuItem];

            [map removeObjectForKey:aMenuItem];

            // Break out of loop
            break;
        }
    }
}

// Update the text displayed in the Toolbar Status UI element
- (void)updateToolbarStatus {
    NSString* statusText = @"";
    NSString* sharing = isSharingWindow | isSharingMonitor ? @" | Sharing Content" : @"";

    switch (vidyoConnectorState) {
        case VidyoConnectorStateConnected:
            statusText = @"Connected";
            break;
        case VidyoConnectorStateDisconnected:
            statusText = @"Disconnected";
            break;
        case VidyoConnectorStateDisconnectedUnexpected:
            statusText = @"Unexpected disconnection";
            [controlsStatusText setStringValue:statusText];
            [controlsStatusText setTextColor:[NSColor redColor]];
            break;
        case VidyoConnectorStateFailure:
            statusText = @"Connection failed";
            [controlsStatusText setStringValue:statusText];
            [controlsStatusText setTextColor:[NSColor redColor]];
            break;
        default:
            statusText = @"Connected";
            break;
    }
    [toolbarStatusText setStringValue:[statusText stringByAppendingString:sharing]];
}

#pragma mark - VCConnectorIConnect

// Handle successful connection.
- (void)onSuccess {
    [logger Log:@"onSuccess: Connected."];
    [self connectorStateUpdated:VidyoConnectorStateConnected refreshUI:true];
}

// Handle attempted connection failure.
- (void)onFailure:(VCConnectorFailReason)reason {
    [logger Log:@"onFailure: Connection attempt failed."];
    [self connectorStateUpdated:VidyoConnectorStateFailure refreshUI:true];
}

//  Handle an existing session being disconnected.
- (void)onDisconnected:(VCConnectorDisconnectReason)reason {
    // Handle special case: Disconnecting as part of clean-up while app is quitting.
    // - Assumes that app triggered this disconnect during closing of main window.
    // - Assumes that app will perform remaining clean-up upon detecting disconnected state.
    if ( appIsQuitting ) {
        [logger Log:@"onDisconnected: Disconnected on exit."];
        [self connectorStateUpdated:VidyoConnectorStateDisconnected refreshUI:false];
    } else if ( reason == VCConnectorDisconnectReasonDisconnected ) {
        [logger Log:@"onDisconnected: Succesfully disconnected."];
        [self connectorStateUpdated:VidyoConnectorStateDisconnected refreshUI:true];
    } else {
        [logger Log:@"onDisconnected: Unexpected disconnection."];
        [self connectorStateUpdated:VidyoConnectorStateDisconnectedUnexpected refreshUI:true];
    }
}

#pragma mark - VCConnectorIRegisterLocalCameraEventListener

// Handle a new camera being added.
- (void)onLocalCameraAdded:(VCLocalCamera *)camera {
    if ( camera ) {
        // Add the camera to the camera list
        [deviceLock lock];

        unsigned long menuOffset = NO_CAMERA_MENU_OFFSET + cameraMap.count + 1;

        // populate the menu item and insert it
        NSMenuItem *menuItem = [devicesMenu insertItemWithTitle:[camera getName]
                                                         action:@selector( cameraSelected: )
                                                  keyEquivalent:@""
                                                        atIndex:menuOffset];
        [menuItem setTarget:self];

        [cameraMap setObject:camera forKey:menuItem];

        menuOffset = NO_VIDEO_CONTENT_SHARE_MENU_OFFSET + videoContentShareMap.count + 1;
        menuItem = [contentMenu insertItemWithTitle:[camera getName]
                                             action:@selector( videoContentShareSelected: )
                                      keyEquivalent:@""
                                            atIndex:menuOffset];
        [menuItem setTarget:self];

        [videoContentShareMap setObject:camera forKey:menuItem];

        [deviceLock unlock];

        [logger Log:@"onLocalCameraAdded success"];

    } else {
        [logger Log:@"onLocalCameraAdded received NULL added camera."];
    }
}

// Handle a camera being removed.
- (void)onLocalCameraRemoved:(VCLocalCamera *)camera {
    if ( camera ) {

        [deviceLock lock];

        [self removeCameraFromMap:cameraMap ID:[camera getId] MENU:devicesMenu];
        [self removeCameraFromMap:videoContentShareMap ID:[camera getId] MENU:contentMenu];
        [self videoContentShareRemoved];

        [deviceLock unlock];

        [logger Log:@"onLocalCameraRemoved success"];
    } else {
        [logger Log:@"onLocalCameraRemoved received NULL removed camera."];
    }
}

// Handle a camera being selected.
- (void)onLocalCameraSelected:(VCLocalCamera *)camera {
    [logger Log:@"onLocalCameraSelected camera selected."];

    VCLocalCamera *camPtr = nil;
    BOOL found = NO;

    // Set the max resolution for the selected local camera
    selectedLocalCamera = camera; // must be set prior to setMaxResolution call
    if ( selectedLocalCamera ) {
        [self setMaxResolution:selectedMaxResolutionMenuItem];
    }

    [deviceLock lock];

    // Iterate through the cameraMap
    for ( NSMenuItem * aMenuItem in cameraMap ) {
        camPtr = [cameraMap objectForKey:aMenuItem];

        // Check for selected device
        if ( camera && [[camPtr getId] isEqualToString:[camera getId]] ) {
            // Check the selected device in the menu
            [aMenuItem setState:NSOnState];
            found = YES;
        } else {
            // Uncheck each device that was not selected
            [aMenuItem setState:NSOffState];
        }
    }

    // Set the state of the "None" camera menu item depending if a camera was selected
    [noCameraMenuItem setState:(found ? NSOffState : NSOnState)];

    if (camera)
        [self disableCameraInMap:videoContentShareMap ID:[camera getId]];
    else
        for ( NSMenuItem * aMenuItem in videoContentShareMap )
            [aMenuItem setEnabled:true];

    [deviceLock unlock];
}

// Handle a camera state updates when suspended or has errors when starting.
- (void)onLocalCameraStateUpdated:(VCLocalCamera *)camera State:(VCDeviceState)state {
    [logger Log:@"onLocalCameraStateUpdated"];
}

#pragma mark - VCConnectorIRegisterLocalMicrophoneEventListener

// Handle a microphone being added to the system.
- (void)onLocalMicrophoneAdded:(VCLocalMicrophone *)microphone {
    if ( microphone ) {
        // Add the microphone to the microphone list
        [deviceLock lock];

        unsigned long menuOffset = NO_MICROPHONE_MENU_OFFSET + cameraMap.count + microphoneMap.count + 1;

        // populate the menu item and insert it
        NSMenuItem *menuItem = [devicesMenu insertItemWithTitle:[microphone getName]
                                                         action:@selector( microphoneSelected: )
                                                  keyEquivalent:@""
                                                        atIndex:menuOffset];
        [menuItem setTarget:self];
        [microphoneMap setObject:microphone forKey:menuItem];

        menuOffset = NO_AUDIO_CONTENT_SHARE_MENU_OFFSET + videoContentShareMap.count + audioContentShareMap.count + 1;
        menuItem = [contentMenu insertItemWithTitle:[microphone getName]
                                             action:@selector( audioContentShareSelected: )
                                      keyEquivalent:@""
                                            atIndex:menuOffset];
        [menuItem setTarget:self];
        [audioContentShareMap setObject:microphone forKey:menuItem];

        [deviceLock unlock];

        [logger Log:@"onLocalMicrophoneAdded success"];
    } else {
        [logger Log:@"onLocalMicrophoneAdded received NULL added microphone."];
    }
}

// Handle a microphone being removed.
- (void)onLocalMicrophoneRemoved:(VCLocalMicrophone *)microphone {
    if ( microphone ) {

        [deviceLock lock];

        [self removeMicrophoneFromMap:microphoneMap ID:[microphone getId] MENU:devicesMenu];
        [self removeMicrophoneFromMap:audioContentShareMap ID:[microphone getId] MENU:contentMenu];
        [self audioContentShareRemoved];

        [deviceLock unlock];

        [logger Log:@"onLocalMicrophoneRemoved success"];
    } else {
        [logger Log:@"onLocalMicrophoneRemoved received NULL removed microphone."];
    }
}

// Handle a microphone being selected.
- (void)onLocalMicrophoneSelected:(VCLocalMicrophone *)microphone {
    [logger Log:@"onLocalMicrophoneSelected microphone selected."];

    VCLocalMicrophone *micPtr = nil;
    BOOL found = NO;

    [deviceLock lock];

    // Iterate through the microphoneMap
    for ( NSMenuItem * aMenuItem in microphoneMap ) {
        micPtr = [microphoneMap objectForKey:aMenuItem];

        // Check for selected device
        if ( microphone && [[micPtr getId] isEqualToString:[microphone getId]] ) {
            // Check the selected device in the menu
            [aMenuItem setState:NSOnState];
            found = YES;
        } else {
            // Uncheck each device that was not selected
            [aMenuItem setState:NSOffState];
        }
    }

    // Set the state of the "None" microphone menu item depending if a microphone was selected
    [noMicrophoneMenuItem setState:(found ? NSOffState : NSOnState)];

    if (microphone)
        [self disableMicrophoneInMap:audioContentShareMap ID:[microphone getId]];
    else
        for ( NSMenuItem * aMenuItem in audioContentShareMap )
            [aMenuItem setEnabled:true];

    [deviceLock unlock];
}

// Handle a microphone state updates when suspended or has errors when starting.
- (void)onLocalMicrophoneStateUpdated:(VCLocalMicrophone *)microphone State:(VCDeviceState)state {
    [logger Log:@"onLocalMicrophoneStateUpdated"];
}

#pragma mark - VCConnectorIRegisterLocalSpeakerEventListener

// Handle a speaker being added.
- (void)onLocalSpeakerAdded:(VCLocalSpeaker *)speaker {
    if ( speaker ) {
        // Add the speaker to the speaker list
        [deviceLock lock];

        unsigned long menuOffset = NO_SPEAKER_MENU_OFFSET + cameraMap.count + microphoneMap.count + speakerMap.count + 1;

        // populate the menu item and insert it
        NSMenuItem *menuItem = [devicesMenu insertItemWithTitle:[speaker getName]
                                                         action:@selector( speakerSelected: )
                                                  keyEquivalent:@""
                                                        atIndex:menuOffset];
        [menuItem setTarget:self];

        [speakerMap setObject:speaker forKey:menuItem];

        [deviceLock unlock];

        [logger Log:@"onLocalSpeakerAdded success"];
    } else {
        [logger Log:@"onLocalSpeakerAdded received NULL added speaker."];
    }
}

// Handle a speaker being removed.
- (void)onLocalSpeakerRemoved:(VCLocalSpeaker *)speaker {
    if ( speaker ) {
        VCLocalSpeaker *speakerPtr = nil;

        [deviceLock lock];

        // Iterate through the speakerMap
        for ( NSMenuItem * aMenuItem in speakerMap ) {
            speakerPtr = [speakerMap objectForKey:aMenuItem];

            // Check for speaker to remove
            if ( [[speakerPtr getId] isEqualToString:[speaker getId]] ) {
                // Free the memory, remove from menu, and remove from map
                speakerPtr = nil; // memory will be freed due to ARC

                [devicesMenu removeItem:aMenuItem];

                [speakerMap removeObjectForKey:aMenuItem];

                // Break out of loop
                break;
            }
        }

        [deviceLock unlock];

        [logger Log:@"onLocalSpeakerRemoved success"];
    } else {
        [logger Log:@"onLocalSpeakerRemoved received NULL removed speaker."];
    }
}

// Handle a speaker being selected.
- (void)onLocalSpeakerSelected:(VCLocalSpeaker *)speaker {
    [logger Log:@"onLocalSpeakerSelected speaker selected."];

    VCLocalSpeaker *speakerPtr = nil;
    BOOL found = NO;

    [deviceLock lock];

    // Iterate through the speakerMap
    for ( NSMenuItem * aMenuItem in speakerMap ) {
        speakerPtr = [speakerMap objectForKey:aMenuItem];

        // Check for selected device
        if ( speaker && [[speakerPtr getId] isEqualToString:[speaker getId]] ) {
            // Check the selected device in the menu
            [aMenuItem setState:NSOnState];
            found = YES;
        } else {
            // Uncheck each device that was not selected
            [aMenuItem setState:NSOffState];
        }
    }

    // Set the state of the "None" speaker menu item depending if a speaker was selected
    [noSpeakerMenuItem setState:(found ? NSOffState : NSOnState)];

    [deviceLock unlock];
}

// Handle a speaker state updates when suspended or has errors when starting.
- (void)onLocalSpeakerStateUpdated:(VCLocalSpeaker *)speaker State:(VCDeviceState)state {
    [logger Log:@"onLocalSpeakerStateUpdated"];
}

#pragma mark - VCConnectorIRegisterLocalMonitorEventListener

// Handle a new monitor being added.
- (void)onLocalMonitorAdded:(VCLocalMonitor *)localMonitor {
    if ( localMonitor ) {
        // Add the localMonitor to the monitor share list
        [deviceLock lock];

        unsigned long menuOffset = NO_MONITOR_SHARE_MENU_OFFSET + monitorShareMap.count + 1;

        // populate the menu item and insert it
        NSMenuItem *menuItem = [sharesMenu insertItemWithTitle:[localMonitor getName]
                                                         action:@selector( monitorShareSelected: )
                                                  keyEquivalent:@""
                                                        atIndex:menuOffset];
        [menuItem setTarget:self];

        [monitorShareMap setObject:localMonitor forKey:menuItem];

        [deviceLock unlock];

        [logger Log:@"onLocalMonitorAdded success"];
    } else {
        [logger Log:@"onLocalMonitorAdded received NULL added monitor."];
    }
}

// Handle a monitor being removed.
- (void)onLocalMonitorRemoved:(VCLocalMonitor *)localMonitor {
    if ( localMonitor ) {
        VCLocalMonitor *monitorPtr = nil;

        [deviceLock lock];

        // Iterate through the monitorShareMap
        for ( NSMenuItem * aMenuItem in monitorShareMap ) {
            monitorPtr = [monitorShareMap objectForKey:aMenuItem];

            // Check for monitor to remove
            if ( [[monitorPtr getId] isEqualToString:[localMonitor getId]] ) {
                // Free the memory, remove from menu, and remove from map
                monitorPtr = nil; // memory will be freed due to ARC

                [sharesMenu removeItem:aMenuItem];

                [monitorShareMap removeObjectForKey:aMenuItem];

                // Break out of loop
                break;
            }
        }

        [deviceLock unlock];

        [logger Log:@"onLocalMonitorRemoved success"];
    } else {
        [logger Log:@"onLocalMonitorRemoved received NULL removed monitor."];
    }
}

// Handle a monitor share being selected.
- (void)onLocalMonitorSelected:(VCLocalMonitor *)localMonitor {
    [logger Log:@"onLocalMonitorSelected monitor selected."];

    VCLocalMonitor *monitorPtr = nil;

    [deviceLock lock];

    isSharingMonitor = NO;

    // Iterate through the monitorShareMap
    for ( NSMenuItem * aMenuItem in monitorShareMap ) {
        monitorPtr = [monitorShareMap objectForKey:aMenuItem];

        // Check for selected device
        if ( localMonitor && [[monitorPtr getId] isEqualToString:[localMonitor getId]] ) {
            // Check the selected device in the menu
            [aMenuItem setState:NSOnState];
            isSharingMonitor = YES;
        } else {
            // Uncheck each device that was not selected
            [aMenuItem setState:NSOffState];
        }
    }

    // Set the state of the "None" monitor menu item depending if a monitor was selected
    [noMonitorShareMenuItem setState:(isSharingMonitor ? NSOffState : NSOnState)];

    [deviceLock unlock];

    [self updateToolbarStatus];
}

// Handle a monitor state updates when suspended or has errors when starting.
- (void)onLocalMonitorStateUpdated:(VCLocalMonitor *)localMonitor State:(VCDeviceState)state {
    [logger Log:@"onLocalMonitorStateUpdated"];
}

#pragma mark - VCConnectorIRegisterLocalWindowShareEventListener

// Handle a new window share being added.
- (void)onLocalWindowShareAdded:(VCLocalWindowShare *)localWindowShare {
    if ( localWindowShare ) {
        if ( [[localWindowShare getName] length] > 0 ) {
            // Add the localWindowShare to the window share list
            [deviceLock lock];

            unsigned long menuOffset = NO_WINDOW_SHARE_MENU_OFFSET + windowShareMap.count + monitorShareMap.count + 1;

            // populate the menu item and insert it
            NSMenuItem *menuItem = [sharesMenu insertItemWithTitle:[NSString stringWithFormat:@"%@ : %@", [localWindowShare getApplicationName], [localWindowShare getName]]
                                                            action:@selector( windowShareSelected: )
                                                     keyEquivalent:@""
                                                           atIndex:menuOffset];
            [menuItem setTarget:self];

            [windowShareMap setObject:localWindowShare forKey:menuItem];

            [deviceLock unlock];

            [logger Log:@"onLocalWindowShareAdded success"];
        }
    } else {
        [logger Log:@"onLocalWindowShareAdded received NULL added window share."];
    }
}

// Handle a window share being removed.
- (void)onLocalWindowShareRemoved:(VCLocalWindowShare *)localWindowShare {
    if ( localWindowShare ) {
        VCLocalWindowShare *windowSharePtr = nil;

        [deviceLock lock];

        // Iterate through the windowShareMap
        for ( NSMenuItem * aMenuItem in windowShareMap ) {
            windowSharePtr = [windowShareMap objectForKey:aMenuItem];

            // Check for window share to remove
            if ( [[windowSharePtr getId] isEqualToString:[localWindowShare getId]] ) {
                // Free the memory, remove from menu, and remove from map
                windowSharePtr = nil; // memory will be freed due to ARC

                [sharesMenu removeItem:aMenuItem];

                [windowShareMap removeObjectForKey:aMenuItem];

                // Break out of loop
                break;
            }
        }

        [deviceLock unlock];

        [logger Log:@"onLocalWindowShareRemoved success"];
    } else {
        [logger Log:@"onLocalWindowShareRemoved received NULL removed window share."];
    }
}

// Handle a window share being selected.
- (void)onLocalWindowShareSelected:(VCLocalWindowShare *)localWindowShare {
    [logger Log:@"onLocalWindowShareSelected window share selected."];

    VCLocalWindowShare *windowSharePtr = nil;

    [deviceLock lock];

    isSharingWindow = NO;

    // Iterate through the windowShareMap
    for ( NSMenuItem * aMenuItem in windowShareMap ) {
        windowSharePtr = [windowShareMap objectForKey:aMenuItem];

        // Check for selected device
        if ( localWindowShare && [[windowSharePtr getId] isEqualToString:[localWindowShare getId]] ) {
            // Check the selected device in the menu
            [aMenuItem setState:NSOnState];
            isSharingWindow = YES;
        } else {
            // Uncheck each device that was not selected
            [aMenuItem setState:NSOffState];
        }
    }

    // Set the state of the "None" window share menu item depending if a window share was selected
    [noWindowShareMenuItem setState:(isSharingWindow ? NSOffState : NSOnState)];

    [deviceLock unlock];

    [self updateToolbarStatus];
}

// Handle a window share state updates when suspended or has errors when starting.
- (void)onLocalWindowShareStateUpdated:(VCLocalWindowShare *)localWindowShare State:(VCDeviceState)state {
    [logger Log:@"onLocalWindowShareStateUpdated"];
}

#pragma mark - VCConnectorIRegisterRemoteCameraEventListener

// Handle a new camera being added.
- (void)onRemoteCameraAdded:(VCRemoteCamera *)remoteCamera Participant:(VCParticipant *)participant {
    if ( remoteCamera ) {
        [logger Log:@"onRemoteCameraAdded success"];
    } else {
        [logger Log:@"onRemoteCameraAdded received NULL added camera."];
    }
}

// Handle a camera being removed.
- (void)onRemoteCameraRemoved:(VCRemoteCamera *)remoteCamera Participant:(VCParticipant *)participant {
    if ( remoteCamera ) {
        [logger Log:@"onRemoteCameraRemoved success"];
    } else {
        [logger Log:@"onRemoteCameraRemoved received NULL removed camera."];
    }
}

// Handle a camera state updates when suspended or has errors when starting.
- (void)onRemoteCameraStateUpdated:(VCRemoteCamera *)camera Participant:(VCParticipant *)participant State:(VCDeviceState)state {
    [logger Log:@"onRemoteCameraStateUpdated"];
    if (state == VCDeviceStateControllable) {
        [camera showCameraControl:true];
    } else if (state == VCDeviceStateNotControllable) {
        [camera showCameraControl:false];
    }
}

#pragma mark - VCConnectorIRegisterNetworkInterfaceEventListener

// Handle interface being added.
- (void)onNetworkInterfaceAdded:(VCNetworkInterface *)networkInterface {
    [logger Log:@"onNetworkInterfaceAdded success"];
}

// Handle interface being removed.
- (void)onNetworkInterfaceRemoved:(VCNetworkInterface *)networkInterface {
    [logger Log:@"onNetworkInterfaceRemoved success"];
}

// Handle notification when the interface is being used for a connection.
- (void)onNetworkInterfaceSelected:(VCNetworkInterface *)networkInterface TransportType:(VCNetworkInterfaceTransportType)transportType {
    [logger Log:@"onNetworkInterfaceSelected"];
}

// Handle interface updates when the the interface is UP or DOWN.
- (void)onNetworkInterfaceStateUpdated:(VCNetworkInterface *)networkInterface State:(VCNetworkInterfaceState)state {
    [logger Log:@"onNetworkInterfaceStateUpdated"];
}

#pragma mark - VCConnectorIRegisterLogEventListener

// Handle a message being logged.
- (void)onLog:(VCLogRecord*)logRecord {
    [logger LogClientLib:logRecord.message];
}

#pragma mark - VCConnectorIRegisterParticipantEventListener

// Handle a participant joining
- (void)onParticipantJoined:(VCParticipant *)participant {
    NSString *str = [NSString stringWithFormat:@"%@ Joined", [participant getName]];

    [logger Log:str];

    // Execute this code on the main thread since it is updating the UI
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->participantStatusText setStringValue:str];
    });
}

// Handle a participant leaving
- (void)onParticipantLeft:(VCParticipant *)participant {
    NSString *str = [NSString stringWithFormat:@"%@ Left", [participant getName]];
    [logger Log:str];

    // Execute this code on the main thread since it is updating the UI
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->participantStatusText setStringValue:str];
    });
}

// Handle order of participants changing
- (void)onDynamicParticipantChanged:(NSMutableArray *)participants {
}

// Handle loudest speaker change
- (void)onLoudestParticipantChanged:(VCParticipant *)participant AudioOnly:(BOOL)audioOnly {
    // Execute this code on the main thread since it is updating the UI
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->participantStatusText setStringValue:[NSString stringWithFormat:@"%@ Speaking", [participant getName]]];
    });
}

#pragma mark - VCConnectorIRegisterMessageEventListener

// Received a chat message from another participant in the conference
-(void) onChatMessageReceived:(VCParticipant*)participant ChatMessage:(VCChatMessage*)chatMessage {
    if ([chatMessage type] == VCChatMessageTypeChat) {
        // Populate the chatTableUsers and chatTableMessages arrays with the received message's
        // display name and chat message. This data is used to populate the chatTableView.
        [chatTableUsers addObject:[participant getName]];
        [chatTableMessages addObject:[chatMessage body]];

        // Reload the data in the chatTableView and scroll to bottom of table.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.chatTableView reloadData];
            [self.chatTableView scrollRowToVisible:[self.chatTableView numberOfRows] - 1];
        });
    }
}

#pragma mark - Table View Data Source and Delegate

// Specify the number of rows in the chat table view
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return chatTableMessages.count;
}

// Populate the chat table view
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = nil;
    if (tableColumn == tableView.tableColumns[0]) {
        cell = [tableView makeViewWithIdentifier:@"UserCellID" owner:nil];
        cell.textField.stringValue = [chatTableUsers objectAtIndex:row];
    } else if (tableColumn == tableView.tableColumns[1]) {
        cell = [tableView makeViewWithIdentifier:@"ChatMessageCellID" owner:nil];
        cell.textField.stringValue = [chatTableMessages objectAtIndex:row];
    }
    return cell;
}

#pragma mark - Window Handling Events

// User resized the window, so resize the video to the new available area.
- ( void )windowDidEndLiveResize:( NSNotification * )notification {
    [logger Log:@"VidyoViewController: window resized."];
    [self refreshUI];
}

// Destruct the Vidyo Connector and uninitialize the VidyoClient
- (void)windowWillClose:( NSNotification * )notification {
    // Prepare to notify other parts of this app that it is quitting;
    //  Asynchronous or time-consuming functions should check this flag.
    appIsQuitting = true;

    // Since this app is designed with a single main window, closing it means that the app is quitting.
    // In order to quit gracefully, make sure that the VidyoClient is disconnected.
    if ( VidyoConnectorStateConnected == vidyoConnectorState ) {
        [vc disconnect];
        // ...Disconnecting can take time, and it might involve other threads.
        // Therefore, use a wait-loop to check when that operation has completed.
        // The wait condition should occur upon the "disconnected" callback.
        // Wait for a limited time; Let any other threads run while this waits.
        const size_t WAIT_DISCONNECT_MS = 9000; // Total wait time, in milliseconds.
        const size_t WAIT_ITERATION_MS  = 100; // Duration of each iteration, in milliseconds
        for ( size_t iters = 0; iters < ( WAIT_DISCONNECT_MS / WAIT_ITERATION_MS ); ++iters ) {
            // If desired condition occurs, exit this wait-loop early.
            if ( VidyoConnectorStateConnected != vidyoConnectorState ) {
                break;
            }
            [NSThread sleepForTimeInterval:0.1]; // sleep for 100 milliseconds
        }
    }

    // Release the devices.
    selectedLocalCamera = nil;
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

@end
