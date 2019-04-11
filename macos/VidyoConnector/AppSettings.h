/**
{file:
	{name: AppSettings.h}
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
#ifndef APPSETTINGS_H_INCLUDED
#define APPSETTINGS_H_INCLUDED

#import <Cocoa/Cocoa.h>

@interface AppSettings : NSObject

@property(nonatomic, readwrite) NSString *displayName;
@property(nonatomic, readwrite) NSString *experimentalOptions;
@property(nonatomic, readwrite) NSString *portal;
@property(nonatomic, readwrite) NSString *roomKey;
@property(nonatomic, readwrite) NSString *roomPin;
@property(nonatomic, readwrite) BOOL enableDebug;
@property(nonatomic, readwrite) BOOL cameraPrivacy;
@property(nonatomic, readwrite) BOOL microphonePrivacy;
@property(nonatomic, readwrite) BOOL speakerPrivacy;
@property(nonatomic, readwrite) BOOL hideConfig;
@property(nonatomic, readwrite) BOOL autoJoin;
@property(nonatomic, readwrite) BOOL allowReconnect;

-(void) extract;
-(BOOL) toggleDebug;
-(BOOL) toggleCameraPrivacy;
-(BOOL) toggleMicrophonePrivacy;
-(BOOL) toggleSpeakerPrivacy;

@end

#endif /* APPSETTINGS_H_INCLUDED */
