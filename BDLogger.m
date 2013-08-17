//
// BDLogger.m
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

#import "BDLogger.h"
#import <sqlite3.h>

#define BD_ERROR_DOMAIN @"com.blackdog.bdlogger"

// --------------------------------------------------------------------------------------------------
// BDEntry implementation
// --------------------------------------------------------------------------------------------------
@implementation BDEntry

-(id)init {
	self = [super init];
	if (self != nil) {
		_timestamp = [NSDate date];
		_severity = BDSeverityNotice;
		_message = @"";
		_userInfo = nil;
	}
	return self;
}

-(NSString *)description {
	static NSString *severityDescriptions[] = { @"Emergency",@"Alert",@"Critical",@"Error",@"Warning",@"Notice",@"Info",@"Debug" };
	NSString *severityDescription = self.severity > BDSeverityDebug ? @"Unknown" : severityDescriptions[self.severity];
	return [NSString stringWithFormat:@"%@ [%@] %@ %@", self.timestamp, severityDescription, self.message, self.userInfo == nil ? @"" : self.userInfo];
}

@end


// --------------------------------------------------------------------------------------------------
// BDLogger implementation
// --------------------------------------------------------------------------------------------------
@interface BDLogger ()

/** The location of the log store */
@property (nonatomic, strong) NSURL *logStoreURL;

/** The underlying sqlite connection object */
@property (nonatomic, assign) sqlite3 *connection;

/** The pre-prepared insert statement to insert new records */
@property (nonatomic, assign) sqlite3_stmt *insertStatement;

/** The GCD background queue that all logging inserts get executed on */
@property (nonatomic, strong) dispatch_queue_t dispatchQueue;

/** When was the log store was last checked to see if needed pruning.  Does not persist over instiations of this class. */
@property (nonatomic, strong) NSDate *lastCheckForPruning;

@end

@implementation BDLogger

-(id)initWithURL:(NSURL *)logStoreURL {
	self = [super init];
	if (self != nil) {
		_logStoreURL = logStoreURL;
		_connection = NULL;
		_insertStatement = NULL;
		_dispatchQueue = dispatch_queue_create("com.blackdog.bdlogger.queue", DISPATCH_QUEUE_SERIAL);
		_lastCheckForPruning = [NSDate dateWithTimeIntervalSince1970:0];
		_filterSeverity = BDSeverityWarning;
		_pruneLimitDays = @(7);
		_pruneFrequencySecs = @(3600);
#if TARGET_IPHONE_SIMULATOR
		_shouldNSLog = YES;
#else
		_shouldNSLog = NO;
#endif
	}
	return self;
}

