//
//  KNAppGuideHUDPresenter.h
//  KNAppGuide
//
//  Created by Daniel Kennett on 13/05/2009.
//  Copyright 2009 KennettNet Software Limited. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <KNAppGuide/KNAppGuidePresenter.h>
#import <KNAppGuide/KNAppGuideDelegate.h>


@interface KNAppGuideHUDPresenter : NSWindowController <KNAppGuidePresenter, KNAppGuideDelegate>

-(IBAction)clickNext:(id)sender;
-(IBAction)clickPrevious:(id)sender;
-(IBAction)clickPerformAction:(id)sender;

@end
