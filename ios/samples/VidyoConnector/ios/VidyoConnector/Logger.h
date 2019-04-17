/**
{file:
	{name: Logger.h}
	{description: Logger interface to log to file. }
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
#ifndef LOGGER_H_INCLUDED
#define LOGGER_H_INCLUDED

@interface Logger : NSObject
{
@private
    
    NSString        *appLogPrefix;
    NSString        *libLogPrefix;
    NSFileHandle    *fileHandle;
    NSRecursiveLock *logFileLock;
}

- (void)Close;
- (void)Log:(NSString*)str;
- (void)LogClientLib:(const char*)str;

@end

#endif // LOGGER_H_INCLUDED