#
#pragma mark - Setup and teardown
#
-(BOOL)open:(NSError **)error {
	__block BOOL success = YES;
	dispatch_sync(self.dispatchQueue, ^(void) {
		sqlite3 *connection;
		
		NSUInteger rc = sqlite3_open([[self.logStoreURL absoluteString] UTF8String], &connection);
		if (rc != SQLITE_OK) {
			if (error != NULL) {
				NSString *message = [NSString stringWithFormat:@"Unable to open connection to %@ (rc=%d): %s", [self.logStoreURL absoluteString], rc, sqlite3_errmsg(connection)];
				*error = [NSError errorWithDomain:BD_ERROR_DOMAIN code:rc userInfo:@{ NSLocalizedDescriptionKey : message }];
				success = NO;
				return;
			}
		}
		self.connection = connection;

		NSString *createTableSQL = @"CREATE TABLE IF NOT EXISTS LOG_ENTRIES (Z_TIMESTAMP REAL, Z_SEVERITY INTEGER, Z_MESSAGE TEXT, Z_USERINFO BLOB)";
		rc = sqlite3_exec(self.connection, [createTableSQL UTF8String], NULL, NULL, NULL);
		if (rc != SQLITE_OK) {
			if (error != NULL) {
				NSString *message = [NSString stringWithFormat:@"Unable to create LOG_ENTRIES table (rc=%d): %s", rc, sqlite3_errmsg(self.connection)];
				*error = [NSError errorWithDomain:BD_ERROR_DOMAIN code:rc userInfo:@{ NSLocalizedDescriptionKey : message }];
				success = NO;
				return;
			}
		}
		
		NSString *createIndexSQL = @"CREATE INDEX IF NOT EXISTS LOG_TSTAMP_I ON LOG_ENTRIES (Z_TIMESTAMP DESC, Z_SEVERITY DESC)";
		rc = sqlite3_exec(self.connection, [createIndexSQL UTF8String], NULL, NULL, NULL);
		if (rc != SQLITE_OK) {
			if (error != NULL) {
				NSString *message = [NSString stringWithFormat:@"Unable to create LOG_TSTAMP_I index (rc=%d): %s", rc, sqlite3_errmsg(self.connection)];
				*error = [NSError errorWithDomain:BD_ERROR_DOMAIN code:rc userInfo:@{ NSLocalizedDescriptionKey : message }];
				success = NO;
				return;
			}
		}
		
		sqlite3_stmt *insertStatement;
		NSString *sql = @"INSERT INTO LOG_ENTRIES (Z_TIMESTAMP, Z_SEVERITY, Z_MESSAGE, Z_USERINFO) VALUES (?, ?, ?, ?)";
		rc = sqlite3_prepare_v2(self.connection, [sql UTF8String], (int)[sql length], &insertStatement, NULL);
		if (rc != SQLITE_OK) {
			if (error != NULL) {
				NSString *message = [NSString stringWithFormat:@"Unable to prepare insert statement (rc=%d): %s", rc, sqlite3_errmsg(self.connection)];
				*error = [NSError errorWithDomain:BD_ERROR_DOMAIN code:rc userInfo:@{ NSLocalizedDescriptionKey : message }];
				success = NO;
				return;
			}
		}
		self.insertStatement = insertStatement;
	});
	return success;
}

-(BOOL)close:(NSError **)error {
	__block BOOL success = YES;
	dispatch_sync(self.dispatchQueue, ^(void) {

		if (self.insertStatement != NULL) {
			NSUInteger rc = sqlite3_finalize(self.insertStatement);
			if (rc != SQLITE_OK) {
				if (error != NULL) {
					NSString *message = [NSString stringWithFormat:@"Unable to finalize insert statement (rc=%d): %s", rc, sqlite3_errmsg(self.connection)];
					*error = [NSError errorWithDomain:BD_ERROR_DOMAIN code:rc userInfo:@{ NSLocalizedDescriptionKey : message }];
				}
				success = NO;
				return;
			}
			self.insertStatement = NULL;
		}
			
		if (self.connection != NULL) {
			NSUInteger rc = sqlite3_close(self.connection);
			if (rc != SQLITE_OK) {
				if (error != NULL) {
					NSString *message = [NSString stringWithFormat:@"Unable to close connection (rc=%d): %s", rc, sqlite3_errmsg(self.connection)];
					*error = [NSError errorWithDomain:BD_ERROR_DOMAIN code:rc userInfo:@{ NSLocalizedDescriptionKey : message }];
				}
				success = NO;
				return;
			}
			self.connection = NULL;
		}
	});
	return success;
}

#
#pragma mark - Logging entries
#
-(void)log:(BDSeverity)severity message:(NSString *)message {
	// no point proceeding further if we aren't going to log
	if (![self isLoggingSeverity:severity])
		return;
	
	BDEntry *entry = [[BDEntry alloc] init];
	entry.message = message;
	entry.severity = severity;
	[self log:entry];
}

-(void)log:(BDSeverity)severity messageWithFormat:(NSString *)messageFormat, ... {
	// no point proceeding further if we aren't going to log
	if (![self isLoggingSeverity:severity])
		return;

	va_list args;
	va_start(args, messageFormat);
	NSString *message = [[NSString alloc] initWithFormat:messageFormat arguments:args];
	va_end(args);
	[self log:severity message:message];
}

