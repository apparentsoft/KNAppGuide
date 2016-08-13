//
//  KNAppGuideHUDPresenter.m
//  KNAppGuide
//
//  Created by Daniel Kennett on 13/05/2009.
//  Copyright 2009 KennettNet Software Limited. All rights reserved.
//

#import "KNAppGuideHUDPresenter.h"
#import "KNAppGuideStep.h"
#import "KNAppGuideClassicHighlight.h"
#import "NSWindow+Fade.h"
#import "KNAppGuideDelegate.h"
#import "KNAppGuide.h"
#import <WebKit/WebKit.h>



@interface KNAppGuideResizingWebView : WKWebView

@property (nonatomic, readwrite) NSSize intrinsicContentSize;

@end


@implementation KNAppGuideResizingWebView

-(void)	setIntrinsicContentSize:(NSSize)intrinsicContentSize
{
	_intrinsicContentSize = intrinsicContentSize;
	[self invalidateIntrinsicContentSize];
}


-(BOOL)	isOpaque
{
	return NO;
}

@end


@interface KNAppGuideHUDPresenter () <WKScriptMessageHandler>
 {
	id <KNAppGuide> guide;
	id <KNAppGuidePresenterDelegate> delegate;
	KNAppGuideClassicHighlight *currentControlHighlight;
	IBOutlet NSTextField *stepExplanationTextField;
	IBOutlet NSButton *nextButton;
	IBOutlet NSView *stepExplanationWebViewContainer;
	KNAppGuideResizingWebView *stepExplanationWebView;	// In 10.11 and earlier, WKWebView can not be created using initWithCoder (i.e. from a XIB).
	WKWebViewConfiguration *stepExplanationWebViewConfiguration;
}

@end


@implementation KNAppGuideHUDPresenter

-(id)init {
	return [self initWithGuide:nil];
}

-(id)initWithGuide:(id <KNAppGuide>)g {
	
	if (!g) {
		// Insist on having a guide
		[self release];
		return nil;
	}
	
	if (self = [super initWithWindowNibName:@"KNAppGuideHUDPresenter"]) {
		
		NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
		NSString *appName = [[NSFileManager defaultManager] displayNameAtPath: bundlePath];
		
		[[self window] setTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"default window title", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @""), appName]];
		
		[self willChangeValueForKey:@"guide"];
		guide = [g retain];
		[self didChangeValueForKey:@"guide"];
		
		[[self guide] setDelegate:self];
		[[self guide] reset];
	}
	return self;
}

-(void)dealloc {
	[stepExplanationWebView removeFromSuperview];
	[stepExplanationWebView release];
	stepExplanationWebView = nil;
	
	[guide release];
	guide = nil;
	
	if (currentControlHighlight) {
		
		NSDisableScreenUpdates();
		
		[currentControlHighlight fadeOutWithDuration:0.25];
		
		[[currentControlHighlight parentWindow] removeChildWindow:currentControlHighlight];
		[currentControlHighlight release];
		currentControlHighlight = nil;
		
		NSEnableScreenUpdates();
	}
	
	
	[super dealloc];
	
}

@synthesize guide;
@synthesize delegate;

-(void)showWindow:(id)sender {
	[self beginPresentation];
}

-(void)beginPresentation {
	[self retain];
	
	if ([[self delegate] respondsToSelector:@selector(presenter:willBeginPresentingGuide:)]) {
		[[self delegate] presenter:self willBeginPresentingGuide:[self guide]];
	}
	
	[[self window] fadeInWithDuration:0.25];
	
	if ([[self delegate] respondsToSelector:@selector(presenter:didBeginPresentingGuide:)]) {
		[[self delegate] presenter:self didBeginPresentingGuide:[self guide]];
	}
}

-(void)closePresentation {
	
	if ([[self delegate] respondsToSelector:@selector(presenter:willFinishPresentingGuide:completed:)]) {
		[[self delegate] presenter:self willFinishPresentingGuide:[self guide] completed:([[self guide] currentStep] == [[[self guide] steps] lastObject])];
	}
	
	[nextButton setTarget:nil];
	[nextButton setAction:nil];
	
	[[self window] fadeOutWithDuration:0.25];
	
	if ([[self delegate] respondsToSelector:@selector(presenter:didFinishPresentingGuide:completed:)]) {
		[[self delegate] presenter:self didFinishPresentingGuide:[self guide] completed:([[self guide] currentStep] == [[[self guide] steps] lastObject])];
	}
	
	[self release];
}


