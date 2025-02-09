//
//  SecretSocksController.m
//  Secret Socks
//
//  Created by Joshua Chan on 11/07/09.
//  Enhanced by Ling Mo 20/01/2013

#import "SecretSocksController.h"

@implementation SecretSocksController


- (id)init {
    NSLog(@"init");
	self = [super init];

	isConnected = false;
	windowHasBeenClosed = false;
	thisBundle = [NSBundle bundleForClass:[self class]];

	preferences = [[NSUserDefaults standardUserDefaults] retain];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
	  @"" ,@"hostName",
	  @"22" , @"portNumber",
	  @"", @"obfuscationKey",
	  @"", @"username",
      @"",@"password",
	  @"7070", @"socksPort",
      @"30",@"timeout",
	  [NSNumber numberWithInt:0], @"applyToNetwork",
      [NSNumber numberWithInt:0], @"isAsyncKeysFirst",
      [NSNumber numberWithInt:1], @"isAutoLogin",
	  nil ]; // terminate the list
	[preferences registerDefaults:dict];
    
	return self;
}


// Show the config screen
- (IBAction)showConfig:(id)sender {
	if ([drawer state] != NSDrawerOpenState) {
		[toggleDrawer performClick: self];
	}
	[tabs selectTabViewItemWithIdentifier:@"config"];
}

// Show the status screen
- (IBAction)showStatus:(id)sender {
	if ([drawer state] != NSDrawerOpenState) {
		[toggleDrawer performClick: self];
	}
	[tabs selectTabViewItemWithIdentifier:@"status"];
}

// Show the help screen
- (IBAction)showHelp:(id)sender {
	if ([drawer state] != NSDrawerOpenState) {
		[toggleDrawer performClick: self];
	}
	[tabs selectTabViewItemWithIdentifier:@"help"];
}


// Respond to clicking the "Connect" button
- (IBAction)doConnect:(id)sender {
	[self doAutoConnect];
}

-(bool)doAutoConnect{

	if (!isConnected) {
		// Make sure hostname settings is present
		if ([[hostnameField stringValue] length] == 0) {
			[self showConfig: self];
			return false;
		}
		// Get password
		else if ([passwordDrawer state] == NSDrawerOpenState) {
			// standalone passwd has priority if drawer is open
		    [passwordField setStringValue: [passwordField2 stringValue]];
		}
        // If the user wants to try public/private keys first,
        // no point to prompt for password
		else if ([[passwordField stringValue] length] == 0 &&
                 [isAsyncKeysFirst state] == NSOffState)
        {
			//
            if ([[passwordField2 stringValue] length] == 0)  {
				// Neither settings nor standalone has a passwd
				[passwordDrawer open];
				return false;
			} else {
				// Copy standalone passwd to settings
				[passwordField setStringValue: [passwordField2 stringValue]];
			}
		} else {
			// Copy settings passwd to standalone box
			[passwordField2 setStringValue: [passwordField stringValue]];
		}

        
        //save the user setting
        [self savePrefs];

		// Initialize sshInterface with config settings
		sshInterface = [ssh_interface alloc];
		[sshInterface setLocalSocksPort:[socksportField stringValue]];
		[sshInterface setServerSshPort:[portnumField stringValue]];
		[sshInterface setServerHostname:[hostnameField stringValue]];
		[sshInterface setServerSshObfuscatedKey:[keyField stringValue]];
		[sshInterface setServerSshUsername:[usernameField stringValue]];
		[sshInterface setServerSshPasswd:[passwordField stringValue]];
		// Connect
		[sshInterface connectToServer:self];
        
        isConnected=[self checkConnection];
		
		if (isConnected) {
			[passwordDrawer close];
            [self showEnableIcon];
		}
		
	} else {
		// Disconnect
		[sshInterface disconnectFromServer];
		[sshInterface dealloc];
        [self showDisableIcon];
	}
    return isConnected;
}

// in the near future,i will add code to check the connection status
// but now just return true;
- (bool)checkConnection
{
    return true;
}

//save prefs when the check box status changes
- (IBAction)stateChanged:(id)sender
{
    [self savePrefs];
}



// This callback is implemented as part of conforming to the ProcessController protocol.
// It will be called whenever there is output from the TaskWrapper.
- (void)appendOutput:(NSString *)output
{
    // add the string to the NSTextView's
    // backing store, in the form of an attributed string
    [[statusLabel textStorage] appendAttributedString: [[[NSAttributedString alloc]
                             initWithString: output] autorelease]];
    [self performSelector:@selector(scrollToVisible:) withObject:nil afterDelay:0.0];
}