-(void)log:(BDEntry *)entry {
	// OK, so do we really even need to log this entry?
	if (![self isLoggingSeverity:entry.severity])
		return;

	// now we'll make sure our pruning is up-to-date
	[self pruneIfNecessary];
	
	dispatch_async(self.dispatchQueue, ^(void) {
		if (self.shouldNSLog) {
			NSLog(@"%@", [entry description]);
		}
		
		sqlite3_reset(self.insertStatement);
		sqlite3_bind_double(self.insertStatement, 1, [entry.timestamp timeIntervalSince1970]);
		sqlite3_bind_int(self.insertStatement, 2, entry.severity);
		sqlite3_bind_text(self.insertStatement, 3, [entry.message UTF8String], -1, NULL);
		if (entry.userInfo == nil)
			sqlite3_bind_blob(self.insertStatement, 4, NULL, 0, NULL);
		else {
			NSData *data = [NSKeyedArchiver archivedDataWithRootObject:entry.userInfo];
			sqlite3_bind_blob(self.insertStatement, 4, [data bytes], (int)[data length], NULL);
		}
		
		NSUInteger rc = sqlite3_step(self.insertStatement);
		if (rc != SQLITE_DONE) {
			// hmm... if, for some reason, we can't save it into the log store, let's at least dump it
			// out via NSLog along with an error
			NSLog(@"Failed to save log entry (rc=%d): %s", rc, sqlite3_errmsg(self.connection));
			NSLog(@"%@", [entry description]);
		}
	});
}

-(BOOL)isLoggingSeverity:(BDSeverity)severity {
	return self.filterSeverity >= severity;
}

#
#pragma mark - Retrieving entries
#
-(NSArray *)retrieveBetweenStart:(NSDate *)startDate end:(NSDate *)endDate severity:(BDSeverity)severity error:(NSError **)error {
	return [self retrieveBetweenStart:startDate end:endDate severity:severity maxEntries:NSUIntegerMax ascending:YES error:error];
}

-(NSArray *)retrieveRecent:(NSUInteger)entryCount severity:(BDSeverity)severity error:(NSError **)error {
	return [self retrieveBetweenStart:nil end:nil severity:severity maxEntries:entryCount ascending:NO error:error];
}

-(NSArray *)retrieveBetweenStart:(NSDate *)startDate end:(NSDate *)endDate severity:(BDSeverity)severity maxEntries:(NSUInteger)maxEntries ascending:(BOOL)ascending error:(NSError **)error {
	// first thing to do is to make sure our pruning is up-to-date
	[self pruneIfNecessary];
	
	__block NSMutableArray *entries = [NSMutableArray array];
	dispatch_sync(self.dispatchQueue, ^(void) {
		sqlite3_stmt *statement;
		NSTimeInterval startTimeInterval = startDate == nil ? 0 : [startDate timeIntervalSince1970];
		NSTimeInterval endTimeInterval   = endDate == nil ? [[NSDate date] timeIntervalSince1970] : [endDate timeIntervalSince1970];
		NSString *sql = [NSString stringWithFormat:@"SELECT Z_TIMESTAMP, Z_SEVERITY, Z_MESSAGE, Z_USERINFO FROM LOG_ENTRIES WHERE Z_TIMESTAMP BETWEEN ? AND ? AND Z_SEVERITY <= ? ORDER BY Z_TIMESTAMP %@", (ascending ? @"ASC" : @"DESC")];
		NSUInteger rc = sqlite3_prepare_v2(self.connection, [sql UTF8String], -1, &statement, NULL);
		if (rc == SQLITE_OK) {
			NSUInteger count = 0;
			sqlite3_bind_double(statement, 1, startTimeInterval);
			sqlite3_bind_double(statement, 2, endTimeInterval);
			sqlite3_bind_int(statement, 3, severity);
			while (sqlite3_step(statement) == SQLITE_ROW && count < maxEntries) {
				// timestamp
				NSDate *timestamp = [[NSDate alloc] initWithTimeIntervalSince1970:sqlite3_column_double(statement, 0)];
				// severity
				BDSeverity severity = sqlite3_column_int(statement, 1);
				// message
				const unsigned char *messageBytes = sqlite3_column_text(statement, 2);
				NSUInteger messageLength = sqlite3_column_bytes(statement, 2);
				NSString *message = [[NSString alloc] initWithBytes:messageBytes length:messageLength encoding:NSUTF8StringEncoding];
				// userInfo
				const void *userInfoBytes = sqlite3_column_blob(statement, 3);
				NSUInteger userInfoLength = sqlite3_column_bytes(statement, 3);
				NSDictionary *userInfo = nil;
				if (userInfoLength != 0) {
					userInfo = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithBytes:userInfoBytes length:userInfoLength]];
				}
				// create entry and populate
				BDEntry *entry = [[BDEntry alloc] init];
				entry.timestamp = timestamp;
				entry.severity = severity;
				entry.message = message;
				entry.userInfo = userInfo;
				[entries addObject:entry];
				
				count++;
			}
			rc = sqlite3_finalize(statement);
			if (rc != SQLITE_OK) {
				if (error != NULL) {
					NSString *message = [NSString stringWithFormat:@"Unable to finalise retrieve entries statement (rc=%d): %s", rc, sqlite3_errmsg(self.connection)];
					*error = [NSError errorWithDomain:BD_ERROR_DOMAIN code:rc userInfo:@{ NSLocalizedDescriptionKey : message }];
				}
				entries = nil;
			}
		}
		else {
			if (error != NULL) {
				NSString *message = [NSString stringWithFormat:@"Unable to prepare statement for retrieving entries (rc=%d): %s", rc, sqlite3_errmsg(self.connection)];
				*error = [NSError errorWithDomain:BD_ERROR_DOMAIN code:rc userInfo:@{ NSLocalizedDescriptionKey : message }];
			}
			entries = nil;
		}
	});
	return entries;
}

