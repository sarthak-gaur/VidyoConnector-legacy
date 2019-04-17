/**
{file:
	{name: Logger.m}
	{description: Logger to log to file and console. }
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
#include <stdio.h>
#import "Logger.h"

@interface Logger ()

@end

@implementation Logger

// initialize the Logger
- ( id )init {
    self = [super init];

    // Lock used in case LogApp and LogClientLib are called at same time on multiple threads
    logFileLock = [[NSRecursiveLock alloc] init];

    // Prefix to the app logging and VidyoClientLibrary logging
    appLogPrefix = [[NSString alloc] initWithUTF8String:"VidyoConnector App:"];
    libLogPrefix = [[NSString alloc] initWithUTF8String:"VidyoClientLibrary:"];
    
    // Get the path the users documents directory
    NSArray  *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *filePath = [[NSString alloc] initWithString:[documentsDirectory stringByAppendingPathComponent:@"VidyoConnectorApp.log"]];
    
    // Write the header to the file and clear it if it already exists
    NSString *fileHeader = [NSString stringWithUTF8String:"VidyoConnector App Log File\n==============================\n"];
    [fileHeader writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // Obtain the file handle (must be done after writing to file above)
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];

    return self;
}

// close the file handle
- ( void )Close {
    if ( fileHandle ) {
        [fileHandle closeFile];
    }
}

// log data to console and file which originated from the app
- ( void )Log:( NSString * )str {
    // Log to console
    NSLog( @"%@", str );

    // Log to file
    if (fileHandle) {
        [logFileLock lock];
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[[NSString stringWithFormat:@"%@ %@\n", appLogPrefix, str] dataUsingEncoding:NSUTF8StringEncoding]];
        [logFileLock unlock];
    }
}

// log data to console and file which originated from the VidyoClientLibrary
- ( void )LogClientLib:( const char * )str {
    // No need to log to console here, since that is implicitly done when calling registerLogEventListener.

    // Log to file
    if (fileHandle) {
        // Convert to NSString*
        NSString* nsStr = [NSString stringWithUTF8String:str];

        [logFileLock lock];
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[[NSString stringWithFormat:@"%@ %@\n", libLogPrefix, nsStr] dataUsingEncoding:NSUTF8StringEncoding]];
        [logFileLock unlock];
    }
}

@end
