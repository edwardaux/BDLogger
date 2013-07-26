//
// BDLogger.h
//
// Copyright (c) 2013 Craig Edwards
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, BDSeverity) {
	BDSeverityEmergency = 0,
	BDSeverityAlert     = 1,
	BDSeverityCritical  = 2,
	BDSeverityError     = 3,
	BDSeverityWarning   = 4,
	BDSeverityNotice    = 5,
	BDSeverityInfo      = 6,
	BDSeverityDebug     = 7
};

/**
 * Represents a single log entry in the log store.  Is used both when creating an entry to
 * write to the log store, and also when retrieving from the log store.
 */
@interface BDEntry : NSObject

/** The timestamp of the log entry. If not set, defaults to current system time */
@property (nonatomic, strong) NSDate *timestamp;

/** The actual text of the message to be logged. If not set, defaults to empty string. */
@property (nonatomic, strong) NSString *message;

/** The severity of the log entry. If not set, defaults to BDSeverityNotice */
@property (nonatomic, assign) BDSeverity severity;

/** An arbitrary collection of values that will be logged along with the message. Can be nil. */
@property (nonatomic, strong) NSDictionary *userInfo;

@end


/**
 * Provides the ability to store and retrieve log entries into a simple log store for later
 * retrieval and analysis.  Key features include:
 *
 *   - Supports logging only entries that have a certain severity or worse
 *   - Keeping only 'n' days worth of logs in order to keep log store size manageable
 *   - Conditionally log using NSLog as well as writing to the log store (allows for easy visibility while debugging in Xcode)
 *   - Quick and easy retrieval of log messages based on date range and severity
 *   - Storage of additional user-specific data per message 
 *
 * All calls to the log: methods run using their own background GCD queue in order to reduce the impact
 * that logging has on the application performance. 
 *
 * A convenience class method called +logger returns an application-wide singleton logger that places 
 * the log store in the user's Caches directory.  The most basic example of how to use the logger is as
 * follows:
 *
 *     BDLogger *logger = [BDLogger logger];
 *     logger.filterSeverity = BDSeverityDebug;
 *     [logger log:BDSeverityInfo message:@"this is a msg"];
 *
 * If you need to store additional information against each log entry, you can create an instance of an
 * BDEntry, and set the userInfo property to a dictionary containing whatever information you like.
 *
 *     BDEntry *entry = [[BDEntry alloc] init];
 *     entry.severity = BDSeverityAlert;
 *     entry.message = @"Some alert";
 *     entry.userInfo = @{ @"somekey" : @"somevalue", @"otherkey" : @(123) };
 *     [logger log:entry];
 *
 * In addition to saving log entries, they can easily be retrieved by calling the -entriesBetweenStart:end:severity:error:
 * method.  For example:
 * 
 *     BDLogger *logger = [BDLogger logger];
 *     NSError *error = nil;
 *     NSDate *startDate = ...;
 *     NSDate *endDate = ...;
 *     NSArray *entries = [logger entriesBetweenStart:startDate end:endDate severity:BDSeverityInfo error:&error];
 *
 * While the system offers a singleton logger object, you can still create your own loggers if you want to
 * control where the log store gets written.
 *
 *     NSError *error = nil;
 *     NSString *pathToFile = ...;
 *     BDLogger *logger = [[BDLogger alloc] initWithURL:[NSURL URLWithString:pathToFile]];
 *     [logger open:&error];
 *     [logger log:BDSeverityInfo message:@"this is a msg"];
 * 
 * Pruning the entries out of the log file can be controlled via the pruneLimitDays and pruneFrequencySecs properties.
 * By default, the logger will keep one week's worth of entries in the file and will prune off the trailing records every
 * hour.  
 * @warning Because the settings for pruning are *not* persisted across application launches, if you want to set the 
 * pruneLimitDays to a longer period than a week, you will need make sure that you set it again when the application 
 * relaunches *before* any calls to -log get invoked.  Otherwise, the very first call the the BDLogger code will trigger
 * a prune based on the default period of 7 days.
 */
