//
//  KNAppGuideLoader.m
//  KNAppGuide
//
//  Created by Daniel Kennett on 12/05/2009.
//  Copyright 2009 KennettNet Software Limited. All rights reserved.
//

#import "KNAppGuideLoader.h"
#import "KNAppGuide.h"
#import "KNAppGuideResolver.h"

// WARNING: This class contains heroics. 

@interface KNAppGuideLoader (KNAppGuideFileLoadingPrivate)

-(id <KNAppGuide>)guideWithDictionary:(NSDictionary *)dict;
-(BOOL)keyIsKeyPathQualifier:(NSString *)key;
-(id)instantiatedObjectFromClassName:(NSString *)name;
-(id)valueForKey:(NSString *)key inDictionary:(NSDictionary *)dict parentClassName:(NSString *)className;
-(id <KNAppGuideStep>)stepForDictionary:(NSDictionary *)stepDictionary;
-(id)objectFromDictionary:(NSDictionary *)dict shouldConformToProtocol:(Protocol *)protocol fallbackClass:(Class)class;

@end

@implementation KNAppGuideLoader

+(id <KNAppGuide>)guideFromHTMLFile:(NSString *)guidePath resolver:(id <KNAppGuideResolver>)aResolver {
	
	// The file at path should be a plist conforming to the KNAppGuide structure. 
	
	NSURL *guideURL = [NSURL fileURLWithPath: guidePath];
	NSError *err = nil;
	NSXMLDocument *guideXMLDoc = [[[NSXMLDocument alloc] initWithContentsOfURL: guideURL options:NSDataReadingMappedIfSafe error: &err] autorelease];
	if( ! guideXMLDoc ) {
		NSLog(@"error loading HTML help file: %@", err);
		return nil;
	}
	
	NSMutableDictionary*	guideDict = [NSMutableDictionary dictionary];

	NSArray *titleElems = [guideXMLDoc nodesForXPath: @"//html/head/title" error:&err];
	NSXMLNode *titleElem = titleElems.firstObject;
	NSString *title = titleElem.stringValue;
	if( title )
		[guideDict setObject: title forKey: @"title"];
	NSArray<NSXMLElement*> *setterNodes = [guideXMLDoc nodesForXPath: @"//html/head/appguide:set" error:&err];
	[self addTagsFromElements: setterNodes toGuideDictionary: guideDict];
	NSArray *headElems = [guideXMLDoc nodesForXPath: @"//html/head/node()" error:&err];
	NSMutableString *headHTML = [NSMutableString string];
	for( NSXMLNode *headElem in headElems )
	{
		if( ![headElem.name hasPrefix: @"appguide:"] && [headElem.name caseInsensitiveCompare: @"style"] != NSOrderedSame )
			[headHTML appendString: headElem.description];
	}
	[guideDict setObject: headHTML forKey: @"headHTML"];
	[guideDict setObject: [guideURL URLByDeletingLastPathComponent] forKey: @"baseDocumentURL"];
	
	NSMutableArray *guideStepsArray = [NSMutableArray array];
	NSArray<NSXMLElement*> *guideStepElems = [guideXMLDoc nodesForXPath: @"//html/body/section" error:&err];
	for (NSXMLElement* currGuideStep in guideStepElems) {
		NSMutableDictionary *stepGuideDict = [NSMutableDictionary dictionary];
		[stepGuideDict setObject: currGuideStep.description forKey: @"explanation"];
		[stepGuideDict setObject: @"html" forKey: @"explanationFormat"];
		setterNodes = [currGuideStep nodesForXPath: @"appguide:set" error:&err];
		[self addTagsFromElements: setterNodes toGuideDictionary: stepGuideDict];
		setterNodes = [currGuideStep nodesForXPath: @"appguide:action/node()" error:&err];
		if( setterNodes != nil ) {
			NSMutableDictionary *actionGuideDict = [NSMutableDictionary dictionary];
			[self addTagsFromElements: setterNodes toGuideDictionary: actionGuideDict];
			if( actionGuideDict.count > 0 )
				[stepGuideDict setObject: actionGuideDict forKey: @"action"];
		}
		[guideStepsArray addObject: stepGuideDict];
	}
	[guideDict setObject: guideStepsArray forKey: @"steps"];
	if( guideDict[objectClassNameKey] == nil ) {	// In HTML, the guide class name is optional at the root.
		[guideDict setObject: @"KNAppGuide" forKey: objectClassNameKey];
	}
	
	KNAppGuideLoader *loader = [[self alloc] init];	
	[loader setResolver:aResolver];
	id <KNAppGuide> guide = [loader guideWithDictionary:guideDict];
	[loader release];
	
	return guide;
}


