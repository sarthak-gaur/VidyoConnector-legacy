/**
{file:
	{name: WelcomeViewController.m}
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
#import "VidyoConnectorAppDelegate.h"
#import "WelcomeViewController.h"

@interface WelcomeViewController ()

@end

@implementation WelcomeViewController

- (void)viewDidAppear:(BOOL)animated {
    // Display the welcome screen.
    [super viewDidAppear:animated];

    // If launched by a different app, then segue immediately.
	// ...In other words, if not launched by a different app, then delay the segue.
    if (nil == [(VidyoConnectorAppDelegate *)[[UIApplication sharedApplication] delegate] urlParameters]) {
        [NSThread sleepForTimeInterval:1.5];
    }
	// Navigate to the VidyoViewController
    [self performSegueWithIdentifier:@"segueStartToVidyoView" sender:self];
}

@end
