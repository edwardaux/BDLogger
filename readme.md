## Introducing BDLogger
BDLogger is a very simple, yet powerful, alternative to the ASL logging infrastructure on the iPhone.

Consider the case where your application needs to capture some error information for later diagnosis by production support.  If you just output it using `NSLog`, unless you have physical access to the phone, or ask your user to manually extract the console logs, it is very difficult to get back the information you need.

ASL purports to offer the ability to store messages into a persistent store that can then be queried at a later time, filtering by timestamp, severity and a whole bunch more.

BDLogger offers a very similar feature set to ASL, albeit with a few more niceties.  Key features include:

* Supports logging only entries that have a certain severity or worse
* Keeping only 'n' days worth of logs in order to keep log store size manageable
* Conditionally log using NSLog as well as writing to the log store (allows for easy visibility while debugging in Xcode)
* Quick and easy retrieval of log messages based on date range and severity
* Storage of additional user-specific data per message 

### Why not ASL?
Unfortunately there are a number of [undocumented gotchas](http://openradar.appspot.com/14461599) that make using ASL on the iPhone challenging.  In particular, ASL apparently only keeps the most recent 256 log entries around and only in-memory so if your application closes, those are lost forever.

Additionally, even were we to accept the undocumented limitations, the standard ASL query functionality [does not return the previously saved log entries](http://openradar.appspot.com/14461411).  

The two radars mentioned above basically mean that ASL is not able to be used in any meaningful way on an iPhone application.

### Logging Using BDLogger
At its simplest, you can log an entry to the BDLogger store by using the following code:

<pre lang="objc">
BDLogger *logger = [BDLogger logger];
[logger log:BDSeverityError message:@"this is an error msg"];
</pre>

Of course, in production, you probably want to be able to control what severity entries get saved into the log store. You can do that by setting the `filterSeverity` property on the logger (obviously this only has to be done once each time your application starts): 

<pre lang="objc">
BDLogger *logger = [BDLogger logger];
logger.filterSeverity = BDSeverityInfo;
</pre>

What about storing other fields against in the log entry, I hear you ask?  BDLogger has you covered:

<pre lang="objc">
BDEntry *entry = [[BDEntry alloc] init];
entry.severity = BDSeverityAlert;
entry.message = @"Some alert";
entry.userInfo = @{ 
	@"somekey" : @"somevalue", 
	@"otherkey" : @(123) 
};
[logger log:entry];
</pre>

### Retrieving Entries
It is all well and good being able to save entries, but you need to be able to selectively retrieve them.  Two examples of retrieving entries are shown below:

<pre lang="objc">
BDLogger *logger = [BDLogger logger];

// returns entries between two dates that are Info severity (or worse)
NSDate *startDate = ...;
NSDate *endDate = ...;
NSArray *entries = [logger entriesBetweenStart:startDate end:endDate severity:BDSeverityInfo error:nil];

// returns the last 10 entries that are Info severity or worse
NSArray *entries = [logger retrieveRecent:10 severity:BDSeverityInfo error:nil];
</pre>

### Housekeeping
By default, BDLogger will keep your log entries for up to 7 days.  If you set the `pruneLimitDays` property to a longer or shorter period, BDLogger will ensure that the older log entries get pruned off in a timely manner so that your user's phone doesn't get filled with old log entries.

### Mac OS X Support
BDLogger works just fine on Mac OS X too. 

However, having said that, the ASL infrastructure on Mac OS X doesn't suffer from the limitations that are present on the iPhone so ASL may well be a practical option for you on Mac OS X.

## How to Install
### Compile Time
To embed BDLogger in your code, you simply need to have `BDLogger.h` and `BDLogger.m` compiled into your code.  

##### Option 1: Copy files
The simplest way to do this is to perform a `git clone` of the [BDLogger project](https://github.com/edwardaux/bdlogger) and manually copy (or reference) the files into your project. 

##### Option 2: Add as a submodule
Another technique is to add BDLogger as a submodule.  Run the following commands from your project's root directory:

<pre lang="text">
git submodule init
git submodule add https://github.com/edwardaux/bdlogger
</pre>

and then from a Finder window, drag `BDLogger.h` and `BDLogger.m` into your project and add them to your application's target.
 
### Linking Requirements
You will also need to add `libsqlite3.dylib` into the list of Linked Libraries for your target.

## License
BDLogger is licensed under the MIT License.

	Copyright (c) 2013 Craig Edwards
	
	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.
	
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
	THE SOFTWARE.