+(void)	addTagsFromElements: (NSArray<NSXMLElement*>*)setterNodes toGuideDictionary: (NSMutableDictionary*)guideDict
{
	for( NSXMLElement *currSetterElem in setterNodes )
	{
		for( NSXMLNode *theAttr in currSetterElem.attributes )
		{
			NSString *name = theAttr.name;
			id value = theAttr.stringValue;
			BOOL isYesBool = [value caseInsensitiveCompare: @"YES"] == NSOrderedSame;
			if( isYesBool || [value caseInsensitiveCompare: @"NO"] == NSOrderedSame ) {
				value = [NSNumber numberWithBool: isYesBool];
			}
			[guideDict setObject: value forKey: name];
		}
	}
}


+(id <KNAppGuide>)guideFromFile:(NSString *)guidePath resolver:(id <KNAppGuideResolver>)aResolver {
	
	// The file at path should be a plist conforming to the KNAppGuide structure. 
	
	NSDictionary *guideDict = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:guidePath]
															            options:NSPropertyListImmutable
																		 format:nil
																		  error:nil];
	
	KNAppGuideLoader *loader = [[self alloc] init];	
	[loader setResolver:aResolver];
	id <KNAppGuide> guide = [loader guideWithDictionary:guideDict];
	[loader release];
	
	return guide;
}

+(id <KNAppGuide>)guideFromBundle:(NSBundle *)bundle withName:(NSString *)name resolver:(id <KNAppGuideResolver>)aResolver {
	
	if (!bundle) {
		return [self guideFromBundle:[NSBundle mainBundle] withName:name resolver:aResolver];
	} else {
		
		NSString *path = [bundle pathForResource:name ofType:@"guide"];
		
		if (!path) {
			path = [bundle pathForResource:name ofType: @"html"];
		}
		if (!path) {
			path = [bundle pathForResource:name ofType: @"htm"];
		}
		if (!path) {
			path = [bundle pathForResource:name ofType:nil];
		}
		
		if (!path) {
			return nil;
		} else {
			NSString *suffix = [path pathExtension];
			if ([suffix caseInsensitiveCompare: @"html"] == NSOrderedSame
				|| [suffix caseInsensitiveCompare: @"htm"] == NSOrderedSame) {
				return [self guideFromHTMLFile:path resolver:aResolver];
			} else {
				return [self guideFromFile:path resolver:aResolver];
			}
		}
	}
}

+(id <KNAppGuide>)guideWithName:(NSString *)name resolver:(id <KNAppGuideResolver>)aResolver {
	return [self guideFromBundle:[NSBundle mainBundle] withName:name resolver:aResolver];
}

#pragma mark -

@synthesize resolver;

static NSString *keyPathQualifier = @"ShouldBeResolved";
static NSString *objectClassNameKey = @"objectClass";

-(id <KNAppGuide>)guideWithDictionary:(NSDictionary *)dict {
	
	if (!dict) {
		return nil;
	}
	
	id <KNAppGuide> guide = [self objectFromDictionary:dict 
							   shouldConformToProtocol:@protocol(KNAppGuide)
										 fallbackClass:[KNAppGuide class]];
	
	for (NSString *key in [dict allKeys]) {
		
		// To be flexible for subclasses, as well as looking for keys we know about,
		// we look through them all and setValue:forKey: with them.
		
		if ([key isEqualToString:@"steps"]) {
			// Deal with the special case of  steps
			
			NSArray *stepDictionaries = [dict valueForKey:key];
			NSMutableArray *stepObjects = [NSMutableArray array];
			
			for (NSDictionary *stepDict in stepDictionaries) {
				
				id <KNAppGuideStep> step = [self stepForDictionary:stepDict];
				
				if ([step conformsToProtocol:@protocol(KNAppGuideStep)]) {
					[stepObjects addObject:step];
				}
				
			}
			
			[guide setSteps:stepObjects];
			
		} else {
			
			if (![self keyIsKeyPathQualifier:key] && ![key isEqualToString:objectClassNameKey]) {
				// ^ We don't want to try and set the key path qualifier or object class name keys
				
				[(NSObject *)guide setValue:[self valueForKey:key 
												 inDictionary:dict 
											  parentClassName:[(NSObject *)guide className]]
									 forKey:key];
			}
		}
	}
	
	return guide;
}