-(void)windowDidLoad
{
	[super windowDidLoad];
	
	[self.window setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameVibrantDark]];
	
	//Javascript string
    NSString * source = @"window.onload=function () { window.webkit.messageHandlers.sizeNotification.postMessage({width: document.width, height: document.height});};";

    //UserScript object
    WKUserScript * script = [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];

    //Content Controller object
    WKUserContentController * controller = [[WKUserContentController alloc] init];

    //Add script to controller
    [controller addUserScript:script];

    //Add message handler reference
    [controller addScriptMessageHandler:self name:@"sizeNotification"];

    //Create configuration
    stepExplanationWebViewConfiguration = [[WKWebViewConfiguration alloc] init];

    //Add controller to configuration
    stepExplanationWebViewConfiguration.userContentController = controller;
	
	stepExplanationWebView = [[KNAppGuideResizingWebView alloc] initWithFrame: NSZeroRect configuration: stepExplanationWebViewConfiguration];
	[stepExplanationWebView setValue: @YES forKey: @"drawsTransparentBackground"];	// +++ Not sure this is MAS-safe.
	[stepExplanationWebView setContentHuggingPriority: 1000 forOrientation: NSLayoutConstraintOrientationVertical];
	[stepExplanationWebViewContainer addSubview: stepExplanationWebView];
	stepExplanationWebView.translatesAutoresizingMaskIntoConstraints = NO;
	[stepExplanationWebView.leftAnchor constraintEqualToAnchor: stepExplanationWebViewContainer.leftAnchor].active = YES;
	[stepExplanationWebView.rightAnchor constraintEqualToAnchor: stepExplanationWebViewContainer.rightAnchor].active = YES;
	[stepExplanationWebView.topAnchor constraintEqualToAnchor: stepExplanationWebViewContainer.topAnchor].active = YES;
	[stepExplanationWebView.bottomAnchor constraintEqualToAnchor: stepExplanationWebViewContainer.bottomAnchor].active = YES;
}


- (BOOL)windowShouldClose:(id)window {
	
	// If we return yes, the window gets closed immediately and we 
	// don't get a chance to fade it. Instead, return NO and fade ourselves.
	
	[self closePresentation];
	return NO;
}


- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    CGRect frame = message.webView.frame;
    frame.size.height = [[message.body valueForKey:@"height"] floatValue];
	((KNAppGuideResizingWebView*)message.webView).intrinsicContentSize = frame.size;
	[((KNAppGuideResizingWebView*)message.webView) setNeedsLayout: YES];
	[((KNAppGuideResizingWebView*)message.webView).window layoutIfNeeded];
}


-(IBAction)clickNext:(id)sender {
	
	if ([[self guide] hasFinished]) {
		[self closePresentation];
	} else {
		[[self guide] moveToNextStep];
	}
	
}

-(IBAction)clickPrevious:(id)sender {
	if (![[self guide] isAtBeginning]) {
		[[self guide] moveToPreviousStep];
	}
}

-(IBAction)clickPerformAction:(id)sender {
	[[[self guide] currentStep] performAction];
}


#pragma mark -
#pragma mark UI Labels and such

-(NSString *)showMeButtonTitle {
	return NSLocalizedStringFromTableInBundle(@"show me button title", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @"");
}

+(NSSet *)keyPathsForValuesAffectingNextButtonTitle {
	return [NSSet setWithObjects:@"guide.hasFinished", nil];
}

-(NSString *)nextButtonTitle {
	if ([[self guide] hasFinished]) {
		return NSLocalizedStringFromTableInBundle(@"done button title", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @"");
	} else {
		return NSLocalizedStringFromTableInBundle(@"next button title", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @"");
	}
}

-(NSString *)previousButtonTitle {
	return NSLocalizedStringFromTableInBundle(@"previous button title", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @"");
}

+(NSSet *)keyPathsForValuesAffectingGuideProgressTitle {
	return [NSSet setWithObjects:@"guide", @"guide.currentStep", nil];
}

-(NSString *)guideProgressTitle {
	return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"progress label", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @""),
			[[[self guide] steps] indexOfObject:[[self guide] currentStep]] + 1,
			[[[self guide] steps] count]];
}

#pragma mark -
#pragma mark Tags