@interface BDLogger : NSObject

/** Sets the most verbose severity to log. Defaults to BDSeverityWarning */
@property (nonatomic, assign) BDSeverity filterSeverity;

/** In addition to logging to the store, should it also log using NSLog. Defaults to YES when running in simulator, NO otherwise. */
@property (nonatomic, assign) BOOL shouldNSLog;

/** Controls how many day's worth of log entries are kept in the store. Defaults to 7.0 */
@property (nonatomic, strong) NSNumber *pruneLimitDays;

/** Controls how often the log store will check for entries that are due to be pruned. Defaults to 3600 (1 hour) */
@property (nonatomic, strong) NSNumber *pruneFrequencySecs;

/**
 * Initialises the logger with a custom log store location
 *
 * @param storeURL The log store location
 */
-(id)initWithURL:(NSURL *)logStoreURL;

/**
 * Opens a connection to the underlying log store.
 *
 * @param error A pointer to an NSError instance which will be populated upon error
 * @return A boolean indicating whether the log store was able to be successfully opened and initialised
 */
-(BOOL)open:(NSError **)error;

/**
 * Closes the connection to the underlying log store.  Normally only called by the BDLogger instance on deallocation,
 * however, it is available for calling if you know for sure that you are finished with the logger instance.
 *
 * @param error A pointer to an NSError instance which will be populated upon error
 * @return A boolean indicating whether the log store was able to be successfully closed
  */ 
-(BOOL)close:(NSError **)error;

/**
 * Write a log message with a particular severity.  Only messages that are of equal or worse severity to the
 * filterSeverity property will be written to the log store. Places the message on a background GCD queue, and 
 * returns immediately.
 *
 * @param severity The severity of the message
 * @param message The message text
 */
-(void)log:(BDSeverity)severity message:(NSString *)message;

/**
 * Write a log message using the standard NSString format specifiers and parameters with a particular severity.  Only 
 * messages that are of equal or worse severity to the filterSeverity property will be written to the log store. Places 
 * the message on a background GCD queue, and returns immediately.
 *
 * @param severity The severity of the message
 * @param messageFormat A format string, followed by the parameter to be substituted
 */
-(void)log:(BDSeverity)severity messageWithFormat:(NSString *)messageFormat, ...;

/**
 * Write a pre-created log entry.  Only log entries that are of equal or worse severity to the filterSeverity property 
 * will be written to the log store. Places the message on a background GCD queue, and returns immediately.
 *
 * @param entry The entry that contains the details to be logged
 */
-(void)log:(BDEntry *)entry;

/**
 * Retrieves all log entries within a given date range, with equal to or worse severity.  The entries will be sorted in
 * descending timestamp order (ie. most recent first).
 * 
 * @param startDate The start date.  If nil, an unbounded start date will be used.
 * @param endDate The end date.  If nil, an unbounded end date will be used.
 * @param severity The level of entry severity (or worse) to be returned 
 * @param error A pointer to an NSError instance which will be populated upon error
 * @return A collection of the log entries matching the input criteria, or nil if an error occurs.
 */
-(NSArray *)retrieveBetweenStart:(NSDate *)startDate end:(NSDate *)endDate severity:(BDSeverity)severity error:(NSError **)error;

/**
 * Retrieves the most recent log entries, with equal to or worse severity.  The entries will be sorted in descending 
 * timestamp order (ie. most recent first).
 *
 * @param entryCount The maximum number of recent entries to retrieve.
 * @param severity The level of entry severity (or worse) to be returned
 * @param error A pointer to an NSError instance which will be populated upon error
 * @return A collection of the log entries matching the input criteria, or nil if an error occurs.
 */
-(NSArray *)retrieveRecent:(NSUInteger)entryCount severity:(BDSeverity)severity error:(NSError **)error;

/**
 * Returns an application-wide instance of a logger using the default settings.
 * @return Application-wide instance of BDLogger
 */
+(instancetype)logger;

@end