// This routine is called after adding new results to the text view's backing store.
// We now need to scroll the NSScrollView in which the NSTextView sits to the part
// that we just added at the end
- (void)scrollToVisible:(id)ignore {
    [statusLabel scrollRangeToVisible:NSMakeRange([[statusLabel string] length], 0)];
}


// A callback that gets called when a TaskWrapper is launched, allowing us to do any setup
// that is needed from the app side.
- (void)processStarted
{
    [self appendOutput:@"\nConnecting...\n"];
    [connectButton setTitle:@"Disconnect?"];
	[busySpin startAnimation: self];
	
	char searchStr[255];
	char outputStr[1024];
	FILE *fh;
	int hasMatch, hasTimedOut;
	NSDate *timeStarted = [NSDate date];
	sprintf(searchStr, "127.0.0.1.%s", [[socksportField stringValue] cStringUsingEncoding:1]);
	
	// Warning: n00b hack
	// Keep running netstat to check whether the local SOCKS port is listening
	do {
		sleep(1);
		hasMatch = false;
		fh = popen("netstat -na", "r");
		do {
			fgets(outputStr, sizeof(outputStr), fh);
			if (strstr(outputStr, searchStr)) {
				hasMatch = true;
				break;
			}
		} while (!feof(fh));
		pclose(fh);
        [self appendOutput:@"."];
		//hasTimedOut = (abs((int)[timeStarted timeIntervalSinceNow]) > SSH_TIMEOUT);
        hasTimedOut = (abs((int)[timeStarted timeIntervalSinceNow]) > [timeoutField integerValue]);
	} while (!hasTimedOut && !hasMatch && ![sshInterface hasTerminated]);
	
	[busySpin stopAnimation: self];
    [self appendOutput:@"\n"];

	// Check if socks proxy is open
	if (hasMatch) {
		[self toggleCheckmark: true];
		[self appendOutput:@"Success!\n"];
		// Turn on SOCKS in the system wide settings
		if ([applyToNetwork state] == NSOnState) {
			[self toggleSOCKSSetting: true];
		}
	} else {
		// Timed out
		isConnected = false;
		[sshInterface disconnectFromServer];
		[sshInterface dealloc];
		[self appendOutput:@"Failed to connect.\n"];
	}
}


// A callback that gets called when a TaskWrapper is completed, allowing us to do any cleanup
// that is needed from the app side.  This method is implemented as a part of conforming
// to the ProcessController protocol.
- (void)processFinished
{
	[NSApp requestUserAttention:NSCriticalRequest];
	[tabs selectTabViewItemWithIdentifier:@"status"];
	[self toggleCheckmark: false];
	[self appendOutput:@"Not connected.\n"];
    [connectButton setTitle:@"Connect"];
	isConnected = false;
	// Turn off SOCKS in the system wide settings
	if ([applyToNetwork state] == NSOnState) {
		[self toggleSOCKSSetting: false];
	}
}


/*
- (void)toggleSOCKSSetting:(bool)state
{
	if (state == false && !isSettingsApplied) {
		// No need to toggle OFF the settings if they were not turned ON yet.
		return;
	}

	FILE *fh;
	char activeInterfaceName[80] = "AirPort"; // default
	//char **argv;
	char *argv[5];

	// Determine the active network interface
	fh = popen(
		[[NSString stringWithFormat:@"\"%@/%@\"", [thisBundle resourcePath], @"getservice"] cStringUsingEncoding:1], 
		"r"
	);
	while (!feof(fh)) {
		fgets(activeInterfaceName, 80, fh);
	}
	pclose(fh);

	AuthorizationFlags authFlags = kAuthorizationFlagDefaults |
            kAuthorizationFlagExtendRights |
            kAuthorizationFlagInteractionAllowed |
            kAuthorizationFlagPreAuthorize;
	AuthorizationItem authItems = {kAuthorizationRightExecute, 0, NULL, 0};
	AuthorizationRights authRights = {1, &authItems};
	OSStatus authStatus;
	AuthorizationRef authRef; 
	
	authStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, authFlags, &authRef);
	if (authStatus == 0) {
		authStatus = AuthorizationCopyRights(authRef, &authRights, NULL, authFlags, NULL);
	}
	if (authStatus == 0) {
		// Enable/disable the system wide SOCKS proxy setting
		if (state) {
			argv[0] = "-setsocksfirewallproxy";
			argv[1] = activeInterfaceName;
			argv[2] = "127.0.0.1";
			argv[3] = (char*)[[socksportField stringValue] cStringUsingEncoding:1];
			argv[4] = "off";
		} else {
			argv[0] = "-setsocksfirewallproxystate";
			argv[1] = activeInterfaceName;
			argv[2] = "off";
			argv[3] = "";
			argv[4] = "";
		}
		authStatus = AuthorizationExecuteWithPrivileges(
			authRef, "/usr/sbin/networksetup", kAuthorizationFlagDefaults, argv, NULL
		);
		AuthorizationFree (authRef,kAuthorizationFlagDestroyRights);
		if (authStatus == 0) {
			isSettingsApplied = true;
		}
	}
}
*/