#
#pragma mark - Housekeeping and pruning
#
-(void)pruneIfNecessary {
	dispatch_async(self.dispatchQueue, ^(void) {
		NSDate *now = [NSDate date];
		NSTimeInterval nextPruneCheckTime = [self.lastCheckForPruning timeIntervalSince1970] + [self.pruneFrequencySecs doubleValue];
		if (nextPruneCheckTime >= [now timeIntervalSince1970])
			return;
		
		NSTimeInterval pruneCutoffTime = [now timeIntervalSince1970] - ([self.pruneLimitDays doubleValue] * 24 * 60 * 60);
		
		sqlite3_stmt *statement;
		NSString *sql = @"DELETE FROM LOG_ENTRIES WHERE Z_TIMESTAMP < ?";
		NSUInteger rc = sqlite3_prepare_v2(self.connection, [sql UTF8String], -1, &statement, NULL);
		if (rc == SQLITE_OK) {
			sqlite3_bind_double(statement, 1, pruneCutoffTime);
			rc = sqlite3_step(statement);
			if (rc != SQLITE_DONE) {
				NSLog(@"Unable to execute prune statement (rc=%d): %s", rc, sqlite3_errmsg(self.connection));
			}
			rc = sqlite3_finalize(statement);
			if (rc != SQLITE_OK) {
				NSLog(@"Unable to finalise prune statement (rc=%d): %s", rc, sqlite3_errmsg(self.connection));
			}
		}
		else {
			NSLog(@"Unable to prepare prune statement (rc=%d): %s", rc, sqlite3_errmsg(self.connection));
		}
		self.lastCheckForPruning = now;
	});
}

-(void)dealloc {
	[self close:nil];
}

#
#pragma mark - Singleton logger
#
+(instancetype)logger {
	static BDLogger *logger;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		// by default we store the log file in the caches directory
		NSString *cacheDirPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
		if (![[NSFileManager defaultManager] fileExistsAtPath:cacheDirPath isDirectory:&(BOOL){0}])
			[[NSFileManager defaultManager] createDirectoryAtPath:cacheDirPath withIntermediateDirectories:YES attributes:nil error:nil];
		NSString *logFilePath = [cacheDirPath stringByAppendingPathComponent:@"BDLogger.logdb"];
		logger = [[BDLogger alloc] initWithURL:[NSURL URLWithString:logFilePath]];
		NSError *error = nil;
		if ([logger open:&error] == NO) {
			logger = nil;
			NSLog(@"Unable to open %@: %@", logFilePath, [error localizedDescription]);
		}
	});
	return logger;
}
@end