+(NSSet *)keyPathsForValuesAffectingTaggedStepExplanation {
	return [NSSet setWithObjects:@"guide", @"guide.currentStep", nil];
}

-(NSString *)taggedStepExplanation {
	
	NSString *str = [[[[self guide] currentStep] explanation] stringByReplacingOccurrencesOfString:@"%PREVIOUSBUTTONTITLE" 
																						withString:NSLocalizedStringFromTableInBundle(@"previous button title", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @"")];
	
	str = [str stringByReplacingOccurrencesOfString:@"%NEXTBUTTONTITLE"
										 withString:NSLocalizedStringFromTableInBundle(@"next button title", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @"")];
	
	str = [str stringByReplacingOccurrencesOfString:@"%DONEBUTTONTITLE"
										 withString:NSLocalizedStringFromTableInBundle(@"done button title", @"KNAppGuideHUDPresenterStrings", [NSBundle bundleForClass:[self class]], @"")];
	
	
	if ([[self delegate] respondsToSelector:@selector(presenter:willDisplayExplanation:forStep:inGuide:)]) {
		str = [[self delegate] presenter:self willDisplayExplanation:str forStep:[[self guide] currentStep] inGuide:[self guide]];
	}
	
	if( !self.guide.currentStep.explanationIsHTML ){
		str = [str stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"];
		str = [str stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
		str = [str stringByReplacingOccurrencesOfString: @">" withString: @"&gt;"];
		str = [str stringByReplacingOccurrencesOfString: @"\"" withString: @"&quot;"];
		str = [str stringByReplacingOccurrencesOfString: @"\r\n" withString: @"\n"];
		str = [str stringByReplacingOccurrencesOfString: @"\r" withString: @"\n"];
		str = [str stringByReplacingOccurrencesOfString: @"\n" withString: @"<br />"];
	}
	
	return str;
}


#pragma mark -
#pragma mark KNAppGuideDelegate

-(void)guide:(id <KNAppGuide>)aGuide willMoveToStep:(id <KNAppGuideStep>)step {
	
	// Remove the existing highlight, if any
	
	if (aGuide == [self guide]) {
		// ^ Well, you never know!
		
		if ([[self delegate] respondsToSelector:@selector(presenter:willMoveToStep:inGuide:)]) {
			[[self delegate] presenter:self willMoveToStep:step inGuide:[self guide]];
		}
		
		if (currentControlHighlight) {
			
			NSDisableScreenUpdates();
			
			[currentControlHighlight fadeOutWithDuration:0.25];
			
			[[currentControlHighlight parentWindow] removeChildWindow:currentControlHighlight];
			[currentControlHighlight release];
			currentControlHighlight = nil;
			
			NSEnableScreenUpdates();
		}
	}	
}

-(void)guide:(id <KNAppGuide>)aGuide didMoveToStep:(id <KNAppGuideStep>)step {
	
	// Add the new highlight, if possible
	
	if ([step highlightedItem]) {
		
		currentControlHighlight = [[KNAppGuideClassicHighlight highlightForItem:[step highlightedItem]] retain];
	}
	
	NSFont *theFont = [NSFont systemFontOfSize: [NSFont systemFontSize]];
	NSString *htmlString = [NSString stringWithFormat: @"<html><head><style>body { margin: 0pt; background-color: transparent; } h1 { font-family: '%1$@'; font-style: bold; font-size: %2$d; color: white; } section { font-family: '%1$@'; font-size: %2$d; color: white; }</style>%5$@</head><body><h1>%4$@</h1>%3$@</body></html>", theFont.familyName, (int)theFont.pointSize, self.taggedStepExplanation, self.guide.title, self.guide.headHTML];
	[stepExplanationWebView loadHTMLString: htmlString baseURL: self.guide.baseDocumentURL];
	
	if ([[self delegate] respondsToSelector:@selector(presenter:didMoveToStep:inGuide:)]) {
		[[self delegate] presenter:self didMoveToStep:step inGuide:[self guide]];
	}
}

-(void)guide:(id <KNAppGuide>)aGuide action:(id <KNAppGuideAction>)anAction wasPerformedForStep:(id <KNAppGuideStep>)step {
	
	if (aGuide == [self guide]) {
		// ^ Well, you never know!

		if (step == [[[self guide] steps] lastObject] && step == [[self guide] currentStep]) {
			[self closePresentation];
		}
	}
}

@end