- (void)toggleSOCKSSetting:(bool)state
{
	FILE *fh;
	int count = 0;
	char buffer;
	char activeInterfaceName[80];
	memset(activeInterfaceName, 0, 80);

	// Determine the active network interface
	fh = popen(
		// Rely on the bundled "getservice" Python script to discover the active network service name
		[[NSString stringWithFormat:@"\"%@/%@\"", [thisBundle resourcePath], @"getservice.py"] cStringUsingEncoding:1], 
		"r"
	);
	while (!feof(fh)) {
		buffer = fgetc(fh);
		if (iscntrl(buffer) || count >= 80) {
			break;
		}
		activeInterfaceName[count] = buffer;
		count++;
	}
	pclose(fh);

	if (strlen(activeInterfaceName) < 1) {
		// default to AirPort in case "getservice" script fails mysteriously
		strcpy(activeInterfaceName, "AirPort");
	}

	// Enable/disable the system wide SOCKS proxy setting
	if (state) {
		fh = popen(
			[[NSString stringWithFormat:@"networksetup -setsocksfirewallproxy %s 127.0.0.1 %@ off 2> /dev/null",
				activeInterfaceName, [socksportField stringValue]] cStringUsingEncoding:1], "r"
		);
	} else {
		fh = popen(
			[[NSString stringWithFormat:@"networksetup -setsocksfirewallproxystate %s off  2> /dev/null",
				activeInterfaceName] cStringUsingEncoding:1], "r"
		);
	}
	
	int exitCode;
	if ((exitCode = pclose(fh))) {
		printf("networksetup exit with code: %d\n", exitCode);
	}
}


- (void)toggleCheckmark:(bool)state
{
	// Disable/enable all text fields
	[hostnameField setEditable: !state];
	[portnumField setEditable: !state];
	[keyField setEditable: !state];
	[usernameField setEditable: !state];
	[passwordField setEditable: !state];
	[socksportField setEditable: !state];
    [timeoutField setEditable:!state];

	if (state) {
		// Display check mark
		NSString *imageFile = [[thisBundle resourcePath] stringByAppendingString:@"/path4068.png"];
		NSImage *image = [[NSImage alloc]initWithContentsOfFile: imageFile];
		[checkmark setImage: image];
		[disconnectMenu setEnabled:true];
		[connectMenu setEnabled:false];
        [image release];
	} else {
		// Display open padlock
		[checkmark setImage: [NSImage imageNamed: NSImageNameLockUnlockedTemplate]];
		[disconnectMenu setEnabled:false];
		[connectMenu setEnabled:true];
	}
}


- (void)loadPrefs
{
	[hostnameField setStringValue:[preferences stringForKey:@"hostName"]];
	[portnumField setStringValue:[preferences stringForKey:@"portNum"]];
	[keyField setStringValue:[preferences stringForKey:@"obfuscationKey"]];
	[usernameField setStringValue:[preferences stringForKey:@"username"]];
    [passwordField setStringValue:[preferences stringForKey:@"password"]];
	[socksportField setStringValue:[preferences stringForKey:@"socksPort"]];
	[applyToNetwork setState:[preferences integerForKey:@"applyToNetwork"]];
    [timeoutField setStringValue:[preferences stringForKey:@"timeout"]];
    [isAsyncKeysFirst setState:[preferences integerForKey:@"isAsyncKeysFirst"]];
    [isAutoLogin setState:[preferences integerForKey:@"isAutoLogin"]];
}

- (void)savePrefs
{
	[preferences setObject: [hostnameField stringValue] forKey:@"hostName"];
	[preferences setObject: [portnumField stringValue] forKey:@"portNum"];
	[preferences setObject: [keyField stringValue] forKey:@"obfuscationKey"];
	[preferences setObject: [usernameField stringValue] forKey:@"username"];
    [preferences setObject: [passwordField stringValue] forKey:@"password"];
	[preferences setObject: [socksportField stringValue] forKey:@"socksPort"];
	[preferences setInteger: [applyToNetwork state] forKey:@"applyToNetwork"];
    [preferences setObject:[timeoutField stringValue] forKey:@"timeout"];
    [preferences setInteger:[isAsyncKeysFirst state] forKey:@"isAsyncKeysFirst"];
    [preferences setInteger:[isAutoLogin state] forKey:@"isAutoLogin"];
	[preferences synchronize];
}


