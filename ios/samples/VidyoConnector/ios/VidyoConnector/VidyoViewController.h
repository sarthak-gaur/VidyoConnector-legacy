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

#import <UIKit/UIKit.h>
#import <Lmi/VidyoClient/VidyoConnector_Objc.h>

@interface VidyoViewController : UIViewController <UITextFieldDelegate, VCConnectorIConnect, VCConnectorIRegisterLocalCameraEventListener, VCConnectorIRegisterLocalMicrophoneEventListener, VCConnectorIRegisterLocalSpeakerEventListener, VCConnectorIRegisterLogEventListener>

@property (weak, nonatomic) IBOutlet UITextField *portal;
@property (weak, nonatomic) IBOutlet UITextField *displayName;
@property (weak, nonatomic) IBOutlet UITextField *roomKey;
@property (weak, nonatomic) IBOutlet UITextField *roomPin;
@property (weak, nonatomic) IBOutlet UILabel     *toolbarStatusText;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *connectionSpinner;

@property (weak, nonatomic) IBOutlet UIButton *toggleConnectButton;
@property (weak, nonatomic) IBOutlet UIButton *microphonePrivacyButton;
@property (weak, nonatomic) IBOutlet UIButton *cameraPrivacyButton;

@property (weak, nonatomic) IBOutlet UIView  *controlsView;
@property (weak, nonatomic) IBOutlet UIView  *videoView;
@property (weak, nonatomic) IBOutlet UIView  *toolbarView;
@property (weak, nonatomic) IBOutlet UILabel *bottomControlSeparator;
@property (weak, nonatomic) IBOutlet UILabel *clientVersion;

- (IBAction)toggleConnectButtonPressed:(id)sender;
- (IBAction)cameraPrivacyButtonPressed:(id)sender;
- (IBAction)microphonePrivacyButtonPressed:(id)sender;
- (IBAction)cameraSwapButtonPressed:(id)sender;
- (IBAction)toggleDebugButtonPressed:(id)sender;
- (IBAction)toggleToolbar:(UITapGestureRecognizer *)sender;

@end

#endif // VIDYOVIEWCONTROLLER_H_INCLUDED