-(id)objectFromDictionary:(NSDictionary *)dict shouldConformToProtocol:(Protocol *)protocol fallbackClass:(Class)class {
	
	if (!dict) {
		return nil;
	}
	
	id obj = nil;
	
	// Before we do anything, we need to create the object so look for a custom class name and try to instantiate it.
	
	NSString *className = [self valueForKey:objectClassNameKey inDictionary:dict parentClassName:nil];
	
	if (!className) {
		className = NSStringFromClass(class);
	}
	
	obj = [[self instantiatedObjectFromClassName:className] retain];
	
	// Check if the object conforms to the given protocol. If it doesn't, release it
	// and instantiate an instance of the fallback class.
	
	if (![obj conformsToProtocol:protocol]) {
		[obj release];
		obj = [[class alloc] init];
	}
	
	return [obj autorelease];
	
}


-(id <KNAppGuideStep>)stepForDictionary:(NSDictionary *)stepDictionary {
	
	// This is quite similar to the guide setup...
	
	if (!stepDictionary) {
		return nil;
	}
	
	id <KNAppGuideStep> step = [self objectFromDictionary:stepDictionary 
								  shouldConformToProtocol:@protocol(KNAppGuideStep) 
											fallbackClass:[KNAppGuideStep class]];
	
	
	for (NSString *key in [stepDictionary allKeys]) {
		
		// To be flexible for subclasses, as well as looking for keys we know about,
		// we look through them all and setValue:forKey: with them.
		
		if ([key isEqualToString:@"action"]) {
			// Deal with the special case of  the action
			
			NSDictionary *actionDict = [stepDictionary valueForKey:key];
			
			id <KNAppGuideAction> action = [self objectFromDictionary:actionDict 
											  shouldConformToProtocol:@protocol(KNAppGuideAction) 
														fallbackClass:nil];
			
			for (NSString *actionKey in [actionDict allKeys]) {
				if (![self keyIsKeyPathQualifier:actionKey] && ![actionKey isEqualToString:objectClassNameKey]) {
					
					[(NSObject *)action setValue:[self valueForKey:actionKey 
													  inDictionary:actionDict 
												   parentClassName:[(NSObject *)action className]]
										  forKey:actionKey];
				}
			}
			
			if (action) {
				[step setAction:action];
			}
			
		} else {
			
			if (![self keyIsKeyPathQualifier:key] && ![key isEqualToString:objectClassNameKey]) {
				// ^ We don't want to try and set the key path qualifier or object class name keys
				
				[(NSObject *)step setValue:[self valueForKey:key 
												inDictionary:stepDictionary 
											 parentClassName:[(NSObject *)step className]]
									forKey:key];
			}
		}
	}
	
	return step;
}


-(id)valueForKey:(NSString *)key inDictionary:(NSDictionary *)dict parentClassName:(NSString *)className {
	
	// This method gets the final value for a property in the dictionary, in that if the value has an "is key path" qualifier, we
	// try to resolve that key path and return the resolved value instead of the actual value stored in the dictionary.
	
	id value = nil;
	
	if ([[dict valueForKey:[NSString stringWithFormat:@"%@%@", key, keyPathQualifier]] boolValue] == YES) {
		
		value = [[self resolver] resolveValue:[dict valueForKey:key]
									 forKey:key
								   inClassNamed:className];
		
	} else {
		value = [dict valueForKey:key];
	}
	
	return value;
}

-(BOOL)keyIsKeyPathQualifier:(NSString *)key {
	
	// This only checks that the key path qualifier is contained in the key, rather than if it's at the end.
	// Is that good enough?
	
	return !([key rangeOfString:keyPathQualifier options:0].location == NSNotFound);
	
}

-(id)instantiatedObjectFromClassName:(NSString *)name {
	
	Class aClass = NSClassFromString(name);
	
	if (aClass) {
		return [[[aClass alloc] init] autorelease];
	} else {
		return nil;
	}
	
}

-(void)dealloc {
	[self setResolver:nil];
	
	[super dealloc];
}

@end