// Drawer management -- the config drawer is taller than the actual window.
// So we need some resizing trickery.
- (BOOL)drawerShouldOpen:(NSDrawer *)sender
{
	// Resize drawer height to 100px before opening
	NSSize size = [sender contentSize];
	size.height = 100;
	[sender	setContentSize: size];
	return YES;
}
- (void)drawerDidOpen:(NSNotification *)notification
{
	// Reize drawer to full height after opening
	NSSize size = [drawer maxContentSize];
    size.height+=60;
	[drawer setContentSize: size];
}
- (BOOL)drawerShouldClose:(NSDrawer *)sender
{
	// Resize drawer height to 100px before closing
	NSSize size = [sender minContentSize];
	size.height = 100;
	[sender	setContentSize: size];
	return YES;
}
- (void)windowDidMiniaturize:(NSNotification *)notification
{
	// Miniaturizing and restoring results in a messed up drawer.
	// Close all drawers to avoid the problem.
	[drawer close];
	[toggleDrawer setState: NSOffState];
	[passwordDrawer close];
}
- (void)windowDidDeminiaturize:(NSNotification *)notification
{
	[[drawer contentView] setHidden: false];
	[[passwordDrawer contentView] setHidden: false];
}

/*
// Confirm with user before terminating
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)theSender
{
	if (windowHasBeenClosed || !isConnected) {
		// Must terminate if the window has already been closed.
		return NSTerminateNow;
	}

	NSAlert *alert = [[NSAlert alloc]init];
	[alert setMessageText: @"Please confirm if you really want to quit and turn off your SOCKS proxy"];
	[alert addButtonWithTitle: @"Quit"];
	[alert addButtonWithTitle: @"Don't quit"];

	if ([alert runModal] == NSAlertFirstButtonReturn) {
        [alert release];
		return NSTerminateNow;
	} else {
        [alert release];
		return NSTerminateCancel;
	}
}
*/

// Confirm with user before closing window
- (BOOL)windowShouldClose:(id)theWindow
{
    /*
	if ([self applicationShouldTerminate: NSApp]) {
		windowHasBeenClosed = true;
		return YES;
	} else {
		return NO;
	}
     */
    //hide window,but not exit
    [window orderOut:nil];
    return NO;
}


// Make sure to disconnect from SSH when terminating
- (void)applicationWillTerminate:(NSApplication *)theApplication
{
	[self quitApp:self];
    return;
}

-(void)quitApp:(id)sender
{
    if (isConnected) {
        [sshInterface disconnectFromServer];
        [sshInterface dealloc];
    }
    if (sender) {
        [NSApp terminate:sender];
    }
}

//open window when click
-(BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    [window makeKeyAndOrderFront:nil];
    return YES;
}


// Terminate when window is closed
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSLog(@"didFinishLaunching");
    NSMenu *menu = [self createMenu];
    
    statusItem = [[[NSStatusBar systemStatusBar]
                   statusItemWithLength:NSSquareStatusItemLength] retain];
    [statusItem setMenu:menu];
    [statusItem setHighlightMode:YES];
    [statusItem setToolTip:@"Secret Socks"];
    
    [self showEnableIcon];
    
    [menu release];
    
    [window center];
	[self loadPrefs];
    NSLog(@"didFinishLaunching, load Prefs");
    if ([isAutoLogin state]==NSOnState)
    {
        NSLog(@"Start to do auto login");
        if ([self doAutoConnect])
        {
            [self showEnableIcon];
            [window orderOut:nil];
        } else {
            [self showDisableIcon];
        }
    }
}

- (void)showEnableIcon
{
    NSLog(@"show enable Icon");
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:[thisBundle pathForResource:@"locked-socks" ofType:@"png"]];
    
    [statusItem setImage:img];
    [img release];
}

- (void)showDisableIcon
{
    NSLog(@"show disable Icon");
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:[thisBundle pathForResource:@"locked-socks-disable" ofType:@"png"]];
    
    [statusItem setImage:img];
    [img release];
}

- (NSMenu *) createMenu
{
    NSLog(@"createMenu run");
    NSZone *menuZone = [NSMenu menuZone];
    NSMenu *menu = [[NSMenu allocWithZone:menuZone] init];
    NSMenuItem *menuItem;
    
    // Add To Items
    menuItem = [menu addItemWithTitle:@"Open Window"
                               action:@selector(openWindow)
                        keyEquivalent:@""];
    [menuItem setTarget:self];
    // Add Separator
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Add Quit Action
    menuItem = [menu addItemWithTitle:@"Quit"
                               action:@selector(quitApp:)
                        keyEquivalent:@""];
    [menuItem setToolTip:@"Click to Quit this App"];
    [menuItem setTarget:self];
    return menu;
}

- (void) openWindow
{
    [window makeKeyAndOrderFront:nil];
    [window setLevel: NSStatusWindowLevel];
}

@end
