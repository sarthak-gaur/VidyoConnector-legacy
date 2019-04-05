/**
{file:
	{name: VidyoViewController.h}
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
#ifndef VIDYOVIEWCONTROLLER_H_INCLUDED
#define VIDYOVIEWCONTROLLER_H_INCLUDED

#import <Cocoa/Cocoa.h>
#import <Lmi/VidyoClient/VidyoConnector_Objc.h>
#import "Logger.h"
#import "AppSettings.h"

enum VidyoConnectorState {
    VidyoConnectorStateConnected,
    VidyoConnectorStateDisconnected,
    VidyoConnectorStateDisconnectedUnexpected,
    VidyoConnectorStateFailure
};

@interface VidyoViewController : NSViewController<NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, VCConnectorIConnect, VCConnectorIRegisterLocalCameraEventListener, VCConnectorIRegisterLocalMicrophoneEventListener, VCConnectorIRegisterLocalSpeakerEventListener, VCConnectorIRegisterLogEventListener, VCConnectorIRegisterLocalMonitorEventListener, VCConnectorIRegisterLocalWindowShareEventListener, VCConnectorIRegisterParticipantEventListener, VCConnectorIRegisterRemoteCameraEventListener, VCConnectorIRegisterNetworkInterfaceEventListener, VCConnectorIRegisterMessageEventListener>
{
@private
    VCConnector     *vc;
    NSMapTable      *cameraMap;
    NSMapTable      *videoContentShareMap;
    NSMapTable      *microphoneMap;
    NSMapTable      *audioContentShareMap;
    NSMapTable      *speakerMap;
    NSMapTable      *monitorShareMap;
    NSMapTable      *windowShareMap;
    NSMutableArray  *chatTableUsers;
    NSMutableArray  *chatTableMessages;
    NSMenu          *devicesMenu;
    NSMenu          *sharesMenu;
    NSMenu          *contentMenu;
    NSRecursiveLock *deviceLock;
    Logger          *logger;
    NSImage         *callStartImage;
    NSImage         *callEndImage;
    NSMenuItem      *connectMenuItem;
    NSMenuItem      *disconnectMenuItem;
    NSMenuItem      *debugMenuItem;
    NSMenuItem      *noCameraMenuItem;
    NSMenuItem      *noMicrophoneMenuItem;
    NSMenuItem      *noSpeakerMenuItem;
    NSMenuItem      *noVideoContentShareMenuItem;
    NSMenuItem      *noAudioContentShareMenuItem;
    NSMenuItem      *noMonitorShareMenuItem;
    NSMenuItem      *noWindowShareMenuItem;
    NSMenuItem      *selectedMaxResolutionMenuItem;
    NSMenuItem      *showSharePreviewMenuItem;
    VCLocalCamera   *selectedLocalCamera;

    enum VidyoConnectorState vidyoConnectorState;
    BOOL isSharingWindow;
    BOOL isSharingMonitor;
    BOOL showSharePreview;
    AppSettings *appSettings;
}

@property (assign) IBOutlet NSTextField *portal;
@property (assign) IBOutlet NSTextField *roomKey;
@property (assign) IBOutlet NSTextField *displayName;
@property (assign) IBOutlet NSTextField *roomPin;
@property (assign) IBOutlet NSTextField *controlsStatusText;
@property (assign) IBOutlet NSTextField *toolbarStatusText;
@property (assign) IBOutlet NSTextField *participantStatusText;
@property (assign) IBOutlet NSTextField *chatMessage;

@property (assign) IBOutlet NSButton *toggleConnectButton;
@property (assign) IBOutlet NSButton *cameraPrivacyButton;
@property (assign) IBOutlet NSButton *microphonePrivacyButton;
@property (assign) IBOutlet NSButton *speakerPrivacyButton;
@property (assign) IBOutlet NSProgressIndicator *connectionSpinner;
@property (weak)   IBOutlet NSTableView *chatTableView;

- (IBAction)toggleConnectButtonPressed:(id)sender;
- (IBAction)cameraPrivacyButtonPressed:(id)sender;
- (IBAction)microphonePrivacyButtonPressed:(id)sender;
- (IBAction)speakerPrivacyButtonPressed:(id)sender;
- (IBAction)toggleChatButtonPressed:(id)sender;
- (IBAction)sendChatButtonPressed:(id)sender;

@property (assign) IBOutlet NSView *mainView;
@property (assign) IBOutlet NSView *controlsView;
@property (assign) IBOutlet NSView *previewView;
@property (assign) IBOutlet NSView *chatView;

@end

#endif // VIDYOVIEWCONTROLLER_H_INCLUDED
